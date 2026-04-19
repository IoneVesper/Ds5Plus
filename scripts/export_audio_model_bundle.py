#!/usr/bin/env python3
"""Export the lightweight PyTorch checkpoint into a Swift-friendly JSON bundle."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch

from train_audio_mlp import (
    MultiTaskMLP,
    build_mel_filterbank,
    compute_file_features,
    summarize_segment_features,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export model.pt into a Swift-friendly JSON asset.")
    parser.add_argument(
        "--checkpoint",
        default="/Volumes/SSD/音频数据集/prepared_dataset/training_runs/full-mps-baseline/model.pt",
        help="Path to the model.pt checkpoint.",
    )
    parser.add_argument(
        "--output",
        default="Ds5plus/Resources/AudioSemanticModel.json",
        help="Output JSON path inside the app bundle.",
    )
    parser.add_argument(
        "--analysis-window-seconds",
        type=float,
        default=1.0,
        help="Trailing audio window used for runtime feature extraction.",
    )
    parser.add_argument(
        "--runtime-update-interval-seconds",
        type=float,
        default=0.12,
        help="How often the macOS runtime should refresh ML inference.",
    )
    return parser.parse_args()


def gelu(values: np.ndarray) -> np.ndarray:
    return 0.5 * values * (1.0 + np.erf(values / math.sqrt(2.0)))


def softmax(values: np.ndarray) -> np.ndarray:
    shifted = values - np.max(values)
    exp_values = np.exp(shifted)
    return exp_values / np.maximum(exp_values.sum(), 1e-8)


def expected_class_probability(logits: np.ndarray) -> float:
    probabilities = softmax(logits)
    class_ids = np.arange(len(probabilities), dtype=np.float32)
    return float(np.dot(probabilities, class_ids) / max(len(probabilities) - 1, 1))


def summarize_prediction(
    logits: dict[str, torch.Tensor],
    dominant_source_vocab: list[str],
) -> dict[str, float | list[float]]:
    dominant_logits = np.asarray(logits["dominant_source"].squeeze(0), dtype=np.float32)
    dominant_probabilities = softmax(dominant_logits)
    dominant_by_name = {
        name: float(dominant_probabilities[index])
        for index, name in enumerate(dominant_source_vocab)
    }
    return {
        "dominantSourceLogits": dominant_logits.tolist(),
        "musicSuppressLogits": np.asarray(logits["music_suppress"].squeeze(0), dtype=np.float32).tolist(),
        "impactStrengthLogits": np.asarray(logits["impact_strength"].squeeze(0), dtype=np.float32).tolist(),
        "movementStrengthLogits": np.asarray(logits["movement_strength"].squeeze(0), dtype=np.float32).tolist(),
        "sustainStrengthLogits": np.asarray(logits["sustain_strength"].squeeze(0), dtype=np.float32).tolist(),
        "dominantSourceProbabilities": dominant_probabilities.tolist(),
        "musicSuppressExpected": expected_class_probability(np.asarray(logits["music_suppress"].squeeze(0), dtype=np.float32)),
        "impactStrengthExpected": expected_class_probability(np.asarray(logits["impact_strength"].squeeze(0), dtype=np.float32)),
        "movementStrengthExpected": expected_class_probability(np.asarray(logits["movement_strength"].squeeze(0), dtype=np.float32)),
        "sustainStrengthExpected": expected_class_probability(np.asarray(logits["sustain_strength"].squeeze(0), dtype=np.float32)),
        "dominantImpact": dominant_by_name.get("impact", 0.0),
        "dominantMixed": dominant_by_name.get("mixed", 0.0),
        "dominantMovement": dominant_by_name.get("movement", 0.0),
        "dominantMusic": dominant_by_name.get("music", 0.0),
        "dominantSilence": dominant_by_name.get("silence", 0.0),
    }


def build_runtime_reference(
    *,
    model: MultiTaskMLP,
    dominant_source_vocab: list[str],
    feature_mean: np.ndarray,
    feature_std: np.ndarray,
    sample_rate: int,
    n_fft: int,
    win_length: int,
    hop_length: int,
    n_mels: int,
) -> dict[str, object]:
    duration_seconds = 1.0
    sample_count = int(sample_rate * duration_seconds)
    time = np.arange(sample_count, dtype=np.float32) / np.float32(sample_rate)

    sine_components = [
        {"frequencyHz": 110.0, "amplitude": 0.30},
        {"frequencyHz": 440.0, "amplitude": 0.18},
        {"frequencyHz": 1760.0, "amplitude": 0.08},
    ]
    impulse_envelopes = [
        {"startSeconds": 0.12, "lengthSamples": 24, "peakAmplitude": 0.90},
        {"startSeconds": 0.37, "lengthSamples": 24, "peakAmplitude": 0.90},
        {"startSeconds": 0.63, "lengthSamples": 24, "peakAmplitude": 0.90},
        {"startSeconds": 0.81, "lengthSamples": 24, "peakAmplitude": 0.90},
    ]

    waveform = np.zeros(sample_count, dtype=np.float32)
    for component in sine_components:
        waveform += np.float32(component["amplitude"]) * np.sin(2.0 * math.pi * np.float32(component["frequencyHz"]) * time)
    for envelope in impulse_envelopes:
        start_sample = int(round(float(envelope["startSeconds"]) * sample_rate))
        length = int(envelope["lengthSamples"])
        end_sample = min(sample_count, start_sample + length)
        decay = np.linspace(
            float(envelope["peakAmplitude"]),
            0.0,
            max(end_sample - start_sample, 1),
            dtype=np.float32,
        )
        waveform[start_sample:end_sample] += decay[: max(end_sample - start_sample, 0)]
    waveform = np.clip(waveform, -1.0, 1.0)

    mel_filter = build_mel_filterbank(
        sample_rate=sample_rate,
        n_fft=n_fft,
        n_mels=n_mels,
        f_min=20.0,
        f_max=sample_rate / 2,
    ).astype(np.float32)
    file_features = compute_file_features(
        waveform=waveform,
        sample_rate=sample_rate,
        n_fft=n_fft,
        win_length=win_length,
        hop_length=hop_length,
        mel_filter=mel_filter,
    )
    feature_vector = summarize_segment_features(
        file_features=file_features,
        start_ms=0,
        end_ms=int(duration_seconds * 1000),
        sample_rate=sample_rate,
        hop_length=hop_length,
    ).astype(np.float32)
    normalized = (feature_vector - feature_mean) / np.where(feature_std < 1e-5, 1.0, feature_std)
    with torch.no_grad():
        runtime_logits = model(torch.from_numpy(normalized.reshape(1, -1)))

    prediction = summarize_prediction(runtime_logits, dominant_source_vocab)
    return {
        "sampleRate": sample_rate,
        "sampleCount": sample_count,
        "durationSeconds": duration_seconds,
        "sineComponents": sine_components,
        "impulseEnvelopes": impulse_envelopes,
        "prediction": {
            "dominantImpact": prediction["dominantImpact"],
            "dominantMixed": prediction["dominantMixed"],
            "dominantMovement": prediction["dominantMovement"],
            "dominantMusic": prediction["dominantMusic"],
            "dominantSilence": prediction["dominantSilence"],
            "musicSuppression": prediction["musicSuppressExpected"],
            "impactStrength": prediction["impactStrengthExpected"],
            "movementStrength": prediction["movementStrengthExpected"],
            "sustainStrength": prediction["sustainStrengthExpected"],
        },
    }


def main() -> int:
    args = parse_args()
    checkpoint_path = Path(args.checkpoint).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    state_dict = checkpoint["model_state_dict"]
    feature_mean = np.asarray(checkpoint["feature_mean"], dtype=np.float32).reshape(-1)
    feature_std = np.asarray(checkpoint["feature_std"], dtype=np.float32).reshape(-1)
    dominant_source_vocab = list(checkpoint["dominant_source_vocab"])

    model = MultiTaskMLP(
        input_dim=checkpoint["config"]["input_dim"],
        dominant_classes=len(dominant_source_vocab),
    )
    model.load_state_dict(state_dict)
    model.eval()

    sample_rate = 16_000
    n_fft = 512
    win_length = 400
    hop_length = 160
    n_mels = 48
    mel_filter = build_mel_filterbank(
        sample_rate=sample_rate,
        n_fft=n_fft,
        n_mels=n_mels,
        f_min=20.0,
        f_max=sample_rate / 2,
    ).astype(np.float32)
    analysis_window = np.hanning(win_length).astype(np.float32)

    reference_raw = feature_mean.astype(np.float32)
    normalized_reference = (reference_raw - feature_mean) / np.where(feature_std < 1e-5, 1.0, feature_std)
    reference_tensor = torch.from_numpy(normalized_reference.reshape(1, -1))
    with torch.no_grad():
        reference_logits = model(reference_tensor)

    reference_prediction = summarize_prediction(reference_logits, dominant_source_vocab)
    reference = {
        "rawFeatureVector": reference_raw.tolist(),
        "normalizedFeatureVector": normalized_reference.tolist(),
        **reference_prediction,
    }
    runtime_reference = build_runtime_reference(
        model=model,
        dominant_source_vocab=dominant_source_vocab,
        feature_mean=feature_mean,
        feature_std=feature_std,
        sample_rate=sample_rate,
        n_fft=n_fft,
        win_length=win_length,
        hop_length=hop_length,
        n_mels=n_mels,
    )

    payload = {
        "version": 1,
        "inputDimension": int(checkpoint["config"]["input_dim"]),
        "analysis": {
            "sampleRate": sample_rate,
            "nFFT": n_fft,
            "winLength": win_length,
            "hopLength": hop_length,
            "nMels": n_mels,
            "analysisWindowSeconds": float(args.analysis_window_seconds),
            "runtimeUpdateIntervalSeconds": float(args.runtime_update_interval_seconds),
            "analysisWindow": analysis_window.tolist(),
            "melFilterbankRows": int(mel_filter.shape[0]),
            "melFilterbankColumns": int(mel_filter.shape[1]),
            "melFilterbank": mel_filter.reshape(-1).tolist(),
        },
        "dominantSourceVocab": dominant_source_vocab,
        "featureMean": feature_mean.tolist(),
        "featureStd": feature_std.tolist(),
        "linear1": export_linear_layer(state_dict, "backbone.0"),
        "layerNorm1": export_layer_norm(state_dict, "backbone.1", epsilon=1e-5),
        "linear2": export_linear_layer(state_dict, "backbone.4"),
        "heads": {
            "dominant_source": export_linear_layer(state_dict, "dominant_head"),
            "music_suppress": export_linear_layer(state_dict, "music_head"),
            "impact_strength": export_linear_layer(state_dict, "impact_head"),
            "movement_strength": export_linear_layer(state_dict, "movement_head"),
            "sustain_strength": export_linear_layer(state_dict, "sustain_head"),
        },
        "reference": reference,
        "runtimeReference": runtime_reference,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(output_path)
    return 0


def export_linear_layer(state_dict: dict[str, torch.Tensor], prefix: str) -> dict[str, object]:
    weight = state_dict[f"{prefix}.weight"].detach().cpu().numpy().astype(np.float32)
    bias = state_dict[f"{prefix}.bias"].detach().cpu().numpy().astype(np.float32)
    return {
        "rows": int(weight.shape[0]),
        "columns": int(weight.shape[1]),
        "weights": weight.reshape(-1).tolist(),
        "bias": bias.tolist(),
    }


def export_layer_norm(
    state_dict: dict[str, torch.Tensor],
    prefix: str,
    *,
    epsilon: float,
) -> dict[str, object]:
    weight = state_dict[f"{prefix}.weight"].detach().cpu().numpy().astype(np.float32)
    bias = state_dict[f"{prefix}.bias"].detach().cpu().numpy().astype(np.float32)
    return {
        "dimension": int(weight.shape[0]),
        "weight": weight.tolist(),
        "bias": bias.tolist(),
        "epsilon": float(epsilon),
    }


if __name__ == "__main__":
    raise SystemExit(main())
