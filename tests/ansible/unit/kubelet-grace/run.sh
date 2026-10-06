#!/bin/bash
# The kubelet's shutdown grace compared by value, not text: kubeadm writes 180s back as 3m0s (the full run's step 13
# failed on it, 2026-10-06). upgrade-kubeadm's two checks (the ConfigMap before, the kubelet's file after) and
# node-config's ConfigMap patch, each run as the playbook holds it, on both spellings and on 0s.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=$(command -v python3)
"$PY" - <<'PY'
import json, subprocess, sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))
pb = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-kubeadm.yml"))
tasks = {t.get("name"): t for t in pb[0]["tasks"]}
WANT = "shutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s"
for name in ("The kubelet-config ConfigMap keeps the shutdown grace (180s / 30s)",
             "The kubelet runs with the shutdown grace after the upgrade (180s / 30s)"):
    cmd = tasks[name]["ansible.builtin.shell"]
    normalizer = cmd[cmd.index("python3 -c"):]
    for text, ok in (("shutdownGracePeriod: 3m0s\nshutdownGracePeriodCriticalPods: 30s\n", True),
                     ("shutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n", True),
                     ("shutdownGracePeriod: 0s\nshutdownGracePeriodCriticalPods: 0s\n", False)):
        out = subprocess.run(["bash", "-c", normalizer], input=text, capture_output=True, text=True).stdout.strip()
        check(f"{name[:40]}: {text.split()[1]}", out == WANT, ok)
t = yaml.safe_load(open("deploy/ansible/playbooks/tasks/node-config.yml"))
cmd = next(x for x in t if "ConfigMap" in x.get("name", ""))["ansible.builtin.shell"]
patcher = cmd[cmd.index("python3 -c '") + len("python3 -c '"):cmd.index("' > \"$patch\"")]
def patch(kubelet):
    r = subprocess.run([sys.executable, "-c", patcher], input=json.dumps({"data": {"kubelet": kubelet}}),
                       capture_output=True, text=True)
    return json.loads(r.stdout)["data"]["kubelet"] if r.stdout.strip() else None
check("node-config: 3m0s is the value - no patch", patch("a: 1\nshutdownGracePeriod: 3m0s\nshutdownGracePeriodCriticalPods: 30s\n"), None)
check("node-config: 0s patched to 180s / 30s",
      patch("a: 1\nshutdownGracePeriod: 0s\nshutdownGracePeriodCriticalPods: 0s\n"),
      "a: 1\nshutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n")
check("node-config: missing added", patch("a: 1\n"), "a: 1\nshutdownGracePeriod: 180s\nshutdownGracePeriodCriticalPods: 30s\n")
print("kubelet-grace: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
