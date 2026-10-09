#!/bin/bash
# Every Kubernetes package a minor pins is held - kubeadm, kubelet, kubectl and the minor's kubernetes-cni and
# cri-tools - after a build (setup-kubeadm.yml) and after a minor's upgrade (upgrade-kubeadm.yml): unheld, an apt upgrade
# on the node moved the CNI plugins and crictl past the minor's pins (ten held the first three only, read 2026-10-09).
# The upgrade installs the minor's pair over the held ones (allow_change_held_packages), as it does kubelet's.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import re, sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, load, plays, tasks  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


def held(path):
    out = set()
    for t in tasks(load(path)):
        for m, v in actions(t):
            if m.endswith("dpkg_selections") and (v or {}).get("selection") == "hold":
                names = t.get("loop") if "{{ item }}" in str(v.get("name")) else [v.get("name")]
                out |= set(names or [])
    return out


ALL = {"kubeadm", "kubelet", "kubectl", "kubernetes-cni", "cri-tools"}
check("setup-kubeadm.yml holds every Kubernetes package", sorted(held("deploy/ansible/playbooks/setup-kubeadm.yml") & ALL),
      sorted(ALL))
up = "deploy/ansible/playbooks/upgrade-kubeadm.yml"
pinned = {re.sub(r"=.*", "", p) for v in plays(load(up))[0]["vars"]["minor_packages"].values() for p in v}
check("the upgrade's minor packages are kubernetes-cni and cri-tools", sorted(pinned), ["cri-tools", "kubernetes-cni"])
check("upgrade-kubeadm.yml holds them and kubeadm, kubelet, kubectl", sorted(held(up) & ALL), sorted(ALL))
inst = next((v for t in tasks(load(up)) for m, v in actions(t)
             if m.endswith(".apt") and "minor_packages" in str((v or {}).get("name"))), {})
check("  and installs the minor's pair over the held ones", inst.get("allow_change_held_packages"), True)
print("k8s-package-holds: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
