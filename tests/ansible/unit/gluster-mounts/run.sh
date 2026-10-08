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
echo "  File: \"${@: -1}\""
STUB
chmod +x "$W/bin/findmnt" "$W/bin/stat"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYGM'
import os, subprocess, sys
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
