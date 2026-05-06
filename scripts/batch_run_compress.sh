#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <substring> <directory> [--recursive] [--dry-run]"
    exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"

"$script_dir/batch_run.sh" \
    "~/code/media-utils/scripts/compress_video.sh -x hevc_vt -q50" \
    "$1" "$2" "${@:3}"
