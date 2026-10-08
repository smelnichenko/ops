#!/bin/bash
# The places that wait for a Job's Complete and Failed side by side and stop the other wait - strimzi-v1-conversion,
# backup-check (vagrant-smoke polls instead) - their lines as the files hold them, kubectl a stub (one condition at once, the other
# sleeping - both orders), `kill` recorded (passed on to the running wait alone): only the wait still running is
# signalled - the one wait -n reaped is no process of theirs any more (its PID free for another) - and it stops.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
# the playbook as Ansible loads it first: a quote in a free-form shell block's comment fails its argument splitting
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, deploy/ansible/playbooks/strimzi-v1-conversion.yml > /dev/null 2>&1 \
  || { echo "FAIL deploy/ansible/playbooks/strimzi-v1-conversion.yml does not load"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# FIRST: the condition that comes at once; the other wait sleeps until signalled
cat > "$W/kubectl" <<'STUB'
#!/bin/bash
case "$*" in *"condition=$FIRST"*) exit 0 ;; *condition=*) exec sleep 30 ;; esac
STUB
chmod +x "$W/kubectl"
fails=0
for f in deploy/ansible/playbooks/strimzi-v1-conversion.yml tests/ansible/upgrade/backup-check.yml
do
  for first in Complete Failed; do
    # from the Complete waiter through the kill (its first line not a comment that names kill): the file's own lines,
    # indentation dropped
    block=$(sed -n '/--for=condition=Complete/,/^[^#]*kill /p' "$f" | sed 's/^ *//')
    {
      # recorded; passed on only to the wait still running - never to a PID wait -n reaped
      echo 'running() { [ "$FIRST" = Complete ] && echo "$failed" || echo "$ok"; }'
      echo 'kill() { echo "$*" >> "$W/killed"; local p; for p; do [ "$p" != "$(running)" ] || builtin kill "$p"; done; }'
      echo "K=$W/kubectl job=x"
      printf '%s\n' "$block"
      echo 'r=$(running); wait "$r"; echo "RUNNING_RC=$? RUNNING=$r"'
    } > "$W/block.sh"
    : > "$W/killed"
    out=$(W=$W FIRST=$first timeout 20 bash "$W/block.sh" 2>&1)
    running=$(sed -n 's/.* RUNNING=\([0-9]*\)$/\1/p' <<< "$out")
    got="$(tr '\n' ' ' < "$W/killed")| $(grep -o 'RUNNING_RC=[0-9]*' <<< "$out")"
    if [ -n "$running" ] && [ "$got" = "$running | RUNNING_RC=143" ]; then
      echo "PASS $f, $first first: only the wait still running signalled, stopped"
    else
      echo "FAIL $f, $first first: kill got '$got' (want '$running | RUNNING_RC=143')"
      printf '%s\n' "$out" | head -5; fails=$((fails + 1))
    fi
  done
done
# both conditions at once: the other wait has ended too - bash collected it (a pause after wait -n lets it), its PID
# free for another process: nothing signalled
cat > "$W/kubectl" <<'STUB'
#!/bin/bash
exit 0
STUB
for f in deploy/ansible/playbooks/strimzi-v1-conversion.yml tests/ansible/upgrade/backup-check.yml; do
  block=$(sed -n '/--for=condition=Complete/,/^[^#]*kill /p' "$f" | sed 's/^ *//' | sed '/^wait -n /a sleep 0.5')
  {
    echo 'kill() { echo "$*" >> "$W/killed"; }'
    echo "K=$W/kubectl job=x"
    printf '%s\n' "$block"
  } > "$W/block.sh"
  : > "$W/killed"
  out=$(W=$W timeout 20 bash "$W/block.sh" 2>&1)
  if [ ! -s "$W/killed" ]; then echo "PASS $f, both at once: the other wait ended - nothing signalled"
  else echo "FAIL $f, both at once: signalled '$(tr '\n' ' ' < "$W/killed")' - a PID bash already collected"
    fails=$((fails + 1)); fi
done
echo "waiter-kill: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
