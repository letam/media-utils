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

**Update from real-world test:** the q=50 default is much too generous.
On a screen recording where libx265 CRF 28 produced 377 MB in 38m22s,
hevc_vt q=50 produced 1.79 GB in 16m22s — 4.7× larger, only 2.3× faster.
Lower q aggressively for screen content: try q=38, then q=32. q is
roughly logarithmic, so each 10-point drop ≈ halves the file.

## Why hevc_vt files are larger than expected

- **Encoder efficiency.** VideoToolbox HEVC trades compression for speed
  and silicon area — no exhaustive motion estimation, simpler rate-
  distortion optimization. Genuinely worse quality-per-byte than libx265.
- **Screen content is libx265's strength.** It has tuning specifically
  for static frames with text/UI. The gap widens on this material.
- **Default q=50 is high.** For meetings/screens, q=32–40 is usually fine.

## Why hardware speedup is less than 5–10×

- **Decode is the floor.** ProRes / high-bitrate HEVC inputs take time
  to decode that no encoder can skip.
- **Disk I/O.** Writing a 1.79 GB output is meaningful wall time.
- **At lower q, hardware is also faster** — fewer bits to emit means
  the encoder finishes sooner. The 2.3× was partly a q=50 problem.

## Tuning recommendations, in order of effect

1. **Lower `-q` aggressively for screen content** — start at 38, drop
   to 32 if size still too big, 28 if quality holds.
2. **Software with faster preset** (`-p veryfast`) when quality-per-byte
   matters more than fan noise — keeps libx265's compression edge,
   ~10–15 min instead of 38, file ~5–15% larger than `medium`.
3. **Bitrate-targeted mode** for predictable file sizes, e.g.
   `-b:v 2M -maxrate 2.5M -bufsize 4M`. For 30 fps screens at ≤1920px,
   1.5–2.5 Mbps is plenty. Not yet exposed by `compress_video.sh`.

## Other knobs worth knowing

- **`-tune stillimage`** (libx265) — helps screen content with mostly
  static frames.
- **`-tune fastdecode`** (libx265) — optimizes for playback CPU over
  file size.
- **`-realtime 0`** for hevc_videotoolbox — allows more analysis,
  marginal gain but free.
- **Frame rate and resolution are bigger levers than codec tuning**
  for slide-heavy meetings: `-r 15 -w 1280` shrinks files dramatically
  with little perceptual loss.
- **Audio is already minimal** at 96k mono — not a useful target for
  further savings.

## Other ways to reduce CPU/fans without changing codec

- `-p fast` or `-p veryfast` — faster preset, ~5–15% larger files at
  same CRF.
- `nice -n 19 ./compress_video.sh ...` — keeps foreground apps
  responsive without changing total energy used.

## Commits

- `b54dd60` Add VideoToolbox hardware encoder option to compress_video.sh
- `a3a02c9` Add notes on software vs hardware encoder choice
