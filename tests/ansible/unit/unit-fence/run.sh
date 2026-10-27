#!/bin/bash
# tests/ansible/unit/run.sh's fence, on harnesses of this test's own: a harness that reaches ssh, kubectl or vagrant
# fails the suite, named with what it ran - also when it tolerates the call's failure (the stub's exit 97 could pass a
# negative case, its FENCED line unseen) - and one that rebuilds its PATH keeps the fence through FENCE; a harness that
# reaches none passes.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tolerates" "$W/rebuilds" "$W/clean"
printf '#!/bin/bash\nssh pi1 uptime || true\nexit 0\n' > "$W/tolerates/run.sh"
printf '#!/bin/bash\nenv -i PATH="${FENCE:+$FENCE:}/usr/bin:/bin" kubectl get nodes || true\nexit 0\n' > "$W/rebuilds/run.sh"
printf '#!/bin/bash\necho fine\nexit 0\n' > "$W/clean/run.sh"
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1))
}
for h in tolerates rebuilds clean; do
  mkdir -p "$W/suite-$h/$h"; cp "$W/$h/run.sh" "$W/suite-$h/$h/run.sh"
  # without the caller's FENCE: the runner's own export is what the rebuilding harness must find
  out=$(env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-$h" 2>&1); rc=$?
  case $h in
    clean) check "a harness reaching no host: the suite passes" "$rc" 0 ;;
    *) check "a harness that $h (its failure tolerated): the suite fails, naming the call" \
         "$rc $(grep -c "FENCED: $h reached" <<< "$out")" "1 1" ;;
  esac
