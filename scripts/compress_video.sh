#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 [options] <file-or-folder>

Compresses video(s) using ffmpeg. Tuned defaults for screen recordings of
meetings: H.265, CRF 28, 30 fps, max 1920px wide, 96k mono audio.
Creates compressed copies in a "compressed" subfolder (originals untouched).

Options:
  -c CRF     Constant Rate Factor, lower = better quality/larger file
             (h265: 18-32 reasonable, default 28; h264: add ~6)
  -r FPS     Output frame rate (default: 30)
  -w WIDTH   Max width in pixels, keeps aspect ratio (default: 1920)
  -x CODEC   Video codec: h265 or h264 (default: h265)
  -p PRESET  ffmpeg preset: ultrafast..veryslow (default: medium)
  -a RATE    Audio bitrate, e.g. 64k, 96k, 128k (default: 96k)
  -m         Mono audio (default: keep source channels)
  -n         Dry-run (show the ffmpeg command, don't run it)
  -h         Show help

### Examples

* Compress a single meeting recording with defaults:
./compress_video.sh ~/Downloads/meeting.mov

* More aggressive (smaller file, lower quality):
./compress_video.sh -c 32 -w 1440 -r 15 meeting.mov

* Compress every video in a folder:
./compress_video.sh ~/Recordings

* Preview the ffmpeg command without running it:
./compress_video.sh -n meeting.mov

EOF
}

crf=28
fps=30
width=1920
codec="h265"
preset="medium"
audio_rate="96k"
mono="false"
dryrun="false"

while getopts ":c:r:w:x:p:a:mnh" opt; do
  case "$opt" in
    c) crf="$OPTARG" ;;
    r) fps="$OPTARG" ;;
    w) width="$OPTARG" ;;
    x) codec="$OPTARG" ;;
    p) preset="$OPTARG" ;;
    a) audio_rate="$OPTARG" ;;
    m) mono="true" ;;
    n) dryrun="true" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

if [[ $# -lt 1 ]]; then
  echo "Error: file or folder argument required." >&2
  usage
  exit 1
fi

target="$1"

case "$codec" in
  h265|hevc) vcodec="libx265"; vtag=(-tag:v hvc1) ;;
  h264|avc)  vcodec="libx264"; vtag=() ;;
  *) echo "Error: unknown codec '$codec' (use h265 or h264)." >&2; exit 2 ;;
esac

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg not found on PATH." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
date_from_name="$script_dir/set_file_date_from_filename.sh"

# Collect input files
if [[ -d "$target" ]]; then
  shopt -s nocaseglob nullglob
  files=( "$target"/*.{mov,mp4,m4v,mkv,avi,webm} )
  shopt -u nocaseglob nullglob
  parent="${target%/}"
elif [[ -f "$target" ]]; then
  files=( "$target" )
  parent="$(dirname -- "$target")"
else
  echo "Error: '$target' is not a file or directory." >&2
  exit 1
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No videos found in '$target'."
  exit 0
fi

echo "Found ${#files[@]} video(s)"
echo "Settings: codec=$codec crf=$crf fps=$fps width<=${width}px preset=$preset audio=$audio_rate mono=$mono"

outdir="$parent/compressed"
[[ "$dryrun" == "false" ]] && mkdir -p "$outdir"

# Scale filter: fit within width, keep aspect, ensure even dimensions
vf="scale='min($width,iw)':-2,fps=$fps"

ac_args=()
[[ "$mono" == "true" ]] && ac_args=(-ac 1)

count=0
for file in "${files[@]}"; do
  basename="$(basename -- "$file")"
  stem="${basename%.*}"
  out="$outdir/${stem}.mp4"

  cmd=(
    ffmpeg -hide_banner -y -i "$file"
    -vf "$vf"
    -c:v "$vcodec" -preset "$preset" -crf "$crf"
    -pix_fmt yuv420p
    ${vtag[@]+"${vtag[@]}"}
    -c:a aac -b:a "$audio_rate" ${ac_args[@]+"${ac_args[@]}"}
    -movflags +faststart
    "$out"
  )

  if [[ "$dryrun" == "true" ]]; then
    printf '[dry-run]'; printf ' %q' "${cmd[@]}"; printf '\n'
  else
    echo "Compressing: $basename -> compressed/${stem}.mp4"
    "${cmd[@]}"
    touch -r "$file" "$out"
    if command -v SetFile >/dev/null 2>&1; then
      btime=$(stat -f "%SB" -t "%m/%d/%Y %H:%M:%S" "$file")
      SetFile -d "$btime" "$out"
    fi
    "$date_from_name" "$out"
    orig_size=$(stat -f%z "$file")
    new_size=$(stat -f%z "$out")
    pct=$((100 - (new_size * 100 / orig_size)))
    orig_mb=$((orig_size / 1024 / 1024))
    new_mb=$((new_size / 1024 / 1024))
    echo "Done: $basename (${orig_mb}MB -> ${new_mb}MB, ${pct}% smaller)"
  fi
  ((count++))
done

if [[ "$dryrun" == "false" ]]; then
  echo "Finished. ${count} video(s) saved to $outdir"
fi
