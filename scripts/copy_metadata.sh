#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 [-n] <source-file> <dest-file>
  $0 [-n] <source-file>            # dest defaults to <dir>/compressed/<stem>.mp4
  $0 [-n] <folder>                 # copy each video's tags into folder/compressed/<stem>.mp4

Copies metadata (GPS/geolocation, creation/modify dates, camera make/model)
from a source media file onto another file using exiftool. Useful for
restoring tags onto an already-compressed copy, e.g. files compressed before
compress_video.sh learned to preserve them.

By default it also syncs the destination's filesystem timestamps (modification
time, and on macOS the Finder creation time) to match the source file's
on-disk times. Pass -T to copy only the embedded metadata and leave filesystem
times untouched, or -c to set them from the embedded capture date instead.

The single-file and folder forms assume the compress_video.sh output layout:
a "compressed/<stem>.mp4" sibling of each source.

Options:
  -c   Set filesystem timestamps from the embedded capture date
       (CreationDate/CreateDate) rather than the source file's on-disk times.
       Timezone-aware: uses the local wall-clock time of capture.
  -T   Don't sync filesystem timestamps (embedded metadata only)
  -n   Dry-run (show what would be copied, don't modify any files)
  -h   Show help

Requires exiftool (brew install exiftool).
EOF
}

# Tags carried from source to dest. -keys:all picks up Apple's QuickTime mdta
# atoms (incl. com.apple.quicktime.location.ISO6709); -gps:all / -location:all
# cover GPS however it's stored.
TAGS=(-gps:all -location:all -keys:all -CreateDate -ModifyDate -Make -Model)

EXTS=(mov mp4 m4v mkv avi webm)

# dest_for <source-file>  ->  <dir>/compressed/<stem>.mp4
dest_for() {
  local src="$1" dir base stem
  dir="$(dirname -- "$src")"
  base="$(basename -- "$src")"
  stem="${base%.*}"
  printf '%s/compressed/%s.mp4' "$dir" "$stem"
}

# Set dst's birth (macOS) and modification times to a "YYYY-MM-DD HH:MM:SS"
# wall-clock string.
set_times_to() {
  local dst="$1" ts="$2"
  local y=${ts:0:4} mo=${ts:5:2} d=${ts:8:2} H=${ts:11:2} M=${ts:14:2} S=${ts:17:2}
  touch -t "${y}${mo}${d}${H}${M}.${S}" "$dst"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -d "${mo}/${d}/${y} ${H}:${M}:${S}" "$dst"
  else
    echo "  Warning: SetFile not found; cannot set creation time on $dst" >&2
  fi
}

# Sync dst's filesystem mtime and (macOS) birth time. With $time_source=capture,
# derive them from the embedded capture date (timezone-resolved local time),
# preferring Keys:CreationDate (carries the true capture offset) and falling
# back to QuickTime:CreateDate (UTC, converted to local). Otherwise copy the
# source file's on-disk times.
sync_filesystem_times() {
  local src="$1" dst="$2"

  if [[ "${time_source:-file}" == "capture" ]]; then
    local cap
    cap=$(exiftool -s3 -api QuickTimeUTC=1 -d '%Y-%m-%d %H:%M:%S' \
            -CreationDate -CreateDate "$src" 2>/dev/null | head -n1)
    if [[ -n "$cap" ]]; then
      set_times_to "$dst" "$cap"
      return 0
    fi
    echo "  Warning: no embedded capture date in $(basename -- "$src"); using file times" >&2
  fi

  touch -r "$src" "$dst"
  if command -v SetFile >/dev/null 2>&1; then
    local btime
    btime=$(stat -f "%SB" -t "%m/%d/%Y %H:%M:%S" "$src")
    SetFile -d "$btime" "$dst"
  else
    echo "  Warning: SetFile not found; cannot set creation time on $dst" >&2
  fi
}

# copy_metadata <src> <dst>. Honors $dryrun and $sync_times ("true"/"false").
copy_metadata() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || { echo "Error: source not found: $src" >&2; return 1; }
  [[ -f "$dst" ]] || { echo "Error: dest not found: $dst" >&2; return 1; }

  local prefix=""
  [[ "${dryrun:-false}" == "true" ]] && prefix="[dry-run] "
  echo "${prefix}metadata: $(basename -- "$src") -> $dst"
  [[ "${dryrun:-false}" == "true" ]] && return 0

  exiftool -q -overwrite_original -tagsFromFile "$src" "${TAGS[@]}" "$dst" \
    || { echo "Warning: exiftool metadata copy failed for $dst" >&2; return 1; }
  [[ "${sync_times:-true}" == "true" ]] && sync_filesystem_times "$src" "$dst"
}

dryrun="false"
sync_times="true"
time_source="file"
while getopts ":ncTh" opt; do
  case "$opt" in
    n) dryrun="true" ;;
    c) time_source="capture" ;;
    T) sync_times="false" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
  echo "Error: exiftool not found on PATH (brew install exiftool)." >&2
  exit 1
fi

# Explicit source + dest.
if [[ $# -eq 2 ]]; then
  copy_metadata "$1" "$2"
  exit $?
fi

target="$1"
if [[ -d "$target" ]]; then
  shopt -s nocaseglob nullglob
  files=( "$target"/*.{mov,mp4,m4v,mkv,avi,webm} )
  shopt -u nocaseglob nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No videos found in '$target'."
    exit 0
  fi
  rc=0
  for f in "${files[@]}"; do
    dst="$(dest_for "$f")"
    if [[ -f "$dst" ]]; then
      copy_metadata "$f" "$dst" || rc=1
    else
      echo "Skipping (no compressed copy): $f" >&2
    fi
  done
  exit $rc
elif [[ -f "$target" ]]; then
  copy_metadata "$target" "$(dest_for "$target")"
else
  echo "Error: '$target' is not a file or directory." >&2
  exit 1
fi
