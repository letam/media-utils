#!/usr/bin/env bash
# Print stats from <dir>/.processor/log.jsonl.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: stats.sh [-p PLUGIN] [-r] <dir>

Read <dir>/.processor/log.jsonl and print stats.

Options:
  -p PLUGIN  Plugin name (default: compress_video). Used to filter log
             entries and to call the plugin's --stats reporter.
  -r         Raw: dump only the plugin's --stats JSON.
  -h         Show help
EOF
}

plugin="compress_video"
raw="false"
while getopts ":p:rh" opt; do
  case "$opt" in
    p) plugin="$OPTARG" ;;
    r) raw="true" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
    :)  echo "Option -$OPTARG requires an argument" >&2; usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND-1))

[[ $# -ge 1 ]] || { usage >&2; exit 2; }

dir="$1"
log_file="$dir/.processor/log.jsonl"
[[ -f "$log_file" ]] || { echo "No log at $log_file" >&2; exit 1; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_path="$script_dir/plugins/${plugin}.sh"
[[ -x "$plugin_path" ]] || { echo "Error: plugin '$plugin' not found at $plugin_path" >&2; exit 1; }

if [[ "$raw" == "true" ]]; then
  "$plugin_path" --stats "$log_file"
  exit 0
fi

echo "Plugin: $plugin"
echo "Log:    $log_file"
echo

echo "Per-file results:"
{
  printf 'STATUS\tDURATION\tIN\tOUT\tSAVED\tFILE\n'
  jq -r --arg p "$plugin" '
    select(.plugin == $p)
    | [
        .status,
        ((.duration_s // 0) | tostring + "s"),
        (((.data.input_size  // 0) / 1048576) | floor | tostring + "MB"),
        (((.data.output_size // 0) / 1048576) | floor | tostring + "MB"),
        (if (.data.input_size // 0) > 0
          then ((((.data.input_size - .data.output_size) * 100) / .data.input_size) | floor | tostring + "%")
          else "-"
          end),
        (.input | split("/") | last)
      ]
    | @tsv
  ' "$log_file"
} | column -t -s $'\t'
echo

echo "Aggregate:"
agg="$("$plugin_path" --stats "$log_file")"
echo "$agg" | jq -r '
  "  records:           \(.total_records)",
  "  successes:         \(.successes)",
  "  skipped:           \(.skipped)",
  "  errors:            \(.errors)",
  "  input total:       \(.input_gb_total  | . * 100 | floor / 100) GB",
  "  output total:      \(.output_gb_total | . * 100 | floor / 100) GB",
  "  saved:             \(((.saved_bytes // 0) / 1073741824) | . * 100 | floor / 100) GB  (\(.reduction_pct | floor)%)",
  "  encode wall time:  \(.encode_seconds_total)s  (\(.encode_seconds_total / 60 | floor) min)",
  "  encode throughput: \(.encode_throughput_mb_per_s | . * 100 | floor / 100) MB/s of input"
'
