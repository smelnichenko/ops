#!/bin/bash
# A task that can refuse (its script or message says REFUSED) fails the play when it does: no ignore_errors, no
# failed_when false on it - an ignore_errors on the Consul quorum read let a restart go on with no spare server, and
# no harness noticed. Every playbook and task file of deploy/ansible and tests/ansible, blocks walked.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_REFUSALS'
import glob, sys, yaml
def walk(ts):
    for t in ts or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always", "tasks", "pre_tasks", "post_tasks", "handlers"):
                yield from walk(t.get(k))
def ignored(t):
    fw = t.get("failed_when")
    return bool(t.get("ignore_errors")) or fw is False or str(fw).strip().lower() == "false"
files = sorted(set(glob.glob("deploy/ansible/**/*.yml", recursive=True)) | set(glob.glob("tests/ansible/**/*.yml", recursive=True)))
files = [f for f in files if "/venv/" not in f and "/collections/" not in f]
bad, refusing = [], 0
for f in files:
    try:
        doc = yaml.safe_load(open(f))
    except yaml.YAMLError:
        continue
    if not isinstance(doc, list):
        continue
    for t in walk(doc):
        if "REFUSED" not in yaml.safe_dump({k: v for k, v in t.items() if k not in ("block", "rescue", "always")}):
            continue
        refusing += 1
        if ignored(t):
            bad.append(f"{f}: {t.get('name')}")
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
check("tasks that can refuse found (the walk reads them)", refusing > 20, True)
check("none ignores its own failure", bad, [])
# the walk's own control: a refusing task with ignore_errors, and one with failed_when false, are named
probe = [{"name": "a", "ansible.builtin.shell": "echo REFUSED; exit 1", "ignore_errors": True},
         {"block": [{"name": "b", "ansible.builtin.fail": {"msg": "REFUSED"}, "failed_when": False}]}]
check("control: both named", [t["name"] for t in walk(probe) if "REFUSED" in yaml.safe_dump(
    {k: v for k, v in t.items() if k != "block"}) and ignored(t)], ["a", "b"])
print("refusals-not-ignored: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_REFUSALS
