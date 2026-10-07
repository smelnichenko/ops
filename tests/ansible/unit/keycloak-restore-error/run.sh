#!/bin/bash
# tasks/patroni-keycloak-restore.yml's message when the restore fails, as the task holds it (rendered with Jinja, the
# Ansible tests it uses given): psql's ERROR line is said; its DETAIL and CONTEXT - the dump's rows (realm keys, client
# secrets, credential hashes) - are not.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import re, sys
import jinja2, yaml
task = next(t for b in yaml.safe_load(open("deploy/ansible/playbooks/tasks/patroni-keycloak-restore.yml"))
            for t in [b] + (b.get("block") or []) if t.get("name") == "Restored (psql's own error otherwise)")
env = jinja2.Environment()
env.tests["search"] = lambda s, p: re.search(p, s) is not None
env.tests["match"] = lambda s, p: re.match(p, s) is not None
stderr = ["psql:/var/backups/patroni-first-install/keycloak.sql:4711: ERROR:  duplicate key value violates unique "
          "constraint \"constraint_a\"",
          "DETAIL:  Key (id)=(SECRET-ROW-VALUE) already exists.",
          "CONTEXT:  COPY credential, line 3: \"c1  user1  password  {\"value\":\"HASH-OF-A-PASSWORD\"}\""]
msg = env.from_string(task["ansible.builtin.assert"]["fail_msg"]).render(
    _restored={"rc": 3, "stderr": "\n".join(stderr), "stderr_lines": stderr})
fails = 0
for name, ok in (("psql's ERROR said", "duplicate key value violates" in msg),
                 ("its DETAIL's row not", "SECRET-ROW-VALUE" not in msg),
                 ("its CONTEXT's row not", "HASH-OF-A-PASSWORD" not in msg)):
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {msg}"))
print("keycloak-restore-error: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
