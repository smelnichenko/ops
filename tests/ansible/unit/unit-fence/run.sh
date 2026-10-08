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
echo "unit-fence: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
