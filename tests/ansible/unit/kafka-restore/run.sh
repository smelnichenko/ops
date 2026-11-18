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
#   R04 the fetch: the newest complete dump holding messages, a dump of 0 refused unless allowed, the source pinned (its
#       marker says how to unpin); a store read that fails stops it - never an older dump taken for the newest
#   R05 tasks/kafka-baseline.yml: the topics named (or all), why; an earlier BASELINE no dump followed kept covered, one
#       a dump followed replaced; a store read that fails writes nothing. The restore's: its topics, or all, its dump
#   R06 playbooks/kafka-backup-unpin.yml: a pinned dump unpinned, said; one not pinned said, nothing changed
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=$(command -v python3)
"$PY" -c 'import yaml, jinja2, ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_KAFKA_RESTORE'
import json, os, re, subprocess, sys, tempfile
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
check("R02 the lock read and required, the Job built, the block, what was restored - in that order",
      [n.split(" ")[1] for n in names[names.index("The restore Job") - 2:names.index("What was restored") + 1]],
      ["restore's", "backup", "restore", "restore,", "was"])
lockfact = next(t for t in tasks if str(t.get("name", "")).startswith("The restore's lock as the backup CronJob mounts it"))["ansible.builtin.set_fact"]["_kr_lock"]
cj = lambda vols: {"stdout": json.dumps({"spec": {"jobTemplate": {"spec": {"template": {"spec": {"volumes": vols}}}}}})}
check("R02 the lock's name read from the CronJob's restoring volume; none there - empty, so the assert refuses",
      (render(lockfact, _kr_cronjob=cj([{"name": "tmp", "emptyDir": {}}, {"name": "restoring", "configMap": {"name": "x-kafka-backup-restoring", "optional": True}}])).strip(),
       render(lockfact, _kr_cronjob=cj([{"name": "tmp", "emptyDir": {}}])).strip()), ("x-kafka-backup-restoring", ""))
need = next(t for t in tasks if str(t.get("name", "")).startswith("The backup CronJob holds the lock's mount"))["ansible.builtin.assert"]["that"]
check("R02   the assert: a name passes, none refuses", (condition(need, _kr_lock="x"), condition(need, _kr_lock="")), (True, False))
inner = [t["name"] for t in blk["block"]]
check("R02 inside: the ConfigMap made, no dump unfinished, the restore Job run, the baseline - in that order",
      [n.split(" ")[1] for n in inner], ["restoring", "dump", "restore", "store's"])
mkcmd = blk["block"][0]["ansible.builtin.shell"]["cmd"]
check("R02 made by create (one there already: another restore's, or stale - stops), its since a UTC stamp, out of Velero's backups",
      ("create configmap {{ _kr_lock }}" in mkcmd, "| $k create -f -" in mkcmd, "apply" in mkcmd,
       '--from-literal=since="$(date -u +%Y%m%dT%H%M%SZ)"' in mkcmd, '"velero.io/exclude-from-backup": "true"' in mkcmd), (True, True, False, True, True))
alw = blk.get("always") or []
check("R02 always: the ConfigMap removed, a missing one no error, retried",
      [("delete configmap {{ _kr_lock }}" in str(t.get("ansible.builtin.command")), "--ignore-not-found" in str(t.get("ansible.builtin.command")),
        t.get("retries")) for t in alw], [(True, True, 3)])
w = alw[0]["when"]
ok, bad = {"failed": False, "changed": True}, {"failed": True}
check("R02   removed by the run that made it alone: its create failed (another's lock) - kept",
      condition(w, _kr_locked=bad, _kr_run=ok), False)
check("R02   the restore succeeded, or never started (a dump unfinished refused it) - removed",
      (condition(w, _kr_locked=ok, _kr_run=ok), condition(w, _kr_locked=ok)), (True, True))
check("R02   the restore failed - kept (a Kafka half restored; a dump now would capture the half)",
      condition(w, _kr_locked=ok, _kr_run=bad), False)
fw = blk["block"][1]["failed_when"]
check("R02 a dump unfinished refuses: named Jobs fail it, none passes, a broken read fails",
      (condition(fw, _kr_dumping={"rc": 0, "stdout": "schnappy-production-kafka-backup-29371530"}),
       condition(fw, _kr_dumping={"rc": 0, "stdout": "\n"}), condition(fw, _kr_dumping={"rc": 1, "stdout": ""})), (True, False, True))

# R03
sh = blk["block"][1]["ansible.builtin.shell"]["cmd"]
py = sh[sh.index("python3 -c '") + len("python3 -c '"):sh.rindex("'")]
job = lambda name, owner, conds: {"metadata": {"name": name, "ownerReferences": [{"kind": owner[0], "name": owner[1]}] if owner else []},
                                  "status": {"conditions": [{"type": c, "status": "True"} for c in conds]}}
