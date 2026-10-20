#!/bin/bash
# Summarize a usagectl soak log: line count, non-200s, 429s, max gap between lines.
set -euo pipefail
log="${1:-$HOME/Library/Application Support/cc.kuoc.claude-usage/soak.log}"
[ -f "$log" ] || { echo "no log: $log" >&2; exit 1; }
echo "log: $log"
echo "lines: $(wc -l < "$log" | tr -d ' ')"
echo "200: $(rg -c 'http=200' "$log" || echo 0)"
echo "429: $(rg -c 'http=429' "$log" || echo 0)"
echo "non-200 lines:"
rg -v 'http=200' "$log" || echo "  none"
max=0; prev=""; at=""
while read -r ts _; do
  t=$(TZ=UTC gdate -d "$ts" +%s 2>/dev/null || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s)
  if [ -n "$prev" ] && [ $((t - prev)) -gt $max ]; then max=$((t - prev)); at=$ts; fi
  prev=$t
done < "$log"
echo "max gap: ${max}s${at:+ (ending $at)}"
echo "last: $(tail -1 "$log")"
