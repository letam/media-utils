#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: $0 [-r] [-n] <substring> <directory> -- <command> [args...]

Runs <command> [args...] <file> for each file in <directory> whose name
contains <substring>, sorted by modification time (oldest first).

Options:
  -r    Recurse into subdirectories (default: top-level only)
  -n    Dry-run (print commands without executing)
  -h    Show this help
EOF
}

recursive=false
dry_run=false
while getopts ":rnh" opt; do
    case $opt in
        r) recursive=true ;;
        n) dry_run=true ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -lt 4 || "$3" != "--" ]]; then
    usage
    exit 2
fi

substr="$1"
dir="$2"
shift 3
cmd=("$@")

if [[ ! -d "$dir" ]]; then
    echo "Error: directory not found: $dir" >&2
    exit 1
fi

find_args=(-type f -name "*${substr}*")
$recursive || find_args=(-maxdepth 1 "${find_args[@]}")

# Filenames containing newlines are not supported.
files=()
while IFS= read -r line; do
    files+=("${line#*$'\t'}")
done < <(
    while IFS= read -r -d '' f; do
        printf '%s\t%s\n' "$(stat -f '%m' "$f")" "$f"
    done < <(find "$dir" "${find_args[@]}" -print0) | sort -n
)

for file in "${files[@]+"${files[@]}"}"; do
    if $dry_run; then
        printf '[dry-run]'
        printf ' %q' "${cmd[@]}" "$file"
        printf '\n'
    else
        echo "Processing: $file"
        "${cmd[@]}" "$file"
    fi
done