jobs = {"items": [job("schnappy-production-kafka-backup-1", ("CronJob", "schnappy-production-kafka-backup"), []),
                  job("schnappy-production-kafka-backup-2", ("CronJob", "schnappy-production-kafka-backup"), ["SuccessCriteriaMet"]),
                  job("schnappy-production-kafka-backup-0", ("CronJob", "schnappy-production-kafka-backup"), ["Complete"]),
                  job("schnappy-production-kafka-backup-9", ("CronJob", "schnappy-production-kafka-backup"), ["Failed"]),
                  job("schnappy-production-clickhouse-backup-1", ("CronJob", "schnappy-production-clickhouse-backup"), []),
                  job("kafka-restore-1", None, [])]}
r = subprocess.run(["python3", "-c", py], input=json.dumps(jobs), capture_output=True, text=True)
check("R03 a kafka-backup Job not Complete nor Failed named (one just made, no pod counted yet); finished ones, another CronJob's, the restore's not",
      (r.returncode, sorted(r.stdout.split())), (0, ["schnappy-production-kafka-backup-1", "schnappy-production-kafka-backup-2"]))

# R04: the fetch - the newest complete dump holding messages (an empty newer one passed over), a dump of 0 refused unless
#      allowed, the source pinned - its script as rendered, against a stub rclone over a store of directories
jt = next(t for t in tasks if t.get("name") == "The restore Job")["ansible.builtin.set_fact"]["_kr_job"]
fetch_src = jt["spec"]["template"]["spec"]["initContainers"][0]["command"][2]
def store_dir(d, store, top=None):
    """A store of dumps: {name: (DONE's line or None, [other files])}; top: {file at the bucket's root: text}"""
    os.makedirs(d + "/bin", exist_ok=True); os.makedirs(d + "/store/b", exist_ok=True)
    for name, (done, extra) in (store or {}).items():
        os.makedirs("%s/store/b/%s" % (d, name))
        if done is not None:
            open("%s/store/b/%s/DONE" % (d, name), "w").write(done + "\n")
        for f in extra:
            open("%s/store/b/%s/%s" % (d, name, f), "w").write("x\n")
    for f, text in (top or {}).items():
        open("%s/store/b/%s" % (d, f), "w").write(text)
    # the stub rclone: a call whose verb and path match $FAIL (verb:path-part) fails as a store blip does
    with open(d + "/bin/rclone", "w") as f:
        f.write("""#!/bin/sh
p() { echo "$W/store/${1#store:}"; }
path=$(eval echo "\\${$#}"); [ "$1" = rcat ] || [ "$1" = cat ] || [ "$1" = deletefile ] && path=$2; [ "$1" = copy ] && path=$2
case "$1:$path" in $FAIL) echo "rclone: $1 $path: connection reset" >&2; exit 1 ;; esac
case "$1" in
  lsf) dd=$(p "$path"); [ -d "$dd" ] || exit 0
       case "$*" in *--dirs-only*) for e in "$dd"/*/; do [ -d "$e" ] && basename "$e" | sed 's#$#/#'; done ;;
                    *--files-only*) for e in "$dd"/*; do [ -f "$e" ] && basename "$e"; done ;; esac ;;
  cat) cat "$(p "$2")" ;;
  copy) mkdir -p "$3"; cp -r "$(p "$2")"/. "$3"/ ;;
  rcat) cat > "$(p "$2")" ;;
  deletefile) rm "$(p "$2")" ;;
  *) exit 2 ;;
esac
exit 0
""")
    os.chmod(d + "/bin/rclone", 0o755)
def run_store(d, script, fail="__none__"):
    r = subprocess.run(["sh", "-c", "set -eu\n" + script], capture_output=True, text=True, timeout=60,
                       env={"PATH": d + "/bin:/usr/bin:/bin", "W": d, "STORE": "store:b", "FAIL": fail})
    # stderr first: the script's own last line last
    return r.returncode, (r.stderr + r.stdout).strip().split("\n")
def fetch(which, allow=False, store=None, fail="__none__"):
    with tempfile.TemporaryDirectory() as d:
        store_dir(d, store); os.makedirs(d + "/dump")
        script = render(fetch_src, _which=which, kafka_allow_empty=allow).replace("/dump/", d + "/dump/")
        rc, out = run_store(d, script, fail)
        fetched = sorted(os.listdir(d + "/dump"))
        pinned = sorted(n for n in os.listdir(d + "/store/b") if os.path.exists("%s/store/b/%s/PINNED" % (d, n)))
        pin_text = {n: open("%s/store/b/%s/PINNED" % (d, n)).read() for n in pinned}
        return rc, fetched, pinned, out[-1], pin_text
