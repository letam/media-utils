# Video Compression — Work Report

**Created:** 2026-04-24 13:15 EDT
**Target:** `files/meeting-2026-04-24.mov` (screen recording of a meeting)

## Goal

Build a reusable script to compress large meeting screen recordings and apply it to the 4.8 GB source file.

## Deliverable

`scripts/compress_video.sh` — bash script in the same style as the existing `scripts/reduce_photo_size.sh`.

### Usage

```
./scripts/compress_video.sh [options] <file-or-folder>
```

| Flag | Default | Meaning |
|------|---------|---------|
| `-c CRF` | `28` | Constant Rate Factor (lower = higher quality, bigger file) |
| `-r FPS` | `30` | Output frame rate |
| `-w WIDTH` | `1920` | Max width in px (keeps aspect, ensures even dims) |
| `-x CODEC` | `h265` | `h265` or `h264` |
| `-p PRESET` | `medium` | ffmpeg preset (`ultrafast`..`veryslow`) |
| `-a RATE` | `96k` | Audio bitrate |
| `-m` | off | Force mono audio |
| `-n` | off | Dry-run, print the ffmpeg command only |

Outputs land in a `compressed/` subfolder next to the input; originals are untouched.

## Source file details

| Attribute | Value |
|---|---|
| Size | 4806 MB (≈4.8 GB) |
| Duration | 13:02 |
| Resolution | 3024 × 1964 |
| Frame rate | 60 fps |
| Video codec | H.264 |
| Video bitrate | ~49.8 Mbps |
| Audio | AAC, 388 kbps |

## Result

| Attribute | Value |
|---|---|
| Output file | `files/compressed/meeting-2026-04-24.mp4` |
| Size | 41 MB |
| Reduction | **~99.2% (≈120× smaller)** |
| Resolution | 1920 × 1247 (scaled, aspect preserved) |
| Frame rate | 30 fps |
| Video codec | HEVC (libx265), tagged `hvc1` |
| Audio | AAC 96 kbps stereo |
| Encode time | ~4 min on this machine |

## Findings / Gotchas

### 1. QuickTime wouldn't play libx265 output (fixed)

**Symptom:** First output opened in VLC but showed no video in QuickTime.

**Cause:** By default, ffmpeg's `libx265` muxes the HEVC stream with the `hev1` codec tag. Apple's media frameworks (QuickTime, Preview, Finder previews) only render HEVC-in-MP4 when tagged `hvc1`. The streams are byte-identical — only the FourCC in the container differs.

**Fix:** Added `-tag:v hvc1` when the codec is HEVC. No effect for H.264.

**Re-muxing existing files** (no re-encode needed):
```
ffmpeg -i in.mp4 -c copy -tag:v hvc1 -movflags +faststart out.mp4
```

### 2. File extension cleanup

Initial script produced `name.hevc.mp4` — the `.hevc` was a codec label, not a real extension. The container is MP4, so the filename should just be `.mp4`. Script now writes `name.mp4` regardless of codec.

### 3. `set -u` + empty bash arrays

With `set -euo pipefail`, expanding an empty array as `"${arr[@]}"` triggers "unbound variable". Use the `${arr[@]+"${arr[@]}"}` idiom to expand-if-set. This matters for the optional `-ac 1` (mono) and `-tag:v hvc1` flags, which are appended as arrays.

### 4. Why the compression ratio is so extreme

Screen recordings compress very well with modern codecs:

- Dropping 60 → 30 fps halves the frame count.
- Scaling 3024px → 1920px wide cuts pixel count by ~60%.
- H.264 → H.265 is roughly 2× more efficient at equal quality.
- The source was nearly lossless (~50 Mbps); CRF 28 is visually close to transparent for screen content but a fraction of that bitrate.

Combined, 49.8 Mbps → ~440 kbps is plausible without visible degradation for a talking-head + slides meeting.

## Recommended tuning

- **Smaller still:** `-c 32 -w 1440 -r 15` — acceptable for audio-first review.
- **Higher quality:** `-c 23` — noticeably crisper text, maybe 3–4× the size.
- **Broad compatibility** (older devices, web players without HEVC): `-x h264` — files will be ~1.5–2× larger than h265 at equivalent quality.
- **Speech-only meetings:** add `-m -a 64k` to halve audio size.

## Follow-up

Spot-check the 41 MB output for audio intelligibility and on-screen text legibility. If either is marginal, re-encode with `-c 23` or `-w 2560`.
