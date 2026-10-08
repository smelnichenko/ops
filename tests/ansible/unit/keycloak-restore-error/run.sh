#!/bin/bash
# tasks/patroni-keycloak-restore.yml's message when the restore fails, as the task holds it (rendered by Ansible's
# templar): psql's ERROR line is said, what it quotes masked (an ERROR can quote a value); its DETAIL and CONTEXT - the
# dump's rows (realm keys, client secrets, credential hashes) - are not.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
task = next(t for b in yaml.safe_load(open("deploy/ansible/playbooks/tasks/patroni-keycloak-restore.yml"))
            for t in [b] + (b.get("block") or []) if t.get("name") == "Restored (psql's own error otherwise)")
stderr = ["psql:/var/backups/patroni-first-install/keycloak.sql:4711: ERROR:  duplicate key value violates unique "
          "constraint \"constraint_a\"",
          "DETAIL:  Key (id)=(SECRET-ROW-VALUE) already exists.",
          "CONTEXT:  COPY credential, line 3: \"c1  user1  password  {\"value\":\"HASH-OF-A-PASSWORD\"}\""]
msg = render(task["ansible.builtin.assert"]["fail_msg"],
             _restored={"rc": 3, "stderr": "\n".join(stderr), "stderr_lines": stderr})
fails = 0
for name, ok in (("psql's ERROR said", "duplicate key value violates" in msg),
                 ("its DETAIL's row not", "SECRET-ROW-VALUE" not in msg),
                 ("its CONTEXT's row not", "HASH-OF-A-PASSWORD" not in msg)):
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {msg}"))
# an ERROR line can quote a value itself: what it quotes masked, the error said
stderr = ["psql:/var/backups/patroni-first-install/keycloak.sql:812: ERROR:  invalid input syntax for type uuid: "
          "\"A-CLIENT-SECRET\""]
msg = render(task["ansible.builtin.assert"]["fail_msg"],
             _restored={"rc": 3, "stderr": "\n".join(stderr), "stderr_lines": stderr})
for name, ok in (("an ERROR quoting a value: said", "invalid input syntax for type uuid" in msg),
                 ("the value it quotes not", "A-CLIENT-SECRET" not in msg)):
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {msg}"))
# a value with a quote inside: masked to the end of the line (a mask to the next quote let its tail through)
stderr = ["psql:/var/backups/patroni-first-install/keycloak.sql:812: ERROR:  invalid input syntax for type json: "
          "\"{\"secret\":\"A-SECRET-TAIL\"}\""]
msg = render(task["ansible.builtin.assert"]["fail_msg"],
             _restored={"rc": 3, "stderr": "\n".join(stderr), "stderr_lines": stderr})
for name, ok in (("a value quoting a quote: said", "invalid input syntax for type json" in msg),
                 ("no part of it", "A-SECRET-TAIL" not in msg and "secret" not in msg)):
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {msg}"))
print("keycloak-restore-error: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
