#!/usr/bin/env bash
# Every 2 s until the file STOP exists beside it: the open captures' lag and drops, and the spill instance's state.
dir="$(dirname "$0")"
out="$dir/spill-watch.tsv"
printf 'time\treceiver\tbehind_s\tdropped_s\tiq_mem\tiq_keys\tload1\n' > "$out"
while [ ! -f "$dir/STOP" ]; do
    t="$(date +%H:%M:%S)"
    mem="$(docker exec radar-valkey-iq-1 valkey-cli -p 6380 info memory 2>/dev/null | sed -n 's/^used_memory_human:\([^[:space:]]*\).*/\1/p')"
    keys="$(docker exec radar-valkey-iq-1 valkey-cli -p 6380 dbsize 2>/dev/null | tr -d '\r')"
    load="$(cut -d' ' -f1 /proc/loadavg)"
    curl -s -m 3 http://127.0.0.1:8090/api/sdr/opens | python3 -c '
import sys, json
for r in json.load(sys.stdin):
    if r.get("end_reason") is None:
        print("\t".join(str(x) for x in (r["receiver"], r.get("behind_s"), r.get("dropped_s"))))
' 2>/dev/null | while IFS= read -r line; do printf '%s\t%s\t%s\t%s\t%s\n' "$t" "$line" "$mem" "$keys" "$load" >> "$out"; done
    sleep 2
done
