#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-n] [-r] <file-or-folder> [<file-or-folder>...]

Updates each file's creation AND modification time (macOS only,
via SetFile + touch) to match a date encoded in its filename in
the Samsung Galaxy convention, e.g.
  "20260423_074030.mp4"
  "20260221_103335 shower dancing.mp4"

Both timestamps are updated because Galaxy files copied off the
phone arrive with both birth and mtime overwritten to the copy
time — the filename is the only surviving record of capture time.

Files without a parseable date in the name, or whose creation
time already matches, are skipped.

Options:
  -n   Dry-run (show what would change, don't touch any files)
  -r   Recurse into subdirectories
  -h   Show help
EOF
}

# Extract a YYYY-MM-DD HH:MM:SS date from a Galaxy-style filename
# beginning with YYYYMMDD_HHMMSS. Echoes nothing if not found or
# if the components are out of range.
parse_filename_date() {
  local name="$1"
  local re='^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})'
  [[ "$name" =~ $re ]] || return 0

  local Y="${BASH_REMATCH[1]}" M="${BASH_REMATCH[2]}" D="${BASH_REMATCH[3]}"
  local h="${BASH_REMATCH[4]}" m="${BASH_REMATCH[5]}" s="${BASH_REMATCH[6]}"

  if (( 10#$M < 1 || 10#$M > 12 || 10#$D < 1 || 10#$D > 31 || \
        10#$h > 23 || 10#$m > 59 || 10#$s > 59 )); then
    return 0
  fi

  printf '%s-%s-%s %s:%s:%s' "$Y" "$M" "$D" "$h" "$m" "$s"
}

# Set $file's birth and modification times to the date encoded
# in its filename. No-op when the filename has no date or the
# birth time already matches. Honors $dryrun ("true"/"false").
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
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -d "${mm}/${dd}/${yyyy} ${HH}:${MM}:${SS}" \
            -m "${mm}/${dd}/${yyyy} ${HH}:${MM}:${SS}" "$file"
  else
    echo "  Warning: SetFile not found; cannot set creation time on $file" >&2
  fi
  touch -t "${yyyy}${mm}${dd}${HH}${MM}.${SS}" "$file"
}

# Only run main when executed directly, not sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  dryrun="false"
  recursive="false"
  while getopts ":nrh" opt; do
    case "$opt" in
      n) dryrun="true" ;;
      r) recursive="true" ;;
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
      if [[ "$recursive" == "true" ]]; then
        while IFS= read -r -d '' f; do
          update_file_date_from_name "$f"
        done < <(find "$target" -type f -print0)
      else
        shopt -s nullglob
        for f in "$target"/*; do
          [[ -f "$f" ]] && update_file_date_from_name "$f"
        done
        shopt -u nullglob
      fi
    elif [[ -f "$target" ]]; then
      update_file_date_from_name "$target"
    else
      echo "Skipping (not a file or directory): $target" >&2
    fi
  done
fi
