#!/bin/bash
# Keycloak's upgrade path (plan 122): upgrade-keycloak.yml - every Pi in the run, its decisions (a run taken forward or
# refused, one version on both Pis, never a downgrade, nothing to do, the Pi that starts first) as Ansible renders them,
# the version read against stubbed systemctl/pgrep/readlink, the dump against a stubbed pg_dump (named for the schema
# the database holds, the 5 newest kept, a failed one leaving nothing counted), and the order: the dump before anything
# stops, every Pi stopped before /opt/keycloak moves, the first Pi started and serving before the other; and the two
# refusals that keep a version move out of every other run - setup-pi-services installs only where Keycloak is missing,
# keycloak-restart.yml (setup-pi-services', setup-patroni's) refuses a Keycloak running another version than installed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_KU'
import os, subprocess, sys, tempfile, time
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
work = tempfile.mkdtemp()
play = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-keycloak.yml"))[0]
T = play["tasks"]
task = lambda name: next(t for t in T if str(t.get("name", "")).startswith(name))
reg = lambda r: next(t for t in T if t.get("register") == r)
idx = lambda t: T.index(t)

# ── the version read, systemctl / pgrep / readlink stubbed (as pi-restart-guard reads keycloak-restart's) ──────────
bin_ = os.path.join(work, "bin"); os.makedirs(bin_)
def stub(name, body):
    with open(os.path.join(bin_, name), "w") as f:
        f.write("#!/bin/bash\n" + body)
    os.chmod(os.path.join(bin_, name), 0o755)
stub("systemctl", 'echo "${KC_PID:-0}"\n')
stub("pgrep", '[ -n "${KC_CHILD:-}" ] && echo "$KC_CHILD"; exit 0\n')
stub("readlink", 'if [ "$1" = -f ]; then [ -n "${KC_LINK:-}" ] && echo "$KC_LINK"; exit 0; fi\n'
                 'case $1 in /proc/*/fd/*) p=${1#/proc/}; p=${p%%/*}; v="KC_FDS_$p"; [ -n "${!v:-}" ] && tr , "\\n" <<< "${!v}" ;; esac\n')
read_cmd = reg("_read")["ansible.builtin.shell"]["cmd"]
def read(cmd, link, pid=0, child="", **fds):
    env = dict(os.environ, PATH=bin_ + ":" + os.environ["PATH"], KC_LINK=link, KC_PID=str(pid), KC_CHILD=child,
               **{f"KC_FDS_{k[1:]}": v for k, v in fds.items()})
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout.splitlines()
jar = lambda v: f"/opt/keycloak-{v}/lib/lib/main/a.jar,/opt/keycloak-{v}/lib/quarkus-run.jar"
check("the read: installed and running (the child's jars); moved; two at once; not running; no install open yet; no link",
      [read(read_cmd, "/opt/keycloak-26.5.7", 41, "42", p42=jar("26.5.7")),
       read(read_cmd, "/opt/keycloak-26.8.2", 41, "42", p42=jar("26.5.7")),
       read(read_cmd, "/opt/keycloak-26.8.2", 41, "42", p41="/opt/keycloak-26.5.7/bin/kc.sh", p42=jar("26.8.2")),
       read(read_cmd, "/opt/keycloak-26.5.7"), read(read_cmd, "/opt/keycloak-26.5.7", 41, "42"), read(read_cmd, "")],
      [(0, ["26.5.7", "26.5.7"]), (0, ["26.8.2", "26.5.7"]), (0, ["26.8.2", "26.5.7 26.8.2"]),
       (0, ["26.5.7", "not-running"]), (0, ["26.5.7", "unknown"]), (0, ["none", "not-running"])])
check("  read again while a JVM holds no install open (unknown), not past it",
      [condition(reg("_read")["until"], _read={"rc": 0, "stdout_lines": lines})
       for lines in (["26.5.7", "unknown"], ["26.5.7", "26.5.7"], ["26.5.7", "not-running"])], [False, True, True])
