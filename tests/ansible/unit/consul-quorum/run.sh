#!/bin/bash
# setup-consul's restart play: a Consul server is restarted only while the other two carry the quorum (before), and the
# next one only once it is back (after) - autopilot: healthy, one loss tolerated, three healthy voters. Each command
# as the playbook holds it, curl answering with the case's autopilot health: all healthy passes; one server down, no
# loss tolerated, a non-voter, an unanswered API - each refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import json, os, subprocess, sys, tempfile
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))
plays = yaml.safe_load(open("deploy/ansible/playbooks/setup-consul.yml"))
restart = next(p for p in plays if p.get("name", "").startswith("Restart the Consul servers"))
def tasks(ts):
    for t in ts:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k, []))
cmds = {t["name"]: t["ansible.builtin.shell"]["cmd"] for t in tasks(restart["tasks"]) if "ansible.builtin.shell" in t
        and "autopilot/health" in t["ansible.builtin.shell"]["cmd"]}
check("both checks found (before and after the restart)", sorted(cmds), sorted(
    ["Before - every server healthy, one loss tolerated", "Back and caught up - every server healthy, one loss tolerated"]))
work = tempfile.mkdtemp()
with open(os.path.join(work, "curl"), "w") as f:
    f.write('#!/bin/bash\n[ -e "$H" ] || exit 7\ncat "$H"\n')
os.chmod(os.path.join(work, "curl"), 0o755)
def server(name, healthy=True, voter=True):
    return {"Name": name, "Healthy": healthy, "Voter": voter}
CASES = [
    ("all healthy, one loss tolerated", {"Healthy": True, "FailureTolerance": 1,
                                         "Servers": [server("pi1"), server("pi2"), server("ten")]}, 0),
    ("one server unhealthy", {"Healthy": False, "FailureTolerance": 0,
                              "Servers": [server("pi1"), server("pi2", False), server("ten")]}, 1),
    ("healthy but no loss tolerated", {"Healthy": True, "FailureTolerance": 0,
                                       "Servers": [server("pi1"), server("pi2"), server("ten")]}, 1),
    ("a non-voter", {"Healthy": True, "FailureTolerance": 1,
                     "Servers": [server("pi1"), server("pi2", voter=False), server("ten")]}, 1),
    ("two servers only", {"Healthy": True, "FailureTolerance": 1, "Servers": [server("pi1"), server("ten")]}, 1),
    ("the API unanswered", None, 1),
]
for name, cmd in sorted(cmds.items()):
    for case, health, want in CASES:
        h = os.path.join(work, "health.json")
        if os.path.exists(h):
            os.remove(h)
        if health is not None:
            json.dump(health, open(h, "w"))
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                           env={**os.environ, "PATH": work + ":" + os.environ["PATH"], "H": h})
        check(f"{name.split(' - ')[0]}: {case}", 0 if r.returncode == 0 else 1, want)
print("consul-quorum: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
