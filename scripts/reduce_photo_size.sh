#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 [options] <folder>

Reduces the file size of photos in a folder using macOS sips.
Creates resized copies in a "reduced" subfolder (originals are untouched).

Options:
  -m MAX    Max dimension in pixels for the longest side (default: 2048)
  -q QUAL   JPEG quality 0-100, lower = smaller file (default: 80)
  -n        Dry-run (show what would be processed, don't resize)
  -h        Show help

### Examples

* Reduce all photos in current directory with defaults (2048px, quality 80):
./reduce_photo_size.sh .

* Resize to max 1200px, quality 70:
./reduce_photo_size.sh -m 1200 -q 70 ~/Photos/vacation

* Dry-run to preview what would be processed:
./reduce_photo_size.sh -n ~/Photos/vacation

EOF
}

max_dim=2048
quality=80
dryrun="false"

while getopts ":m:q:nh" opt; do
  case "$opt" in
    m) max_dim="$OPTARG" ;;
    q) quality="$OPTARG" ;;
    n) dryrun="true" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

if [[ $# -lt 1 ]]; then
  echo "Error: folder argument required." >&2
  usage
  exit 1
fi

folder="$1"

if [[ ! -d "$folder" ]]; then
  echo "Error: '$folder' is not a directory." >&2
  exit 1
fi

# Enable case-insensitive globbing
shopt -s nocaseglob nullglob

files=( "$folder"/*.{jpg,jpeg,png,heic,tiff,tif,webp} )

shopt -u nocaseglob nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No photos found in '$folder'."
  exit 0
fi

echo "Found ${#files[@]} photo(s) in '$folder'"
echo "Settings: max ${max_dim}px, quality ${quality}"

outdir="${folder%/}/reduced"

if [[ "$dryrun" == "false" ]]; then
  mkdir -p "$outdir"
fi

count=0
for file in "${files[@]}"; do
  basename="$(basename -- "$file")"

  if [[ "$dryrun" == "true" ]]; then
    echo "[dry-run] $basename -> reduced/$basename"
  else
    cp -- "$file" "$outdir/$basename"
    sips --resampleHeightWidthMax "$max_dim" -s formatOptions "$quality" "$outdir/$basename" >/dev/null 2>&1
    orig_size=$(stat -f%z "$file")
    new_size=$(stat -f%z "$outdir/$basename")
    pct=$((100 - (new_size * 100 / orig_size)))
    echo "Reduced: $basename (${pct}% smaller)"
  fi
  ((count++))
done

if [[ "$dryrun" == "false" ]]; then
  echo "Done. ${count} photo(s) saved to $outdir"
fi
