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
#   R06 tasks/kafka-unpin.yml: a pinned dump unpinned, said; one not pinned said, nothing changed; one not there refused
#   R07 playbooks/kafka-backup-retire.yml: a dump's DONE removed (no longer complete), why kept; a pinned one refused
#   R08 the copy's refused dump (tests/ansible/copy/tasks/kafka-guard-refused.yml): each topic named gone, none excused named
#   R09 the restore's wait: an API read that fails is tried again (the Job runs on); its fetch, topics and restored lines
#   R10 the restore Job as built from the CronJob: its env (TOPICS, FORCE, RESET_GROUPS), its volumes (the scratch 2Gi),
#       the dump container's mounts, the pod's labels and annotations (no checksum), its ServiceAccount; the playbook:
#       restored, then dumped, then said
#   R11 the backup's and the store's waits through a failing read; the store Job's scratch the upload's own /tmp
#   R12 the baseline's "spent": an earlier BASELINE a complete dump followed - the dumps before it in the store too
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
check("R02 inside: the ConfigMap made, no dump unfinished, the restore Job run, what it restored, the baseline - in that order",
      [n.split(" ")[1] for n in inner], ["restoring", "dump", "restore", "it", "store's"])
mkcmd = blk["block"][0]["ansible.builtin.shell"]["cmd"]
check("R02 made by create (one there already: another restore's, or stale - stops), its since a UTC stamp, out of Velero's backups",
      ("create configmap {{ _kr_lock }}" in mkcmd, "| $k create -f -" in mkcmd, "apply" in mkcmd,
       '--from-literal=since="$(date -u +%Y%m%dT%H%M%SZ)"' in mkcmd, '"velero.io/exclude-from-backup": "true"' in mkcmd), (True, True, False, True, True))
check("R02   it names the restore Job (the stale lock's runbook judges that Job, never another restore's)",
      "--from-literal=job={{ _kr_name }}" in mkcmd, True)
alw = blk.get("always") or []
rm = next(t for t in alw if str(t.get("name", "")).startswith("The restoring ConfigMap removed"))
check("R02 always: the ConfigMap removed, a missing one no error, retried",
      ("delete configmap {{ _kr_lock }}" in str(rm.get("ansible.builtin.command")), "--ignore-not-found" in str(rm.get("ansible.builtin.command")),
       rm.get("retries")), (True, True, 3))
w = rm["when"]
ok, bad = {"failed": False, "changed": True}, {"failed": True}
nb, began, unread = {"rc": 0, "stdout": "not-began"}, {"rc": 0, "stdout": "began"}, {"rc": 1, "stdout": ""}
check("R02   removed by the run that made it alone: its create failed (another's lock) - kept",
      condition(w, _kr_locked=bad, _kr_run=ok), False)
check("R02   the restore succeeded, or never started (a dump unfinished refused it) - removed",
      (condition(w, _kr_locked=ok, _kr_run=ok), condition(w, _kr_locked=ok)), (True, True))
check("R02   the restore failed after its restore container began - kept (a Kafka half restored)",
      condition(w, _kr_locked=ok, _kr_run=bad, _kr_began=began), False)
check("R02   the Job failed, its restore container never began (the fetch failed: Kafka untouched) - removed",
      condition(w, _kr_locked=ok, _kr_run=bad, _kr_began=nb), True)
check("R02   that answer not read - kept (never removed on a guess)",
      (condition(w, _kr_locked=ok, _kr_run=bad, _kr_began=unread), condition(w, _kr_locked=ok, _kr_run=bad)), (False, False))
bc = next(t for t in alw if str(t.get("name", "")).startswith("Whether the restore container began"))
bsh = bc["ansible.builtin.shell"]["cmd"]
bpy = bsh[bsh.index("python3 -c '") + len("python3 -c '"):bsh.rindex("'")]
def began_of(pods):
    r = subprocess.run(["python3", "-c", bpy], input=json.dumps({"items": pods}), capture_output=True, text=True)
    return r.returncode, r.stdout.strip()
