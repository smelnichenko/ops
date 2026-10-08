#!/bin/bash
# setup-gluster.yml's check of the backup volumes' mounts, as the playbook holds it (in the play that mounts them, its
# list the play's own), findmnt a stub: each volume mounted at its own mount point from itself passes; one not mounted,
# or mounted from another volume, fails naming it (one line matching any volume passed: two of three unmounted passed).
# Skipped in a preview: it checks what the play did.
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
chmod +x "$W/bin/findmnt"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYGM'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
plays = yaml.safe_load(open("deploy/ansible/playbooks/setup-gluster.yml"))
mounting = next(p for p in plays if p.get("name") == "Mount backup GlusterFS volumes")
vols = mounting["vars"]["backup_volumes"]
t = next((t for t in mounting["tasks"] if "findmnt" in str(t.get("ansible.builtin.shell", "")) and "NOT MOUNTED" in str(t)),
         None)
check("the play that mounts the volumes checks each one", t is not None, True)
if t:
    sh = t["ansible.builtin.shell"]
    script = render(sh if isinstance(sh, str) else sh["cmd"], backup_volumes=vols)
    env = {k: str(render(str(v), backup_volumes=vols)) for k, v in (t.get("environment") or {}).items()}
    def run(mounts):
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"],
                                    MOUNTS="\n".join(mounts), **env))
        return r.returncode, r.stdout
    own = [f"{v['mount']}=10.0.0.1:/{v['name']}" for v in vols]
    check("each mounted from itself: passes", run(own)[0], 0)
    rc, out = run(own[1:])
    check(f"{vols[0]['name']} not mounted: fails, named", (rc != 0, vols[0]["name"] in out and "NOT MOUNTED" in out),
          (True, True))
    rc, out = run([own[0].replace(f":/{vols[0]['name']}", f":/{vols[1]['name']}")] + own[1:])
    check(f"{vols[0]['name']}'s mount point serving another volume: fails, named", (rc != 0, vols[0]["name"] in out),
          (True, True))
    check("skipped in a preview (it checks what the play did)",
          [condition(t.get("when", True), ansible_check_mode=cm) for cm in (False, True)], [True, False])
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
