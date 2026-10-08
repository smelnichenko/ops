#!/bin/bash
# test:upgrade:step's two cuts that keep the proof (the full run's minutes): the VMs' readiness checked again unless
# the step before it, green in this same run, changed no host (no playbook lines) - a step run alone, or the first,
# checks all; the isolation from production applied again after a step's own playbook lines, and its proof (--tags
# proof: the DNS answers, IPv6, the node's and a pod's probes) run every step. The Taskfile's own shell, run here.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PYCHECK'
import re, subprocess, sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
tf = yaml.safe_load(open("Taskfile.yml"))["tasks"]
step = tf["test:upgrade:step"]
recheck = step["vars"]["HOST_RECHECK"]["sh"]
def host_recheck(prev):
    r = subprocess.run(["bash", "-c", recheck.replace("{{.PREV_STEP}}", prev)], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else f"rc {r.returncode}: {r.stderr.strip()}"
check("no step before it (run alone, or the first): checked", host_recheck(""), "yes")
check("after a step with playbook lines (containerd): checked", host_recheck("14-containerd"), "yes")
check("after a step without (Velero's): not", host_recheck("10-velero"), "no")
check("a step before it that is no step: fails (never read as none)", host_recheck("99-none").startswith("rc "), True)
cmds = [c["cmd"] if isinstance(c, dict) else c for c in step["cmds"]]
vms = [c for c in cmds if "vms-ready.yml" in c]
check("vms-ready by HOST_RECHECK", len(vms) == 1 and '{{.HOST_RECHECK}}' in vms[0], True)
iso = [c for c in cmds if "isolate-cluster.yml" in c]
check("the isolation applied again after the step's playbook lines, its proof alone otherwise",
      len(iso) == 1 and bool(re.search(r'"\{\{\.HAS_PLAYBOOKS\}\}" = yes \]; then\s+\S.*isolate-cluster\.yml\s*\n\s*else\s*\n\s*.*isolate-cluster\.yml --tags proof', iso[0])),
      True)
full = tf["test:upgrade:full"]["cmds"]
check("the full run passes each step the one before it",
      sum('PREV_STEP="${prev%% *}"' in str(c.get("cmd", "") if isinstance(c, dict) else c) for c in full), 1)
# the proof the tag runs: every probe and the DNS answer - each named (a probe left untagged would silently not run)
plays = yaml.safe_load(open("tests/ansible/upgrade/isolate-cluster.yml"))
tagged = sorted(t["name"] for p in plays for t in p.get("tasks") or [] if "proof" in (t.get("tags") or []))
check("the proof: the guard, the addresses, the DNS answer, IPv6, the node's and a pod's probes", tagged, sorted([
    "Vagrant VMs only (fails closed on any other host)", "Production's public addresses",
    "The cluster's DNS answers pmon.dev with Vagrant addresses", "No IPv6 beyond link-local",
    "Prove it - the node cannot reach production's VIP nor its public addresses, and can reach the Vagrant VIP",
    "Prove it - a pod cannot reach production's VIP nor its public addresses, and can reach the Vagrant VIP"]))
probes = sorted(t["name"] for p in plays for t in p.get("tasks") or [] if t.get("name", "").startswith("Prove it"))
check("every probe in the proof", [n for n in probes if n not in tagged], [])
print("step-host-recheck: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
