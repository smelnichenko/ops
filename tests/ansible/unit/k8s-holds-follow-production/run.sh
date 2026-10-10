#!/bin/bash
# kubernetes-cni and cri-tools as production has them until upgrade-kubeadm holds them: ten holds three of the five
# (read 2026-10-09), setup-kubeadm and upgrade-kubeadm hold all five. The copy's build (setup-kubeadm) put back to ten's
# state for a run from before the first upgrade-kubeadm step; that step and the later ones expect them held (full run
# 14: the build's inventory check found them held).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


steps = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
first = next(s for s in steps if re.search(r"(?m)^playbook upgrade-kubeadm\.yml",
                                           open(f"tests/ansible/upgrade/steps/{s}.txt").read()))
pair = ("cri-tools", "kubernetes-cni")


def held(step):
    out = subprocess.run(["scripts/upgrade-expected-inventory.py", step], capture_output=True, text=True).stdout
    return tuple(next((ln.endswith("(held)") for ln in out.splitlines() if ln.startswith(f"pkg {p} ")), None)
                 for p in pair)


check(f"production's inventory: not held; held from {first} (the first upgrade-kubeadm) through the last step",
      [held(s) for s in (steps[steps.index(first) - 1], first, steps[-1])],
      [(False, False), (True, True), (True, True)])
ps = yaml.safe_load(open("tests/ansible/upgrade/production-state.yml"))
tasks = next(p for p in ps if p.get("hosts") == "target")["tasks"]
t = next((t for t in tasks if "ansible.builtin.dpkg_selections" in t), {})
sel = t.get("ansible.builtin.dpkg_selections") or {}
check("the build's two holds put back to ten's state", (sorted(t.get("loop") or []), sel.get("selection")),
      (sorted(pair), "install"))
gate = t.get("when") or "false"
check(f"only for a run from {first} or before",
      [condition(gate, **({"upgrade_from": f} if f else {})) for f in (None, steps[0], first,
                                                                       steps[steps.index(first) + 1])],
      [True, True, True, False])
# every task that diffs a fresh copy against production's inventory puts the pair back first: the baseline tasks diffed
# right after setup-kubeadm and always differed (its run, tagged holds - the guard with it)
tf = yaml.safe_load(open("Taskfile.yml"))["tasks"]
diffing = {n: [str(c.get("cmd", c)) if isinstance(c, dict) else str(c) for c in (t or {}).get("cmds") or []]
           for n, t in tf.items() if "prod-inventory.txt" in str((t or {}).get("cmds"))}
order = {n: (next((i for i, c in enumerate(cs) if "production-state.yml" in c and "--tags holds" in c), None),
             next((i for i, c in enumerate(cs) if "prod-inventory.txt" in c), None)) for n, cs in diffing.items()
         if not any("test:upgrade:argo" in c or "production-state.yml" in c and "--tags" not in c for c in cs)}
check("the baseline tasks put the pair back (production-state.yml --tags holds) before their diff",
      sorted(n for n, (h, d) in order.items() if d is not None and (h is None or h > d)), [])
check("... its task tagged holds, its guard always",
      ("holds" in (t.get("tags") or []), "always" in (tasks[0].get("tags") or []), "vagrant-only" in str(tasks[0])),
      (True, True, True))
print("k8s-holds-follow-production: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
