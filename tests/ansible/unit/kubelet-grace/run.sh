#!/bin/bash
# The kubelet's shutdown grace compared by value, not text: kubeadm writes 180s back as 3m0s (the full run's step 13
# failed on it, 2026-10-06). upgrade-kubeadm's two checks (the ConfigMap before, the kubelet's file after) and
# node-config's ConfigMap patch, each run as the playbook holds it, on both spellings and on 0s - the two checks judged
# by their own failed_when, evaluated by Ansible's templar over the registered result.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "kubelet-grace: no python3 with ansible and yaml (PATH, repo venv)"; exit 2; }
"$PY" - <<'PY'
import json, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))
pb = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-kubeadm.yml"))
tasks = {t.get("name"): t for t in pb[0]["tasks"]}
def failed(task, result):
    """The task's failed_when over its registered result, as Ansible evaluates a conditional."""
    return render("{{ " + task["failed_when"] + " }}", **{task["register"]: result})
import os, tempfile
work = tempfile.mkdtemp()
kubelet_file = os.path.join(work, "config.yaml")
stub = os.path.join(work, "kubectl")  # answers `get configmap kubelet-config -o jsonpath=...` with the test's text
with open(stub, "w") as f:  # ...and exits with STUB_RC: a kubectl that printed, then failed
    f.write("#!/bin/sh\ncat %s\nexit ${STUB_RC:-0}\n" % kubelet_file)
os.chmod(stub, 0o755)
for name in ("The kubelet-config ConfigMap keeps the shutdown grace (180s / 30s)",
             "The kubelet runs with the shutdown grace after the upgrade (180s / 30s)"):
    # the whole command as the playbook holds it, its inputs replaced: the ConfigMap by the stub, the file by ours
    cmd = render(tasks[name]["ansible.builtin.shell"], kubectl=stub).replace(
        "/var/lib/kubelet/config.yaml", kubelet_file)
    for text, ok in (("shutdownGracePeriod: 3m0s\nshutdownGracePeriodCriticalPods: 30s\n", True),
                     ("shutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n", True),
                     ("shutdownGracePeriod: 0s\nshutdownGracePeriodCriticalPods: 0s\n", False),
                     ("", False)):
        with open(kubelet_file, "w") as f:
            f.write("a: 1\n" + text)
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True)
        result = {"rc": r.returncode, "stdout_lines": r.stdout.splitlines()}
        check(f"{name[:40]}: {(text.split() or ["none"])[1 if text else 0]}", not failed(tasks[name], result), ok)
# the ConfigMap read: the right text, but kubectl failed - not a proof (the file check's rc adds nothing: any failure
# there leaves no complete output to compare)
name = "The kubelet-config ConfigMap keeps the shutdown grace (180s / 30s)"
with open(kubelet_file, "w") as f:
    f.write("shutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n")
r = subprocess.run(["bash", "-c", render(tasks[name]["ansible.builtin.shell"], kubectl=stub)],
                   capture_output=True, text=True, env=dict(os.environ, STUB_RC="1"))
check("The kubelet-config ConfigMap read failed", not failed(tasks[name], {"rc": r.returncode,
                                                                           "stdout_lines": r.stdout.splitlines()}), False)
t = yaml.safe_load(open("deploy/ansible/playbooks/tasks/node-config.yml"))
cmd = render(next(x for x in t if "ConfigMap" in x.get("name", ""))["ansible.builtin.shell"])
patcher = cmd[cmd.index("python3 -c '") + len("python3 -c '"):cmd.index("' > \"$patch\"")]  # its python, fed JSON
def patch(kubelet):
    r = subprocess.run([sys.executable, "-c", patcher], input=json.dumps({"data": {"kubelet": kubelet}}),
                       capture_output=True, text=True)
    return json.loads(r.stdout)["data"]["kubelet"] if r.stdout.strip() else None
check("node-config: 3m0s is the value - no patch", patch("a: 1\nshutdownGracePeriod: 3m0s\nshutdownGracePeriodCriticalPods: 30s\n"), None)
check("node-config: 0s patched to 180s / 30s",
      patch("a: 1\nshutdownGracePeriod: 0s\nshutdownGracePeriodCriticalPods: 0s\n"),
      "a: 1\nshutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n")
check("node-config: missing added", patch("a: 1\n"), "a: 1\nshutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n")
# the patch applied only when there is one: an empty one (the ConfigMap right already) went to `kubectl patch -p ''`
apply = next(x for x in t if x.get("name", "").startswith("Keep the shutdown grace across kubeadm upgrades"))
applies = lambda out: render("{{ " + apply["when"] + " }}", _kubelet_config_patch={"stdout": out})
check("node-config: the ConfigMap right already - nothing applied", applies(""), False)
check("node-config: a patch - applied", applies('{"data": {"kubelet": "x"}}'), True)
print("kubelet-grace: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
