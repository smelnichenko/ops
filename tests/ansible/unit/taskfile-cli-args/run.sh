#!/bin/bash
# Every deploy task that runs a playbook against production passes the arguments after `--` on to it: one that did not
# ran `task --yes deploy:caddy -- --check` as a real run - production's Caddy changed and restarted by what was meant
# as a preview (2026-11-16). Each ansible-playbook command against inventory/production.yml in a deploy:* task ends in
# {{.CLI_ARGS}}.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PYCHECK'
import sys, yaml
tasks = yaml.safe_load(open("Taskfile.yml"))["tasks"]
found, bad = 0, []
for name, v in tasks.items():
    if not (name.startswith("deploy:") and isinstance(v, dict)):
        continue
    for c in v.get("cmds") or []:
        cmd = c if isinstance(c, str) else (c.get("cmd") or "") if isinstance(c, dict) else ""
        for line in cmd.splitlines():
            if "ansible-playbook" in line and "inventory/production.yml" in line:
                found += 1
                if "{{.CLI_ARGS}}" not in line:
                    bad.append(f"{name}: {line.strip()[:100]}")
ok = found > 20 and not bad
print(("PASS" if ok else "FAIL") + f" every production playbook a deploy task runs takes the arguments after -- ({found} found)")
for b in bad:
    print("    " + b)
print("taskfile-cli-args: " + ("ALL-PASS" if ok else "1 FAILED"))
sys.exit(0 if ok else 1)
PYCHECK
