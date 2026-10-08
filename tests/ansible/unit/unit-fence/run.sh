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
  out=$(bash tests/ansible/unit/run.sh "$W/suite-$h" 2>&1); rc=$?
  case $h in
    clean) check "a harness reaching no host: the suite passes" "$rc" 0 ;;
    *) check "a harness that $h (its failure tolerated): the suite fails, naming the call" \
         "$rc $(grep -c "FENCED: $h reached" <<< "$out")" "1 1" ;;
  esac
done
echo "unit-fence: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