S = {"20261101T023000Z": ("20261101T023000Z 2 topics 5 messages", []), "20261102T023000Z": ("20261102T023000Z 2 topics 0 messages", []),
     "20261103T023000Z": (None, [])}
rc, fetched, pinned, last, pin_text = fetch("newest", store=S)
check("R04 newest: the newest complete dump holding messages - the empty newer one and the incomplete passed over; it pinned",
      (rc, fetched, pinned), (0, ["20261101T023000Z"], ["20261101T023000Z"]))
pl = pin_text.get("20261101T023000Z", "").rstrip("\n").split("\n")
check("R04   its PINNED: when, why, how to unpin it",
      (bool(re.fullmatch(r"[0-9]{8}T[0-9]{6}Z", pl[0])), pl[1:]),
      (True, ["why the source of a restore (ops tasks/kafka-restore.yml)",
              "unpin task deploy:kafka-backup-unpin -- -e kafka_dump=20261101T023000Z"]))
rc, fetched, pinned, last, _ = fetch("20261102T023000Z", store=S)
check("R04 a dump of 0 messages named: refused, nothing pinned", (rc, pinned, "holds 0 messages: not restored" in last), (1, [], True))
rc, fetched, pinned, last, _ = fetch("20261102T023000Z", allow=True, store=S)
check("R04   allowed (kafka_allow_empty): restored from, pinned", (rc, pinned), (0, ["20261102T023000Z"]))
rc, fetched, pinned, last, _ = fetch("newest", store={"20261102T023000Z": ("20261102T023000Z 2 topics 0 messages", [])})
check("R04 newest with every dump empty: refused, said", (rc, "no complete dump holding messages" in last), (1, True))
S2 = {"20261101T023000Z": ("20261101T023000Z 2 topics 5 messages", []), "20261102T023000Z": ("20261102T023000Z 2 topics 7 messages", [])}
for fail, why in (("lsf:store:b/20261102T023000Z/", "listing the newest dump"), ("cat:store:b/20261102T023000Z/DONE", "reading its DONE"),
                  ("lsf:store:b/", "listing the store"), ("copy:store:b/20261102T023000Z", "fetching it"),
                  ("rcat:store:b/20261102T023000Z/PINNED", "pinning it")):
    rc, fetched, pinned, last, _ = fetch("newest", store=S2, fail=fail)
    check("R04 newest, %s fails: stopped, said - never the older dump taken" % why,
          (rc, "20261101T023000Z" in fetched, pinned, "failed" in last), (1, False, [], True))
rc, fetched, pinned, last, _ = fetch("newest", store=S2)
check("R04   the same store, no failure: the newest taken", (rc, fetched, pinned), (0, ["20261102T023000Z"], ["20261102T023000Z"]))

# R05: the BASELINE
bt = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/tasks/kafka-baseline.yml")))
need_t = bt[0]["ansible.builtin.assert"]["that"]
check("R05 its topics: names pass, all alone passes; all among names, a quote, a $, nothing refused",
      [condition(need_t, kafka_baseline_topics=t) for t in ("chat-events", " a.b c_d-1 ", "all", "all chat", "a'b", "a$b", "  ")],
      [True, True, True, False, False, False, False])
inc = bt[1]
def baseline(topics, why, top=None, store=None, fail="__none__"):
    kb = render(inc["vars"]["_kb_topics"], kafka_baseline_topics=topics)
    script = render(inc["vars"]["kafka_store_cmd"], _kb_topics=kb, kafka_baseline_why=why)
    with tempfile.TemporaryDirectory() as d:
        store_dir(d, store, top)
        rc, out = run_store(d, script, fail)
        p = d + "/store/b/BASELINE"
        lines = open(p).read().rstrip("\n").split("\n") if os.path.exists(p) else None
        return rc, lines, out[-1]
ts = re.compile(r"[0-9]{8}T[0-9]{6}Z$")
rc, lines, last = baseline("chat-events", "the topic removed: chat's events moved; it's $done `x`")
check("R05 none there: its time, why (cut to plain characters), the topic; said",
      (rc, bool(ts.match(lines[0])), lines[1:], last.split(":")[1:] and last.endswith(": chat-events")),
      (0, True, ["why the topic removed: chat_s events moved_ it_s _done _x_", "topic chat-events"], True))
