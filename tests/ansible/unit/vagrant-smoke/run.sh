#!/bin/bash
# scripts/vagrant-smoke.sh's two inline programs as the file holds them - the render's pick (pick.py) and the remote
# shell (the 'SH' heredoc), kubectl a stub: each run's Job and ConfigMap carry a name of its own, and the remote shell
# deletes them when it ends, also when its connection is gone (its caller stopped by a step's check: a run left behind
# held the fixed name the next run deleted and applied - its own end then deleted the next run's Job). The run's bound
# and poll reach the remote shell as its arguments (ssh forwards no environment, sudo resets it: the caller's were
# read on the VM as unset), numbers only; its deadline on the VM's /proc/uptime (bash's SECONDS follows the wall clock).
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
check "the remote shell given the run's name, its bound and its poll" \
  "$(grep -c "\"sudo bash -s \$name \$SMOKE_SECONDS \$SMOKE_POLL\" <<'SH'" "$S")" 1
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
  *jsonpath*conditions*) [ -z "${SLOW_GET:-}" ] || sleep 1; echo "${ENDED:-}"
    # FAKE_CLOCK: the VM's uptime 1000 s on at each poll
    [ -z "${FAKE_CLOCK:-}" ] || { read -r u _ < "$W/uptime"; echo "$(( ${u%.*} + 1000 )).00 0.00" > "$W/uptime"; } ;;
  *jsonpath*succeeded*) [ "${ENDED:-}" = Complete ] && echo 1 ;;
  *" logs "*) echo "✓ status is 200" ;;
  # the smoke objects by label: LEFTOVER - an earlier run's, an hour old; CONCURRENT - another run's, a minute old;
  # SLOW_GET - each poll's read takes a second (the deadline is the clock's, not a count of polls)
  *"get job,configmap -l app.kubernetes.io/name=vagrant-k6-smoke"*)
    [ -z "${LEFTOVER:-}" ] || echo "Job/vagrant-k6-smoke-0ld $(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
    [ -z "${CONCURRENT:-}" ] || echo "Job/vagrant-k6-smoke-fr3sh $(date -u -d '-1 minute' +%Y-%m-%dT%H:%M:%SZ)" ;;
  *"delete job/"*|*"delete configmap/"*) echo "${*##* }" | sed 's|.*/||; s|^|deleted |' ;;
