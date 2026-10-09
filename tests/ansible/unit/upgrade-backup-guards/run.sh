#!/bin/bash
# upgrade-backup.yml's guards as the playbook holds them: Kafka's broker copy judges a broker stopped by kubectl's
# answer - a pod not running on the cordoned node, or gone - and kubectl failing is not stopped (its empty answer read
# as "not Running" copied a live broker's files); ClickHouse's snapshot cleanup removes only wave0_* under the data
# path's shadow/ and refuses a data path of / ; its check after fails on a snapshot left.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W AP=$AP "$PY" - <<'PY'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W, AP = os.environ["W"], os.environ["AP"]
def tasks(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k))
book = [t for p in yaml.safe_load(open("deploy/ansible/playbooks/upgrade-backup.yml")) for t in tasks(p.get("tasks"))]
by = lambda prefix: next(t for t in book if str(t.get("name", "")).startswith(prefix))
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {detail}"))
# Kafka: stopped(), the playbook's own lines, kubectl a stub answering ANSWER (FAIL=1: refused)
kafka = next(t for t in book if "stopped() {" in str(t.get("ansible.builtin.shell", "")))
cmd = kafka["ansible.builtin.shell"]["cmd"]
fn = cmd[cmd.index("stopped() {"):cmd.index("\n}", cmd.index("stopped() {")) + 2]
open(os.path.join(W, "kubectl"), "w").write(
    '#!/bin/sh\n[ -z "$FAIL" ] || { echo "connection refused" >&2; exit 1; }\nprintf %s "$ANSWER"\n')
os.chmod(os.path.join(W, "kubectl"), 0o755)
driver = f'K={W}/kubectl node=n1\n{fn}\nstopped ns pod; echo "rc=$?"'
for name, env_, want in (("running on the cordoned node: not stopped", {"ANSWER": "Running/n1"}, "rc=1"),
                         ("Pending there (recreated, cordoned out): stopped", {"ANSWER": "Pending/n1"}, "rc=0"),
                         ("gone: stopped", {"ANSWER": ""}, "rc=0"),
                         ("kubectl failing: not stopped", {"ANSWER": "", "FAIL": "1"}, "rc=2")):
    r = subprocess.run(["bash", "-c", driver], capture_output=True, text=True,
                       env=dict(os.environ, **{"FAIL": "", **env_}))
    check(f"Kafka: {name}", r.stdout.strip().endswith(want), r.stdout + r.stderr)
# Kafka: the whole copy script, kubectl and tar stubs - the node cordoned before a broker is deleted; a broker running
# when its copy would start: refused, nothing tarred, the node uncordoned all the same; the control copies
kb = os.path.join(W, "kbin")
os.makedirs(kb)
open(os.path.join(kb, "kubectl"), "w").write("""#!/bin/bash
echo "$*" >> "$W/kcalls"
case "$*" in
  *" get pod "*"--ignore-not-found"*) printf %s "$PHASE" ;;
  *" get pod "*"{.spec.nodeName}"*) echo n1 ;;
  *) ;;
esac
exit 0
""")
open(os.path.join(kb, "tar"), "w").write('#!/bin/bash\necho "tar $*" >> "$W/kcalls"\n')
for f in ("kubectl", "tar"):
    os.chmod(os.path.join(kb, f), 0o755)
whole = by("Kafka - every broker stopped, its volume tarred")["ansible.builtin.shell"]["cmd"]
os.makedirs(os.path.join(W, "brokerdir"))
script = render(whole, kubectl="kubectl", _kafka_clusters={"stdout": "ns k1"},
                _kafka={"stdout": "ns k1 broker-0 " + os.path.join(W, "brokerdir")}, local_dir=os.path.join(W, "local"),
                _stamp="s")
def copy(phase):
    open(os.path.join(W, "kcalls"), "w").close()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, W=W, PHASE=phase, PATH=kb + ":" + os.environ["PATH"]))
    calls = open(os.path.join(W, "kcalls")).read().splitlines()
    at = lambda word: next((i for i, c in enumerate(calls) if word in c), None)
    return r, calls, at
r, calls, at = copy("Pending/n1")
check("Kafka control: a broker kept out (Pending on the cordoned node) copied, the node uncordoned after",
      (r.returncode, any(c.startswith("tar ") for c in calls), (at("uncordon n1") or 0) > (at("tar ") or 0)) == (0, True, True),
      (r.returncode, calls))
check("Kafka: the node cordoned before its broker is deleted",
      at(" cordon n1") is not None and at("delete pod broker-0") is not None and at(" cordon n1") < at("delete pod broker-0"),
      calls)
r, calls, at = copy("Running/n1")
check("Kafka: the broker running when its copy would start: refused, nothing tarred, the node uncordoned",
      (r.returncode != 0, "running before its copy" in r.stdout, any(c.startswith("tar ") for c in calls),
       at("uncordon n1") is not None) == (True, True, False, True), (r.returncode, r.stdout, calls))
# ClickHouse: the cleanup, its data path from the query's third field
clean = by("ClickHouse - the snapshot released")["ansible.builtin.shell"]["cmd"]
data = os.path.join(W, "ch")
os.makedirs(os.path.join(data, "shadow", "wave0_1"))
os.makedirs(os.path.join(data, "shadow", "other"))
run = lambda path: subprocess.run(["bash", "-c", render(clean, _ch={"stdout": f"a b {path}"})],
                                  capture_output=True, text=True)
r = run(data)
check("ClickHouse: wave0_* removed, nothing else", r.returncode == 0 and os.listdir(os.path.join(data, "shadow"))
      == ["other"], (r.returncode, os.listdir(os.path.join(data, "shadow")), r.stderr))
r = run("/")
check("ClickHouse: a data path of / refused, saying so", r.returncode != 0 and "refus" in (r.stdout + r.stderr).lower(),
      (r.returncode, r.stdout, r.stderr))
r = run(os.path.join(W, "none"))
check("ClickHouse: no shadow directory: nothing to do", r.returncode == 0, (r.returncode, r.stderr))
# ClickHouse: the check after - a snapshot left fails it (ansible-playbook, the task as written)
left = by("ClickHouse - no snapshot left")
os.makedirs(os.path.join(data, "shadow", "wave0_2"))
for name, leftover, want_rc in (("a snapshot left: fails", True, 1), ("none: passes", False, 0)):
    if not leftover:
        os.rmdir(os.path.join(data, "shadow", "wave0_2"))
    yaml.safe_dump([{"hosts": "localhost", "gather_facts": False, "vars": {"_ch": {"stdout": f"a b {data}"}},
                     "tasks": [left]}], open(os.path.join(W, "left.yml"), "w"))
    r = subprocess.run([AP, "-i", "localhost,", "-c", "local", os.path.join(W, "left.yml")], capture_output=True,
                       text=True)
    check(f"ClickHouse no snapshot left: {name}", min(r.returncode, 1) == want_rc, r.stdout[-300:])
print("upgrade-backup-guards: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
