#!/bin/bash
# List files edited in the past 7 days, or grep through them
# Usage:
#   ./recent-files.sh              # list recent files
#   ./recent-files.sh -g "pattern" # grep recent files for pattern

DIR="."
DAYS=7
GREP_PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g) GREP_PATTERN="$2"; shift 2;;
    -d) DAYS="$2"; shift 2;;
     *) DIR="$1"; shift;;
  esac
done

CUTOFF=$(date -v-${DAYS}d +%s 2>/dev/null || date -d "$DAYS days ago" +%s)

# Collect recent files
recent_files=()
while IFS= read -r file; do
  mod=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file")
  if [ "$mod" -ge "$CUTOFF" ]; then
    recent_files+=("$file")
  fi
done < <(find "$DIR" -type f -not -path '*/.*')

if [ -n "$GREP_PATTERN" ]; then
  grep -in --color=always "$GREP_PATTERN" "${recent_files[@]}"
else
  echo "Files edited in the past $DAYS days:"
  echo "---"
  for file in "${recent_files[@]}"; do
    mod=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file")
    date_str=$(date -r "$mod" "+%Y-%m-%d %H:%M" 2>/dev/null || date -d "@$mod" "+%Y-%m-%d %H:%M")
    echo "$mod $date_str  $file"
  done | sort -rn | cut -d' ' -f2-
  echo "---"
fi
