#!/usr/bin/env python3
"""Train a lightweight multi-task audio model from annotated gameplay segments.

This script is designed for small local Apple Silicon machines. It uses:

- full-file decoding with ffmpeg to mono 16 kHz float PCM
- compact log-mel summary features per labeled segment
- a small multi-task MLP in PyTorch

The model predicts:
- dominant_source
- music_suppress
- impact_strength
- movement_strength
- sustain_strength
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
import subprocess
import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as F
from scipy.signal import stft
from sklearn.metrics import accuracy_score, f1_score

from prepare_audio_dataset import discover_items, write_manifests


DEFAULT_SOURCE_ROOT = "/Volumes/SSD/音频数据集"
DEFAULT_PREPARED_ROOT = "/Volumes/SSD/音频数据集/prepared_dataset"
ANNOTATION_COLUMNS = [
    "start_ms",
    "end_ms",
    "dominant_source",
    "music_suppress",
    "impact_strength",
    "movement_strength",
    "sustain_strength",
    "confidence",
    "notes",
]
TASK_COLUMNS = [
    "dominant_source",
    "music_suppress",
    "impact_strength",
    "movement_strength",
    "sustain_strength",
]


@dataclass(frozen=True)
class SegmentRecord:
    dataset_id: str
    game: str
    source_path: str
    start_ms: int
    end_ms: int
    dominant_source: str
    music_suppress: int
    impact_strength: int
    movement_strength: int
    sustain_strength: int
    confidence: int


class MultiTaskMLP(nn.Module):
    def __init__(self, input_dim: int, dominant_classes: int) -> None:
        super().__init__()
        self.backbone = nn.Sequential(
            nn.Linear(input_dim, 256),
            nn.LayerNorm(256),
            nn.GELU(),
            nn.Dropout(0.15),
            nn.Linear(256, 128),
            nn.GELU(),
            nn.Dropout(0.10),
        )
        self.dominant_head = nn.Linear(128, dominant_classes)
        self.music_head = nn.Linear(128, 4)
        self.impact_head = nn.Linear(128, 4)
        self.movement_head = nn.Linear(128, 4)
        self.sustain_head = nn.Linear(128, 4)

    def forward(self, inputs: torch.Tensor) -> dict[str, torch.Tensor]:
        shared = self.backbone(inputs)
        return {
            "dominant_source": self.dominant_head(shared),
            "music_suppress": self.music_head(shared),
            "impact_strength": self.impact_head(shared),
            "movement_strength": self.movement_head(shared),
            "sustain_strength": self.sustain_head(shared),
        }


class ArrayDataset(torch.utils.data.Dataset):
    def __init__(
        self,
        features: np.ndarray,
        targets: dict[str, np.ndarray],
        sample_weights: np.ndarray,
    ) -> None:
        self.features = torch.from_numpy(features.astype(np.float32, copy=False))
        self.targets = {
            key: torch.from_numpy(value.astype(np.int64, copy=False))
            for key, value in targets.items()
        }
        self.sample_weights = torch.from_numpy(sample_weights.astype(np.float32, copy=False))

    def __len__(self) -> int:
        return self.features.shape[0]

    def __getitem__(self, index: int) -> tuple[torch.Tensor, dict[str, torch.Tensor], torch.Tensor]:
        return (
            self.features[index],
            {key: value[index] for key, value in self.targets.items()},
            self.sample_weights[index],
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a lightweight gameplay audio model.")
    parser.add_argument("--source-root", default=DEFAULT_SOURCE_ROOT)
    parser.add_argument("--prepared-root", default=DEFAULT_PREPARED_ROOT)
    parser.add_argument("--annotation-root", default=None)
    parser.add_argument("--manifest-path", default=None)
    parser.add_argument("--ffmpeg-bin", default="ffmpeg")
    parser.add_argument("--ffprobe-bin", default="ffprobe")
    parser.add_argument("--device", default=None, help="cpu, mps, or cuda. Auto-detected when omitted.")
    parser.add_argument("--sample-rate", type=int, default=16000)
    parser.add_argument("--n-mels", type=int, default=48)
    parser.add_argument("--n-fft", type=int, default=512)
    parser.add_argument("--win-length", type=int, default=400)
    parser.add_argument("--hop-length", type=int, default=160)
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--learning-rate", type=float, default=2e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-files", type=int, default=None)
    parser.add_argument("--cache-path", default=None)
    parser.add_argument("--run-name", default=None)
    parser.add_argument("--recompute-features", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    source_root = Path(args.source_root).expanduser().resolve()
    prepared_root = Path(args.prepared_root).expanduser().resolve()
    annotation_root = (
        Path(args.annotation_root).expanduser().resolve()
        if args.annotation_root
        else prepared_root / "annotations_auto"
    )
    manifest_path = (
        Path(args.manifest_path).expanduser().resolve()
        if args.manifest_path
        else prepared_root / "manifests" / "sources.csv"
    )
    cache_path = (
        Path(args.cache_path).expanduser().resolve()
        if args.cache_path
        else prepared_root / "training_cache" / "features_v1.npz"
    )

    ensure_manifest(
        source_root=source_root,
        prepared_root=prepared_root,
        manifest_path=manifest_path,
        ffprobe_bin=args.ffprobe_bin,
    )

    source_lookup = load_source_lookup(manifest_path)
    records = load_segment_records(annotation_root, source_lookup, max_files=args.max_files)
    if not records:
        raise RuntimeError("No annotation records were loaded.")

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    if cache_path.exists() and not args.recompute_features:
        dataset = load_feature_cache(cache_path)
        if not is_feature_cache_compatible(dataset, records):
            dataset = build_feature_dataset(
                records=records,
                ffmpeg_bin=args.ffmpeg_bin,
                sample_rate=args.sample_rate,
                n_fft=args.n_fft,
                win_length=args.win_length,
                hop_length=args.hop_length,
                n_mels=args.n_mels,
            )
            save_feature_cache(cache_path, dataset)
    else:
        dataset = build_feature_dataset(
            records=records,
            ffmpeg_bin=args.ffmpeg_bin,
            sample_rate=args.sample_rate,
            n_fft=args.n_fft,
            win_length=args.win_length,
            hop_length=args.hop_length,
            n_mels=args.n_mels,
        )
        save_feature_cache(cache_path, dataset)

    split = build_file_level_split(dataset["dataset_ids"], dataset["games"], seed=args.seed)
    run_dir = build_run_dir(prepared_root, args.run_name)
    run_dir.mkdir(parents=True, exist_ok=True)

    train_outputs = train_model(
        dataset=dataset,
        split=split,
        device=resolve_device(args.device),
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate,
        weight_decay=args.weight_decay,
        run_dir=run_dir,
        seed=args.seed,
    )

    metadata = {
        "source_root": str(source_root),
        "prepared_root": str(prepared_root),
        "annotation_root": str(annotation_root),
        "manifest_path": str(manifest_path),
        "cache_path": str(cache_path),
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "learning_rate": args.learning_rate,
        "weight_decay": args.weight_decay,
        "seed": args.seed,
        "device": train_outputs["device"],
        "feature_dim": int(dataset["features"].shape[1]),
        "segments": int(dataset["features"].shape[0]),
        "train_segments": int(split["train_mask"].sum()),
        "val_segments": int(split["val_mask"].sum()),
        "test_segments": int(split["test_mask"].sum()),
    }
    (run_dir / "config.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    (run_dir / "metrics.json").write_text(json.dumps(train_outputs["metrics"], ensure_ascii=False, indent=2), encoding="utf-8")
    write_split_summary(dataset, split, run_dir / "split_summary.csv")

    torch.save(train_outputs["checkpoint"], run_dir / "model.pt")

    print(json.dumps(
        {
            "run_dir": str(run_dir),
            "cache_path": str(cache_path),
            "best_epoch": train_outputs["best_epoch"],
            "val_metrics": train_outputs["metrics"]["best_val"],
            "test_metrics": train_outputs["metrics"]["test"],
        },
        ensure_ascii=False,
        indent=2,
    ))
    return 0


def ensure_manifest(
    source_root: Path,
    prepared_root: Path,
    manifest_path: Path,
    ffprobe_bin: str,
) -> None:
    if manifest_path.exists():
        return

    items = discover_items(
        source_root=source_root,
        ffprobe_bin=ffprobe_bin,
        limit=None,
        selected_games=None,
    )
    if not items:
        raise RuntimeError(f"No media files found under {source_root}")

    write_manifests(items, prepared_root)


def load_source_lookup(manifest_path: Path) -> dict[str, dict[str, str]]:
    lookup: dict[str, dict[str, str]] = {}
    with manifest_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            lookup[row["dataset_id"]] = row
    return lookup


def load_segment_records(
    annotation_root: Path,
    source_lookup: dict[str, dict[str, str]],
    *,
    max_files: int | None,
) -> list[SegmentRecord]:
    records: list[SegmentRecord] = []
    files = sorted(
        path for path in annotation_root.rglob("*.csv")
        if path.is_file() and not path.name.startswith(".")
    )
    if max_files is not None:
        files = files[:max_files]

    for annotation_path in files:
        dataset_id = annotation_path.stem
        if dataset_id not in source_lookup:
            continue
        source_row = source_lookup[dataset_id]
        with annotation_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            missing = [column for column in ANNOTATION_COLUMNS if column not in reader.fieldnames]
            if missing:
                raise RuntimeError(f"{annotation_path} is missing columns: {missing}")
            for row in reader:
                start_ms = int(float(row["start_ms"]))
                end_ms = int(float(row["end_ms"]))
                if end_ms <= start_ms:
                    continue
                records.append(
                    SegmentRecord(
                        dataset_id=dataset_id,
                        game=source_row["game"],
                        source_path=source_row["source_path"],
                        start_ms=start_ms,
                        end_ms=end_ms,
                        dominant_source=row["dominant_source"],
                        music_suppress=int(row["music_suppress"]),
                        impact_strength=int(row["impact_strength"]),
                        movement_strength=int(row["movement_strength"]),
                        sustain_strength=int(row["sustain_strength"]),
                        confidence=int(row.get("confidence", "3") or "3"),
                    )
                )
    return records


def load_feature_cache(cache_path: Path) -> dict[str, np.ndarray]:
    with np.load(cache_path, allow_pickle=True) as payload:
        return {key: payload[key] for key in payload.files}


def save_feature_cache(cache_path: Path, dataset: dict[str, np.ndarray]) -> None:
    np.savez(
        cache_path,
        **dataset,
    )


def is_feature_cache_compatible(
    dataset: dict[str, np.ndarray],
    records: list[SegmentRecord],
) -> bool:
    if "features" not in dataset or "dataset_ids" not in dataset:
        return False
    if int(dataset["features"].shape[0]) != len(records):
        return False

    cache_counts = Counter(dataset["dataset_ids"].tolist())
    record_counts = Counter(record.dataset_id for record in records)
    return cache_counts == record_counts


def build_feature_dataset(
    *,
    records: list[SegmentRecord],
    ffmpeg_bin: str,
    sample_rate: int,
    n_fft: int,
    win_length: int,
    hop_length: int,
    n_mels: int,
) -> dict[str, np.ndarray]:
    grouped_records: dict[str, list[SegmentRecord]] = defaultdict(list)
    source_paths: dict[str, str] = {}
    for record in records:
        grouped_records[record.dataset_id].append(record)
        source_paths[record.dataset_id] = record.source_path

    mel_filter = build_mel_filterbank(
        sample_rate=sample_rate,
        n_fft=n_fft,
        n_mels=n_mels,
        f_min=20.0,
        f_max=sample_rate / 2,
    )

    feature_chunks: list[np.ndarray] = []
    dominant_targets: list[int] = []
    music_targets: list[int] = []
    impact_targets: list[int] = []
    movement_targets: list[int] = []
    sustain_targets: list[int] = []
    confidence_values: list[float] = []
    dataset_ids: list[str] = []
    games: list[str] = []

    dominant_vocab = sorted({record.dominant_source for record in records})
    dominant_to_index = {label: index for index, label in enumerate(dominant_vocab)}

    for dataset_id in sorted(grouped_records.keys()):
        file_records = grouped_records[dataset_id]
        waveform = decode_audio_file(
            source_path=Path(source_paths[dataset_id]),
            ffmpeg_bin=ffmpeg_bin,
            sample_rate=sample_rate,
        )
        file_features = compute_file_features(
            waveform=waveform,
            sample_rate=sample_rate,
            n_fft=n_fft,
            win_length=win_length,
            hop_length=hop_length,
            mel_filter=mel_filter,
        )
        for record in file_records:
            feature_vector = summarize_segment_features(
                file_features=file_features,
                start_ms=record.start_ms,
                end_ms=record.end_ms,
                sample_rate=sample_rate,
                hop_length=hop_length,
            )
            feature_chunks.append(feature_vector.astype(np.float32, copy=False))
            dominant_targets.append(dominant_to_index[record.dominant_source])
            music_targets.append(record.music_suppress)
            impact_targets.append(record.impact_strength)
            movement_targets.append(record.movement_strength)
            sustain_targets.append(record.sustain_strength)
            confidence_values.append(confidence_to_weight(record.confidence))
            dataset_ids.append(record.dataset_id)
            games.append(record.game)

    return {
        "features": np.stack(feature_chunks).astype(np.float32, copy=False),
        "dominant_source": np.asarray(dominant_targets, dtype=np.int64),
        "music_suppress": np.asarray(music_targets, dtype=np.int64),
        "impact_strength": np.asarray(impact_targets, dtype=np.int64),
        "movement_strength": np.asarray(movement_targets, dtype=np.int64),
        "sustain_strength": np.asarray(sustain_targets, dtype=np.int64),
        "sample_weights": np.asarray(confidence_values, dtype=np.float32),
        "dataset_ids": np.asarray(dataset_ids, dtype="<U64"),
        "games": np.asarray(games, dtype="<U32"),
        "dominant_source_vocab": np.asarray(dominant_vocab, dtype="<U32"),
    }


def decode_audio_file(source_path: Path, ffmpeg_bin: str, sample_rate: int) -> np.ndarray:
    command = [
        ffmpeg_bin,
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(source_path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-f",
        "f32le",
        "-acodec",
        "pcm_f32le",
        "-",
    ]
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    waveform = np.frombuffer(result.stdout, dtype=np.float32).copy()
    if waveform.size == 0:
        raise RuntimeError(f"Decoded empty waveform from {source_path}")
    return waveform


def compute_file_features(
    *,
    waveform: np.ndarray,
    sample_rate: int,
    n_fft: int,
    win_length: int,
    hop_length: int,
    mel_filter: np.ndarray,
) -> dict[str, np.ndarray]:
    _, _, stft_matrix = stft(
        waveform,
        fs=sample_rate,
        nperseg=win_length,
        noverlap=win_length - hop_length,
        nfft=n_fft,
        padded=False,
        boundary=None,
    )
    power = np.abs(stft_matrix).astype(np.float32) ** 2
    mel_power = mel_filter @ power
    log_mel = np.log(mel_power + 1e-6).astype(np.float32)
    rms = np.sqrt(np.maximum(power.mean(axis=0), 1e-8)).astype(np.float32)

    delta = np.diff(log_mel, axis=1, prepend=log_mel[:, :1])
    spectral_flux = np.sqrt(np.maximum(delta, 0).sum(axis=0)).astype(np.float32)

    freq_bins = np.linspace(0.0, sample_rate / 2, power.shape[0], dtype=np.float32)
    low_mask = freq_bins < 180
    mid_mask = (freq_bins >= 180) & (freq_bins < 2200)
    high_mask = freq_bins >= 2200
    low_band = np.log(power[low_mask].mean(axis=0) + 1e-6).astype(np.float32)
    mid_band = np.log(power[mid_mask].mean(axis=0) + 1e-6).astype(np.float32)
    high_band = np.log(power[high_mask].mean(axis=0) + 1e-6).astype(np.float32)

    return {
        "log_mel": log_mel,
        "rms": rms,
        "spectral_flux": spectral_flux,
        "low_band": low_band,
        "mid_band": mid_band,
        "high_band": high_band,
    }


def summarize_segment_features(
    *,
    file_features: dict[str, np.ndarray],
    start_ms: int,
    end_ms: int,
    sample_rate: int,
    hop_length: int,
) -> np.ndarray:
    start_frame = max(0, int(math.floor((start_ms / 1000.0) * sample_rate / hop_length)))
    end_frame = max(start_frame + 1, int(math.ceil((end_ms / 1000.0) * sample_rate / hop_length)))

    log_mel = slice_frames(file_features["log_mel"], start_frame, end_frame)
    rms = slice_frames(file_features["rms"], start_frame, end_frame)
    flux = slice_frames(file_features["spectral_flux"], start_frame, end_frame)
    low_band = slice_frames(file_features["low_band"], start_frame, end_frame)
    mid_band = slice_frames(file_features["mid_band"], start_frame, end_frame)
    high_band = slice_frames(file_features["high_band"], start_frame, end_frame)

    duration_seconds = (end_ms - start_ms) / 1000.0
    summary = np.concatenate(
        [
            log_mel.mean(axis=1),
            log_mel.std(axis=1),
            log_mel.max(axis=1),
            np.asarray(
                [
                    duration_seconds,
                    rms.mean(),
                    rms.std(),
                    rms.max(),
                    flux.mean(),
                    flux.max(),
                    low_band.mean(),
                    mid_band.mean(),
                    high_band.mean(),
                    low_band.std(),
                    mid_band.std(),
                    high_band.std(),
                ],
                dtype=np.float32,
            ),
        ]
    )
    return np.nan_to_num(summary, nan=0.0, posinf=0.0, neginf=0.0).astype(np.float32)


def slice_frames(array: np.ndarray, start_frame: int, end_frame: int) -> np.ndarray:
    if array.ndim == 2:
        if start_frame >= array.shape[1]:
            start_frame = max(0, array.shape[1] - 1)
        end_frame = min(max(end_frame, start_frame + 1), array.shape[1])
        return array[:, start_frame:end_frame]

    if start_frame >= array.shape[0]:
        start_frame = max(0, array.shape[0] - 1)
    end_frame = min(max(end_frame, start_frame + 1), array.shape[0])
    return array[start_frame:end_frame]


def build_mel_filterbank(
    *,
    sample_rate: int,
    n_fft: int,
    n_mels: int,
    f_min: float,
    f_max: float,
) -> np.ndarray:
    def hz_to_mel(frequency: float) -> float:
        return 2595.0 * math.log10(1.0 + frequency / 700.0)

    def mel_to_hz(mel: float) -> float:
        return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

    mel_min = hz_to_mel(f_min)
    mel_max = hz_to_mel(f_max)
    mel_points = np.linspace(mel_min, mel_max, n_mels + 2, dtype=np.float32)
    hz_points = np.asarray([mel_to_hz(value) for value in mel_points], dtype=np.float32)
    fft_freqs = np.linspace(0.0, sample_rate / 2, n_fft // 2 + 1, dtype=np.float32)

    filters = np.zeros((n_mels, fft_freqs.shape[0]), dtype=np.float32)
    for mel_index in range(n_mels):
        left = hz_points[mel_index]
        center = hz_points[mel_index + 1]
        right = hz_points[mel_index + 2]

        left_slope = (fft_freqs - left) / max(center - left, 1e-6)
        right_slope = (right - fft_freqs) / max(right - center, 1e-6)
        filters[mel_index] = np.maximum(0.0, np.minimum(left_slope, right_slope))

    filters /= np.maximum(filters.sum(axis=1, keepdims=True), 1e-6)
    return filters


def confidence_to_weight(confidence: int) -> float:
    return {
        1: 0.6,
        2: 0.8,
        3: 1.0,
    }.get(confidence, 0.8)


def build_file_level_split(dataset_ids: np.ndarray, games: np.ndarray, seed: int) -> dict[str, np.ndarray]:
    rng = random.Random(seed)
    file_to_game: dict[str, str] = {}
    for dataset_id, game in zip(dataset_ids.tolist(), games.tolist()):
        file_to_game.setdefault(dataset_id, game)

    by_game: dict[str, list[str]] = defaultdict(list)
    for dataset_id, game in file_to_game.items():
        by_game[game].append(dataset_id)

    train_files: set[str] = set()
    val_files: set[str] = set()
    test_files: set[str] = set()
    for game, file_ids in by_game.items():
        rng.shuffle(file_ids)
        total = len(file_ids)
        val_count = max(1, round(total * 0.10))
        test_count = max(1, round(total * 0.10))
        if total - val_count - test_count < 1:
            test_count = 1
            val_count = max(1, total - test_count - 1)

        val_files.update(file_ids[:val_count])
        test_files.update(file_ids[val_count:val_count + test_count])
        train_files.update(file_ids[val_count + test_count:])

    train_mask = np.asarray([dataset_id in train_files for dataset_id in dataset_ids], dtype=bool)
    val_mask = np.asarray([dataset_id in val_files for dataset_id in dataset_ids], dtype=bool)
    test_mask = np.asarray([dataset_id in test_files for dataset_id in dataset_ids], dtype=bool)
    return {
        "train_mask": train_mask,
        "val_mask": val_mask,
        "test_mask": test_mask,
    }


def resolve_device(device_override: str | None) -> torch.device:
    if device_override:
        return torch.device(device_override)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def train_model(
    *,
    dataset: dict[str, np.ndarray],
    split: dict[str, np.ndarray],
    device: torch.device,
    epochs: int,
    batch_size: int,
    learning_rate: float,
    weight_decay: float,
    run_dir: Path,
    seed: int,
) -> dict[str, object]:
    features = dataset["features"]
    train_mask = split["train_mask"]
    val_mask = split["val_mask"]
    test_mask = split["test_mask"]

    train_features = features[train_mask]
    val_features = features[val_mask]
    test_features = features[test_mask]

    mean = train_features.mean(axis=0, keepdims=True).astype(np.float32)
    std = train_features.std(axis=0, keepdims=True).astype(np.float32)
    std = np.where(std < 1e-5, 1.0, std)

    norm_features = ((features - mean) / std).astype(np.float32)

    targets = {task: dataset[task] for task in TASK_COLUMNS}
    train_dataset = ArrayDataset(
        features=norm_features[train_mask],
        targets={task: values[train_mask] for task, values in targets.items()},
        sample_weights=dataset["sample_weights"][train_mask],
    )
    val_dataset = ArrayDataset(
        features=norm_features[val_mask],
        targets={task: values[val_mask] for task, values in targets.items()},
        sample_weights=dataset["sample_weights"][val_mask],
    )
    test_dataset = ArrayDataset(
        features=norm_features[test_mask],
        targets={task: values[test_mask] for task, values in targets.items()},
        sample_weights=dataset["sample_weights"][test_mask],
    )

    generator = torch.Generator()
    generator.manual_seed(seed)
    train_loader = torch.utils.data.DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=0,
        generator=generator,
    )
    val_loader = torch.utils.data.DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=0,
    )
    test_loader = torch.utils.data.DataLoader(
        test_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=0,
    )

    model = MultiTaskMLP(
        input_dim=norm_features.shape[1],
        dominant_classes=len(dataset["dominant_source_vocab"]),
    ).to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=learning_rate, weight_decay=weight_decay)

    train_class_weights = {
        task: build_class_weights(dataset[task][train_mask], num_classes=len(dataset["dominant_source_vocab"]) if task == "dominant_source" else 4).to(device)
        for task in TASK_COLUMNS
    }

    best_state = None
    best_epoch = 0
    best_score = -float("inf")
    history: list[dict[str, float]] = []

    for epoch in range(1, epochs + 1):
        train_loss = run_epoch(
            model=model,
            loader=train_loader,
            optimizer=optimizer,
            device=device,
            class_weights=train_class_weights,
            training=True,
        )
        val_metrics = evaluate(model, val_loader, device, dataset["dominant_source_vocab"])
        history.append({"epoch": epoch, "train_loss": train_loss, **flatten_metrics("val", val_metrics)})
        val_score = (
            val_metrics["dominant_source_accuracy"] +
            val_metrics["music_suppress_accuracy"] +
            val_metrics["impact_strength_accuracy"] +
            val_metrics["movement_strength_accuracy"] +
            val_metrics["sustain_strength_accuracy"]
        ) / 5.0
        if val_score > best_score:
            best_score = val_score
            best_epoch = epoch
            best_state = {key: value.detach().cpu() for key, value in model.state_dict().items()}

    assert best_state is not None
    model.load_state_dict(best_state)

    best_val_metrics = evaluate(model, val_loader, device, dataset["dominant_source_vocab"])
    test_metrics = evaluate(model, test_loader, device, dataset["dominant_source_vocab"])

    pd.DataFrame(history).to_csv(run_dir / "history.csv", index=False)

    checkpoint = {
        "model_state_dict": best_state,
        "feature_mean": mean,
        "feature_std": std,
        "dominant_source_vocab": dataset["dominant_source_vocab"].tolist(),
        "config": {
            "input_dim": int(norm_features.shape[1]),
            "tasks": TASK_COLUMNS,
        },
    }

    return {
        "device": str(device),
        "best_epoch": best_epoch,
        "checkpoint": checkpoint,
        "metrics": {
            "best_val": best_val_metrics,
            "test": test_metrics,
        },
    }


def build_class_weights(targets: np.ndarray, num_classes: int) -> torch.Tensor:
    counts = np.bincount(targets.astype(np.int64), minlength=num_classes).astype(np.float32)
    weights = counts.sum() / np.maximum(counts, 1.0)
    weights = np.sqrt(weights)
    weights /= weights.mean()
    return torch.from_numpy(weights.astype(np.float32))


def run_epoch(
    *,
    model: nn.Module,
    loader: torch.utils.data.DataLoader,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
    class_weights: dict[str, torch.Tensor],
    training: bool,
) -> float:
    model.train(training)
    total_loss = 0.0
    total_examples = 0
    for features, targets, sample_weights in loader:
        features = features.to(device)
        sample_weights = sample_weights.to(device)
        targets = {key: value.to(device) for key, value in targets.items()}

        if training:
            optimizer.zero_grad(set_to_none=True)

        logits = model(features)
        losses = []
        for task in TASK_COLUMNS:
            per_sample = F.cross_entropy(
                logits[task],
                targets[task],
                weight=class_weights[task],
                reduction="none",
            )
            losses.append((per_sample * sample_weights).mean())
        loss = sum(losses) / len(losses)

        if training:
            loss.backward()
            optimizer.step()

        batch_size = features.shape[0]
        total_loss += float(loss.detach().cpu()) * batch_size
        total_examples += batch_size

    return total_loss / max(total_examples, 1)


@torch.no_grad()
def evaluate(
    model: nn.Module,
    loader: torch.utils.data.DataLoader,
    device: torch.device,
    dominant_vocab: np.ndarray,
) -> dict[str, float]:
    model.eval()
    collected_targets: dict[str, list[np.ndarray]] = {task: [] for task in TASK_COLUMNS}
    collected_predictions: dict[str, list[np.ndarray]] = {task: [] for task in TASK_COLUMNS}

    for features, targets, _sample_weights in loader:
        features = features.to(device)
        logits = model(features)
        for task in TASK_COLUMNS:
            prediction = torch.argmax(logits[task], dim=1).cpu().numpy()
            collected_predictions[task].append(prediction)
            collected_targets[task].append(targets[task].numpy())

    metrics: dict[str, float] = {}
    for task in TASK_COLUMNS:
        y_true = np.concatenate(collected_targets[task], axis=0)
        y_pred = np.concatenate(collected_predictions[task], axis=0)
        metrics[f"{task}_accuracy"] = float(accuracy_score(y_true, y_pred))

    dominant_true = np.concatenate(collected_targets["dominant_source"], axis=0)
    dominant_pred = np.concatenate(collected_predictions["dominant_source"], axis=0)
    metrics["dominant_source_macro_f1"] = float(
        f1_score(dominant_true, dominant_pred, average="macro")
    )
    metrics["dominant_source_classes"] = {
        label: int(index) for index, label in enumerate(dominant_vocab.tolist())
    }
    return metrics


def build_run_dir(prepared_root: Path, run_name: str | None) -> Path:
    if run_name:
        return prepared_root / "training_runs" / run_name
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    return prepared_root / "training_runs" / f"run-{timestamp}"


def flatten_metrics(prefix: str, metrics: dict[str, float]) -> dict[str, float]:
    return {
        f"{prefix}_{key}": value
        for key, value in metrics.items()
        if isinstance(value, (int, float))
    }


def write_split_summary(dataset: dict[str, np.ndarray], split: dict[str, np.ndarray], output_path: Path) -> None:
    rows = []
    for split_name, mask_key in [("train", "train_mask"), ("val", "val_mask"), ("test", "test_mask")]:
        mask = split[mask_key]
        unique_files = sorted(set(dataset["dataset_ids"][mask].tolist()))
        rows.append(
            {
                "split": split_name,
                "segments": int(mask.sum()),
                "files": len(unique_files),
            }
        )
    pd.DataFrame(rows).to_csv(output_path, index=False)


if __name__ == "__main__":
    raise SystemExit(main())
