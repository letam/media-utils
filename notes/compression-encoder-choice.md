# compress_video.sh: software vs hardware encoder

Notes from the 2026-04-28 fan-noise investigation.

## Why this exists

`compress_video.sh` defaulted to `libx265 -preset medium`, which pegs
all CPU cores and runs the fans loud. We added VideoToolbox codec
options so encoding can move to the Apple Silicon media engine.

## Is the loud-fan version safe?

Yes. macOS thermal-throttles before damage, and sustained 100% CPU is
within the SoC's design envelope. The only real risk is blocked vents
(laptop on bedding, etc.). Fan noise = cooling working as intended.

## When to pick which codec

| Codec      | Encoder              | Speed    | Fan noise | File size        | Quality/byte |
| ---------- | -------------------- | -------- | --------- | ---------------- | ------------ |
| `h265`     | libx265 (CPU)        | slow     | loud      | smallest         | best         |
| `h264`     | libx264 (CPU)        | medium   | medium    | larger than h265 | good         |
| `hevc_vt`  | hevc_videotoolbox    | fast     | quiet     | slightly larger  | good         |
| `h264_vt`  | h264_videotoolbox    | fastest  | quiet     | larger           | ok           |

Heuristic:
- **Archival / shareable masters** → `h265` (default), best size for quality.
- **Personal meeting recordings, batch jobs, anything you're running
  while doing other work** → `hevc_vt`, near-silent and ~5–10x faster.

## Quality scales

- libx265 / libx264: `-c CRF` — lower = better. Default 28 (h265).
- VideoToolbox: `-q QUAL` 0–100 — higher = better. Default 50.

CRF 28 (libx265) ≈ q=50 (hevc_vt) in subjective quality for screen
recordings, but content-dependent. A/B on one file before committing
to a batch.

## Other ways to reduce CPU/fans without changing codec

- `-p fast` or `-p veryfast` — faster preset, ~5–15% larger files at
  same CRF.
- `nice -n 19 ./compress_video.sh ...` — keeps foreground apps
  responsive without changing total energy used.

## Commit

`b54dd60` Add VideoToolbox hardware encoder option to compress_video.sh
