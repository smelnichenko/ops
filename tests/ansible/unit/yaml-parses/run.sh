#!/bin/bash
# Every YAML file of the repo parses (its playbooks and task files, the Vagrant tests, the CI pipelines, the Taskfile,
# the PromQL tests): ansible-lint reads only deploy/ansible/playbooks, and a test playbook broken by a plain scalar
# holding ": " ran nowhere until a Pi hand test.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PYCHECK'
import fnmatch, subprocess, sys
import yaml
# the repo's own files - tracked, or new and not ignored: what a checkout has (git-ignored collections and venvs
# installed here are no file of the repo; CI's clone never had them)
# (safe.directory: a checkout owned by another user than the one testing it - a container's root - is still read)
ls = subprocess.run(["git", "-c", "safe.directory=*", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                    capture_output=True)
if ls.returncode:
    sys.exit("yaml-parses: FAILED - git cannot list the repo's files: " + ls.stderr.decode().strip())
own = ls.stdout.decode().split("\0")
files = sorted({f for f in own for pat in ("deploy/*.y*ml", "tests/*.y*ml", ".woodpecker/*.y*ml", "Taskfile.yml")
                if fnmatch.fnmatch(f, pat)} | {f for f in own if "/" not in f and fnmatch.fnmatch(f, "*.y*ml")})
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
