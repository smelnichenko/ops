#!/bin/bash
# scripts/vagrant-smoke.sh's two inline programs as the file holds them - the render's pick (pick.py) and the remote
# shell (the 'SH' heredoc), kubectl a stub: each run's Job and ConfigMap carry a name of its own, and the remote shell
# deletes them when it ends, also when its connection is gone (its caller stopped by a step's check: a run left behind
# held the fixed name the next run deleted and applied - its own end then deleted the next run's Job).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
S=scripts/vagrant-smoke.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1))
}
sed -n "/^cat > \"\$work\/pick.py\" <<'EOF'$/,/^EOF$/p" "$S" | sed '1d;$d' > "$W/pick.py"
sed -n "/<<'SH'/,/^SH$/p" "$S" | sed '1d;$d' > "$W/remote.sh"
check "the remote shell given the run's name" "$(grep -c "\"sudo bash -s \$name\" <<'SH'" "$S")" 1
[ -s "$W/pick.py" ] && [ -s "$W/remote.sh" ] || { echo "FAIL the inline programs not found"; exit 1; }
# the names: one per run, as the script makes them
names=$(for _ in 1 2; do bash -c "$(grep -m1 '^name=' "$S"); echo \"\$name\""; done | sort -u | wc -l)
check "each run's name its own" "$names" 2
cat > "$W/rendered.yaml" <<'Y'
kind: ConfigMap
metadata: {name: schnappy-k6-smoke}
data: {script.js: "x"}
---
kind: Job
metadata: {name: schnappy-production-k6-smoke, annotations: {argocd.argoproj.io/hook: PostSync}}
spec:
  backoffLimit: 3
  template:
    spec:
      volumes: [{name: script, configMap: {name: schnappy-k6-smoke}}]
Y
picked=$(python3 "$W/pick.py" "$W/rendered.yaml" vagrant-k6-smoke-ab12 | python3 -c '
import sys, yaml
d = list(yaml.safe_load_all(sys.stdin))
print(" ".join([x["metadata"]["name"] for x in d if x] + [d[1]["spec"]["template"]["spec"]["volumes"][0]["configMap"]["name"]]))')
check "the render: the ConfigMap, the Job and its mount named for the run" "$picked" \
  "vagrant-k6-smoke-ab12 vagrant-k6-smoke-ab12 vagrant-k6-smoke-ab12"
# kubectl: every call recorded; COMPLETE: the Complete condition at once (else neither comes - both waits sleep)
cat > "$W/kubectl" <<'STUB'
#!/bin/bash
echo "$*" >> "$W/calls"
case "$*" in
  *condition=Complete*) [ -n "${COMPLETE:-}" ] && exit 0; echo $$ >> "$W/waits"; exec sleep 30 ;;
  *condition=Failed*) echo $$ >> "$W/waits"; exec sleep 30 ;;
  *jsonpath*succeeded*) echo 1 ;;
  *" logs "*) echo "✓ status is 200" ;;
esac
exit 0
STUB
chmod +x "$W/kubectl"
mkdir -p "$W/bin"; ln -s "$W/kubectl" "$W/bin/kubectl"
remote() {  # remote <env...>: the remote shell as root runs it - its stdin the program, the run's name its argument
  : > "$W/calls"; : > "$W/waits"
  env "$@" W="$W" PATH="$W/bin:$PATH" bash -s vagrant-k6-smoke-ab12 < "$W/remote.sh"
}
out=$(remote COMPLETE=1 | tr -d '\r')
objects=$(grep -oE '(job|job/|configmap) ?[a-z0-9-]*k6-smoke[a-z0-9-]*' "$W/calls" | awk '{print $NF}' | sed 's|.*/||' \
  | sort -u | tr '\n' ' ')
check "a passing run: passed, every Job and ConfigMap it names the run's own" \
  "$(grep -c '^SMOKE PASSED$' <<< "$out") $objects" "1 vagrant-k6-smoke-ab12 "
check "a passing run: its Job and ConfigMap deleted" \
  "$(grep -cE '^.*delete (job|configmap) vagrant-k6-smoke-ab12' "$W/calls")" 2
# its connection gone (the caller stopped): the next heartbeat's write fails - it ends, deletes its Job and ConfigMap,
# and its waits are gone
t0=$SECONDS
remote | head -c 0
sleep 1
left=0; for p in $(cat "$W/waits"); do [ -e "/proc/$p" ] && left=$((left + 1)); done
check "its connection gone: it ends within a heartbeat, its Job and ConfigMap deleted, its waits gone" \
  "$((SECONDS - t0 < 15)) $(grep -cE 'delete (job|configmap) vagrant-k6-smoke-ab12' "$W/calls") $left" "1 2 0"
echo "vagrant-smoke: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
