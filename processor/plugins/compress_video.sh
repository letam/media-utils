#!/usr/bin/env bash
# Plugin: compress_video
# Calls ~/code/media-utils/scripts/compress_video.sh -x hevc_vt -q 50 on a
# single file and emits {input_size, output_size, output} JSON on stdout.
set -euo pipefail

EXTS=(mov mp4 m4v mkv avi webm)
COMPRESS_SCRIPT="$HOME/code/media-utils/scripts/compress_video.sh"
COMPRESS_ARGS=(-x hevc_vt -q 50)

usage() {
  cat <<'EOF'
Plugin: compress_video
  --filter                       Print accepted file extensions, one per line.
  --process [--force] <file>     Compress <file>. Skips if compressed/<stem>.mp4
                                 already exists (unless --force).
                                 Exit 0 = success, 2 = skipped, other = error.
  --stats <log_file>             Print aggregate stats JSON for this plugin.
EOF
}

emit_data() {
  # emit_data <output> <input_size> <output_size> [note]
  local out="$1" in_sz="$2" out_sz="$3" note="${4:-}"
  if [[ -n "$note" ]]; then
    jq -nc --arg out "$out" --argjson in "$in_sz" --argjson on "$out_sz" --arg note "$note" \
      '{output:$out, input_size:$in, output_size:$on, note:$note}'
  else
    jq -nc --arg out "$out" --argjson in "$in_sz" --argjson on "$out_sz" \
      '{output:$out, input_size:$in, output_size:$on}'
  fi
}

cmd="${1:-}"
case "$cmd" in
  --filter)
    printf '%s\n' "${EXTS[@]}"
    ;;

  --process)
    shift
    force="false"
    if [[ "${1:-}" == "--force" ]]; then force="true"; shift; fi
    file="${1:?--process requires <file>}"
    [[ -f "$file" ]] || { echo "Error: file not found: $file" >&2; exit 1; }
    [[ -x "$COMPRESS_SCRIPT" ]] || { echo "Error: compress script not found at $COMPRESS_SCRIPT" >&2; exit 1; }

    parent="$(cd -- "$(dirname -- "$file")" && pwd)"
    base="$(basename -- "$file")"
    stem="${base%.*}"
    out="$parent/compressed/${stem}.mp4"

    in_size="$(stat -f%z "$file")"

    if [[ "$force" == "false" && -f "$out" ]]; then
      out_size="$(stat -f%z "$out")"
      emit_data "$out" "$in_size" "$out_size" "output existed, skipped re-encode"
      exit 2
    fi

    # Send the wrapped script's stdout to stderr; we own stdout for the
    # final JSON line.
    "$COMPRESS_SCRIPT" "${COMPRESS_ARGS[@]}" "$file" >&2

    [[ -f "$out" ]] || { echo "Error: expected output not found: $out" >&2; exit 1; }
    out_size="$(stat -f%z "$out")"
    emit_data "$out" "$in_size" "$out_size"
    ;;

  --stats)
    log="${2:?--stats requires <log_file>}"
    [[ -f "$log" ]] || { echo "Error: log not found: $log" >&2; exit 1; }
    jq -s --arg p "compress_video" '
      [.[] | select(.plugin == $p)] as $all
      | [$all[] | select(.status == "success" or .status == "skipped")] as $done
      | [$done[] | select(.status == "success")] as $succ
      | {
          plugin: $p,
          total_records: ($all | length),
          successes: ($succ | length),
          skipped:   [$done[] | select(.status=="skipped")] | length,
          errors:    [$all[] | select(.status=="error")]   | length,
          encode_seconds_total: ([$succ[].duration_s] | add // 0),
          input_bytes_total:    ([$done[].data.input_size]  | add // 0),
          output_bytes_total:   ([$done[].data.output_size] | add // 0),
          encode_input_bytes:   ([$succ[].data.input_size]  | add // 0),
          encode_output_bytes:  ([$succ[].data.output_size] | add // 0),
        }
      | . + {
          saved_bytes:    (.input_bytes_total - .output_bytes_total),
          reduction_pct:  (if .input_bytes_total > 0
                           then ((.input_bytes_total - .output_bytes_total) * 100 / .input_bytes_total)
                           else 0 end),
          input_gb_total:  (.input_bytes_total  / 1073741824),
          output_gb_total: (.output_bytes_total / 1073741824),
          encode_throughput_mb_per_s:
            (if .encode_seconds_total > 0
             then (.encode_input_bytes / 1048576 / .encode_seconds_total)
             else 0 end),
        }
    ' "$log"
    ;;

  --help|-h|"")
    usage
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
