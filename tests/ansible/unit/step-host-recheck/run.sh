#!/bin/bash
# test:upgrade:step's two cuts that keep the proof (the full run's minutes): the VMs' readiness checked again unless
# the step before it, green in this same run, changed no host (no playbook lines) - a step run alone, or the first,
# checks all; the isolation from production - the cluster's and the Pis' - applied again after a step's own playbook
# lines, and the cluster's proof (--tags proof: the DNS answers, IPv6, the node's and a pod's probes) run every step.
# The Taskfile's own shell, run here: its commands against an ansible-playbook stub that records what it is given.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PYCHECK'
import os, re, subprocess, sys, tempfile
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
# each command run as go-task renders it, ansible-playbook a stub recording its playbook and arguments
work = tempfile.mkdtemp()
os.makedirs(os.path.join(work, "deploy/ansible/venv/bin"))
stub = os.path.join(work, "deploy/ansible/venv/bin/ansible-playbook")
open(stub, "w").write('#!/bin/bash\nprintf "%s\\n" "${*: -$(( $# - 2 ))}" >> "$RAN"\n'
                      '[[ -z ${FAILS:-} || $* != *$FAILS* ]]\n')
os.chmod(stub, 0o755)
def ran(cmd, fails="", **values):
    for k, val in values.items():
        cmd = cmd.replace("{{.%s}}" % k, val)
    log = os.path.join(work, "ran")
    open(log, "w").close()
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, cwd=work,
                       env=dict(os.environ, RAN=log, FAILS=fails))
    return r.returncode, [os.path.basename(x.split()[0]) + "".join(" " + w for w in x.split()[1:])
                          for x in open(log).read().splitlines()]
vms = [c for c in cmds if "vms-ready.yml" in c]
check("one command for the VMs' readiness", len(vms), 1)
if vms:
    check("HOST_RECHECK yes: the VMs' readiness checked (vms-ready)", ran(vms[0], HOST_RECHECK="yes", PREV_STEP="x"),
          (0, ["vms-ready.yml"]))
    check("HOST_RECHECK no: not checked again", ran(vms[0], HOST_RECHECK="no", PREV_STEP="x"), (0, []))
iso = [c for c in cmds if "isolate-cluster.yml" in c]
check("one command for the isolation after the step's playbook lines", len(iso), 1)
if iso:
    check("after the step's playbook lines: the Pis' isolation and the cluster's applied again",
          ran(iso[0], HAS_PLAYBOOKS="yes"), (0, ["isolate-pis.yml", "isolate-cluster.yml"]))
    check("no playbook lines: nothing here - the cluster's proof is one of the step's parallel checks",
          ran(iso[0], HAS_PLAYBOOKS="no"), (0, []))
    check("the cluster's proof (--tags proof) one of the parallel step checks, every step",
          open("scripts/upgrade-step-checks.sh").read().count(
              "\nstart isolation play ../../tests/ansible/upgrade/isolate-cluster.yml --tags proof\n"), 1)
    check("the Pis' isolation failing: the command fails there (go-task's shell goes on past a failed line)",
          ran(iso[0], fails="isolate-pis", HAS_PLAYBOOKS="yes"), (1, ["isolate-pis.yml"]))
check("the full run passes each step the one before it (scripts/upgrade-full-steps.sh)",
      sum(1 for l in open("scripts/upgrade-full-steps.sh") if 'PREV_STEP="${prev%% *}"' in l
          and not l.lstrip().startswith("#")), 1)
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