done
# each harness started with its signals at their defaults: a runner started with INT ignored (a background job, a
# nohup) passed it on, and bash cannot trap a signal ignored on entry - a harness's stop cases passed on nothing
mkdir -p "$W/suite-int/traps"
printf '#!/bin/bash
trap "exit 0" INT
kill -INT $$
exit 1
' > "$W/suite-int/traps/run.sh"
out=$( (trap '' INT; env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-int") 2>&1); rc=$?
check "a runner started with INT ignored: each harness gets it at its default (its trap runs)" "$rc" 0
# what a harness leaves in its temp directory goes with it: each runs with a TMPDIR of its own, removed after it (eleven
# left Python temp directories in /tmp - RAM here - on every run)
mkdir -p "$W/suite-tmp/leaks" "$W/tmproot"
printf '#!/bin/bash\nmktemp -d > /dev/null; mktemp > /dev/null\nexit 0\n' > "$W/suite-tmp/leaks/run.sh"
out=$(TMPDIR="$W/tmproot" env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-tmp" 2>&1); rc=$?
check "a harness leaving temp files: gone with it, nothing left in the caller's temp directory" \
  "$rc $(ls -A "$W/tmproot" | wc -l)" "0 0"
# harnesses run side by side, UNIT_JOBS at a time (CI's container has 4 CPUs; one by one the suite outgrew Woodpecker's
# 60 min limit, 2026-10-20): four that each wait until all four have started pass only when run at once - one by one,
# each gives up after 5 s
mkdir -p "$W/suite-par" "$W/meet"
for h in a b c d; do
  mkdir -p "$W/suite-par/$h"
  # met: all four at once (the first to see them marks it for the rest); alone: gives up after 5 s, its mark taken away
  printf '#!/bin/bash\nm=%s\ntouch "$m/%s"\nfor _ in $(seq 50); do\n  if [ -e "$m/all" ] || [ "$(ls "$m" | wc -l)" -ge 4 ]; then touch "$m/all"; echo "%s met"; exit 0; fi\n  sleep 0.1\ndone\nrm -f "$m/%s"; echo "%s alone"; exit 1\n' \
    "$W/meet" "$h" "$h" "$h" "$h" > "$W/suite-par/$h/run.sh"
done
out=$(UNIT_JOBS=4 env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-par" 2>&1); rc=$?
check "UNIT_JOBS=4: four harnesses run at once" "$rc $(grep -c ' met$' <<< "$out")" "0 4"
# side by side, each harness keeps a fence of its own: the one that reaches a host is the one named, the others pass;
# a failing one fails the suite; each harness's output stays whole, under its own heading, in the suite's order
mkdir -p "$W/suite-mix/a-clean" "$W/suite-mix/b-fenced" "$W/suite-mix/c-fails" "$W/suite-mix/d-clean"
printf '#!/bin/bash\nfor i in 1 2 3; do echo "a-clean line $i"; sleep 0.2; done\nexit 0\n' > "$W/suite-mix/a-clean/run.sh"
printf '#!/bin/bash\nsleep 0.3; ssh pi1 uptime || true\necho "b-fenced done"\nexit 0\n' > "$W/suite-mix/b-fenced/run.sh"
printf '#!/bin/bash\necho "c-fails line"\nexit 1\n' > "$W/suite-mix/c-fails/run.sh"
printf '#!/bin/bash\nfor i in 1 2 3; do echo "d-clean line $i"; sleep 0.1; done\nexit 0\n' > "$W/suite-mix/d-clean/run.sh"
out=$(UNIT_JOBS=4 env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-mix" 2>&1); rc=$?
check "side by side: the suite fails; only the harness that reached a host named by the fence" \
  "$rc $(grep -c 'FENCED: b-fenced reached' <<< "$out") $(grep -c 'FENCED: [acd]-' <<< "$out")" "1 1 0"
check "side by side: each harness's output whole under its heading, the headings in the suite's order" \
  "$(grep -E '^== |line' <<< "$out" | tr '\n' '|')" \
  "== a-clean|a-clean line 1|a-clean line 2|a-clean line 3|== b-fenced|== c-fails|c-fails line|== d-clean|d-clean line 1|d-clean line 2|d-clean line 3|"
# UNIT_JOBS=1: one by one, as before - the four that wait for each other fail
rm -f "$W/meet"/*
out=$(UNIT_JOBS=1 env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-par" 2>&1); rc=$?
check "UNIT_JOBS=1: one at a time (the waiting four do not meet)" "$rc $(grep -c ' alone$' <<< "$out")" "1 4"
out=$(UNIT_JOBS=0 env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-tmp" 2>&1); rc=$?
check "UNIT_JOBS not a positive number: refused" "$rc $(grep -c 'UNIT_JOBS' <<< "$out")" "1 1"
# a harness whose runner is killed before it records a verdict (OOM, a stray kill): the suite fails, naming it - the
# runner printed the harnesses up to it and passed on the rest unread
mkdir -p "$W/suite-lost/a-killed" "$W/suite-lost/b-clean"
printf '#!/bin/bash\nkill -9 $PPID\nsleep 1\nexit 0\n' > "$W/suite-lost/a-killed/run.sh"
printf '#!/bin/bash\necho fine\nexit 0\n' > "$W/suite-lost/b-clean/run.sh"
out=$(UNIT_JOBS=2 env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-lost" 2>&1); rc=$?
check "a harness killed before its verdict: the suite fails, naming it" \
  "$rc $(grep -c 'NO VERDICT: a-killed' <<< "$out")" "1 1"
# the harness after the killed one is still printed and judged - its output once, never itself NO VERDICT
check "a harness killed before its verdict: the clean one after it printed once, judged (not NO VERDICT)" \
  "$(grep -c '^fine$' <<< "$out") $(grep -c 'NO VERDICT: b-clean' <<< "$out")" "1 0"
# and one failing after it: printed whole and judged as usual, never swallowed as NO VERDICT (the suite's exit cannot
# tell it apart - the killed one fails the suite already - its own output and no NO VERDICT for it can)
mkdir -p "$W/suite-lost/c-fails"
printf '#!/bin/bash\necho "c-fails line"\nexit 1\n' > "$W/suite-lost/c-fails/run.sh"
out=$(UNIT_JOBS=1 env -u FENCE bash tests/ansible/unit/run.sh "$W/suite-lost" 2>&1); rc=$?
check "a killed harness, then a failing one: both printed - the killed named, the failing one's output whole" \
  "$rc $(grep -c 'NO VERDICT: a-killed' <<< "$out") $(grep -c '^c-fails line$' <<< "$out") $(grep -c 'NO VERDICT: [bc]-' <<< "$out")" \
  "1 1 1 0"
echo "unit-fence: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
