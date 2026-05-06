#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <command> <substring> <directory> [--recursive] [--dry-run]"
    exit 1
fi

cmd="${1/#\~/$HOME}"
substr="$2"
dir="$3"
dry_run=false
recursive=false
for arg in "${@:4}"; do
    [[ "$arg" == "--dry-run" ]] && dry_run=true
    [[ "$arg" == "--recursive" ]] && recursive=true
done

depth=(-maxdepth 1)
$recursive && depth=()

files=()
while IFS= read -r line; do
    files+=("${line#* }")
done < <(
    find "$dir" "${depth[@]+"${depth[@]}"}" -type f -name "*${substr}*" -print0 \
      | xargs -0 stat -f "%SB %N" -t "%Y%m%d%H%M%S" \
      | sort
)

for file in "${files[@]+"${files[@]}"}"; do
    if $dry_run; then
        echo "[dry-run] $cmd $file"
    else
        echo "Processing: $file"
        $cmd "$file"
    fi
done