rc, lines, _ = baseline("all", "a restore from 20261101T023000Z")
check("R05 all: the line all", (rc, lines[1:]), (0, ["why a restore from 20261101T023000Z", "all"]))
OLD = "20261101T120000Z\nwhy a restore from 20261101T023000Z of a\ntopic a\n"
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": OLD}, store={"20261101T023000Z": ("x 1 topics 5 messages", [])})
check("R05 an earlier BASELINE no dump followed (the dumps before it alone): its topics kept, both whys",
      (rc, lines[1:]), (0, ["why b removed", "why a restore from 20261101T023000Z of a", "topic a", "topic b"]))
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": OLD}, store={"20261102T023000Z": (None, [])})
check("R05   a dump begun since but never finished (no DONE): not followed - kept", (rc, lines[2:]),
      (0, ["why a restore from 20261101T023000Z of a", "topic a", "topic b"]))
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": OLD}, store={"20261102T023000Z": ("x 1 topics 5 messages", [])})
check("R05 an earlier BASELINE a complete dump followed: spent, replaced - b alone", (rc, lines[1:]), (0, ["why b removed", "topic b"]))
rc, lines, _ = baseline("all", "all", top={"BASELINE": OLD})
check("R05 all over an earlier one's topics: all", (rc, lines[-1]), (0, "all"))
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": "20261101T120000Z\n"})
check("R05 an earlier timestamp alone (all, to the guard), not followed: all kept", (rc, lines[-1]), (0, "all"))
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": "garbage\n"})
check("R05 an earlier one with no timestamp: replaced, b alone", (rc, lines[1:]), (0, ["why b removed", "topic b"]))
for fail in ("lsf:store:b/", "cat:store:b/BASELINE", "lsf:store:b/20261102T023000Z/", "rcat:store:b/BASELINE"):
    rc, lines, _ = baseline("b", "b removed", top={"BASELINE": OLD}, store={"20261102T023000Z": ("x 1 topics 5 messages", [])}, fail=fail)
    check("R05 %s fails: the task fails, the earlier BASELINE as it was" % fail, (rc != 0, lines), (True, OLD.rstrip("\n").split("\n")))
rb = next(t for t in blk["block"] if str(t.get("name", "")).startswith("The store's BASELINE now"))["vars"]
run_ok = {"stdout_lines": ["fetched x", "restored 12 messages from 20261101T023000Z"]}
got = [(render(rb["kafka_baseline_topics"], **v), render(rb["kafka_baseline_why"], _kr_from=render(rb["_kr_from"], _kr_run=run_ok), **v))
       for v in ({"kafka_topics": "a b"}, {"kafka_topics": ""}, {}, {"kafka_topics": "  "})]
check("R05 the restore's BASELINE: its topics, or all - from the dump it restored (newest named by its time)",
      got, [("a b", "a restore from 20261101T023000Z of a b"), ("all", "a restore from 20261101T023000Z"),
            ("all", "a restore from 20261101T023000Z"), ("all", "a restore from 20261101T023000Z")])

# R06: the unpin
up = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/kafka-backup-unpin.yml")))[0]["tasks"]
ucmd = next(t for t in up if t.get("name") == "Its PINNED removed")["vars"]["kafka_store_cmd"]
check("R06 the dump named by its time alone", [condition(up[0]["ansible.builtin.assert"]["that"], kafka_dump=x)
      for x in ("20261101T023000Z", "newest", "20261101T023000Z/../x")], [True, False, False])
def unpin(store, fail="__none__"):
    with tempfile.TemporaryDirectory() as d:
        store_dir(d, store)
        rc, out = run_store(d, render(ucmd, kafka_dump="20261101T023000Z"), fail)
        return rc, os.path.exists(d + "/store/b/20261101T023000Z/PINNED"), os.path.exists(d + "/store/b/20261101T023000Z/DONE"), out[-1]
rc, still, done_kept, last = unpin({"20261101T023000Z": ("x", ["PINNED"])})
check("R06 a pinned dump: its PINNED gone, the dump kept, said", (rc, still, done_kept, "unpinned" in last), (0, False, True, True))
rc, still, done_kept, last = unpin({"20261101T023000Z": ("x", [])})
check("R06 a dump not pinned: said, nothing changed", (rc, still, done_kept, "not pinned: nothing changed" in last), (0, False, True, True))
rc, still, done_kept, last = unpin({"20261101T023000Z": ("x", ["PINNED"])}, fail="lsf:store:b/20261101T023000Z/")
check("R06 its listing fails: the task fails, still pinned (never read as not pinned)", (rc != 0, still), (True, True))

print("kafka-restore: " + ("ALL-PASS" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY_KAFKA_RESTORE
