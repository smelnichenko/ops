#!/bin/bash
# The copy's Gateway API CRDs as production's before step 07: ten's v1.2.1 was applied client-side (bootstrap.sh; the
# whole CRD in kubectl's last-applied annotation, its fields kubectl-client-side-apply's), the copy's build applies
# server-side (setup-kubeadm since 2026-10-03) - step 07's server-side --force-conflicts takeover of client-side owned
# fields never ran on the copy. tests/ansible/upgrade/production-state.yml applies the bundle the copy runs once more,
# client-side, for a run from before step 07: its version read from the CRDs' own bundle-version annotation.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import actions  # noqa: E402
from templar import condition, render  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


steps = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
gw_step = next(s for s in steps if re.search(r"(?m)^playbook setup-kubeadm\.yml .*--tags gateway-api",
                                             open(f"tests/ansible/upgrade/steps/{s}.txt").read()))
ps = yaml.safe_load(open("tests/ansible/upgrade/production-state.yml"))
cluster = next(p for p in ps if p.get("hosts") == "target")
flat = []
for t in cluster.get("tasks") or []:
    flat += [dict(x, when=(t.get("when") if "block" in t else None)) for x in t["block"]] if "block" in t else [t]
read = next((t for t in flat if "bundle-version" in str(t.get("ansible.builtin.command", ""))), None)
apply_ = next((t for t in flat if "standard-install.yaml" in str(t.get("ansible.builtin.command", ""))), None)
argv = [str(a) for a in ((apply_ or {}).get("ansible.builtin.command") or {}).get("argv", [])]
check("the installed bundle's version read from its CRDs, then that bundle applied client-side",
      (read is not None, apply_ is not None, "--server-side" not in argv and "apply" in argv,
       read is not None and apply_ is not None and read.get("register", "x") in " ".join(argv)),
      (True, True, True, True))
gate = (apply_ or {}).get("when") or "false"
check(f"only for a run from before {gw_step} (the step that moves Gateway API; its takeover then runs)",
      [condition(gate, **({"upgrade_from": f} if f else {})) for f in (None, steps[0], gw_step,
                                                                       steps[steps.index(gw_step) + 1])],
      [True, True, True, False])
print("production-state-gateway: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
