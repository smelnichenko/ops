#!/bin/bash
# The copy's Gluster as production's Pis have it before step 00 (tests/ansible/upgrade/production-state.yml): the
# copy's build runs today's setup-gluster.yml, so step 00 changed nothing there - the fstab rewrite, the boot unit and
# four live `gluster volume set` production will make never ran in a full run. Before step 00 the copy is put back to
# production's: the glusterfs fstab lines without the boot unit's ordering, no gluster-volumes-ready, forgejo-repos'
# and backup-git-mirror's owner options unset, the mirror's root root:root 0755 (read 2026-10-08) - each derived from
# what setup-gluster writes; only for a run from step 00 (a later run's copy is production after it).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import actions  # noqa: E402
from templar import condition, render  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


ps = yaml.safe_load(open("tests/ansible/upgrade/production-state.yml"))
play = next((p for p in ps if "Gluster" in str(p.get("name"))), {})
tasks = play.get("tasks") or []
check("a play of the Pis puts the copy's Gluster back to production's", (bool(play), play.get("hosts")),
      (True, "pis"))
guard = [i for i, t in enumerate(tasks) if "vagrant-only" in str(t.get("ansible.builtin.import_tasks", ""))]
ends = [i for i, t in enumerate(tasks) if t.get("ansible.builtin.meta") == "end_play"]
step00 = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps"))[0]
check("guarded first, then only for a run from step 00",
      (guard[:1], ends[:1], [condition(tasks[ends[0]].get("when", "false"), **({"upgrade_from": f} if f else {}))
                             for f in (None, step00, "01-argocd-root-retry")] if ends else None),
      ([0], [1], [False, False, True]))
sg = yaml.safe_load(open("deploy/ansible/playbooks/setup-gluster.yml"))
every = [t for p in sg for t in p.get("tasks") or []]
mount_play = next(p for p in sg if p.get("name") == "Mount GlusterFS volume")
options = str(mount_play["vars"]["gluster_mount_options"]).strip()
ordering = re.search(r",(x-systemd\.after=[^,\s]+)", options)
line = f"pi2:/forgejo-repos /var/lib/forgejo/repos glusterfs {render(options, inventory_hostname='pi1', pi1_ip='1', pi2_ip='2')} 0 0"
fstab = next((t for t in tasks for m, v in actions(t) if m.endswith("replace") and v.get("path") == "/etc/fstab"), None)
done = re.sub(fstab["ansible.builtin.replace"]["regexp"], fstab["ansible.builtin.replace"].get("replace", ""), line) \
    if fstab else line
check("fstab: setup-gluster's glusterfs line without its boot ordering, nothing else changed",
      (bool(ordering), done == line.replace("," + ordering[1], "") if ordering else None), (True, True))
unit_files = sorted(v["dest"] for t in every for m, v in actions(t) if isinstance(v, dict)
                    and "gluster-volumes-ready" in str(v.get("dest", "")))
gone = sorted(p for t in tasks for m, v in actions(t) if isinstance(v, dict) and v.get("state") == "absent"
              for p in (t.get("loop") if v.get("path") == "{{ item }}" else [v.get("path")]))
off = [v for t in tasks for m, v in actions(t) if isinstance(v, dict) and v.get("name") == "gluster-volumes-ready"]
check("the boot unit gone: disabled, its unit and script removed (as setup-gluster writes them)",
      (bool(unit_files), gone == unit_files, [o.get("enabled") for o in off]), (True, True, [False]))
loop = next(t for t in every if "storage.owner-uid" in str(t.get("ansible.builtin.shell", "")))["loop"]
owned = {i["name"] for i in loop}
resets = sorted(re.findall(r"gluster volume reset (\S+) (storage\.owner-[ug]id)", str(tasks)))
check("forgejo-repos' and backup-git-mirror's owner options unset (setup-gluster sets them; production has none)",
      (resets, {"forgejo-repos", "backup-git-mirror"} <= owned),
      ([("backup-git-mirror", "storage.owner-gid"), ("backup-git-mirror", "storage.owner-uid"),
        ("forgejo-repos", "storage.owner-gid"), ("forgejo-repos", "storage.owner-uid")], True))
mirror = next(v["mount"] for p in sg for v in (p.get("vars") or {}).get("backup_volumes", []) or []
              if isinstance(v, dict) and v.get("name") == "backup-git-mirror")
root = [v for t in tasks for m, v in actions(t) if isinstance(v, dict) and v.get("path") == mirror
        and v.get("state") == "directory"]
check("the mirror's root root:root 0755 (production's, read 2026-10-08)",
      [(r.get("owner"), r.get("group"), str(r.get("mode"))) for r in root], [("root", "root", "0755")])
reload_ = [v for t in tasks for m, v in actions(t) if isinstance(v, dict) and v.get("daemon_reload") is True]
check("systemd reads the fstab and units as production's", len(reload_) >= 1, True)
# step 00's preview on that state (production's): check mode writes no unit, so systemd finds none to enable (full run
# 14) - enabled in a preview only when its unit is there already
sg = [t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-gluster.yml")) for t in p.get("tasks") or []]
unit = next(t for t in sg if str((t.get("ansible.builtin.copy") or {}).get("dest", "")).endswith(
    "/gluster-volumes-ready.service"))
enable = next(t for t in sg if (t.get("ansible.builtin.systemd_service") or {}).get("name") == "gluster-volumes-ready")
reg = unit.get("register", "_none")
w = enable.get("when", "true")
check("setup-gluster's preview enables the boot unit only when it is there (new: skipped; applied, or there: enabled)",
      [condition(w, ansible_check_mode=cm, **{reg: {"changed": ch}}) for cm, ch in
       ((True, True), (True, False), (False, True), (False, False))], [False, True, True, True])
print("production-state-gluster: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
