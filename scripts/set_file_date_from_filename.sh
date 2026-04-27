#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-n] <file-or-folder> [<file-or-folder>...]

Updates each file's modification time and (on macOS) creation time to
match a date encoded in its filename, e.g.
  "Screen Recording 2026-04-27 at 10.49.40 standup.mov"
  "Screenshot 2026-04-27 at 10.49.40 AM.png"

Files without a parseable date in the name, or whose creation time
already matches, are skipped.

Options:
  -n   Dry-run (show what would change, don't touch any files)
  -h   Show help
EOF
}

# Extract a YYYY-MM-DD HH:MM:SS date from a filename. Recognizes
# "YYYY-MM-DD HH.MM.SS" and "YYYY-MM-DD at HH.MM.SS", with "." or ":"
# between time parts. Echoes nothing if not found.
parse_filename_date() {
  local name="$1"
  local re='([0-9]{4})-([0-9]{2})-([0-9]{2})[ _]+(at[ _]+)?([0-9]{2})[.:]([0-9]{2})[.:]([0-9]{2})'
  if [[ "$name" =~ $re ]]; then
    printf '%s-%s-%s %s:%s:%s' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
      "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}" "${BASH_REMATCH[7]}"
  fi
}

# Set $file's mtime and birth time to the date encoded in its filename.
# No-op when the filename has no date or the birth time already matches.
# Honors $dryrun ("true"/"false") from the caller.
update_file_date_from_name() {
  local file="$1"
  local fname_date current_birth
  fname_date=$(parse_filename_date "$(basename -- "$file")")
  [[ -z "$fname_date" ]] && return 0

  current_birth=$(stat -f "%SB" -t "%Y-%m-%d %H:%M:%S" "$file")
  if [[ "$fname_date" == "$current_birth" ]]; then
    return 0
  fi

  local prefix=""
  [[ "${dryrun:-false}" == "true" ]] && prefix="[dry-run] "
  echo "${prefix}$file: $current_birth -> $fname_date"
  [[ "${dryrun:-false}" == "true" ]] && return 0

  local yyyy=${fname_date:0:4} mm=${fname_date:5:2} dd=${fname_date:8:2}
  local HH=${fname_date:11:2} MM=${fname_date:14:2} SS=${fname_date:17:2}
  touch -t "${yyyy}${mm}${dd}${HH}${MM}.${SS}" "$file"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -d "${mm}/${dd}/${yyyy} ${HH}:${MM}:${SS}" "$file"
  fi
}

# Only run main when executed directly, not sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  dryrun="false"
  while getopts ":nh" opt; do
    case "$opt" in
      n) dryrun="true" ;;
      h) usage; exit 0 ;;
      \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2 ;;
    esac
  done
  shift $((OPTIND-1))

  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  for target in "$@"; do
    if [[ -d "$target" ]]; then
      shopt -s nocaseglob nullglob
      for f in "$target"/*; do
        [[ -f "$f" ]] && update_file_date_from_name "$f"
      done
      shopt -u nocaseglob nullglob
    elif [[ -f "$target" ]]; then
      update_file_date_from_name "$target"
    else
      echo "Skipping (not a file or directory): $target" >&2
    fi
  done
fi