SV = yaml.safe_load(open("deploy/ansible/playbooks/tasks/keycloak-serves.yml"))[0]
stub("curl", 'echo "${KC_HTTP:-000}"\n')
def serves(target, link_pid=41, http="200", **fds):
    cmd = render(SV["ansible.builtin.shell"]["cmd"], keycloak_serve_version=target)
    env = dict(os.environ, PATH=bin_ + ":" + os.environ["PATH"], KC_PID=str(link_pid), KC_CHILD="42", KC_HTTP=http,
               **{f"KC_FDS_{k[1:]}": v for k, v in fds.items()})
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env).returncode
check("the serve check (tasks/keycloak-serves.yml): the target running and answering 200 - done; another version, not "
      "answering, two versions, or down - read again",
      [serves("26.8.2", p42=jar("26.8.2")), serves("26.8.2", p42=jar("26.5.7")), serves("26.8.2", http="503", p42=jar("26.8.2")),
       serves("26.8.2", p41="/opt/keycloak-26.5.7/bin/kc.sh", p42=jar("26.8.2")), serves("26.8.2", link_pid=0)],
      [0, 1, 1, 1, 1])
check("  read again for Keycloak's database-lock wait (15 min) - the first start of a version builds and migrates",
      (SV["retries"] * SV["delay"] >= 900, SV["until"]), (True, "_keycloak_serves_target.rc == 0"))
for name in ("The first Pi runs and serves the target", "Every Pi runs and serves the target"):
    t = task(name)
    check(f"  {name}: the serve check on vars/keycloak.yml's version",
          (t.get("ansible.builtin.include_tasks"), t["vars"]["keycloak_serve_version"]), ("tasks/keycloak-serves.yml", "{{ keycloak_version }}"))

# ── the decisions, as Ansible renders them ────────────────────────────────────────────────────────────────────
check("every Pi in the run: both - on; one left out (--limit) - refused",
      [condition(task("Every Pi in the run")["ansible.builtin.assert"]["that"], ansible_play_hosts=h, groups={"pis": ["pi1", "pi2"]})
       for h in (["pi2", "pi1"], ["pi1"])], [True, False])
fw = task("A run to take forward")
def forward(pi1, pi2, target="26.8.2"):  # each (installed, running - '' when down)
    hv = {"pi1": {"inventory_hostname": "pi1", "_installed": pi1[0], "_running": pi1[1]},
          "pi2": {"inventory_hostname": "pi2", "_installed": pi2[0], "_running": pi2[1]}}
    v = {k: render(x, ansible_play_hosts=["pi1", "pi2"], hostvars=hv) for k, x in fw["vars"].items()}
    return render(fw["ansible.builtin.set_fact"]["_forward"], keycloak_version=target, hostvars=hv, **v)
check("taken forward: a Pi down with the target installed, the other on it; not when one is down on the old install, or both run",
      [forward(("26.8.2", ""), ("26.8.2", "26.8.2")), forward(("26.8.2", ""), ("26.8.2", "")),
       forward(("26.5.7", ""), ("26.5.7", "26.5.7")), forward(("26.8.2", ""), ("26.5.7", "26.5.7")),
       forward(("26.5.7", "26.5.7"), ("26.5.7", "26.5.7"))], [True, True, False, False, False])
one = task("One version on both Pis before")["ansible.builtin.assert"]["that"]
both = lambda a, b, fwd=False: condition(one, _forward=fwd, _resume=False, ansible_play_hosts=["pi1", "pi2"],
                                         hostvars={"pi1": {"_running": a}, "pi2": {"_running": b}})
check("one version on both Pis: the same - on; two - refused (unless taken forward)",
      [both("26.5.7", "26.5.7"), both("26.5.7", "26.8.2"), both("26.8.2", "", True)], [True, False, True])
two = task("One version running here")["ansible.builtin.assert"]["that"]
check("one version running here: one - on; two at once (a stale process) - refused",
      [condition(two, _running="26.5.7"), condition(two, _running="26.5.7 26.8.2")], [True, False])
down = task("Never a downgrade")["ansible.builtin.assert"]["that"]
check("never a downgrade: older or the target - on; newer - refused; down, judged by its install",
      [condition(down, _forward=False, _running=r, _installed=i, keycloak_version="26.8.2")
       for r, i in (("26.5.7", "26.5.7"), ("26.8.2", "26.8.2"), ("27.0.1", "27.0.1"), ("", "26.5.7"), ("", "27.0.1"))],
      [True, True, False, True, False])
end = task("Nothing to do")["when"]
check("nothing to do when every Pi runs AND serves the target - not when one runs another, is down, or still starting",
      [condition(end, keycloak_version="26.8.2", ansible_play_hosts=["pi1", "pi2"],
                 hostvars={"pi1": {"_running": a, "_serves": {"status": sa}}, "pi2": {"_running": b, "_serves": {"status": sb}}})
       for a, b, sa, sb in (("26.8.2", "26.8.2", 200, 200), ("26.5.7", "26.8.2", 200, 200), ("26.8.2", "", 200, -1),
                            ("26.8.2", "26.8.2", 200, -1))], [True, False, False, False])
rs = task("A clean stop to resume")["ansible.builtin.set_fact"]["_resume"]
def resume(pi1, pi2, fwd=False):
    hv = {"pi1": {"_installed": pi1[0], "_running": pi1[1]}, "pi2": {"_installed": pi2[0], "_running": pi2[1]}}
    return render(rs, _forward=fwd, ansible_play_hosts=["pi1", "pi2"], hostvars=hv)
check("a clean stop resumed: every Pi down on one install - yes; one running, mixed installs, or a run taken forward - no",
      [resume(("26.5.7", ""), ("26.5.7", "")), resume(("26.5.7", "26.5.7"), ("26.5.7", "")),
       resume(("26.5.7", ""), ("26.8.2", "")), resume(("26.8.2", ""), ("26.8.2", ""), True)], [True, False, False, False])
er = task("Every Pi running, unless")["ansible.builtin.assert"]["that"]
check("  every Pi running unless taken forward or a clean stop - a Pi down otherwise refused",
      [condition(er, _forward=f, _resume=r, _running=x) for f, r, x in ((False, False, "26.5.7"), (False, False, ""), (True, False, ""), (False, True, ""))],
      [True, False, True, True])
tw = task("The target's install whole - else")["ansible.builtin.assert"]["that"]
check("the target's install whole (kc.sh and quarkus-run.jar) - else refused before anything stops",
      [condition(tw, _target_files={"results": [{"stat": {"exists": a}}, {"stat": {"exists": b}}]}) for a, b in ((True, True), (True, False), (False, True))],
      [True, False, False])
check("  checked before the dump", idx(task("The target's install whole - else")) < idx(task("Keycloak's database dumped")), True)
first = task("The first Pi")["ansible.builtin.set_fact"]["_first"]
def pick(starting, vip):
    hv = {h: {"inventory_hostname": h, "_starting": h == starting, "_addrs": {"stdout": "x" if h == vip else ""}} for h in ("pi1", "pi2")}
    return render(first, ansible_play_hosts=["pi1", "pi2"], hostvars=hv).strip()
check("the first Pi: the one already starting (maybe migrating); else the VIP's holder; else the first in the play",
      [pick("pi2", "pi1"), pick(None, "pi2"), pick(None, None)], ["pi2", "pi2", "pi1"])

D = yaml.safe_load(open("deploy/ansible/playbooks/tasks/keycloak-dump.yml"))
dreg = lambda r: next(t for t in D if t.get("register") == r)
dtask = lambda name: next(t for t in D if str(t.get("name", "")).startswith(name))
inc = task("Keycloak's database dumped")
check("the dump included (tasks/keycloak-dump.yml), skipped on a run taken forward, named for the version both Pis ran",
      (inc.get("ansible.builtin.include_tasks"), "not _forward | bool" in str(inc.get("when", "")),
       render(inc["vars"]["keycloak_dump_running"], ansible_play_hosts=["pi1", "pi2"],
              hostvars={"pi1": {"_running": "26.5.7"}, "pi2": {"_running": "26.5.7"}})),
      ("tasks/keycloak-dump.yml", True, "26.5.7"))
# ── the dump, pg_dump stubbed ──────────────────────────────────────────────────────────────────────────────────
dump = dreg("_dump")
check("the dump: once, on the first Pi, the password on stdin (never on the command line), not logged, its failure its own",
      (dump.get("run_once"), dump.get("delegate_to"), dump.get("no_log"), dump["ansible.builtin.shell"]["stdin"],
       "PGPASSWORD=" not in dump["ansible.builtin.shell"]["cmd"], dump.get("failed_when")),
      (True, "{{ _first }}", True, "{{ keycloak_dump_password }}", True, False))
dbin = os.path.join(work, "dbin"); os.makedirs(dbin); ddir = os.path.join(work, "dumps")
with open(os.path.join(dbin, "pg_dump"), "w") as f:
    f.write('#!/bin/bash\n[ "$PGPASSWORD" = s3cret ] || exit 9\n[ -z "${PGD_FAIL:-}" ] || exit 1\necho "CREATE TABLE realm();"\n'
            '[ -n "${PGD_CUT:-}" ] || echo "-- PostgreSQL database dump complete"\n')
os.chmod(os.path.join(dbin, "pg_dump"), 0o755)
dcmd = render(dump["ansible.builtin.shell"]["cmd"], dump_dir=ddir, _schema={"stdout": "26.5.0\n"}, keycloak_dump_running="26.5.7")
def run_dump(**env):
    r = subprocess.run(["bash", "-c", dcmd], input="s3cret\n", capture_output=True, text=True,
                       env=dict(os.environ, PATH=dbin + ":" + os.environ["PATH"], **env))
    return r.returncode, sorted(os.listdir(ddir)) if os.path.isdir(ddir) else []
rc, kept = run_dump()
check("  whole: kept, named for the version running (the install a way back restores) and the schema, nothing left aside, root's alone",
      (rc, len(kept), kept[0].endswith("-26.5.7-schema-26.5.0.sql.gz"), any(k.endswith(".part") for k in kept), oct(os.stat(ddir).st_mode)[-3:]),
      (0, 1, True, False, "700"))
good = open(os.path.join(ddir, kept[0]), "rb").read()
for env, why in (({"PGD_CUT": "1"}, "cut short (no footer)"), ({"PGD_FAIL": "1"}, "pg_dump failing")):
    time.sleep(1.1)  # another second: a failed dump never overwrites a good one under the same name
    rc, after = run_dump(**env)
    check(f"  {why}: failed, nothing new counted, nothing left aside, the good dump untouched",
          (rc != 0, after == kept, open(os.path.join(ddir, kept[0]), "rb").read() == good), (True, True, True))
for x in os.listdir(ddir):
    os.remove(os.path.join(ddir, x))
made = []
for _ in range(7):
    run_dump(); made = sorted(os.listdir(ddir)); time.sleep(1.1)
names = sorted(os.listdir(ddir))
check("  the 5 newest kept - never the newest rotated away", (len(names), names == sorted(made)[-5:]), (5, True))
held = dtask("The dump taken")["ansible.builtin.assert"]["that"]
check("its check: a dump that ended 0 with the schema read holds; a failed dump, no result, or no schema - refused",
      [condition(held, _dump=d, _schema=s) for d, s in (({"rc": 0}, {"stdout": "26.5.7"}), ({"rc": 1}, {"stdout": "26.5.7"}),
                                                         ({}, {"stdout": "26.5.7"}), ({"rc": 0}, {"stdout": ""}))],
      [True, False, False, False])

# ── the order ──────────────────────────────────────────────────────────────────────────────────────────────────
stop, link = task("Keycloak stopped on every Pi"), task("The target installed")
s1, s2 = task("Started on the first Pi"), task("Then the others")
check("the order: schema read, dump and its check before anything stops; every Pi stopped before /opt/keycloak moves; "
      "the first started and serving before the others",
      (D.index(dreg("_schema")) < D.index(dump) < D.index(dtask("The dump taken")),
       idx(inc) < idx(stop) < idx(link) < idx(s1) < idx(task("The first Pi runs and serves")) < idx(s2)), (True, True))
check("  the steps that change anything skipped on a run taken forward",
      all("not _forward | bool" in str(t.get("when", "")) for t in (task("The target's tarball"), task("The target extracted"),
          inc, stop, link)), True)
check("  the symlink replaced, not nested (force: true on a link)", (link["ansible.builtin.file"]["state"], link["ansible.builtin.file"].get("force")), ("link", True))
check("  a run without every Pi failing everywhere (any_errors_fatal)", play.get("any_errors_fatal"), True)

# ── the refusals elsewhere ─────────────────────────────────────────────────────────────────────────────────────
sps = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-services.yml"))[0]["tasks"]
g = next(t for t in sps if str(t.get("name", "")).startswith("Keycloak installed where missing"))
G2 = {"pis": ["pi1", "pi2"]}
kc_ok = lambda here, peer: condition(g["ansible.builtin.assert"]["that"], _keycloak_installed={"stdout": here},
                                     _keycloak_peer_installed={"stdout": peer}, keycloak_version="26.5.7", groups=G2)
check("setup-pi-services: the same version - on; missing beside none or the same version - installed; missing beside "
      "another (a rebuilt Pi, the pin ahead), another here, or one it cannot read - refused",
      [kc_ok("26.5.7", "x"), kc_ok("missing", "missing"), kc_ok("missing", "26.5.7"), kc_ok("missing", "26.4.0"),
       kc_ok("26.8.2", "x"), kc_ok("unknown", "x")], [True, True, True, False, False, False])
fp = next(t for t in sps if str(t.get("name", "")).startswith("A fresh Forgejo only beside the same version"))
fj = lambda exists, peer: condition(fp["ansible.builtin.assert"]["that"], _forgejo_bin={"stat": {"exists": exists}},
                                    _forgejo_peer={"stdout": peer}, forgejo_version="15.0.11", groups=G2)
check("  Forgejo's sibling: installed already - on; fresh beside none or the same version - on; fresh beside another - refused",
      [fj(True, "x"), fj(False, "missing"), fj(False, "15.0.11"), fj(False, "15.0.10")], [True, True, True, False])
check("  each read of the other Pi delegated to it (it works under --limit) and only for a fresh install",
      [(t.get("delegate_to"), "missing" in str(t.get("when")) or "not _forgejo_bin" in str(t.get("when")))
       for t in sps if t.get("register") in ("_keycloak_peer_installed", "_forgejo_peer")],
      [("{{ groups['pis'] | difference([inventory_hostname]) | first }}", True)] * 2)
names_sps = [str(t.get("name", "")) for t in sps]
check("  its refusal before the tarball, the extract and the symlink",
      names_sps.index(g["name"]) < min(names_sps.index(n) for n in names_sps if n.startswith(("Download Keycloak", "Extract Keycloak", "Symlink Keycloak"))), True)
gr = next(t for t in sps if t.get("register") == "_keycloak_installed")
present = os.path.join(work, "present"); open(present, "w").close()
def installed(link):  # link None: no /opt/keycloak at all
    cmd = gr["ansible.builtin.shell"]["cmd"].replace("[ ! -e /opt/keycloak ]",
                                                    f"[ ! -e {present if link is not None else os.path.join(work, 'absent')} ]")
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                          env=dict(os.environ, PATH=bin_ + ":" + os.environ["PATH"], KC_LINK=link or "")).stdout.strip()
check("  its read: missing; the version a link names; unknown for one it cannot read",
      [installed(None), installed("/opt/keycloak-26.5.7"), installed("/srv/elsewhere")], ["missing", "26.5.7", "unknown"])
kr = yaml.safe_load(open("deploy/ansible/playbooks/tasks/keycloak-restart.yml"))
ka = next(t for t in kr if "deploy:keycloak:upgrade" in str(t.get("ansible.builtin.assert", {}).get("fail_msg", "")))
check("keycloak-restart (setup-patroni imports it too): running the installed version or not running - on; another, or two - refused",
      [condition(ka["ansible.builtin.assert"]["that"], _keycloak_install={"stdout_lines": l})
       for l in (["26.5.7", "26.5.7"], ["26.5.7", "not-running"], ["26.8.2", "26.5.7"], ["26.8.2", "26.5.7 26.8.2"])],
      [True, True, False, False])
kn = [str(t.get("name", "")) for t in kr]
check("  its refusal before any restart", kn.index(ka["name"]) < min(i for i, n in enumerate(kn) if n.startswith("Keycloak restarted where pending")), True)
# ── the way back: tasks/keycloak-restore.yml, restore-keycloak.yml, the copy's rehearsal ──────────────────────────
R = yaml.safe_load(open("deploy/ansible/playbooks/tasks/keycloak-restore.yml"))
rt = lambda name: next(t for t in R if str(t.get("name", "")).startswith(name))
rr = next(t for t in R if t.get("register") == "_restore")
dc = rt("The dump there and whole")
check("the restore: the dump checked where it lies (there, gzip, its trailer) once, before anything stops",
      (dc.get("delegate_to"), dc.get("run_once"), R.index(dc) < R.index(rt("Keycloak stopped on every Pi"))), ("{{ keycloak_restore_host }}", True, True))
def dumpcheck(path):
    cmd = render(dc["ansible.builtin.shell"]["cmd"], keycloak_restore_dump=path, keycloak_restore_host="pi1")
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True).returncode
cut_dump = os.path.join(work, "cut.sql.gz"); subprocess.run(f"echo 'CREATE TABLE realm();' | gzip > {cut_dump}", shell=True, check=True)
whole_dump = os.path.join(work, "whole.sql.gz")
subprocess.run(f"printf 'CREATE TABLE realm();\\n-- PostgreSQL database dump complete\\n' | gzip > {whole_dump}", shell=True, check=True)
check("  whole - on; missing, not gzip, or cut short (no trailer) - refused",
      [dumpcheck(whole_dump), dumpcheck(os.path.join(work, "nope.sql.gz")), dumpcheck(bad_dump if "bad_dump" in dir() else cut_dump), dumpcheck(cut_dump)],
      [0, 1, 1, 1])
check("the restore: the dump's version's install checked, then every Pi stopped, then the database, then /opt/keycloak back, "
      "the first Pi started and serving before the other",
      R.index(rt("Every Pi has the dump's version's install")) < R.index(rt("Keycloak stopped on every Pi")) < R.index(rr)
      < R.index(rt("The database restored")) < R.index(rt("/opt/keycloak back")) < R.index(rt("Started on the first Pi"))
      < R.index(rt("The first Pi runs and serves")) < R.index(rt("Then the others")), True)
check("  the database once, on the Pi holding the dump, the password on stdin, not logged, its failure its own",
      (rr.get("run_once"), rr.get("delegate_to"), rr.get("no_log"), rr["ansible.builtin.shell"]["stdin"], rr.get("failed_when")),
      (True, "{{ keycloak_restore_host }}", True, "{{ keycloak_dump_password }}", False))
check("  a restore that failed - refused, Keycloak left stopped; one that ended 0 holds",
      [condition(rt("The database restored")["ansible.builtin.assert"]["that"], _restore=d) for d in ({"rc": 0}, {"rc": 1}, {})],
      [True, False, False])
check("  the dump's version's install present - on; gone - refused before anything stops",
      [condition(rt("Every Pi has the dump's version's install")["ansible.builtin.assert"]["that"], _restore_install={"stat": st})
       for st in ({"isdir": True}, {"exists": False}, {})], [True, False, False])
# the restore's SQL against a stubbed psql (each call recorded), the dump gzip-checked first
pbin = os.path.join(work, "pbin"); os.makedirs(pbin); plog = os.path.join(work, "psql.log")
with open(os.path.join(pbin, "psql"), "w") as f:
    f.write(f'#!/bin/bash\n[ "$PGPASSWORD" = s3cret ] || exit 9\necho "$*" >> {plog}\n'
            'case "$*" in *migration_model*) echo 26.5.0 ;; *"-q"*) cat > /dev/null ;; esac\n')
os.chmod(os.path.join(pbin, "psql"), 0o755)
good_dump = os.path.join(work, "keycloak-20261127T010000Z-26.5.7-schema-26.5.0.sql.gz")
subprocess.run(f"echo 'CREATE TABLE realm();' | gzip > {good_dump}", shell=True, check=True)
bad_dump = os.path.join(work, "bad.sql.gz"); open(bad_dump, "w").write("not gzip")
def restore(dump):
    if os.path.exists(plog):
        os.remove(plog)
    cmd = render(rr["ansible.builtin.shell"]["cmd"], keycloak_restore_dump=dump, keycloak_db_user="keycloak")
    r = subprocess.run(["bash", "-c", cmd], input="s3cret\n", capture_output=True, text=True, env=dict(os.environ, PATH=pbin + ":" + os.environ["PATH"]))
    return r.returncode, open(plog).read().splitlines() if os.path.exists(plog) else []
rc, calls = restore(good_dump)
check("  its SQL: the database dropped (connections forced off), created owned by keycloak's user, the dump loaded, the schema read",
      (rc, [("DROP DATABASE IF EXISTS keycloak WITH (FORCE)" in c, 'CREATE DATABASE keycloak OWNER "keycloak"' in c, "-d keycloak -1 -q" in c,
             "migration_model" in c) for c in calls]),
      (0, [(True, False, False, False), (False, True, False, False), (False, False, True, False), (False, False, False, True)]))
check("  a dump that is no gzip, or missing: refused before the database is touched",
      [restore(bad_dump), restore(os.path.join(work, "missing.sql.gz"))], [(1, []), (1, [])])
check("  the load one transaction (a failed load leaves no half database a backup could take)", any("-d keycloak -1 -q" in c for c in calls), True)
W_ = yaml.safe_load(open("deploy/ansible/playbooks/restore-keycloak.yml"))[0]["tasks"]
wt = lambda name: next(t for t in W_ if str(t.get("name", "")).startswith(name))
pick = wt("The dump restored")
def chosen(newest, given=None):
    hv = {h: {"inventory_hostname": h, "_newest": {"stdout": p}} for h, p in newest.items()}
    of = render(pick["vars"]["_newest_of"], ansible_play_hosts=list(newest), hostvars=hv)
    extra = {} if given is None else {"keycloak_restore_dump": given[0], "keycloak_restore_host": given[1]}
    return (render(pick["ansible.builtin.set_fact"]["_dump_path"], _newest_of=of, **extra),
            render(pick["ansible.builtin.set_fact"]["_dump_host"], _newest_of=of, **extra))
A, B = "/var/backups/keycloak/keycloak-20261127T010000Z-26.5.7-schema-26.5.0.sql.gz", "/var/backups/keycloak/keycloak-20261128T010000Z-26.8.2-schema-26.8.2.sql.gz"
check("restore-keycloak: the newest dump on either Pi, or the one given; none - empty (refused below)",
      [chosen({"pi1": A, "pi2": ""}), chosen({"pi1": A, "pi2": B}), chosen({"pi1": A, "pi2": B}, ("/x/given.sql.gz", "pi1")), chosen({"pi1": "", "pi2": ""})],
      [(A, "pi1"), (B, "pi2"), ("/x/given.sql.gz", "pi1"), ("", "")])
ver = lambda p: render(wt("Its version")["ansible.builtin.set_fact"]["_dump_version"], _dump_path=p)
check("  the version a dump ran, from its name; a name not a dump's - none", [ver(A), ver(B), ver("/x/other.sql.gz")], ["26.5.7", "26.8.2", ""])
known = wt("A dump, its Pi and its version known")["ansible.builtin.assert"]["that"]
check("  refused before anything stops without a dump, its Pi among the play's, or a version",
      [condition(known, _dump_path=p, _dump_host=h, _dump_version=v, ansible_play_hosts=["pi1", "pi2"])
       for p, h, v in ((A, "pi1", "26.5.7"), ("", "pi1", "26.5.7"), (A, "pi3", "26.5.7"), (A, "pi1", ""))], [True, False, False, False])
