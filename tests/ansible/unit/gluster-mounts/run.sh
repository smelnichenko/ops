#!/bin/bash
# setup-gluster.yml's check of the backup volumes' mounts, as the playbook holds it (in the play that mounts them, its
# list the play's own), findmnt a stub: each volume mounted at its own mount point from itself passes; one not mounted,
# or mounted from another volume, fails naming it (one line matching any volume passed: two of three unmounted passed).
# Skipped in a preview: it checks what the play did. A hung client (a stat stuck in the kernel: no signal ends it, and
# timeout waits for its child) bounded all the same: the stat not waited on, its answer polled until a deadline.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# MOUNTS: "<mount point>=<source>" pairs, one a line - what is mounted where (fuse.glusterfs)
cat > "$W/bin/findmnt" <<'STUB'
#!/bin/bash
mp=""
while [ $# -gt 0 ]; do case "$1" in -M|--mountpoint) mp=$2; shift ;; esac; shift; done
src=$(sed -n "s|^$mp=||p" <<< "$MOUNTS")
[ -n "$src" ] && echo "$src" || exit 1
STUB
# stat -f on a mount point: DEAD="<mount point>" - its FUSE client gone (the kernel answers at once: ENOTCONN), the
# mount still listed in mountinfo; HUNG="<mount point>" - its client hung: the stat never answers, deaf to TERM (as
# one in the kernel's uninterruptible wait is), its PID in $W/hung.pid
cat > "$W/bin/stat" <<'STUB'
#!/bin/bash
for a; do [ "$a" != "${HUNG:-}" ] || { echo $$ > "$W/hung.pid"; trap '' TERM; while :; do sleep 1; done; }; done
for a; do [ "$a" != "${DEAD:-}" ] || { echo "stat: cannot read file system information for '$a': Transport endpoint is not connected" >&2; exit 1; }; done
# a path nothing is mounted at: a new Pi's mount point not made yet - none there
p=${@: -1}
grep -q "^$p=" <<< "${MOUNTS:-}" || { echo "stat: cannot read file system information for '$p': No such file or directory" >&2; exit 1; }
echo "  File: \"$p\""
STUB
chmod +x "$W/bin/findmnt" "$W/bin/stat"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYGM'
import os, re, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render, trust_as_template  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
plays = yaml.safe_load(open("deploy/ansible/playbooks/setup-gluster.yml"))
def end_hung():
    """The stub's stat this test started (deaf to TERM), ended here - gone already, nothing to end."""
    hp = os.path.join(W, "hung.pid")
    if not os.path.exists(hp):
        return
    pid = int(open(hp).read())
    os.remove(hp)
    try:
        if open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")[1:2] == [os.path.join(W, "bin", "stat").encode()]:
            os.kill(pid, 9)
    except (FileNotFoundError, ProcessLookupError):
        pass
# no play gathers the hardware facts: their mount facts stat every mount, a hung client's in a thread no signal ends
check("no play gathers the mounts' facts (network, or none)",
      [p.get("name") for p in plays if p.get("gather_facts", True)
       and not (isinstance(p.get("gather_subset"), list) and not {"all", "hardware"} & set(p["gather_subset"]))], [])
# nor any other playbook's play on the Pis (they hold the Gluster mounts): Keycloak's, Patroni's, Vault's... - each needs
# the platform's and the network's facts alone (architecture, the default address)
import glob  # noqa: E402
pi_plays = [(f, q.get("name") or q.get("hosts")) for f in sorted(glob.glob("deploy/ansible/playbooks/*.yml"))
            for q in (yaml.safe_load(open(f)) or []) if isinstance(q, dict) and "hosts" in q
            and re.search(r"\bpi|\ball\b|gluster", str(q["hosts"])) and q.get("gather_facts", True)
            and not (isinstance(q.get("gather_subset"), list) and not {"all", "hardware"} & set(q["gather_subset"]))]
check("no playbook's play on the Pis gathers the mounts' facts", pi_plays, [])
mounting = next(p for p in plays if p.get("name") == "Mount backup GlusterFS volumes")
vols = mounting["vars"]["backup_volumes"]
t = next((t for t in mounting["tasks"] if "findmnt" in str(t.get("ansible.builtin.shell", "")) and "NOT MOUNTED" in str(t)),
         None)
check("the play that mounts the volumes checks each one", t is not None, True)
if t:
    sh = t["ansible.builtin.shell"]
    pv = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in (mounting.get("vars") or {}).items()}
    pv["mount_answer_seconds"] = 1
    check("the stat not under timeout (it waits for its child, held in the kernel all the same)",
          bool(__import__("re").search(r"\btimeout\b[^\n]*\bstat\b", str(render(sh if isinstance(sh, str) else sh["cmd"], **pv)))),
          False)
    script = render(sh if isinstance(sh, str) else sh["cmd"], **pv)
    env = {k: str(render(str(v), backup_volumes=vols)) for k, v in (t.get("environment") or {}).items()}
    def run(mounts, dead="", hung=""):
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"],
                                    MOUNTS="\n".join(mounts), DEAD=dead, HUNG=hung, W=W, **env))
        return r.returncode, r.stdout
    own = [f"{v['mount']}=10.0.0.1:/{v['name']}" for v in vols]
    check("each mounted from itself: passes", run(own)[0], 0)
    rc, out = run(own[1:])
    check(f"{vols[0]['name']} not mounted: fails, named", (rc != 0, vols[0]["name"] in out and "NOT MOUNTED" in out),
          (True, True))
    rc, out = run([own[0].replace(f":/{vols[0]['name']}", f":/{vols[1]['name']}")] + own[1:])
    check(f"{vols[0]['name']}'s mount point serving another volume: fails, named", (rc != 0, vols[0]["name"] in out),
          (True, True))
    rc, out = run(own, dead=vols[0]["mount"])
    check(f"{vols[0]['name']} mounted from itself, its client dead (listed, not answering): fails, named",
          (rc != 0, vols[0]["name"] in out and "NOT MOUNTED" in out), (True, True))
    import time
    t0 = time.monotonic()
    try:
        rc, out = run(own, hung=vols[0]["mount"])
        got = (rc != 0, vols[0]["name"] in out and "its client hung" in out, time.monotonic() - t0 < 10)
    except subprocess.TimeoutExpired:
        got = "held for good (cut at 30 s)"
    end_hung()
    check(f"{vols[0]['name']}'s client hung (its stat never answers, deaf to TERM): fails at its deadline, named - "
          "never held", got, (True, True, True))
    check("the task bounded too (Ansible's timeout: what no poll can end)", isinstance(t.get("timeout"), int), True)
    check("skipped in a preview (it checks what the play did)",
          [condition(t.get("when", True), ansible_check_mode=cm) for cm in (False, True)], [True, False])
