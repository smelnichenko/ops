#!/bin/bash
# Kafka's restore, its parts no live run can make fail:
#   R01 the restore check's markers reach the producer - its tasks run `kubectl exec -i`, which reads stdin like any
#       command: the first exec took the markers (copy run 5, 2026-11-18, rc 201). The task's shell as Ansible renders it
#       (tests/ansible/unit/templar.py), run with the markers on stdin against a stub exec that swallows its stdin and a
#       producer stub that records what it got: every marker, once, in order
#   R02 tasks/kafka-restore.yml holds the nightly dump off for its span: the restoring ConfigMap (the name platform's
#       kafka-backup CronJob mounts: <namespace>-kafka-backup-restoring) made first, by create; a dump already running
#       refused; the restore Job inside; the ConfigMap removed always
#   R03 that refusal's Job filter: an active Job of the kafka-backup CronJob named, a finished one or another's not
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=$(command -v python3)
"$PY" -c 'import yaml, jinja2, ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_KAFKA_RESTORE'
import json, os, subprocess, sys, tempfile
import yaml
ops = sys.argv[1]
sys.path.insert(0, os.path.join(ops, "tests", "ansible", "unit"))
from templar import condition, render, as_loaded
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))

# R01
play = yaml.safe_load(open(os.path.join(ops, "tests/ansible/copy/kafka-restore-check.yml")))[1]
mk = next(t for t in play["tasks"] if str(t.get("name", "")).startswith("The marker topic made again"))
markers = [render(m) for m in as_loaded(play["vars"]["markers"])]
with tempfile.TemporaryDirectory() as d:
    stub = os.path.join(d, "exec")
    # the stub `kubectl ... exec -i ... -- /opt/kafka/bin`: kbin ends in that path, the tool's name appended
    os.makedirs(stub)
    for tool in ("kafka-topics.sh", "kafka-console-producer.sh"):
        with open(os.path.join(stub, tool), "w") as f:
            f.write("#!/bin/bash\n"
                    # exec -i: whatever is on stdin is read (the producer's lines are its input)
                    'in=$(cat)\n'
                    f'echo "{tool} $*" >> {d}/calls\n'
                    + (f'[ -n "$in" ] && printf "%s\\n" "$in" >> {d}/produced\n' if tool == "kafka-console-producer.sh" else "")
                    + "exit 0\n")
        os.chmod(os.path.join(stub, tool), 0o755)
    cmd = render(mk["ansible.builtin.shell"]["cmd"], kbin=stub, topic="upgrade-restore-check")
    stdin = render(mk["ansible.builtin.shell"]["stdin"], markers=markers)
    r = subprocess.run(["bash", "-c", cmd], input=stdin, capture_output=True, text=True, timeout=60)
    # split at newlines alone: str.splitlines splits at 0x1e too, the headers' own separator
    produced = open(os.path.join(d, "produced")).read().rstrip("\n").split("\n") if os.path.exists(os.path.join(d, "produced")) else []
    calls = open(os.path.join(d, "calls")).read().rstrip("\n").split("\n") if os.path.exists(os.path.join(d, "calls")) else []
want = [m[len("NO_HEADERS\t"):] if m.startswith("NO_HEADERS\t") else m for m in markers]
check("R01 the markers reach the producer past every exec -i: all five, once, in order", (r.returncode, produced), (0, want))
check("R01   the topic deleted and made before them", [c.split()[0] + " " + c.split()[3] for c in calls[:2]],
      ["kafka-topics.sh --delete", "kafka-topics.sh --create"])
r = subprocess.run(["bash", "-c", cmd], input="", capture_output=True, text=True, timeout=60)
check("R01 no markers on stdin: refused before any exec", (r.returncode, "no markers on stdin" in r.stdout), (1, True))

# R02
tasks = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/tasks/kafka-restore.yml")))
names = [t.get("name") for t in tasks]
blk = next(t for t in tasks if "block" in t)
check("R02 the block after the Job is built, before what was restored",
      names.index(blk["name"]) == names.index("The restore Job") + 1 and names[names.index(blk["name"]) + 1] == "What was restored", True)
inner = [t["name"] for t in blk["block"]]
check("R02 inside: the ConfigMap made, no dump running, the restore Job run - in that order",
      [n.split(" ")[1] for n in inner], ["restoring", "dump", "restore"])
lock = lambda **v: render(blk["vars"]["_kr_lock"], **v)
check("R02 the ConfigMap's name, the CronJob's own plus -restoring", (lock(), lock(kafka_namespace="schnappy-test")),
      ("schnappy-production-kafka-backup-restoring", "schnappy-test-kafka-backup-restoring"))
mkcmd = blk["block"][0]["ansible.builtin.shell"]["cmd"]
check("R02 made by create (one there already is another restore's, or stale - stops), its since a UTC stamp",
      ("create configmap {{ _kr_lock }}" in mkcmd, "apply" in mkcmd, '--from-literal=since="$(date -u +%Y%m%dT%H%M%SZ)"' in mkcmd), (True, False, True))
alw = blk.get("always") or []
check("R02 always: the ConfigMap removed, a missing one no error",
      [(("delete configmap {{ _kr_lock }}" in str(t.get("ansible.builtin.command"))), "--ignore-not-found" in str(t.get("ansible.builtin.command"))) for t in alw],
      [(True, True)])
fw = blk["block"][1]["failed_when"]
check("R02 a dump running refuses: named Jobs fail it, none passes, a broken read fails",
      (condition(fw, _kr_dumping={"rc": 0, "stdout": "schnappy-production-kafka-backup-29371530"}),
       condition(fw, _kr_dumping={"rc": 0, "stdout": "\n"}), condition(fw, _kr_dumping={"rc": 1, "stdout": ""})), (True, False, True))

# R03
sh = blk["block"][1]["ansible.builtin.shell"]["cmd"]
py = sh[sh.index("python3 -c '") + len("python3 -c '"):sh.rindex("'")]
job = lambda name, owner, active: {"metadata": {"name": name, "ownerReferences": [{"kind": owner[0], "name": owner[1]}] if owner else []},
                                   "status": {"active": active} if active else {"succeeded": 1}}
jobs = {"items": [job("schnappy-production-kafka-backup-1", ("CronJob", "schnappy-production-kafka-backup"), 1),
                  job("schnappy-production-kafka-backup-0", ("CronJob", "schnappy-production-kafka-backup"), 0),
                  job("schnappy-production-clickhouse-backup-1", ("CronJob", "schnappy-production-clickhouse-backup"), 1),
                  job("kafka-restore-1", None, 1)]}
r = subprocess.run(["python3", "-c", py], input=json.dumps(jobs), capture_output=True, text=True)
check("R03 the active kafka-backup Job named; its finished one, another CronJob's, the restore's own not",
      (r.returncode, r.stdout.split()), (0, ["schnappy-production-kafka-backup-1"]))

print("kafka-restore: " + ("ALL-PASS" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY_KAFKA_RESTORE
