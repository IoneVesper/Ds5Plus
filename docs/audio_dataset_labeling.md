# Audio Dataset Labeling

This project can train better game-audio recognition if each downloaded source
file has a matching annotation CSV that marks useful time ranges.

## Recommended Flow

1. Run `scripts/prepare_audio_dataset.py` to scan the source videos, extract
   `48 kHz` stereo WAV files, and create empty CSV templates.
2. Open one generated WAV file in Audacity.
3. Listen and mark meaningful ranges.
4. Fill one row per range in the matching CSV file.
5. Keep labels focused on haptic usefulness, not on fine-grained sound names.

## Commands

Dry-run the catalog step:

```bash
python3 scripts/prepare_audio_dataset.py scan \
  --source-root "/Volumes/SSD/音频数据集"
```

Prepare the first 6 files as a small pilot:

```bash
python3 scripts/prepare_audio_dataset.py prepare \
  --source-root "/Volumes/SSD/音频数据集" \
  --output-root "/Volumes/SSD/音频数据集/prepared_dataset" \
  --limit 6 \
  --ffmpeg-bin /opt/homebrew/bin/ffmpeg \
  --ffprobe-bin /opt/homebrew/bin/ffprobe
```

Prepare the full three-game set:

```bash
python3 scripts/prepare_audio_dataset.py prepare \
  --source-root "/Volumes/SSD/音频数据集" \
  --output-root "/Volumes/SSD/音频数据集/prepared_dataset" \
  --games silksong,battlefield1,death_stranding_2 \
  --ffmpeg-bin /opt/homebrew/bin/ffmpeg \
  --ffprobe-bin /opt/homebrew/bin/ffprobe
```

## CSV Columns

Each row is one labeled time range.

| Column | Meaning |
| --- | --- |
| `start_ms` | Range start time in milliseconds |
| `end_ms` | Range end time in milliseconds |
| `dominant_source` | One of `music`, `impact`, `movement`, `ambient`, `ui`, `dialogue`, `mixed`, `silence` |
| `music_suppress` | 0-3, how strongly this range should be suppressed as background music |
| `impact_strength` | 0-3, how strongly this range should trigger impact haptics |
| `movement_strength` | 0-3, how strongly this range should trigger movement pulses |
| `sustain_strength` | 0-3, how strongly this range should drive sustained low-frequency rumble |
| `confidence` | 1-3, how sure you are about the label |
| `notes` | Short free-text note |

## Labeling Rules

- Label what should happen in haptics, not just what the sound is.
- Multi-label behavior is expected.
- Background music can coexist with impact events.
- Long music or ambience sections can use longer ranges.
- Short attacks or explosions should still include the attack and short tail.

## Example

```csv
start_ms,end_ms,dominant_source,music_suppress,impact_strength,movement_strength,sustain_strength,confidence,notes
0,2800,music,3,0,0,1,3,pure bgm intro
2800,3320,mixed,1,3,0,1,2,heavy attack over bgm
3320,4180,movement,0,0,2,1,2,footsteps
4180,5100,ambient,1,0,0,1,1,wind and room tone
```
