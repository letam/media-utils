#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: $0 [-r] [-n] [-x CODEC] [-q QUAL] <substring> <directory>

Wrapper over batch_run.sh that runs compress_video.sh on matching files.

Options:
  -r        Recurse into subdirectories
  -n        Dry-run
  -x CODEC  compress_video.sh codec (default: hevc_vt)
  -q QUAL   VideoToolbox quality 0-100 (default: 50)
  -h        Show this help
EOF
}

batch_flags=()
codec=hevc_vt
qual=50
while getopts ":rnx:q:h" opt; do
    case $opt in
        r) batch_flags+=(-r) ;;
        n) batch_flags+=(-n) ;;
        x) codec="$OPTARG" ;;
        q) qual="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"

"$script_dir/batch_run.sh" "${batch_flags[@]+"${batch_flags[@]}"}" \
    "$1" "$2" -- \
    "$script_dir/compress_video.sh" -x "$codec" -q "$qual"
