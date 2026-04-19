#!/usr/bin/env python3
"""Prepare game-audio training data from downloaded videos or audio files.

The script scans a source directory, extracts 48 kHz stereo WAV files, and
creates one CSV annotation template per source item.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".webm", ".m4v"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg"}
ANNOTATION_HEADER = [
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


@dataclass(frozen=True)
class SourceItem:
    dataset_id: str
    game: str
    source_type: str
    source_path: Path
    subtitle_path: Path | None
    part_number: int | None
    duration_seconds: float

    def audio_output_path(self, output_root: Path) -> Path:
        return output_root / "audio" / self.game / f"{self.dataset_id}.wav"

    def annotation_output_path(self, output_root: Path) -> Path:
        return output_root / "annotations" / self.game / f"{self.dataset_id}.csv"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Scan downloaded gameplay files, extract WAV audio, and create "
            "annotation templates for model training."
        )
    )
    parser.add_argument(
        "command",
        choices=("scan", "extract", "templates", "prepare"),
        help="Which step to run.",
    )
    parser.add_argument(
        "--source-root",
        default="/Volumes/SSD/音频数据集",
        help="Directory containing downloaded videos or audio files.",
    )
    parser.add_argument(
        "--output-root",
        help=(
            "Directory for generated manifests, WAV files, and annotation CSVs. "
            "Defaults to '<source-root>/prepared_dataset'."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Process only the first N discovered files after sorting.",
    )
    parser.add_argument(
        "--games",
        help="Comma-separated filter, for example 'silksong,battlefield1'.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing extracted WAVs and annotation templates.",
    )
    parser.add_argument(
        "--ffmpeg-bin",
        default="ffmpeg",
        help="Path to ffmpeg.",
    )
    parser.add_argument(
        "--ffprobe-bin",
        default="ffprobe",
        help="Path to ffprobe.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_root = Path(args.source_root).expanduser().resolve()
    output_root = (
        Path(args.output_root).expanduser().resolve()
        if args.output_root
        else source_root / "prepared_dataset"
    )

    selected_games = None
    if args.games:
        selected_games = {
            game.strip() for game in args.games.split(",") if game.strip()
        }

    items = discover_items(
        source_root=source_root,
        ffprobe_bin=args.ffprobe_bin,
        limit=args.limit,
        selected_games=selected_games,
    )
    if not items:
        print("No matching media files were found.", file=sys.stderr)
        return 1

    write_manifests(items, output_root)

    if args.command in {"extract", "prepare"}:
        extract_audio(items, output_root, args.ffmpeg_bin, force=args.force)
    if args.command in {"templates", "prepare"}:
        create_annotation_templates(items, output_root, force=args.force)

    print_summary(items, output_root, args.command)
    return 0


def discover_items(
    source_root: Path,
    ffprobe_bin: str,
    limit: int | None,
    selected_games: set[str] | None,
) -> list[SourceItem]:
    media_paths = sorted(
        path
        for path in source_root.rglob("*")
        if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS.union(AUDIO_EXTENSIONS)
    )

    grouped_indices: dict[str, int] = {}
    items: list[SourceItem] = []
    for media_path in media_paths:
        game = infer_game(media_path.name)
        if selected_games and game not in selected_games:
            continue

        grouped_indices[game] = grouped_indices.get(game, 0) + 1
        item = SourceItem(
            dataset_id=build_dataset_id(media_path, game, grouped_indices[game]),
            game=game,
            source_type="video" if media_path.suffix.lower() in VIDEO_EXTENSIONS else "audio",
            source_path=media_path,
            subtitle_path=find_matching_subtitle(media_path),
            part_number=infer_part_number(media_path.name),
            duration_seconds=probe_duration_seconds(media_path, ffprobe_bin),
        )
        items.append(item)
        if limit is not None and len(items) >= limit:
            break

    return items


def infer_game(file_name: str) -> str:
    if "丝之歌" in file_name:
        return "silksong"
    if "战地1" in file_name:
        return "battlefield1"
    if "死亡搁浅2" in file_name or "Death Stranding2" in file_name:
        return "death_stranding_2"
    return "unknown"


def infer_part_number(file_name: str) -> int | None:
    match = re.search(r"\s-\s(\d{1,3})\s-\s", file_name)
    if match:
        return int(match.group(1))
    return None


def build_dataset_id(media_path: Path, game: str, ordinal: int) -> str:
    fingerprint = hashlib.sha1(str(media_path).encode("utf-8")).hexdigest()[:8]
    part_number = infer_part_number(media_path.name)
    if part_number is not None:
        return f"{game}_{part_number:03d}_{fingerprint}"
    return f"{game}_x{ordinal:03d}_{fingerprint}"


def find_matching_subtitle(media_path: Path) -> Path | None:
    subtitle_path = media_path.with_suffix(".srt")
    return subtitle_path if subtitle_path.exists() else None


def probe_duration_seconds(media_path: Path, ffprobe_bin: str) -> float:
    command = [
        ffprobe_bin,
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "json",
        str(media_path),
    ]
    result = run_command(command, capture_output=True)
    payload = json.loads(result.stdout)
    return float(payload["format"]["duration"])


def write_manifests(items: Iterable[SourceItem], output_root: Path) -> None:
    manifest_dir = output_root / "manifests"
    manifest_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for item in items:
        rows.append(
            {
                "dataset_id": item.dataset_id,
                "game": item.game,
                "source_type": item.source_type,
                "part_number": item.part_number or "",
                "duration_seconds": f"{item.duration_seconds:.3f}",
                "source_path": str(item.source_path),
                "subtitle_path": str(item.subtitle_path) if item.subtitle_path else "",
                "audio_output_path": str(item.audio_output_path(output_root)),
                "annotation_output_path": str(item.annotation_output_path(output_root)),
            }
        )

    csv_path = manifest_dir / "sources.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    jsonl_path = manifest_dir / "sources.jsonl"
    with jsonl_path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def extract_audio(
    items: Iterable[SourceItem],
    output_root: Path,
    ffmpeg_bin: str,
    *,
    force: bool,
) -> None:
    for item in items:
        audio_path = item.audio_output_path(output_root)
        audio_path.parent.mkdir(parents=True, exist_ok=True)
        if audio_path.exists() and not force:
            continue

        command = [
            ffmpeg_bin,
            "-hide_banner",
            "-loglevel",
            "warning",
            "-y" if force else "-n",
            "-i",
            str(item.source_path),
            "-vn",
            "-ac",
            "2",
            "-ar",
            "48000",
            "-c:a",
            "pcm_s16le",
            str(audio_path),
        ]
        run_command(command, capture_output=False)


def create_annotation_templates(
    items: Iterable[SourceItem],
    output_root: Path,
    *,
    force: bool,
) -> None:
    for item in items:
        annotation_path = item.annotation_output_path(output_root)
        annotation_path.parent.mkdir(parents=True, exist_ok=True)
        if annotation_path.exists() and not force:
            continue

        with annotation_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(ANNOTATION_HEADER)


def run_command(command: list[str], *, capture_output: bool) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=True,
        text=True,
        capture_output=capture_output,
    )


def print_summary(items: list[SourceItem], output_root: Path, command: str) -> None:
    total_duration_seconds = sum(item.duration_seconds for item in items)
    by_game: dict[str, int] = {}
    for item in items:
        by_game[item.game] = by_game.get(item.game, 0) + 1

    print(f"Prepared {len(items)} source items with command '{command}'.")
    print(f"Output root: {output_root}")
    print(f"Total source duration: {total_duration_seconds / 3600:.2f} hours")
    for game, count in sorted(by_game.items()):
        print(f"  - {game}: {count} files")
    print(f"Manifest: {output_root / 'manifests' / 'sources.csv'}")


if __name__ == "__main__":
    raise SystemExit(main())
