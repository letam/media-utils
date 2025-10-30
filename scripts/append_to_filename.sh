#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 <append_text> [files...]
  $0 <append_text> -f filelist.txt
  ls | $0 <append_text>        # read files from stdin (newline)
  ls -0 | $0 <append_text> -0  # read files from stdin (NUL)

Options:
  -f FILE   Read list of files from FILE (newline-delimited by default)
  -0        Treat input as NUL-delimited (for stdin or -f)
  -n        Dry-run (show what would be renamed, don't mv)
  -h        Show help

Notes:
- Appends before the last dot in the filename; if no dot, appends to the end.
- Safely handles spaces and unusual characters.

### Examples

* From a list file:
./append_to_filename.sh "_v2" -f files.txt

* From stdin:
find . -type f -name "*.jpg" | ./append_to_filename.sh "_edited"

* NUL-safe (handles filenames with newlines):
find . -type f -print0 | ./append_to_filename.sh "_bak" -0

* Passing files directly + dry run:
./append_to_filename.sh "_final" a.pdf "weird name.txt" -n

EOF
}

append=""
listfile=""
nuldelim="false"
dryrun="false"

# --- Parse args ---
if [[ $# -lt 1 ]]; then usage; exit 1; fi
append="$1"; shift

while getopts ":f:0nh" opt; do
  case "$opt" in
    f) listfile="$OPTARG" ;;
    0) nuldelim="true" ;;
    n) dryrun="true" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND-1))

# --- Gather files into an array ---
files=()

read_from_stream() {
  if [[ "$nuldelim" == "true" ]]; then
    # NUL-delimited
    while IFS= read -r -d '' line; do files+=("$line"); done
  else
    # Newline-delimited
    while IFS= read -r line; do [[ -n "$line" ]] && files+=("$line"); done
  fi
}

if [[ -n "$listfile" ]]; then
  if [[ "$nuldelim" == "true" ]]; then
    # Use tr to add a trailing NUL if missing; read -d '' consumes until NUL
    tr '\n' '\0' < "$listfile" | read_from_stream
  else
    read_from_stream < "$listfile"
  fi
elif [[ $# -gt 0 ]]; then
  # Remaining args are file paths
  for f in "$@"; do files+=("$f"); done
else
  # If stdin is not a TTY, read from it
  if ! [ -t 0 ]; then
    read_from_stream
  else
    echo "No files provided. Pass files as args, -f listfile, or via stdin." >&2
    exit 1
  fi
fi

# --- Rename function ---
rename_one() {
  local file="$1"
  # Only operate on existing regular files or symlinks to files
  if [[ ! -e "$file" ]]; then
    echo "Skip (not found): $file" >&2
    return
  fi

  local dir base ext new
  dir="$(dirname -- "$file")"
  base="$(basename -- "$file")"

  if [[ "$base" == *.* && "$base" != .* ]]; then
    local name="${base%.*}"
    ext="${base##*.}"
    new="${name}${append}.${ext}"
  else
    # No extension: append to end
    new="${base}${append}"
  fi

  local src="$file"
  local dst="${dir%/}/${new}"

  if [[ -e "$dst" ]]; then
    echo "Skip (target exists): $src -> $dst" >&2
    return
  fi

  if [[ "$dryrun" == "true" ]]; then
    echo "[dry-run] $src -> $dst"
  else
    mv -- "$src" "$dst"
    echo "Renamed: $src -> $dst"
  fi
}

# --- Process all files ---
for f in "${files[@]}"; do
  rename_one "$f"
done