# before anything touches a mount point (makes it, unmounts it, mounts it, sets its owner - each a stat a hung client
# holds for good), every volume mounted there answers, bounded: one that does not refused at its deadline, named; each
# touching task bounded besides (Ansible's timeout)
TOUCH = {"Mount backup GlusterFS volumes": ["Create mount points", "Unmount what another source has mounted there",
                                            "Mount backup volumes", "Fix MinIO data ownership",
                                            "Fix Forgejo data ownership (heal/ownership can lag on a new volume)"],
         "Mount GlusterFS volume": ["Unmount what is mounted there now", "Mount GlusterFS volume", "Fix ownership"]}
def flat(ts):
    for x in ts or []:
        yield x
        for k in ("block", "rescue", "always"):
            yield from flat(x.get(k))
for pname, touching in TOUCH.items():
    play = next(p for p in plays if p.get("name") == pname)
    ts = list(flat(play["tasks"]))
    names = [x.get("name") for x in ts]
    pre = next((x for x in ts if "answer" in str(x.get("name", "")).lower()
                and ("HUNG" in str(x) or "answer_check" in str(x))), None)
    check(f"{pname}: a bounded answer check before every task touching a mount point",
          pre is not None and all(n in names and names.index(pre["name"]) < names.index(n) for n in touching), True)
    check(f"{pname}: each task touching a mount point bounded (Ansible's timeout)",
          [n for n in touching if n not in names or not isinstance(ts[names.index(n)].get("timeout"), int)], [])
    if pre is None:
        continue
    pvars = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in (play.get("vars") or {}).items()}
    pvars["mount_answer_seconds"] = 1
    sh = pre["ansible.builtin.shell"]
    script = render(sh if isinstance(sh, str) else sh["cmd"], **pvars)
    env = {k: str(render(str(v), **pvars)) for k, v in (pre.get("environment") or {}).items()}
    points = [l.split()[1] for l in env.get("VOLUMES", "").splitlines() if l.strip()]
    def pre_run(mounts, hung=""):
        import time
        t0 = time.monotonic()
        try:
            r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30,
                               env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"],
                                        MOUNTS="\n".join(mounts), HUNG=hung, W=W, **env))
            return r.returncode, r.stdout, time.monotonic() - t0 < 10
        except subprocess.TimeoutExpired:
            return "held for good", "", False
        finally:
            end_hung()
    mounted = [f"{m}=10.0.0.1:/x" for m in points]
    check(f"{pname}: the answer check - every mount answering passes; none mounted passes (nothing to touch)",
          [pre_run(mounted)[0], pre_run([])[0]], [0, 0])
    rc, out, prompt = pre_run(mounted, hung=points[0] if points else "")
    check(f"{pname}: a mounted volume whose client hung: refused at its deadline, named - never held",
          (rc != 0, bool(points) and points[0] in out and "HUNG" in out, prompt), (True, True, True))
