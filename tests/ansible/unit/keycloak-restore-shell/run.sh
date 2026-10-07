#!/bin/bash
# tasks/patroni-keycloak-restore.yml's restore task as the file holds it, run by ansible-playbook on localhost (Ansible
# parses and passes the script; its dump directory moved here, psql a stub): psql gets the password through .pgpass,
# escaped as .pgpass wants (\ and :), and never prompts - a password it does not get fails at once (-w). In the full
# run of 2026-10-07 the .pgpass was empty (a comment's backslash had the printf joined into it) and psql waited at a
# password prompt on Ansible's terminal for good. The dump, restored, is kept aside root-only and the waiting one gone.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin" "$W/dumps"
# psql: what it was given recorded; no password in its .pgpass is a prompt (exit 99) - or, with -w, a failure (exit 2)
cat > "$W/bin/psql" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$W/psql.args"
cat "${PGPASSFILE:-/dev/null}" > "$W/pgpass.seen"
pw=$(sed -E 's/^([^:]*:){4}//' "$W/pgpass.seen")
if [ -z "$pw" ]; then
  for a in "$@"; do [ "$a" = -w ] && { echo "psql: fe_sendauth: no password supplied" >&2; exit 2; }; done
  echo "Password for user postgres: (would wait here)" >&2; exit 99
fi
STUB
chmod +x "$W/bin/psql"
W=$W "$PY" - <<'PY' || { echo "FAIL the play could not be built"; exit 1; }
import os, yaml
W = os.environ["W"]
def tasks(node):
    for t in node:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k) or [])
task = next(t for t in tasks(yaml.safe_load(open("deploy/ansible/playbooks/tasks/patroni-keycloak-restore.yml")))
            if t.get("name") == "Restore the waiting Keycloak dump" and "ansible.builtin.shell" in t)
task = yaml.safe_load(yaml.safe_dump(task).replace("/var/backups/patroni-first-install", W + "/dumps"))
for k in ("delegate_to", "run_once", "no_log"):
    task.pop(k, None)
yaml.safe_dump([{"hosts": "pi1", "gather_facts": False, "vars": {"_restore_db": "keycloak"}, "tasks": [
    task, {"ansible.builtin.debug": {"msg": "RESTORE RC {{ _restored.rc }}"}}]}],
    open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
PY
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
run() {  # run <password>: the restore's rc
  rm -f "$W"/dumps/* "$W/psql.args" "$W/pgpass.seen"
  echo "CREATE TABLE realm (id text);" > "$W/dumps/keycloak.sql"
  printf '%s\n' "all:" "  hosts:" "    pi1:" "      ansible_connection: local" "      ansible_host: 127.0.0.1" \
    "      ansible_python_interpreter: '{{ ansible_playbook_python }}'" > "$W/hosts.yml"
  PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" -e "{\"pg_password\": $1}" 2>&1 \
    | sed -n 's/.*"msg": "RESTORE RC \([0-9]*\)".*/\1/p'
}
rc=$(run '"p\\a:ss"')
check "a password with \\ and : - .pgpass holds it escaped, for the leader's address" "$(cat "$W/pgpass.seen" 2> /dev/null)" \
  '127.0.0.1:5432:*:postgres:p\\a\:ss'
check "... restored (rc 0), never prompting (-w), one transaction (-1), into keycloak" \
  "$rc $(grep -cxE -- '-w|-1|keycloak' "$W/psql.args" 2> /dev/null)" "0 3"
check "... the dump kept aside root-only, the waiting one gone" \
  "$(stat -c %a "$W"/dumps/keycloak-restored-*.sql 2> /dev/null) $(ls "$W/dumps/keycloak.sql" 2> /dev/null | wc -l)" "600 0"
rc=$(run '""')
check "no password: fails at once, never at a prompt (psql's -w), the dump still waiting" \
  "$([ -n "$rc" ] && [ "$rc" != 0 ] && [ "$rc" != 99 ] && echo failed) $(ls "$W/dumps/keycloak.sql" 2> /dev/null | wc -l)" \
  "failed 1"
echo "keycloak-restore-shell: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