esac
exit 0
STUB
chmod +x "$W/kubectl"
mkdir -p "$W/bin"; ln -s "$W/kubectl" "$W/bin/kubectl"
remote() {  # remote <env...>: the remote shell as root runs it - its stdin the program, the run's name, bound and poll
  # its arguments (SECS, POLL: 900 and 5 by default, as the script passes them)
  : > "$W/calls"
  # bounded: a shell that never ends fails here rather than hanging the suite
  timeout -k 5 40 env "$@" W="$W" PATH="$W/bin:$PATH" bash -s vagrant-k6-smoke-ab12 "${SECS:-900}" "${POLL:-5}" \
    < "${PROGRAM:-$W/remote.sh}"
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
# (its whole `trap 'exit 1' HUP INT TERM PIPE` line is an equivalent mutant on bash 5.2.37: a fatal HUP, TERM or PIPE
# runs the EXIT trap too - measured, without the line: exits 129, 143, 141, each with its 2 deletes; the line keeps the
# exit explicit)
t0=$SECONDS
remote | head -c 0
check "its connection gone: it ends at its next heartbeat, its Job and ConfigMap deleted" \
  "$((SECONDS - t0 < 10)) $(deleted)" "1 2"
# an earlier run's leftovers (one whose connection and cleanup were both cut) removed before this run's apply, said so;
# none, nothing said; every call bounded (a hung API server held the poll for good)
out=$(remote ENDED=Complete LEFTOVER=1 | tr -d '\r')
first_delete=$(grep -n 'delete job/vagrant-k6-smoke-0ld' "$W/calls" | head -1 | cut -d: -f1)
apply=$(grep -n ' apply ' "$W/calls" | head -1 | cut -d: -f1)
check "an earlier run's leftovers removed by label before the apply, said so" \
  "$([ -n "$first_delete" ] && [ -n "$apply" ] && [ "$first_delete" -lt "$apply" ] && echo before) $(grep -c 'earlier run.s leftovers removed' <<< "$out")" \
  "before 1"
out=$(remote ENDED=Complete | tr -d '\r')
check "none left: nothing said" "$(grep -c 'leftovers' <<< "$out")" 0
# another run's, still within its own bound (a concurrent smoke): left alone - only what outlived any run is removed
out=$(remote ENDED=Complete LEFTOVER=1 CONCURRENT=1 | tr -d '\r')
check "a concurrent run's objects kept, an earlier run's removed" \
  "$(grep -c 'delete job/vagrant-k6-smoke-fr3sh' "$W/calls") $(grep -c 'delete job/vagrant-k6-smoke-0ld' "$W/calls")" "0 1"
# the run's bound is the clock's: a slow poll does not stretch it (180 polls of up to 35 s each were not 15 minutes)
t0=$SECONDS
out=$(SECS=3 POLL=0.1 remote SLOW_GET=1 | tr -d '\r'; echo "exit ${PIPESTATUS[0]}"); rc=${out##*exit }
check "never ending: failed at its deadline, by the clock" "$rc $((SECONDS - t0 < 10)) $(grep -c '^SMOKE FAILED' <<< "$out")" \
  "1 1 1"
check "every kubectl call bounded (--request-timeout)" "$(grep -vc -- '--request-timeout=' "$W/calls")" 0
# the deadline on the VM's uptime: a clock 1000 s on at each poll ends a 1500 s bound at the second poll - bash's
# SECONDS, following the wall clock, waited the 1500 s (here: cut at 40)
sed "s|/proc/uptime|$W/uptime|g" "$W/remote.sh" > "$W/remote-clock.sh"
check "the remote shell's clock read from /proc/uptime (the copy reads a file of the test's)" \
  "$(grep -c "$W/uptime" "$W/remote-clock.sh")" 2
echo "1000.00 0.00" > "$W/uptime"
t0=$SECONDS
out=$(SECS=1500 POLL=0.1 PROGRAM="$W/remote-clock.sh" remote FAKE_CLOCK=1 | tr -d '\r'; echo "exit ${PIPESTATUS[0]}")
rc=${out##*exit }
check "its deadline on the VM's uptime: past it after two polls of a clock 1000 s on each - failed at once" \
  "$rc $((SECONDS - t0 < 10)) $(grep -c 'jsonpath.*conditions' "$W/calls")" "1 1 2"
# the heartbeat is the poll's own write: no process of its own (one left behind signalled a PID that may be another's)
check "no background process in the remote shell (a lone &, not && or a redirection)" \
  "$(grep -cE '(^|[^&<>])&([[:space:]]|$)' "$W/remote.sh")" 0
# the whole script, its smoke failing on the VM: it exits non-zero - its remote shell's output goes through `tr`, and
# without pipefail the pipeline's exit was tr's (0): a failed smoke passed
E=$W/e2e; mkdir -p "$E/ops/scripts" "$E/ops/.upgrade" "$E/bin"
cp "$S" "$E/ops/scripts/"
for r in platform infra; do git init -q -b main "$E/$r"; done
mkdir -p "$E/platform/helm/schnappy" "$E/infra/clusters/production/schnappy-production-apps"
echo "name: schnappy" > "$E/platform/helm/schnappy/Chart.yaml"
echo "x: 1" > "$E/infra/clusters/production/schnappy-production-apps/values.yaml"
for r in platform infra; do
  git -C "$E/$r" add -A; git -C "$E/$r" -c user.name=t -c user.email=t@t commit -q -m c
done
cat > "$E/bin/helm" <<'STUB'
#!/bin/bash
cat <<'Y'
kind: ConfigMap
metadata: {name: schnappy-k6-smoke}
data: {script.js: "x"}
---
kind: Job
metadata: {name: schnappy-production-k6-smoke}
spec:
  backoffLimit: 3
  template:
    spec:
      volumes: [{name: script, configMap: {name: schnappy-k6-smoke}}]
Y
STUB
# the VM: the yaml copied; the remote shell's smoke failing
cat > "$E/bin/ssh" <<'STUB'
#!/bin/bash
cat > /dev/null
case "${@: -1}" in *"bash -s"*) printf 'SMOKE FAILED (Failed)\r\n'; exit 1 ;; esac
exit 0
STUB
chmod +x "$E/bin/helm" "$E/bin/ssh"
out=$(cd "$E/ops" && PATH="$E/bin:$PATH" VAGRANT_SSH_CONFIG=/dev/null bash scripts/vagrant-smoke.sh 2>&1); rc=$?
check "the smoke failing on the VM: the script fails, said" "$((rc != 0)) $(grep -c '^SMOKE FAILED' <<< "$out")" "1 1"
# its latency threshold alone crossed - every check passed, no request failed (the first requests after a step
# restarted every pod): one more run under a name of its own, and that run decides; any other failure stands, no
# second run. The VM answers each run in turn (answer.N, its exit rc.N), as k6's checks print
cat > "$E/bin/ssh" <<'STUB'
#!/bin/bash
cat > /dev/null
case "${@: -1}" in
  # the probe for a production container started lately: "recent" unless $E/no-recent is there
  "sudo bash -s") [ -e "$E/no-recent" ] || echo recent ;;
  *"bash -s"*) n=$(( $(cat "$E/n" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$E/n"; echo "${@: -1}" >> "$E/runs"
    cat "$E/answer.$n" 2> /dev/null; exit "$(cat "$E/rc.$n" 2> /dev/null || echo 1)" ;;
esac
exit 0
STUB
chmod +x "$E/bin/ssh"
DUR="time=\"x\" level=error msg=\"thresholds on metrics 'http_req_duration' have been crossed\""
answer() {  # answer <name> <exit> <lines...>
  local n=$1 r=$2; shift 2
  printf '%s\n' "--- k6 checks" "$@" > "$E/$n"; echo "$r" > "$E/$n.rc"
}
answer pass 0 "    ✓ 'rate==1.0' rate=100.00%" "    ✓ 'p(95)<2000' p(95)=812.00ms" "    ✓ health 200" \
  "    http_req_failed................: 0.00%  0 out of 12" "SMOKE PASSED"
answer latency 1 "$DUR" "    ✓ 'rate==1.0' rate=100.00%" "    ✗ 'p(95)<2000' p(95)=2.88s" "    ✓ health 200" \
  "    http_req_failed................: 0.00%  0 out of 12" "SMOKE FAILED (FailureTarget Failed)"
answer check 1 "time=\"x\" level=error msg=\"thresholds on metrics 'checks, http_req_duration' have been crossed\"" \
  "    ✗ 'rate==1.0' rate=91.66%" "    ✗ 'p(95)<2000' p(95)=2.88s" "    ✗ health 200" \
  "    http_req_failed................: 0.00%  0 out of 12" "SMOKE FAILED (FailureTarget Failed)"
answer request 1 "$DUR" "    ✓ 'rate==1.0' rate=100.00%" "    ✗ 'p(95)<2000' p(95)=2.88s" "    ✓ health 200" \
  "    http_req_failed................: 8.33%  1 out of 12" "SMOKE FAILED (FailureTarget Failed)"
answer warning 1 "$DUR" "time=\"x\" level=error msg=\"setup failed\"" "    ✓ 'rate==1.0' rate=100.00%" \
  "    ✗ 'p(95)<2000' p(95)=2.88s" "    http_req_failed................: 0.00%  0 out of 12" "SMOKE FAILED (Failed)"
answer silent 1 "SMOKE FAILED (Failed)"
# what was printed of k6 cut short: its latency line without its error, or no check passed among it - not known to be
# the latency alone
answer no-error 1 "    ✓ 'rate==1.0' rate=100.00%" "    ✗ 'p(95)<2000' p(95)=2.88s" \
  "    http_req_failed................: 0.00%  0 out of 12" "SMOKE FAILED (Failed)"
answer no-check 1 "$DUR" "    ✗ 'p(95)<2000' p(95)=2.88s" "    http_req_failed................: 0.00%  0 out of 12" \
  "SMOKE FAILED (Failed)"
runs() {  # runs <answers...>: the script's exit, its runs on the VM, their distinct names
  rm -f "$E/n" "$E/runs" "$E"/answer.* "$E"/rc.*; local i=0 a
  for a; do i=$((i + 1)); cp "$E/$a" "$E/answer.$i"; cp "$E/$a.rc" "$E/rc.$i"; done
  out=$(cd "$E/ops" && PATH="$E/bin:$PATH" E="$E" VAGRANT_SSH_CONFIG=/dev/null bash scripts/vagrant-smoke.sh 2>&1)
  echo "$? $(wc -l < "$E/runs") $(grep -oE 'vagrant-k6-smoke-[0-9a-f]+' "$E/runs" | sort -u | wc -l)"
}
check "its latency alone crossed, then passed: passed, two runs under two names" "$(runs latency pass)" "0 2 2"
check "its latency alone crossed twice: failed, two runs" "$(runs latency latency)" "1 2 2"
touch "$E/no-recent"
check "its latency alone crossed, no container started lately: failed, no second run" "$(runs latency pass)" "1 1 1"
rm -f "$E/no-recent"
check "passed: one run" "$(runs pass)" "0 1 1"
check "a check failed (its latency with it): failed, no second run" "$(runs check pass)" "1 1 1"
check "a request failed: failed, no second run" "$(runs request pass)" "1 1 1"
check "another error beside the latency: failed, no second run" "$(runs warning pass)" "1 1 1"
check "failed with nothing of k6's printed: failed, no second run" "$(runs silent pass)" "1 1 1"
check "its latency line without k6's error: failed, no second run" "$(runs no-error pass)" "1 1 1"
check "no check printed as passed: failed, no second run" "$(runs no-check pass)" "1 1 1"
out=$(runs latency pass > /dev/null; cd "$E/ops" && rm -f "$E/n" "$E/runs" && cp "$E/latency" "$E/answer.1" && \
  cp "$E/latency.rc" "$E/rc.1" && cp "$E/pass" "$E/answer.2" && cp "$E/pass.rc" "$E/rc.2" && \
  PATH="$E/bin:$PATH" E="$E" VAGRANT_SSH_CONFIG=/dev/null bash scripts/vagrant-smoke.sh 2>&1)
check "both runs said: the first's latency, why once more, the second's pass" \
  "$(grep -c "p(95)=2.88s" <<< "$out") $(grep -c 'once more' <<< "$out") $(grep -c '^SMOKE PASSED$' <<< "$out")" "1 1 1"
# the caller's bound and poll reach the remote shell, on its command line - numbers only (that line is a shell's)
printf '#!/bin/bash\necho "${@: -1}" >> "%s/ssh-cmds"\ncat > /dev/null\ncase "${@: -1}" in *"bash -s"*) echo "SMOKE PASSED" ;; esac\n' \
  "$E" > "$E/bin/ssh"
: > "$E/ssh-cmds"
out=$(cd "$E/ops" && PATH="$E/bin:$PATH" VAGRANT_SSH_CONFIG=/dev/null SMOKE_SECONDS=7 SMOKE_POLL=2 \
  bash scripts/vagrant-smoke.sh 2>&1); rc=$?
check "the caller's SMOKE_SECONDS and SMOKE_POLL given to the remote shell" \
  "$rc $(grep -cE '^sudo bash -s vagrant-k6-smoke-[0-9a-f]+ 7 2$' "$E/ssh-cmds")" "0 1"
: > "$E/ssh-cmds"
out=$(cd "$E/ops" && PATH="$E/bin:$PATH" VAGRANT_SSH_CONFIG=/dev/null SMOKE_SECONDS='9; reboot' \
  bash scripts/vagrant-smoke.sh 2>&1); rc=$?
check "a bound that is no number: refused, nothing sent to the VM" "$((rc != 0)) $(wc -l < "$E/ssh-cmds")" "1 0"
# a poll of no time: refused (sleep 0 polled the API server without a pause); a fraction of a second taken
for poll in 0 0.0 00; do
  : > "$E/ssh-cmds"
  out=$(cd "$E/ops" && PATH="$E/bin:$PATH" VAGRANT_SSH_CONFIG=/dev/null SMOKE_POLL=$poll bash scripts/vagrant-smoke.sh 2>&1)
  rc=$?
  check "SMOKE_POLL=$poll: refused, nothing sent to the VM" "$((rc != 0)) $(wc -l < "$E/ssh-cmds")" "1 0"
done
: > "$E/ssh-cmds"
out=$(cd "$E/ops" && PATH="$E/bin:$PATH" VAGRANT_SSH_CONFIG=/dev/null SMOKE_POLL=0.5 bash scripts/vagrant-smoke.sh 2>&1)
rc=$?
check "SMOKE_POLL=0.5: taken, given to the remote shell" \
  "$rc $(grep -cE '^sudo bash -s vagrant-k6-smoke-[0-9a-f]+ 900 0.5$' "$E/ssh-cmds")" "0 1"
echo "vagrant-smoke: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
