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
print(" ".join([x["metadata"]["name"] for x in d if x] + [d[1]["spec"]["template"]["spec"]["volumes"][0]["configMap"]["name"]]
               + [x["metadata"].get("labels", {}).get("app.kubernetes.io/name", "-") for x in d if x]))')
check "the render: the ConfigMap, the Job and its mount named for the run, both labelled as a smoke run's" "$picked" \
  "vagrant-k6-smoke-ab12 vagrant-k6-smoke-ab12 vagrant-k6-smoke-ab12 vagrant-k6-smoke vagrant-k6-smoke"
# kubectl: every call recorded; ENDED: the Job's condition (none: still running)
cat > "$W/kubectl" <<'STUB'
#!/bin/bash
echo "$*" >> "$W/calls"
case "$*" in
  *jsonpath*conditions*) echo "${ENDED:-}" ;;
  *jsonpath*succeeded*) [ "${ENDED:-}" = Complete ] && echo 1 ;;
  *" logs "*) echo "✓ status is 200" ;;
  *"delete job,configmap -l app.kubernetes.io/name=vagrant-k6-smoke"*)  # as kubectl 1.34 answers (read on ten)
    if [ -n "${LEFTOVER:-}" ]; then echo 'job.batch "vagrant-k6-smoke-0ld" deleted'; else echo "No resources found"; fi ;;
esac
exit 0
STUB
chmod +x "$W/kubectl"
mkdir -p "$W/bin"; ln -s "$W/kubectl" "$W/bin/kubectl"
remote() {  # remote <env...>: the remote shell as root runs it - its stdin the program, the run's name its argument
  : > "$W/calls"
  # bounded: a shell that never ends fails here rather than hanging the suite
  timeout -k 5 40 env "$@" W="$W" PATH="$W/bin:$PATH" bash -s vagrant-k6-smoke-ab12 < "$W/remote.sh"
}
deleted() { grep -cE 'delete (job|configmap) vagrant-k6-smoke-ab12' "$W/calls"; }
out=$(remote ENDED=Complete | tr -d '\r'; echo "exit ${PIPESTATUS[0]}"); rc=${out##*exit }
objects=$(grep -oE '(job|job/|configmap) ?[a-z0-9-]*k6-smoke[a-z0-9-]*' "$W/calls" | awk '{print $NF}' | sed 's|.*/||' \
  | sort -u | tr '\n' ' ')
check "a passing run: passed, every Job and ConfigMap it names the run's own" \
  "$rc $(grep -c '^SMOKE PASSED$' <<< "$out") $objects" "0 1 vagrant-k6-smoke-ab12 "
check "a passing run: its Job and ConfigMap deleted" "$(deleted)" 2
out=$(remote ENDED=Failed | tr -d '\r'; echo "exit ${PIPESTATUS[0]}"); rc=${out##*exit }
check "a failed Job: failed, said so, its Job and ConfigMap deleted" \
  "$rc $(grep -c '^SMOKE FAILED (Failed)$' <<< "$out") $(deleted)" "1 1 2"
# its connection gone (the caller stopped): the next heartbeat's write fails - it ends, deleting its Job and ConfigMap
# (PIPE in its trap is an equivalent mutant on bash 5.2: a fatal SIGPIPE runs the EXIT trap too - measured
# 2026-10-07, the shell's exit 141 and its deletes; the trap keeps the exit explicit)
t0=$SECONDS
remote | head -c 0
check "its connection gone: it ends at its next heartbeat, its Job and ConfigMap deleted" \
  "$((SECONDS - t0 < 10)) $(deleted)" "1 2"
# an earlier run's leftovers (one whose connection and cleanup were both cut) removed before this run's apply, said so;
# none, nothing said; every call bounded (a hung API server held the poll for good)
out=$(remote ENDED=Complete LEFTOVER=1 | tr -d '\r')
first_delete=$(grep -n 'delete job,configmap -l app.kubernetes.io/name=vagrant-k6-smoke' "$W/calls" | head -1 | cut -d: -f1)
apply=$(grep -n ' apply ' "$W/calls" | head -1 | cut -d: -f1)
check "an earlier run's leftovers removed by label before the apply, said so" \
  "$([ -n "$first_delete" ] && [ -n "$apply" ] && [ "$first_delete" -lt "$apply" ] && echo before) $(grep -c 'earlier run.s leftovers removed' <<< "$out")" \
  "before 1"
out=$(remote ENDED=Complete | tr -d '\r')
check "none left: nothing said" "$(grep -c 'leftovers' <<< "$out")" 0
check "every kubectl call bounded (--request-timeout)" "$(grep -vc -- '--request-timeout=' "$W/calls")" 0
# the heartbeat is the poll's own write: no process of its own (one left behind signalled a PID that may be another's)
check "no background process in the remote shell" "$(grep -cE '&( |$)' "$W/remote.sh")" 0
echo "vagrant-smoke: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
