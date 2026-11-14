#!/bin/bash
# setup-kubeadm's no-downgrade.yml refuses a Cilium run that skips a minor or crosses a major (Cilium's upgrade guide:
# one minor at a time, from the latest patch of the minor before) - the task as the file holds it, its vars and its
# assert rendered by Ansible's templar against the Helm release list's answer: a patch and the next minor pass, two
# minors and a major are refused, no release yet (a first install) and the same version pass; it applies only where
# Cilium's tasks run (all, or --tags cilium) and a cluster exists.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
tasks = yaml.safe_load(open("deploy/ansible/playbooks/tasks/no-downgrade.yml"))
t = next((x for x in tasks if x.get("name", "").startswith("No skipped minor")), None)
check("the one-minor task present", t is not None, True)
if t is None:
    sys.exit(1)
def verdict(running, want):
    helm = '[{"name":"cilium","chart":"cilium-%s"}]' % running if running else '[]'
    v = {"_no_downgrade_helm": {"stdout": helm}, "cilium_version": want}
    for k, e in t["vars"].items():  # in order: each may use the one before
        v[k] = render(e, **v)
    return condition(t["ansible.builtin.assert"]["that"], **v)
for running, want, ok in (("1.20.2", "1.20.4", True), ("1.20.4", "1.21.0", True), ("1.20.2", "1.22.0", False),
                          ("1.20.2", "2.0.0", False), ("1.9.6", "1.10.0", True), ("1.9.6", "1.11.0", False),
                          ("", "1.20.4", True), ("1.20.4", "1.20.4", True)):
    check(f"Cilium {running or '(none)'} -> {want}: {'passes' if ok else 'refused'}", verdict(running, want), ok)
w = t["when"]
check("only where Cilium's tasks run and a cluster exists",
      [condition(w, _no_downgrade_cluster={"stat": {"exists": e}}, ansible_run_tags=tags) for e, tags in
       ((True, ["all"]), (True, ["cilium"]), (True, ["local-path"]), (False, ["all"]))], [True, True, False, False])
print("cilium-one-minor: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
