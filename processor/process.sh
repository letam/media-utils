#!/usr/bin/env bash
# Process every eligible file in <dir> one at a time, via a plugin.
# Appends a JSONL record per file to <dir>/.processor/log.jsonl.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: process.sh [options] <dir>

Process every eligible file in <dir> one at a time using a plugin.
Each event is appended to <dir>/.processor/log.jsonl.

Options:
  -p PLUGIN  Plugin name (default: compress_video)
  -n         Dry-run: list files that would be processed; do nothing
  -f         Force: re-process files even if already in log
  -h         Show help

Plugin contract (each plugin in plugins/<name>.sh):
  <plugin> --filter
      Print one accepted file extension per line (lowercase, no leading dot).
  <plugin> --process [--force] <file>
      Do the work. Print exactly one JSON object on stdout (the "data"
      field for the log record). All progress/log output goes to stderr.
      Exit codes: 0 = success, 2 = skipped (no work needed), other = error.
  <plugin> --stats <log_file>     (optional)
      Print aggregate stats as JSON for this plugin's log entries.
EOF
}

plugin="compress_video"
dryrun="false"
force="false"

while getopts ":p:nfh" opt; do
  case "$opt" in
    p) plugin="$OPTARG" ;;
    n) dryrun="true" ;;
    f) force="true" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument" >&2; usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND-1))

[[ $# -ge 1 ]] || { usage >&2; exit 2; }

dir="$1"
[[ -d "$dir" ]] || { echo "Error: '$dir' is not a directory" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_path="$script_dir/plugins/${plugin}.sh"
[[ -x "$plugin_path" ]] || { echo "Error: plugin '$plugin' not found or not executable: $plugin_path" >&2; exit 1; }

exts=()
while IFS= read -r _line; do
  [[ -n "$_line" ]] && exts+=("$_line")
done < <("$plugin_path" --filter)
[[ ${#exts[@]} -gt 0 ]] || { echo "Error: plugin returned no file extensions" >&2; exit 1; }

log_dir="$dir/.processor"
log_file="$log_dir/log.jsonl"
mkdir -p "$log_dir"
touch "$log_file"

# Collect candidate files: top-level only, by extension, case-insensitive.
shopt -s nullglob nocaseglob
files=()
for ext in "${exts[@]}"; do
  for f in "$dir"/*."$ext"; do
    [[ -f "$f" ]] && files+=("$f")
  done
done
shopt -u nullglob nocaseglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files matching plugin '$plugin' (extensions: ${exts[*]}) in '$dir'"
  exit 0
fi

# Sort by name for stable order (bash 3.2-safe; assumes no newlines in filenames).
_sorted=()
while IFS= read -r _line; do
  _sorted+=("$_line")
done < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort)
files=("${_sorted[@]}")

# A file is "already done" if the log has a success or skipped entry
# for (plugin, input).
already_done() {
  local f="$1"
  jq -e --arg p "$plugin" --arg f "$f" -n '
    [inputs | select(.plugin == $p and .input == $f and (.status == "success" or .status == "skipped"))]
    | length > 0
  ' "$log_file" >/dev/null 2>&1
}

to_process=()
already_count=0
for f in "${files[@]}"; do
  if [[ "$force" == "false" ]] && already_done "$f"; then
    ((already_count++)) || true
  else
    to_process+=("$f")
  fi
done

echo "Plugin: $plugin"
echo "Dir:    $dir"
echo "Log:    $log_file"
echo "Total candidates: ${#files[@]}"
echo "Already in log:   $already_count"
echo "To process:       ${#to_process[@]}"

if [[ "$dryrun" == "true" ]]; then
  echo
  echo "[dry-run] Would process:"
  printf '  %s\n' "${to_process[@]}"
  exit 0
fi

if [[ ${#to_process[@]} -eq 0 ]]; then
  exit 0
fi

# Forwarded plugin args (just --force or nothing).
plugin_force_args=()
[[ "$force" == "true" ]] && plugin_force_args=(--force)

# Process one at a time.
idx=0
for f in "${to_process[@]}"; do
  ((idx++)) || true
  echo
  echo "[$idx/${#to_process[@]}] $(basename -- "$f")"

  start_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start_epoch="$(date +%s)"

  tmp_out="$(mktemp -t processor.XXXXXX)"
  trap 'rm -f "$tmp_out"' EXIT

  set +e
  "$plugin_path" --process ${plugin_force_args[@]+"${plugin_force_args[@]}"} "$f" >"$tmp_out"
  rc=$?
  set -e

  end_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  end_epoch="$(date +%s)"
  dur=$((end_epoch - start_epoch))

  plugin_json="$(cat "$tmp_out")"
  rm -f "$tmp_out"
  trap - EXIT

  case "$rc" in
    0) status="success" ;;
    2) status="skipped" ;;
    *) status="error"   ;;
  esac

  if [[ -n "$plugin_json" ]] && echo "$plugin_json" | jq empty >/dev/null 2>&1; then
    data="$plugin_json"
  else
    data="$(jq -n --arg raw "$plugin_json" '{raw: $raw}')"
  fi

  jq -nc \
    --arg ts "$start_ts" \
    --arg end "$end_ts" \
    --arg p "$plugin" \
    --arg input "$f" \
    --arg status "$status" \
    --argjson dur "$dur" \
    --argjson rc "$rc" \
    --argjson data "$data" \
    '{ts:$ts, end:$end, plugin:$p, input:$input, status:$status, duration_s:$dur, exit:$rc, data:$data}' \
    >>"$log_file"

  echo "  -> $status (${dur}s)"
done

echo
echo "Done. Log: $log_file"
