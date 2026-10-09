#!/bin/bash
# scripts/vagrant-smoke.sh's second chance: a run failed on its latency threshold alone gets one more - only when a
# production container started in the last minutes (the first requests after a restart); a step that restarted
# nothing gets none (a latency regression would pass on a retry). Its own tail run with smoke() and vssh stubbed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # name got want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
src=scripts/vagrant-smoke.sh
tail_=$(sed -n '/^# the run failed on its latency alone/,$p' "$src")
[ -n "$tail_" ] || { echo "FAIL the tail not found"; exit 1; }
latency_out='  ✓ status 200
     ✗ '"'"'p(95)<800'"'"' p(95)=1.2s
     http_req_failed................: 0.00%  0 out of 50
level=error msg="thresholds on metrics '"'"'http_req_duration'"'"' have been crossed"'
run() {  # run <first run's output> <a recent start: yes|no> -> "<exit> <smoke runs>"
  printf '%s\n' "$1" > "$W/first"
  RECENT=$2 W=$W bash -c '
    work=$W; runs=0
    smoke() { runs=$((runs + 1)); echo $runs > "$W/runs"; [ $runs -gt 1 ]; cp "$W/first" "$work/out"; [ $runs -gt 1 ]; }
    vssh() { [ "$RECENT" = yes ] && echo recent; true; }
    name=x
    '"$tail_" > /dev/null 2>&1
  echo "$? $(cat "$W/runs")"
}
check "latency alone crossed, a container started minutes ago: run once more, that run decides" \
  "$(run "$latency_out" yes)" "0 2"
check "latency alone crossed, nothing restarted: no second chance" "$(run "$latency_out" no)" "1 1"
check "another failure: no second chance" "$(run 'level=error msg="something else"' yes)" "1 1"
echo "smoke-rerun: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