pod = lambda *cs: {"status": {"containerStatuses": list(cs)}}
check("R02   began: the restore container running, ended, or restarted; not: only the fetch's status, or no pod (never applied)",
      [began_of([pod({"name": "restore", "state": {"running": {}}})])[1], began_of([pod({"name": "restore", "state": {"terminated": {"exitCode": 1}}})])[1],
       began_of([pod({"name": "restore", "state": {"waiting": {}}, "lastState": {"terminated": {}}})])[1],
       began_of([pod({"name": "restore", "state": {"waiting": {"reason": "PodInitializing"}}})])[1], began_of([{"status": {}}])[1], began_of([])[1]],
      ["began", "began", "began", "not-began", "not-began", "not-began"])
check("R02   asked only when the Job failed", condition(bc["when"], _kr_locked=ok, _kr_run=ok), False)
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
  lsf) dd=$(p "$path"); [ -d "$dd" ] || { echo "rclone: directory not found" >&2; exit 3; }
       case "$*" in *--dirs-only*) for e in "$dd"/*/; do [ -d "$e" ] && basename "$e" | sed 's#$#/#'; done ;;
                    *--files-only*) for e in "$dd"/*; do [ -f "$e" ] && basename "$e"; done ;; esac ;;
  cat) cat "$(p "$2")" ;;
  copy) [ -d "$(p "$2")" ] || exit 3; mkdir -p "$3"; cp -r "$(p "$2")"/. "$3"/ ;;
  mkdir) mkdir -p "$(p "$2")" ;;
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
def fetch(which, allow=False, store=None, fail="__none__", older=False):
    with tempfile.TemporaryDirectory() as d:
        store_dir(d, store); os.makedirs(d + "/dump")
        script = render(fetch_src, _which=which, kafka_allow_empty=allow, kafka_allow_older=older).replace("/dump/", d + "/dump/")
        rc, out = run_store(d, script, fail)
        fetched = sorted(os.listdir(d + "/dump"))
        pinned = sorted(n for n in os.listdir(d + "/store/b") if os.path.exists("%s/store/b/%s/PINNED" % (d, n)))
        pin_text = {n: open("%s/store/b/%s/PINNED" % (d, n)).read() for n in pinned}
        return rc, fetched, pinned, out[-1], pin_text
S = {"20261101T023000Z": ("20261101T023000Z 2 topics 5 messages", []), "20261102T023000Z": ("20261102T023000Z 2 topics 0 messages", []),
     "20261103T023000Z": (None, [])}
rc, fetched, pinned, last, pin_text = fetch("newest", store=S)
check("R04 newest: the newest complete dump holding messages - the empty newer one and the incomplete passed over; it pinned, the newer complete one too",
      (rc, fetched, pinned, last), (0, ["20261101T023000Z"], ["20261101T023000Z", "20261102T023000Z"],
                                   "fetched 20261101T023000Z (5 messages), pinned: 20261102T023000Z 20261101T023000Z"))
check("R04   the newer one's PINNED: newer than the source, how to unpin it",
      pin_text["20261102T023000Z"].split("\n")[1:3], ["why newer than the source of a restore (20261101T023000Z)",
                                                     "unpin task deploy:kafka-backup-unpin -- -e kafka_dump=20261102T023000Z"])
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
rc, fetched, pinned, last, _ = fetch("20261101T023000Z", store=S2)
check("R04 an older dump named, a newer complete one holding messages: refused, nothing pinned (its messages after the source)",
      (rc, fetched, pinned, "newer complete dumps hold messages: 20261102T023000Z" in last), (1, [], [], True))
rc, fetched, pinned, last, pin_text = fetch("20261101T023000Z", store=S2, older=True)
check("R04   allowed (kafka_allow_older): restored from, the newer pinned beside it",
      (rc, fetched, pinned), (0, ["20261101T023000Z"], ["20261101T023000Z", "20261102T023000Z"]))
rc, fetched, pinned, last, _ = fetch("20261103T023000Z", store=S)
check("R04 a dump named that is not complete (no DONE): refused before anything is fetched or pinned",
      (rc, fetched, pinned, "not a complete one" in last), (1, [], [], True))

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
with tempfile.TemporaryDirectory() as d:
    store_dir(d, None); os.rmdir(d + "/store/b")
    kb = render(inc["vars"]["_kb_topics"], kafka_baseline_topics="b")
    rc, out = run_store(d, render(inc["vars"]["kafka_store_cmd"], _kb_topics=kb, kafka_baseline_why="x"))
    check("R05 a fresh store (no bucket until the first upload): made, the BASELINE written - never 'directory not found'",
          (rc, os.path.exists(d + "/store/b/BASELINE")), (0, True))
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
sf = next(t for t in blk["block"] if str(t.get("name", "")).startswith("What it restored"))["ansible.builtin.set_fact"]
bb = next(t for t in blk["block"] if str(t.get("name", "")).startswith("The store's BASELINE now"))
inc_v = bb["block"][0]["vars"]
run_ok = {"stdout_lines": ["fetched 20261101T023000Z (12 messages), pinned: 20261102T023000Z 20261101T023000Z",
                           "topics chat.messages user.events ", "restored 12 messages from 20261101T023000Z"]}
facts = {k: render(v, _kr_run=run_ok) for k, v in sf.items()}
check("R05 the restore's BASELINE: the topics restore.sh says it restored (never all), from the dump it restored; what it pinned",
      (render(inc_v["kafka_baseline_topics"], **facts), render(inc_v["kafka_baseline_why"], **facts), facts["_kr_pinned"]),
      ("chat.messages user.events", "a restore from 20261101T023000Z of chat.messages user.events", "20261102T023000Z 20261101T023000Z"))
fwr = next(t for t in blk["block"] if str(t.get("name", "")).startswith("The restore Job run"))["failed_when"]
check("R05   the restore's log without its topics line (no BASELINE could be named): failed; with it: passed",
      (condition(fwr, _kr_run={"rc": 0, "stdout_lines": [run_ok["stdout_lines"][0], run_ok["stdout_lines"][2]]}),
       condition(fwr, _kr_run=dict(run_ok, rc=0))), (True, False))
check("R05   the BASELINE failing after the restore: says so with the baseline task to run - never the restore again",
      [("deploy:kafka-backup-baseline" in str(t), "kafka_baseline_topics='{{ _kr_topics }}'" in str(t), "deploy:kafka:restore" in str(t))
       for t in bb["rescue"]], [(True, True, False)])
need_r = tasks[0]["ansible.builtin.assert"]["that"]
check("R05 kafka_topics checked before anything: names or none pass; a tab, a quote, a $ refused",
      [condition(need_r, kafka_topics=t) for t in ("a.b c-d", "", "  ", "a\tb", "a'b", "a$b")] + [condition(need_r)],
      [True, True, True, False, False, False, True])

# R06: the unpin
up = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/tasks/kafka-unpin.yml")))
ucmd = next(t for t in up if t.get("name") == "Its PINNED removed")["vars"]["kafka_store_cmd"]
check("R06 the dump named by its time alone", [condition(up[0]["ansible.builtin.assert"]["that"], kafka_dump=x)
      for x in ("20261101T023000Z", "newest", "20261101T023000Z/../x")] + [condition(up[0]["ansible.builtin.assert"]["that"])],
      [True, False, False, False])
upb = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/kafka-backup-unpin.yml")))[0]["tasks"]
check("R06   the playbook: the tasks file (the copy's rehearsal runs the same)",
      [t.get("ansible.builtin.include_tasks") for t in upb if "ansible.builtin.include_tasks" in t], ["tasks/kafka-unpin.yml"])
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
rc, still, done_kept, last = unpin({"20261102T023000Z": ("x", ["PINNED"])})
check("R06 a dump not in the store: refused, said (never 'not pinned')", (rc != 0, "no dump 20261101T023000Z in the store" in last), (True, True))

# R07: the retire
rt = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/kafka-backup-retire.yml")))[0]["tasks"]
rneed = rt[0]["ansible.builtin.assert"]["that"]
check("R07 the dump by its time, and why", [condition(rneed, kafka_dump="20261101T023000Z", kafka_retire_why="topics.txt lost"),
      condition(rneed, kafka_dump="20261101T023000Z", kafka_retire_why=" "), condition(rneed, kafka_dump="newest", kafka_retire_why="x")],
      [True, False, False])
rcmd = next(t for t in rt if t.get("name") == "Its DONE removed")["vars"]["kafka_store_cmd"]
def retire(store, fail="__none__"):
    with tempfile.TemporaryDirectory() as d:
        store_dir(d, store)
        rc, out = run_store(d, render(rcmd, kafka_dump="20261101T023000Z", kafka_retire_why="its topics.txt lost; $x 'y'"), fail)
        b = d + "/store/b/20261101T023000Z/"
        return (rc, os.path.exists(b + "DONE"), open(b + "RETIRED").read().split("\n")[1:3] if os.path.exists(b + "RETIRED") else None, out[-1])
rc, done_left, why, last = retire({"20261101T023000Z": ("20261101T023000Z 2 topics 5 messages", [])})
check("R07 a damaged dump: its DONE gone (no longer complete - never the guard's reference), why and its DONE kept beside it",
      (rc, done_left, why, "retired" in last), (0, False, ["why its topics.txt lost_ _x _y_", "DONE was 20261101T023000Z 2 topics 5 messages"], True))
rc, done_left, why, last = retire({"20261101T023000Z": ("x", ["PINNED"])})
check("R07   a pinned one (a restore's source): refused, its DONE kept", (rc != 0, done_left, "unpin it first" in last), (True, True, True))
rc, done_left, why, last = retire({"20261101T023000Z": (None, [])})
check("R07   no DONE: retired already, nothing changed", (rc, "nothing changed" in last), (0, True))
rc, done_left, why, last = retire({"20261101T023000Z": ("x", [])}, fail="lsf:store:b/20261101T023000Z/")
check("R07   its listing failing: refused, its DONE kept", (rc != 0, done_left), (True, True))

# R08: the copy's refused dump - its judgement of the upload's line
gr = yaml.safe_load(open(os.path.join(ops, "tests/ansible/copy/tasks/kafka-guard-refused.yml")))[0]["failed_when"]
line = lambda body: {"rc": 0, "stdout": "job /1\n" + body, "stdout_lines": ["job /1", body]}
both = "Kafka lost data: b gone (since 20261101T023000Z) - not uploaded, nothing pruned"
check("R08 refused naming the gone topic, the excused one not named: passed",
      condition(gr, _guardcheck=line(both), kafka_guard_gone=["b"], kafka_guard_excused=["a"]), False)
check("R08   the excused one named too (gone, or made again): failed - a restored topic judged",
      (condition(gr, _guardcheck=line(both + "; a gone (since x)"), kafka_guard_gone=["b"], kafka_guard_excused=["a"]),
       condition(gr, _guardcheck=line("Kafka lost data: a made again (TopicId p -> q, since x); b gone (since x)"), kafka_guard_gone=["b"], kafka_guard_excused=["a"])),
      (True, True))
check("R08   a prefix is no name: b-other gone does not name b",
      condition(gr, _guardcheck=line("Kafka lost data: b-other gone (since x)"), kafka_guard_gone=["b"], kafka_guard_excused=[]), True)
check("R08   a name inside another is no name: ab gone does not name b (a refusal for b missed)",
      condition(gr, _guardcheck=line("Kafka lost data: ab gone (since x)"), kafka_guard_gone=["b"], kafka_guard_excused=[]), True)
check("R08   an excused name inside another's: metadata gone does not name data (the excused one not judged)",
      condition(gr, _guardcheck=line("Kafka lost data: b gone (since x); metadata gone (since x)"), kafka_guard_gone=["b"], kafka_guard_excused=["data"]), False)
check("R08   the excused topic named by a partition's loss (data[0] at 3, was 9): failed",
      condition(gr, _guardcheck=line("Kafka lost data: b gone (since x); data[0] at 3, was 9 (x)"), kafka_guard_gone=["b"], kafka_guard_excused=["data"]), True)
check("R08   two named gone, both in the line: passed; one missing: failed",
      (condition(gr, _guardcheck=line("Kafka lost data: a gone (since x); b gone (since x)"), kafka_guard_gone=["a", "b"], kafka_guard_excused=[]),
       condition(gr, _guardcheck=line("Kafka lost data: a gone (since x)"), kafka_guard_gone=["a", "b"], kafka_guard_excused=[])), (False, True))
check("R08   the dump uploaded (the Job succeeded), or no refusal line: failed",
      (condition(gr, _guardcheck={"rc": 0, "stdout": "job 1/\nuploaded", "stdout_lines": ["job 1/", "uploaded"]}, kafka_guard_gone=["b"], kafka_guard_excused=[]),
       condition(gr, _guardcheck=line("connection reset"), kafka_guard_gone=["b"], kafka_guard_excused=[])), (True, True))

# R09: the restore's wait, against a stub kubectl - one read failing, then the Job done
wt = next(t for t in blk["block"] if str(t.get("name", "")).startswith("The restore Job run"))["ansible.builtin.shell"]["cmd"]
def wait(fail_reads, done="1/"):
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(d + "/bin")
        open(d + "/bin/kubectl", "w").write("""#!/bin/bash
case "$*" in
  *" apply "*) cat > /dev/null ;;
  *" get job/"*) n=$(cat "$W/reads" 2> /dev/null || echo 0); echo $((n + 1)) > "$W/reads"
                 [ "$n" -ge "$FAILS" ] || { echo "error: the server is currently unable to handle the request" >&2; exit 1; }; echo "$DONE" ;;
  *"logs "*"-c fetch"*) echo "fetched 20261101T023000Z (5 messages), pinned: 20261101T023000Z" ;;
  *"logs "*"-c restore"*) printf 'topics a b\nrestored 5 messages from 20261101T023000Z\n' ;;
  *" delete "*) ;;
esac
""")
        open(d + "/bin/sleep", "w").write("#!/bin/sh\nexit 0\n")
        os.chmod(d + "/bin/kubectl", 0o755); os.chmod(d + "/bin/sleep", 0o755)
        script = render(wt, kubectl="kubectl", _kr_name="kafka-restore-1", kafka_namespace="ns")
        r = subprocess.run(["bash", "-c", script], input="{}", capture_output=True, text=True, timeout=120,
                           env={"PATH": d + "/bin:/usr/bin:/bin", "W": d, "FAILS": str(fail_reads), "DONE": done})
        return r.returncode, r.stdout.strip().split("\n")
rc, out = wait(2)
check("R09 the restore's wait: two reads failing, then done - its fetch, topics and restored lines (the Job ran on)",
      (rc, out), (0, ["fetched 20261101T023000Z (5 messages), pinned: 20261101T023000Z", "topics a b", "restored 5 messages from 20261101T023000Z"]))
rc, out = wait(10000)
check("R09   every read failing: not done by its deadline, said", (rc, out[-1]), (1, "the restore Job kafka-restore-1 not done 3700 s after its start"))

# R10: the restore Job as built from a CronJob's pod
pod = {"metadata": {"labels": {"app.kubernetes.io/name": "kafka-backup", "x": "y"},
                    "annotations": {"sidecar.istio.io/nativeSidecar": "true", "checksum/scripts": "abc"}},
       "spec": {"serviceAccountName": "sa-kb", "securityContext": {"runAsNonRoot": True},
                "volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "256Mi"}}, {"name": "dump", "emptyDir": {}},
                            {"name": "scripts", "configMap": {"name": "s"}}, {"name": "restoring", "configMap": {"name": "l", "optional": True}}],
                "initContainers": [{"name": "dump", "image": "kafka:4", "env": [{"name": "BOOTSTRAP", "value": "b:9092"}],
                                    "resources": {"limits": {"memory": "1Gi"}}, "securityContext": {"readOnlyRootFilesystem": True},
                                    "volumeMounts": [{"name": "tmp", "mountPath": "/tmp"}, {"name": "dump", "mountPath": "/dump"},
                                                     {"name": "scripts", "mountPath": "/scripts"}]}],
                "containers": [{"name": "upload", "image": "rclone:1", "env": [{"name": "STORE", "value": "store:kafka"}],
                                "resources": {}, "securityContext": {"readOnlyRootFilesystem": True},
                                "volumeMounts": [{"name": "tmp", "mountPath": "/tmp"}, {"name": "dump", "mountPath": "/dump"}]}]}}
cjson = {"stdout": json.dumps({"spec": {"jobTemplate": {"spec": {"template": pod}}}})}
jtask = next(t for t in tasks if t.get("name") == "The restore Job")
from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar
def render_tree(x, **v):  # a task's dict rendered whole, its strings trusted as a playbook's are
    return Templar(loader=DataLoader(), variables=v).template(as_loaded(x))
def job(**v):
    vs = dict(v, _kr_cronjob=cjson, kafka_dump="newest", kafka_namespace="ns")
    for k in ("_ns", "_pod", "_dump_c", "_upload_c", "_which"):  # the task's vars, each on the ones before it
        vs[k] = render(jtask["vars"][k], **vs)
    return render_tree(jtask["ansible.builtin.set_fact"]["_kr_job"], **vs)
j = job(kafka_topics=" a b ", kafka_force=True, kafka_reset_groups=False)
spec = j["spec"]["template"]["spec"]; rc_ = spec["containers"][0]; fc = spec["initContainers"][0]
env = {e["name"]: e["value"] for e in rc_["env"]}
check("R10 the restore container: TOPICS as named (trimmed), FORCE and RESET_GROUPS as asked, the dump container's env kept",
      (env.get("TOPICS"), env.get("FORCE"), env.get("RESET_GROUPS"), env.get("BOOTSTRAP")), ("a b", "1", "no", "b:9092"))
env2 = {e["name"]: e["value"] for e in job()["spec"]["template"]["spec"]["containers"][0]["env"]}
check("R10   by default: every topic, no force, the groups moved", (env2.get("TOPICS"), env2.get("FORCE"), env2.get("RESET_GROUPS")), ("", "", "yes"))
check("R10 its volumes the CronJob's, the scratch 2Gi in place of the upload's 256Mi; both containers on the dump container's mounts",
      ([(v["name"], v.get("emptyDir")) for v in spec["volumes"] if v["name"] in ("tmp", "dump")], [m["mountPath"] for m in rc_["volumeMounts"]],
       [m["mountPath"] for m in fc["volumeMounts"]], [v["name"] for v in spec["volumes"]]),
      ([("dump", {}), ("tmp", {"sizeLimit": "2Gi"})], ["/tmp", "/dump", "/scripts"], ["/tmp", "/dump", "/scripts"], ["dump", "scripts", "restoring", "tmp"]))
check("R10 the pod's labels the CronJob's (its network policy reaches the store), annotations without the checksum, its ServiceAccount, no token, never retried",
      (j["spec"]["template"]["metadata"]["labels"], j["spec"]["template"]["metadata"]["annotations"], spec["serviceAccountName"],
       spec["automountServiceAccountToken"], j["spec"]["backoffLimit"], spec["restartPolicy"], fc["image"], rc_["image"]),
      ({"app.kubernetes.io/name": "kafka-backup", "x": "y"}, {"sidecar.istio.io/nativeSidecar": "true"}, "sa-kb", False, 0, "Never", "rclone:1", "kafka:4"))
pb = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/kafka-restore.yml")))[0]["tasks"]
check("R10 the playbook: the dump named, restored, the restored Kafka dumped, said - in that order",
      [t.get("ansible.builtin.include_tasks") or next(iter(k for k in t if k.startswith("ansible.builtin."))) for t in pb],
      ["ansible.builtin.assert", "tasks/kafka-restore.yml", "tasks/kafka-backup.yml", "ansible.builtin.debug"])

kc = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/kafka-backup-check.yml")))[0]["tasks"]
ja = next(t for t in kc if str(t.get("name", "")).startswith("The guard judged topics"))
check("R10 the copy's Kafka check: the guard's verdict judged topics against a dump - nothing to compare, no dump before, none said: refused",
      [condition(ja["ansible.builtin.assert"]["that"], kafka_backup_guard=g) for g in (
          "Kafka holds everything its dumps held: chat.messages@20261101T023000Z user.events@20261101T023000Z",
          "Kafka holds everything its dumps held: nothing to compare (the BASELINE of x covers every topic, y older)",
          "no complete dump before this one to compare with", "(none said)")] + [condition(ja["when"], kafka_backup_expect_judged=True, ansible_check_mode=False),
          condition(ja["when"], ansible_check_mode=False)],
      [True, False, False, False, True, False])
# R11: the backup's and the store's waits through a failing read
def stub_wait(script, logs, fail_reads, render_vars):
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(d + "/bin")
        open(d + "/bin/kubectl", "w").write("""#!/bin/bash
case "$*" in
  *" create job "*|*" apply "*) cat > /dev/null 2>&1; exit 0 ;;
  *" get job/"*) n=$(cat "$W/reads" 2> /dev/null || echo 0); echo $((n + 1)) > "$W/reads"
                 [ "$n" -ge "$FAILS" ] || { echo "error: the server is currently unable to handle the request" >&2; exit 1; }; echo "1/" ;;
  *"logs "*) printf '%s\\n' "$LOGS" ;;
  *" delete "*) ;;
esac
""")
        open(d + "/bin/sleep", "w").write("#!/bin/sh\nexit 0\n")
        os.chmod(d + "/bin/kubectl", 0o755); os.chmod(d + "/bin/sleep", 0o755)
        r = subprocess.run(["bash", "-c", render(script, **render_vars)], input="{}", capture_output=True, text=True, timeout=120,
                           env={"PATH": d + "/bin:/usr/bin:/bin", "W": d, "FAILS": str(fail_reads), "LOGS": logs})
        return r.returncode, r.stdout.strip().split("\n")
kb = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/tasks/kafka-backup.yml")))
kbs = next(t for t in kb if "ansible.builtin.shell" in t)["ansible.builtin.shell"]["cmd"]
rc, out = stub_wait(kbs, "Kafka holds everything its dumps held: a@20261101T023000Z\nkafka backup 20261102T023000Z: uploaded", 2,
                    {"kubectl": "kubectl", "_kb_ns": "ns", "_kb_job": "kafka-backup-check-1"})
check("R11 the backup's wait: two reads failing, then done - the guard's verdict and the dump's name",
      (rc, out[-2:]), (0, ["guard: Kafka holds everything its dumps held: a@20261101T023000Z", "20261102T023000Z"]))
ks = yaml.safe_load(open(os.path.join(ops, "deploy/ansible/playbooks/tasks/kafka-store.yml")))
kss = next(t for t in ks if str(t.get("name", "")).startswith("The store Job run"))["ansible.builtin.shell"]["cmd"]
rc, out = stub_wait(kss, "baseline 20261102T000000Z: a", 2, {"kubectl": "kubectl", "kafka_namespace": "ns", "_ks_name": "kafka-store-x-1"})
check("R11 the store's wait: two reads failing, then done - its last line", (rc, out[-1]), (0, "baseline 20261102T000000Z: a"))
rc, out = stub_wait(kss, "x", 10000, {"kubectl": "kubectl", "kafka_namespace": "ns", "_ks_name": "kafka-store-x-1"})
check("R11   every read failing: not done by its deadline, said", (rc, out[-1]), (1, "the store Job kafka-store-x-1 not done 660 s after its start"))
sj = next(t for t in ks if t.get("name") == "The store Job")
sjob = render_tree(sj["ansible.builtin.set_fact"]["_ks_job"], _pod=pod, _upload_c=pod["spec"]["containers"][0], kafka_namespace="ns", kafka_store_cmd="echo x", kafka_store_what="x")
check("R11 the store Job's scratch: the upload container's own /tmp mount over a small emptyDir (HOME=/tmp under a read-only root)",
      ([m["mountPath"] for m in sjob["spec"]["template"]["spec"]["containers"][0]["volumeMounts"]], sjob["spec"]["template"]["spec"]["volumes"]),
      (["/tmp"], [{"name": "tmp", "emptyDir": {"sizeLimit": "64Mi"}}]))

# R12: the baseline's spent rule on a store holding dumps before the earlier BASELINE too
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": OLD},
                        store={"20261101T023000Z": ("x 1 topics 5 messages", []), "20261102T023000Z": ("x 1 topics 5 messages", [])})
check("R12 an earlier BASELINE with a dump before it and a complete one after: spent - b alone", (rc, lines[1:]), (0, ["why b removed", "topic b"]))
rc, lines, _ = baseline("b", "b removed", top={"BASELINE": OLD},
                        store={"20261031T023000Z": ("x 1 topics 5 messages", []), "20261101T023000Z": ("x 1 topics 5 messages", [])})
check("R12   dumps before it alone (none after): kept - a and b", (rc, lines[-2:]), (0, ["topic a", "topic b"]))

print("kafka-restore: " + ("ALL-PASS" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY_KAFKA_RESTORE