# a mounted volume's root left as its own plays keep it: the mount points made only for the volumes about to be mounted
# here (the mount module makes a missing one itself), after what another source mounted there is unmounted - every run
# set the git mirror's root (setup-vault-pi's, 0750) to 0755, and setup-vault-pi set it back (full runs 2140 to 1217)
mp = next((t for t in mounting["tasks"] if t.get("name") == "Create mount points"), None)
names = [t.get("name") for t in mounting["tasks"]]
check("the mount points made for the volumes about to be mounted alone, after the unmount, before the mount",
      (mp is not None and str(mp.get("loop", "")).replace(" ", "") == "{{backup_remount}}",
       mp is not None and names.index("Unmount what another source has mounted there") < names.index("Create mount points")
       < names.index("Mount backup volumes")), (True, True))
# no play before the mount play's answer check reaches inside a mounted backup volume (a lookup there held for good
# by a hung client - the old MinIO symlinks' cleanup did): the mounts from the play's own list
mounts = [v["mount"] for v in vols]
before = plays[:plays.index(mounting)]
inside = [t.get("name") for p in before for t in flat(p.get("tasks")) for m in mounts
          if m + "/" in str(t.get("ansible.builtin.shell", "")) + str(t.get("ansible.builtin.command", ""))]
check("no task before the answer check reaches inside a backup volume's mount", inside, [])
# nor walks into one, or into the repos' volume, from a directory above it: a find from there descends into every mount
# under it unless it prunes it (-not -path still descends - Forgejo's UID alignment walked repos/ and data/ so)
gmounts = mounts + sorted({str((p.get("vars") or {}).get("gluster_mount")) for p in plays
                           if (p.get("vars") or {}).get("gluster_mount")})
walks = sorted({(t.get("name"), m) for p in before for t in flat(p.get("tasks")) for m in gmounts
                for text in [str(t.get("ansible.builtin.shell", "")) + str(t.get("ansible.builtin.command", ""))]
                for root in re.findall(r"\bfind\s+(/[^\s;|&)]*)", text)
                if (m + "/").startswith(root.rstrip("/") + "/") and m != root.rstrip("/")
                and not (f"-path {m} " in text and "-prune" in text)})
check("no task before the answer check finds from above a volume's mount without pruning it (repos' among them: "
      f"{'/var/lib/forgejo/repos' in gmounts})", walks, [])
# a remount a run before did not finish (its task's timeout) left its service stopped; the re-run sees the source right,
# stops nothing, starts nothing - the volumes' own services enabled here and not running are started all the same
# (keepalived's - autostart false - never)
starting = next(p for p in plays if p.get("name") == "Start the services of the remounted volumes")
own = next((t for t in mounting["tasks"] if "gluster_autostart_services" in str(t.get("ansible.builtin.set_fact", ""))), None)
left = next((t for t in starting["tasks"] if "_left_stopped" in str(t.get("ansible.builtin.set_fact", ""))), None)
start = next((t for t in starting["tasks"] if t.get("ansible.builtin.systemd")), None)
check("the volumes' own services recorded, those left stopped read, started with the rest",
      (own is not None, left is not None, "_left_stopped" in str((start or {}).get("loop"))), (True, True, True))
if own and left and start:
    autostart = render(own["ansible.builtin.set_fact"]["gluster_autostart_services"], backup_volumes=vols)
    svc = lambda st, en: {"state": st, "status": en}  # noqa: E731
    facts = {"forgejo.service": svc("stopped", "enabled"), "versitygw.service": svc("running", "enabled"),
             "nexus.service": svc("stopped", "enabled")}
    stopped = render(left["ansible.builtin.set_fact"]["_left_stopped"], gluster_autostart_services=autostart,
                     ansible_facts={"services": facts})
    check("the volumes' own services: Forgejo and the store's gateway - never Nexus (keepalived starts it)",
          sorted(autostart), ["forgejo", "versitygw"])
    check("left stopped: enabled and not running alone (Forgejo here) - not one running, not keepalived's",
          list(stopped), ["forgejo"])
    disabled = render(left["ansible.builtin.set_fact"]["_left_stopped"], gluster_autostart_services=autostart,
                      ansible_facts={"services": {"forgejo.service": svc("stopped", "disabled")}})
    check("a disabled one (stopped by intent) never started", list(disabled), [])
    check("started: those the run stopped and those left stopped, once each",
          list(render(start["loop"], gluster_services_to_start=["versitygw"], _left_stopped=["forgejo", "versitygw"])),
          ["versitygw", "forgejo"])
# the volumes Forgejo and Nexus write have their root's owner kept by Gluster (storage.owner-uid/gid): a heal or a
# remount set it back to the arbiter brick's root:root otherwise - forgejo-repos had none (a re-run after a full run
# found its root changed, 2026-10-08)
own = next((t for p in plays for t in p.get("tasks") or [] if "storage.owner-uid" in str(t)), None)
items = {(x["name"], x["id"]) for x in (own or {}).get("loop") or []}
check("the owner kept by Gluster on forgejo-repos and forgejo-data (900), nexus-data (901)",
      {("forgejo-repos", 900), ("forgejo-data", 900), ("nexus-data", 901)} <= items, True)
print("gluster-mounts: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYGM
