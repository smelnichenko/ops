#!/bin/bash
# The Pis' restarts never take the last serving copy of a service down (setup-pi-services' Forgejo and HAProxy
# handlers, its Keycloak restarts where pending, tasks/versitygw.yml's restart loop): throttle and a loop run the second
# Pi even after the first
# one's restart failed. Each command as the playbook holds it, run with curl answering for the hosts set up, systemctl
# and sleep stubbed: serving here and not on the other Pi - refused, nothing restarted; serving on both - restarted;
# serving on neither (a first install, a service down already) - restarted. versitygw's restart waits for its S3 API
# (rclone stubbed), not /health alone, and restarts the Pi holding the VIP last.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, subprocess, sys, tempfile
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))
work = tempfile.mkdtemp()
stubs = os.path.join(work, "bin"); os.makedirs(stubs)
def stub(name, body):
    with open(os.path.join(stubs, name), "w") as f:
        f.write("#!/bin/bash\n" + body)
    os.chmod(os.path.join(stubs, name), 0o755)
# curl: success for a URL whose host is in $UP, or this host's own address once systemctl restarted the service
stub("curl", 'for a in "$@"; do case $a in http*) u=$a;; esac; done\n'
             'h=${u#*://}; h=${h%%[:/]*}\n'
             'case $h in 127.0.0.1|localhost) [ -e "$WORK/restarted" ] && exit 0;; esac\n'
             'for x in $UP; do [ "$x" = "$h" ] && exit 0; done\nexit 22\n')
stub("systemctl", 'echo "$*" >> "$WORK/calls"; case $1 in restart) touch "$WORK/restarted";; esac; exit 0\n')
stub("sleep", "exit 0\n")
# each restart under the lock (files/pi-restart-locked.sh, the helper itself): its consul a fake holding it at once
stub("fake-consul", 'while [ "$#" -gt 0 ] && [ "$1" != pi-restart ]; do shift; done; shift; "$@"; [ "$?" = 0 ] || exit 2\n')
HELPER = os.path.abspath("deploy/ansible/playbooks/files/pi-restart-locked.sh")
# pg_isready (PgBouncer, 127.0.0.1 only): answers once restarted, unless $PGB_DOWN
stub("pg_isready", '[ -z "${PGB_DOWN:-}" ] && [ -e "$WORK/restarted" ]\n')
# rclone (versitygw's S3 check): S3 answers once restarted, unless $S3_DOWN
stub("rclone", 'echo "rclone $*" >> "$WORK/calls"; [ -z "${S3_DOWN:-}" ] && [ -e "$WORK/restarted" ]\n')
open(os.path.join(work, "vgw.env"), "w").write("ROOT_ACCESS_KEY=k\nROOT_SECRET_KEY=s\n")
pb = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-services.yml"))
handlers = {h["name"]: h["ansible.builtin.shell"] for h in pb[0]["handlers"] if "ansible.builtin.shell" in h}
vgw = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/tasks/versitygw.yml"))
           if t.get("name", "").startswith("Restart versitygw"))["ansible.builtin.shell"]
cmds = {n: handlers[n] for n in ("Restart Forgejo", "Restart HAProxy")}
# Keycloak's: the restart where pending (both tasks run the one script), its unit naming no secrets file here
# (tasks/keycloak-restart.yml - setup-pi-services and setup-patroni import it), each restart one Pi at a time
kr = yaml.safe_load(open("deploy/ansible/playbooks/tasks/keycloak-restart.yml"))
kc = next(t for t in kr if t.get("name") == "Keycloak restarted where pending - the Pi without the VIP")
check("Keycloak's three restarts one Pi at a time (throttle)",
      [t.get("throttle") for t in kr if str(t.get("name", "")).startswith("Keycloak restarted where pending")], [1, 1, 1])
unit = os.path.join(work, "keycloak.service")
open(unit, "w").write("[Service]\n")
cmds["Restart Keycloak"] = kc["ansible.builtin.shell"]["cmd"].replace("/etc/systemd/system/keycloak.service", unit)
cmds["Restart versitygw (loop)"] = vgw.replace("/etc/versitygw/env", os.path.join(work, "vgw.env"))
SUBST = {"{{ peer_ip }}": "10.0.0.2", "{{ _peer }}": "10.0.0.2", "{{ inventory_hostname }}": "pi1", "{{ item }}": "pi1",
         "{{ vgw_port }}": "9000"}
def run(cmd, up, **env_extra):
    for k, v in SUBST.items():
        cmd = cmd.replace(k, v)
    assert "{{" not in cmd, cmd
    for f in ("restarted", "calls"):
        if os.path.exists(os.path.join(work, f)):
            os.remove(os.path.join(work, f))
    if "127.0.0.1" in up:
        open(os.path.join(work, "restarted"), "w").close()  # serving here before the restart
    cmd = cmd.replace("/usr/local/bin/pi-restart-locked", HELPER)
    env = dict(os.environ, PATH=stubs + ":" + os.environ["PATH"], WORK=work, UP=" ".join(up),
               PI_RESTART_CONSUL=os.path.join(stubs, "fake-consul"), TMPDIR=work, **env_extra)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env)
    calls = open(os.path.join(work, "calls")).read() if os.path.exists(os.path.join(work, "calls")) else ""
    return r.returncode, any(c.startswith("restart ") for c in calls.splitlines()), r.stderr
for name, cmd in cmds.items():
    rc, restarted, err = run(cmd, ["127.0.0.1", "localhost"])
    check(f"{name}: serving here, not on the other Pi - refused, nothing restarted",
          (rc != 0, restarted, "REFUSED" in err), (True, False, True))
    rc, restarted, _ = run(cmd, ["127.0.0.1", "localhost", "10.0.0.2"])
    check(f"{name}: serving on both - restarted", (rc, restarted), (0, True))
    rc, restarted, _ = run(cmd, [])
    check(f"{name}: serving on neither (a first install) - restarted", (rc, restarted), (0, True))
# versitygw: /health answers before its S3 API serves - the restart waits for a bucket listing, and the Pi holding the
# VIP restarts last (its restart moves the VIP once, to a gateway restarted already)
rc, restarted, err = run(cmds["Restart versitygw (loop)"], ["127.0.0.1", "localhost", "10.0.0.2"], S3_DOWN="1")
check("versitygw: healthy but S3 not serving after its restart - failed", (rc != 0, restarted, "S3" in err),
      (True, True, True))
check("  S3 asked of this gateway with its root key", "rclone lsd vgw:" in open(os.path.join(work, "calls")).read(), True)
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
loop = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/tasks/versitygw.yml"))
            if t.get("name", "").startswith("Restart versitygw"))["loop"]
def order(vip, restart):
    hv = {h: {"inventory_hostname": h, "_vgw_restart": h in restart, "_vgw_vip_here": h == vip} for h in ("pi1", "pi2")}
    return render(loop, ansible_play_hosts=["pi1", "pi2"], hostvars=hv)
check("versitygw: the Pi holding the VIP restarts last", [order("pi1", {"pi1", "pi2"}), order("pi2", {"pi1", "pi2"}),
      order("pi1", {"pi1"})], [["pi2", "pi1"], ["pi1", "pi2"], ["pi1"]])
vipt = next((t for t in yaml.safe_load(open("deploy/ansible/playbooks/tasks/versitygw.yml"))
             if "keepalived_vip" in str(t.get("ansible.builtin.command", ""))), {})
check("  each Pi reads whether it holds the VIP, in a preview too", (vipt.get("check_mode"), vipt.get("register")),
      (False, "_vgw_vip"))
# PgBouncer (setup-pgbouncer.yml's handler): each Pi's apps reach their database through their own (127.0.0.1) - one Pi
# at a time, each answering again before the next, and a failed restart stops the play there (no peer to read: its
# PgBouncer listens on the Pi alone)
pgb = next(h for h in yaml.safe_load(open("deploy/ansible/playbooks/setup-pgbouncer.yml"))[0]["handlers"]
           if h.get("name") == "Restart pgbouncer")
check("PgBouncer: one Pi at a time, a failed restart ends the play",
      (pgb.get("throttle"), pgb.get("any_errors_fatal")), (1, True))
pcmd = pgb.get("ansible.builtin.shell", "").replace("{{ pgbouncer_listen_port }}", "6432")
rc, restarted, _ = run(pcmd, [])
check("PgBouncer: restarted, answering again - done", (rc, restarted), (0, True))
rc, restarted, err = run(pcmd, [], PGB_DOWN="1")
check("PgBouncer: not answering after its restart - failed, said", (rc != 0, restarted, "not serving" in err),
      (True, True, True))
# Keycloak's version: the one it runs (the install its processes hold open) against the one /opt/keycloak names - a new
# version moved only the symlink, the file stamp read current and the old version ran on until a reboot. The read as
# the playbook holds it, systemctl / pgrep / readlink stubbed: the main process and its child (java) holding jars open
kst = os.path.join(work, "kcbin"); os.makedirs(kst)
def kstub(name, body):
    with open(os.path.join(kst, name), "w") as f:
        f.write("#!/bin/bash\n" + body)
    os.chmod(os.path.join(kst, name), 0o755)
