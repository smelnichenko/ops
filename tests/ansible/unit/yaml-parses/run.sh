#!/bin/bash
# Every YAML file of the repo parses (its playbooks and task files, the Vagrant tests, the CI pipelines, the Taskfile,
# the PromQL tests): ansible-lint reads only deploy/ansible/playbooks, and a test playbook broken by a plain scalar
# holding ": " ran nowhere until a Pi hand test.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PYCHECK'
import glob, sys
import yaml
files = sorted(f for pat in ("deploy/**/*.y*ml", "tests/**/*.y*ml", ".woodpecker/*.y*ml", "Taskfile.yml", "*.y*ml")
               for f in glob.glob(pat, recursive=True) if "/venv/" not in f and "/.venv/" not in f)
bad = []
for f in files:
    try:
        list(yaml.safe_load_all(open(f)))
    except yaml.YAMLError as e:
        bad.append(f"{f}: {str(e).splitlines()[0]} {getattr(e, 'problem_mark', '')}".strip())
print(("PASS" if not bad else "FAIL") + f" every YAML file parses ({len(files)})" + "".join("\n  " + b for b in bad))
print("yaml-parses: " + ("ALL-PASS" if not bad and len(files) > 100 else "FAILED"))
sys.exit(0 if not bad and len(files) > 100 else 1)
PYCHECK
