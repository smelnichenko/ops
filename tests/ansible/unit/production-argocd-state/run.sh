#!/bin/bash
# The copy's Argo CD as production's until the first step that runs setup-argocd.yml on ten (31): the copy's build
# installs today's - the Application health check (the root waiting for each sync wave's apps Healthy) and the root's
# sync retries - which production has not had since 2026-10-01 (read on ten 2026-10-09: no such key in argocd-cm, no
# retry on the root). Without them steps 01-30 were proven with waves production does not wait on (the Scylla operator
# Healthy before its Manager moved, steps 15, 18, 21). tests/ansible/upgrade/production-argocd-state.yml takes both
# away right after the build's setup-argocd.yml, for a run from before that step.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import json, os, re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import actions  # noqa: E402
from templar import condition  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


steps = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
first = next(s for s in steps if re.search(r"(?m)^playbook setup-argocd\.yml",
                                            open(f"tests/ansible/upgrade/steps/{s}.txt").read()))
path = "tests/ansible/upgrade/production-argocd-state.yml"
play = (yaml.safe_load(open(path)) if os.path.exists(path) else [{}])[0]
tasks = play.get("tasks") or []
ends = [i for i, t in enumerate(tasks) if t.get("ansible.builtin.meta") == "end_play"]
before = steps[steps.index(first) - 1]
check(f"guarded first, then only for a run from before {first} (the first step running setup-argocd on ten)",
      ([i for i, t in enumerate(tasks) if "vagrant-only" in str(t.get("ansible.builtin.import_tasks", ""))][:1], ends[:1],
       [condition(tasks[ends[0]].get("when", "false"), **({"upgrade_from": f} if f else {}))
        for f in (None, steps[0], first, steps[steps.index(first) + 1])] if ends else None),
      ([0], [1], [False, False, False, True]))
text = json.dumps(tasks)
key = re.search(r"resource\.customizations\.health\.argoproj\.io_Application",
                open("deploy/ansible/playbooks/setup-argocd.yml").read())
check("argocd-cm without the Application health check setup-argocd installs",
      (bool(key), '"op": "remove", "path": "/data/resource.customizations.health.argoproj.io_Application"' in text
       or "/data/resource.customizations.health.argoproj.io_Application" in text), (True, True))
check("the root Application without its sync retries", "/spec/syncPolicy/retry" in text, True)
argo = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:argo"]["cmds"]
cmds = [c.get("cmd", "") if isinstance(c, dict) else str(c) for c in argo]
at = [i for i, c in enumerate(cmds) if "production-argocd-state.yml" in c]
setup = [i for i, c in enumerate(cmds) if "playbooks/setup-argocd.yml" in c]
check("run right after the build's setup-argocd.yml, given the run's start",
      (len(at), at[:1] == [setup[0] + 1] if setup and at else None, "upgrade_from" in (cmds[at[0]] if at else "")),
      (1, True, True))
print("production-argocd-state: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