kstub("systemctl", 'echo "${KC_PID:-0}"\n')
kstub("pgrep", '[ -n "${KC_CHILD:-}" ] && echo "$KC_CHILD"; exit 0\n')
kstub("readlink", 'case $1 in /opt/keycloak) echo "$KC_LINK" ;;\n'
                  '  /proc/*/fd/*) p=${1#/proc/}; p=${p%%/*}; v="KC_FDS_$p"; [ -n "${!v:-}" ] && tr , "\\n" <<< "${!v}" ;; esac\n')
ktasks = yaml.safe_load(open("deploy/ansible/playbooks/tasks/keycloak-restart.yml"))
kread = next(t for t in ktasks if t.get("register") == "_keycloak_install")
def kc(link, pid=0, child="", **fds):
    env = dict(os.environ, PATH=kst + ":" + os.environ["PATH"], KC_LINK=link, KC_PID=str(pid), KC_CHILD=child,
               **{f"KC_FDS_{k[1:]}": v for k, v in fds.items()})
    r = subprocess.run(["bash", "-c", kread["ansible.builtin.shell"]["cmd"]], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout.split("\n")[:2]
jar = lambda v: f"/opt/keycloak-{v}/lib/lib/main/a.jar,/opt/keycloak-{v}/lib/quarkus-run.jar"
check("Keycloak's version read: the one installed and the one its child (java) holds open; moved; two (stale); none",
      [kc("/opt/keycloak-26.5.7", 41, "42", p42=jar("26.5.7")),
       kc("/opt/keycloak-26.8.2", 41, "42", p42=jar("26.5.7")),
       kc("/opt/keycloak-26.8.2", 41, "42", p41="/opt/keycloak-26.5.7/bin/kc.sh", p42=jar("26.8.2"))],
      [(0, ["26.5.7", "26.5.7"]), (0, ["26.8.2", "26.5.7"]), (0, ["26.8.2", "26.5.7 26.8.2"])])
check("  not running: said so; running and holding no install open: empty (read again, then refused)",
      [kc("/opt/keycloak-26.5.7"), kc("/opt/keycloak-26.5.7", 41, "42")], [(0, ["26.5.7", "not-running"]), (0, ["26.5.7", ""])])
from templar import condition, render, as_loaded  # noqa: E402
kdue = next(t for t in ktasks if "_keycloak_restart_due" in (t.get("ansible.builtin.set_fact") or {}))["ansible.builtin.set_fact"]["_keycloak_restart_due"]
def due(pending, installed, running, check_mode=False):
    return render(kdue, ansible_check_mode=check_mode, _restart_pending={"stdout_lines": [pending, "h"]},
                  _keycloak_install={"stdout_lines": [installed, running]})
check("Keycloak's restart due: a file changed; another version running (moved, or two); not when current and the same,"
      " or not running, or a preview",
      [due("pending", "26.5.7", "26.5.7"), due("current", "26.8.2", "26.5.7"), due("current", "26.8.2", "26.5.7 26.8.2"),
       due("current", "26.5.7", "26.5.7"), due("current", "26.8.2", "not-running"), due("pending", "26.8.2", "26.5.7", True)],
      [True, True, True, False, False, False])
check("  each of the three restarts runs on it (not on the file stamp alone)",
      [("_keycloak_restart_due | bool" in t.get("when", [])) and not any("_restart_pending" in str(w) for w in t.get("when", []))
       for t in ktasks if str(t.get("name", "")).startswith("Keycloak restarted where pending")], [True, True, True])
kruns = next(t for t in ktasks if t.get("register") == "_keycloak_runs")
runs = lambda lines: condition(kruns["failed_when"], _keycloak_runs={"rc": 0, "stdout_lines": lines})
check("Keycloak after the restarts: the version installed running - on; the old one, two, or none - refused",
      [runs(["26.8.2", "26.8.2"]), runs(["26.8.2", "26.5.7"]), runs(["26.8.2", "26.5.7 26.8.2"]), runs(["26.8.2", "not-running"])],
      [False, True, True, True])
check("  the read before and the check after are one script", kruns["ansible.builtin.shell"]["cmd"] == kread["ansible.builtin.shell"]["cmd"], True)
# Keycloak's dump before a new version (plan 122 part 3): once, on the play's first Pi, when any Pi's version moves -
# never for a file change alone - checked before it counts, the last 3 kept; a failed dump refuses before any restart
kmoves = next(t for t in ktasks if "_keycloak_version_moves" in (t.get("ansible.builtin.set_fact") or {}))["ansible.builtin.set_fact"]["_keycloak_version_moves"]
moves = lambda installed, running, cm=False: render(kmoves, ansible_check_mode=cm, _keycloak_install={"stdout_lines": [installed, running]})
check("Keycloak's version moves: another running (moved, or two) - yes; the same, not running, a preview - no",
      [moves("26.8.2", "26.5.7"), moves("26.8.2", "26.5.7 26.8.2"), moves("26.5.7", "26.5.7"), moves("26.8.2", "not-running"),
       moves("26.8.2", "26.5.7", True)], [True, True, False, False, False])
kdump = next(t for t in ktasks if t.get("register") == "_keycloak_dump")
dumps = lambda a, b: condition(kdump["when"], ansible_play_hosts=["pi1", "pi2"],
                               hostvars={"pi1": {"_keycloak_version_moves": a}, "pi2": {"_keycloak_version_moves": b}})
check("  the dump when either Pi's version moves, not when neither does (a file change alone)",
      [dumps(False, True), dumps(True, False), dumps(True, True), dumps(False, False)], [True, True, True, False])
check("  once, the password on stdin (never on the command line), not logged; through HAProxy (the primary), checked",
      (kdump.get("run_once"), kdump.get("no_log"), kdump["ansible.builtin.shell"]["stdin"], "PGPASSWORD=" not in kdump["ansible.builtin.shell"]["cmd"],
       "pg_dump -w -h 127.0.0.1 -p 5000 -U postgres keycloak" in kdump["ansible.builtin.shell"]["cmd"]),
      (True, True, "{{ postgres_admin_password }}", True, True))
names = [str(t.get("name", "")) for t in ktasks]
first_restart = min(i for i, n in enumerate(names) if n.startswith("Keycloak restarted where pending"))
kassert = next(t for t in ktasks if "ansible.builtin.assert" in t and "_keycloak_dump" in str(t["ansible.builtin.assert"]))
check("  the dump and its check before the first restart",
      (ktasks.index(kdump) < first_restart, ktasks.index(kassert) < first_restart, ktasks.index(kdump) < ktasks.index(kassert)),
      (True, True, True))
held = lambda dump: condition(" and ".join(f"({x})" for x in kassert["ansible.builtin.assert"]["that"]) if isinstance(kassert["ansible.builtin.assert"]["that"], list)
                              else kassert["ansible.builtin.assert"]["that"], _keycloak_dump=dump)
check("  its check: a dump that ended 0 holds; failed, or no result - refused", [held({"rc": 0}), held({"rc": 1}), held({})], [True, False, False])
# the dump itself, pg_dump stubbed: a whole dump kept under its running version's name; a cut one, or pg_dump failing - none
dw = os.path.join(work, "kcdump"); os.makedirs(os.path.join(dw, "bin")); bdir = os.path.join(dw, "backups")
with open(os.path.join(dw, "bin", "pg_dump"), "w") as f:
    f.write('#!/bin/bash\n[ "$PGPASSWORD" = s3cret ] || exit 9\n[ -z "${PGD_FAIL:-}" ] || exit 1\necho "CREATE TABLE realm();"\n'
            '[ -n "${PGD_CUT:-}" ] || echo "-- PostgreSQL database dump complete"\n')
os.chmod(os.path.join(dw, "bin", "pg_dump"), 0o755)
dcmd = render(kdump["ansible.builtin.shell"]["cmd"], _keycloak_install={"stdout_lines": ["26.8.2", "26.5.7"]}).replace("/var/backups/keycloak", bdir)
def dump(**env):
    r = subprocess.run(["bash", "-c", dcmd], input="s3cret\n", capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(dw, "bin") + ":" + os.environ["PATH"], **env))
    return r.returncode, sorted(os.listdir(bdir)) if os.path.isdir(bdir) else []
rc, kept = dump()
check("  the dump: whole, kept under the version it ran (26.5.7), nothing left aside",
      (rc, len(kept), kept[0].startswith("keycloak-") and kept[0].endswith("-26.5.7.sql.gz"), any(k.endswith(".part") for k in kept)),
      (0, 1, True, False))
for env, why in (({"PGD_CUT": "1"}, "cut short (no footer)"), ({"PGD_FAIL": "1"}, "pg_dump failing")):
    before = sorted(x for x in os.listdir(bdir) if x.endswith(".sql.gz"))
    rc, kept = dump(**env)
    check(f"  a dump {why}: failed, no new dump counted", (rc != 0, sorted(x for x in kept if x.endswith(".sql.gz")) == before), (True, True))
for x in os.listdir(bdir):
    os.remove(os.path.join(bdir, x))
import time as _t  # noqa: E402
for _ in range(5):
    dump(); _t.sleep(1.1)
check("  the last 3 kept", len([x for x in os.listdir(bdir) if x.endswith(".sql.gz")]), 3)
print("pi-restart-guard: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
