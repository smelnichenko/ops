#!/bin/bash
# The two places that wait for a Job's Complete and Failed side by side and stop the other wait - strimzi-v1-conversion
# and vagrant-smoke - their lines as the files hold them, kubectl a stub (Complete at once, Failed for 30 s), `kill`
# recorded (passed on to the running wait alone): only the wait still running is signalled - the one wait -n reaped is
# no process of theirs any more (its PID free for another) - and it stops.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
# the playbook as Ansible loads it first: a quote in a free-form shell block's comment fails its argument splitting
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, deploy/ansible/playbooks/strimzi-v1-conversion.yml > /dev/null 2>&1 \
  || { echo "FAIL deploy/ansible/playbooks/strimzi-v1-conversion.yml does not load"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cat > "$W/kubectl" <<'STUB'
#!/bin/bash
case "$*" in *condition=Complete*) exit 0 ;; *condition=Failed*) exec sleep 30 ;; esac
STUB
chmod +x "$W/kubectl"
fails=0
for f in deploy/ansible/playbooks/strimzi-v1-conversion.yml scripts/vagrant-smoke.sh; do
  # from the Complete waiter through the kill (its first line not a comment that names kill): the file's own lines,
  # indentation dropped
  block=$(sed -n '/--for=condition=Complete/,/^[^#]*kill /p' "$f" | sed 's/^ *//')
  {
    # recorded; passed on only to the Failed wait - a child still running here - never to a PID wait -n reaped
    echo 'kill() { echo "$*" >> "$W/killed"; local p; for p; do [ "$p" != "$failed" ] || builtin kill "$p"; done; }'
    echo "K=$W/kubectl job=x"
    printf '%s\n' "$block"
    echo 'wait "$failed"; echo "FAILED_RC=$? OK=$ok FAILED=$failed"'
  } > "$W/block.sh"
  : > "$W/killed"
  out=$(W=$W timeout 20 bash "$W/block.sh" 2>&1)
  ok=$(sed -n 's/.* OK=\([0-9]*\) .*/\1/p' <<< "$out"); failed=$(sed -n 's/.* FAILED=\([0-9]*\)$/\1/p' <<< "$out")
  got="$(tr '\n' ' ' < "$W/killed")| $(grep -o 'FAILED_RC=[0-9]*' <<< "$out")"
  if [ -n "$ok" ] && [ "$got" = "$failed | FAILED_RC=143" ]; then
    echo "PASS $f: only the wait still running signalled, stopped"
  else
    echo "FAIL $f: kill got '$got' (ok $ok, failed $failed; want '$failed | FAILED_RC=143')"
    printf '%s\n' "$out" | head -5; fails=$((fails + 1))
  fi
done
echo "waiter-kill: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
