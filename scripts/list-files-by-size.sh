#!/usr/bin/env bash

set -eo pipefail

show_help() {
  cat <<'EOF'
List files recursively by size.

Usage:
  list-files-by-size.sh [options]

Options:
  -d, --dir PATH         Directory to scan (default: current directory)
  -r, --reverse          Show largest files first
  -n, --top N            Show only top N results
  -b, --bytes            Show exact byte counts instead of human-readable sizes
  -i, --ignore PATTERN   Exclude paths matching this pattern (can be used multiple times)
                         Example: -i "*/node_modules/*" -i "*/.git/*"
  -h, --help             Show this help message
EOF
}

DIR="."
REVERSE=false
TOP=""
BYTES=false
IGNORE_PATTERNS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      DIR="${2:-}"
      shift 2
      ;;
    -r|--reverse)
      REVERSE=true
      shift
      ;;
    -n|--top)
      TOP="${2:-}"
      shift 2
      ;;
    -b|--bytes)
      BYTES=true
      shift
      ;;
    -i|--ignore)
      IGNORE_PATTERNS+=("${2:-}")
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo
      show_help
      exit 1
      ;;
  esac
done

if [[ ! -d "$DIR" ]]; then
  echo "Error: directory does not exist: $DIR" >&2
  exit 1
fi

if [[ -n "$TOP" && ! "$TOP" =~ ^[0-9]+$ ]]; then
  echo "Error: --top must be a positive integer" >&2
  exit 1
fi

find_cmd=(find "$DIR")

if [[ ${#IGNORE_PATTERNS[@]} -gt 0 ]]; then
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    find_cmd+=( -not -path "$pattern" )
  done
fi

find_cmd+=( -type f )

if [[ "$BYTES" == true ]]; then
  if stat -f "%z %N" /dev/null >/dev/null 2>&1; then
    sort_flag="-n"
    [[ "$REVERSE" == true ]] && sort_flag="-nr"
    "${find_cmd[@]}" -exec stat -f "%z %N" {} + | sort "$sort_flag"
  else
    sort_flag="-n"
    [[ "$REVERSE" == true ]] && sort_flag="-nr"
    "${find_cmd[@]}" -exec stat --format="%s %n" {} + | sort "$sort_flag"
  fi
else
  sort_flag="-h"
  [[ "$REVERSE" == true ]] && sort_flag="-hr"
  "${find_cmd[@]}" -exec du -h {} + | sort "$sort_flag"
fi | {
  if [[ -n "$TOP" ]]; then
    head -n "$TOP"
  else
    cat
  fi
}
