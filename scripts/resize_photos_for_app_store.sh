#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 [options] <folder>

Resizes screenshots to exact App Store dimensions using macOS sips.
Modifies files in-place (make copies first if you need originals).

Options:
  -s SIZE   Target size as WxH (default: 1242x2688, iPhone 6.5")
  -n        Dry-run (show what would be processed, don't resize)
  -h        Show help

Common App Store sizes:
  1242x2688   iPhone 6.5" (default)
  1290x2796   iPhone 6.7"
  1242x2208   iPhone 5.5"
  2048x2732   iPad Pro 12.9"

### Examples

* Resize screenshots in current directory for iPhone 6.5":
./resize_for_app_store.sh .

* Resize for iPhone 6.7":
./resize_for_app_store.sh -s 1290x2796 ~/screenshots

* Dry-run to preview:
./resize_for_app_store.sh -n ~/screenshots

EOF
}

size="1242x2688"
dryrun="false"

while getopts ":s:nh" opt; do
  case "$opt" in
    s) size="$OPTARG" ;;
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

# Parse WxH
if [[ ! "$size" =~ ^([0-9]+)x([0-9]+)$ ]]; then
  echo "Error: invalid size '$size'. Use WxH format, e.g. 1242x2688." >&2
  exit 1
fi
target_w="${BASH_REMATCH[1]}"
target_h="${BASH_REMATCH[2]}"

# Enable case-insensitive globbing
shopt -s nocaseglob nullglob

files=( "$folder"/*.{jpg,jpeg,png,heic,tiff,tif,webp} )

shopt -u nocaseglob nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No images found in '$folder'."
  exit 0
fi

echo "Found ${#files[@]} image(s) in '$folder'"
echo "Target: ${target_w}x${target_h}"

count=0
for file in "${files[@]}"; do
  basename="$(basename -- "$file")"
  cur_w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  cur_h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')

  if [[ "$dryrun" == "true" ]]; then
    echo "[dry-run] $basename (${cur_w}x${cur_h} -> ${target_w}x${target_h})"
  else
    sips --resampleHeightWidth "$target_h" "$target_w" "$file" >/dev/null 2>&1
    echo "Resized: $basename (${cur_w}x${cur_h} -> ${target_w}x${target_h})"
  fi
  ((count++))
done

echo "Done. ${count} image(s) processed."