pin = wt("The unit reverted first")["ansible.builtin.assert"]["that"]
conf = wt("Confirmed by naming the dump")["ansible.builtin.assert"]["that"]
check("  refused until the unit is reverted (the pin the dump's version), and until confirmed by the dump's file name",
      ([condition(pin, keycloak_version=k, _dump_version="26.5.7") for k in ("26.5.7", "26.8.2")],
       [condition(conf, _dump_path=A, **({} if c is None else {"confirm": c})) for c in (A.split("/")[-1], "other", None)]),
      ([True, False], [True, False, False]))
check("  both before anything stops",
      max(W_.index(wt("The unit reverted first")), W_.index(wt("Confirmed by naming"))) < W_.index(wt("Restored")), True)
check("  every Pi in its run, and it runs the restore tasks with the chosen dump",
      (condition(wt("Every Pi in the run")["ansible.builtin.assert"]["that"], ansible_play_hosts=["pi1"], groups={"pis": ["pi1", "pi2"]}),
       wt("Restored").get("ansible.builtin.include_tasks")), (False, "tasks/keycloak-restore.yml"))
C = yaml.safe_load(open("tests/ansible/copy/keycloak-way-back-check.yml"))[1]["tasks"]
phase_of = lambda t: str(t.get("when", "")).split("'")[1] if "phase ==" in str(t.get("when", "")) else None
phases = [phase_of(t) for t in C]
check("the copy's rehearsal: a phase var (never --tags, which would skip the Vagrant guard), each task in one phase, in order",
      ([p for p in phases if p] == sorted([p for p in phases if p], key=["before", "after", "verify", "cleanup"].index),
       "--tags" not in open("Taskfile.yml").read().split("test:copy:keycloak-way-back:")[1].split("\n  test:")[0]),
      (True, True))
first_chk = C[0]["ansible.builtin.assert"]["that"]
check("  a phase and a marker name required (the task's, one per run - never a lookup re-templated per use)",
      [condition(first_chk, **v) for v in ({"phase": "before", "marker": "way-back-20261127T010000Z"}, {"phase": "x", "marker": "way-back-1Z"},
                                          {"phase": "before"}, {"phase": "before", "marker": "{{ lookup('pipe','date') }}"})],
      [True, False, False, False])
ct = lambda name: next(t for t in C if str(t.get("name", "")).startswith(name))
check("  before: a newer target required, the pin serving on both Pis; verify: the pin serving again, the first marker kept and the second lost",
      ([condition(ct("Before - a newer version")["ansible.builtin.assert"]["that"], keycloak_version="26.5.7", **({} if k is None else {"keycloak_to": k}))
        for k in ("26.8.2", "26.5.7", None)],
       ct("Before - every Pi runs and serves the pin")["vars"]["keycloak_serve_version"], ct("Verify - every Pi runs and serves the pin again")["vars"]["keycloak_serve_version"],
       [condition(ct("Verify - the marker from before there")["ansible.builtin.assert"]["that"], _markers={"stdout_lines": m}) for m in (["before"], ["after", "before"], [])]),
      ([True, False, False], "{{ keycloak_version }}", "{{ keycloak_version }}", [True, False, False]))
task_cmd = open("Taskfile.yml").read().split("  test:copy:keycloak-way-back:")[1].split("\n\n")[0]
seq = [l.strip() for l in task_cmd.splitlines() if l.strip().startswith("pb ")]
check("  the task: before, production's upgrade-keycloak.yml to the target, after, production's restore-keycloak.yml with the "
      "upgrade's dump confirmed, verify - each production playbook behind the Vagrant guard, secrets kept out, cleanup always",
      ([("phase=" + l.split("phase=")[1].split()[0]) if "phase=" in l else l.split()[2].split("/")[-1] for l in seq],
       all("vagrant-only-play.yml" in l for l in seq if "playbooks/" in l), "env -i" in task_cmd,
       "trap 'pb \"$C\" -e phase=cleanup" in task_cmd, "keycloak-way-back-confirm" in task_cmd),
      (["phase=before", "upgrade-keycloak.yml", "phase=after", "restore-keycloak.yml", "phase=verify"], True, True, True, True))
print("keycloak-upgrade: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_KU
