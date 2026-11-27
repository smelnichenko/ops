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
for reg_name in ("_first_up", "_up"):
    t = reg(reg_name)
    check(f"  the serve check ({reg_name}) runs the same read, its bash valid when rendered",
          (t["vars"]["_read_script"] == read_cmd,
           subprocess.run(["bash", "-n", "-c", render(t["ansible.builtin.shell"]["cmd"], _read_script=read_cmd, keycloak_version="26.8.2")]).returncode),
          (True, 0))

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
both = lambda a, b, fwd=False: condition(one, _forward=fwd, ansible_play_hosts=["pi1", "pi2"],
                                         hostvars={"pi1": {"_running": a}, "pi2": {"_running": b}})
check("one version on both Pis: the same - on; two - refused (unless taken forward)",
      [both("26.5.7", "26.5.7"), both("26.5.7", "26.8.2"), both("26.8.2", "", True)], [True, False, True])
two = task("One version running here")["ansible.builtin.assert"]["that"]
check("one version running here: one - on; two at once (a stale process) - refused",
      [condition(two, _running="26.5.7"), condition(two, _running="26.5.7 26.8.2")], [True, False])
down = task("Never a downgrade")["ansible.builtin.assert"]["that"]
check("never a downgrade: older or the target - on; newer - refused",
      [condition(down, _forward=False, _running=r, keycloak_version="26.8.2") for r in ("26.5.7", "26.8.2", "27.0.1")], [True, True, False])
end = task("Nothing to do")["when"]
check("nothing to do when every Pi runs the target - not when one runs another or is down",
      [condition(end, keycloak_version="26.8.2", ansible_play_hosts=["pi1", "pi2"], hostvars={"pi1": {"_running": a}, "pi2": {"_running": b}})
       for a, b in (("26.8.2", "26.8.2"), ("26.5.7", "26.8.2"), ("26.8.2", ""))], [True, False, False])
first = task("The first Pi")["ansible.builtin.set_fact"]["_first"]
def pick(starting, vip):
    hv = {h: {"inventory_hostname": h, "_starting": h == starting, "_addrs": {"stdout": "x" if h == vip else ""}} for h in ("pi1", "pi2")}
    return render(first, ansible_play_hosts=["pi1", "pi2"], hostvars=hv).strip()
check("the first Pi: the one already starting (maybe migrating); else the VIP's holder; else the first in the play",
      [pick("pi2", "pi1"), pick(None, "pi2"), pick(None, None)], ["pi2", "pi2", "pi1"])

# ── the dump, pg_dump stubbed ──────────────────────────────────────────────────────────────────────────────────
dump = reg("_dump")
check("the dump: once, on the first Pi, the password on stdin (never on the command line), not logged, its failure its own",
      (dump.get("run_once"), dump.get("delegate_to"), dump.get("no_log"), dump["ansible.builtin.shell"]["stdin"],
       "PGPASSWORD=" not in dump["ansible.builtin.shell"]["cmd"], dump.get("failed_when")),
      (True, "{{ _first }}", True, "{{ keycloak_dump_password }}", True, False))
dbin = os.path.join(work, "dbin"); os.makedirs(dbin); ddir = os.path.join(work, "dumps")
with open(os.path.join(dbin, "pg_dump"), "w") as f:
    f.write('#!/bin/bash\n[ "$PGPASSWORD" = s3cret ] || exit 9\n[ -z "${PGD_FAIL:-}" ] || exit 1\necho "CREATE TABLE realm();"\n'
            '[ -n "${PGD_CUT:-}" ] || echo "-- PostgreSQL database dump complete"\n')
os.chmod(os.path.join(dbin, "pg_dump"), 0o755)
dcmd = render(dump["ansible.builtin.shell"]["cmd"], dump_dir=ddir, _schema={"stdout": "26.5.7\n"})
def run_dump(**env):
    r = subprocess.run(["bash", "-c", dcmd], input="s3cret\n", capture_output=True, text=True,
                       env=dict(os.environ, PATH=dbin + ":" + os.environ["PATH"], **env))
    return r.returncode, sorted(os.listdir(ddir)) if os.path.isdir(ddir) else []
rc, kept = run_dump()
check("  whole: kept, named for the schema the database holds, nothing left aside, the directory root's alone",
      (rc, len(kept), kept[0].endswith("-schema-26.5.7.sql.gz"), any(k.endswith(".part") for k in kept), oct(os.stat(ddir).st_mode)[-3:]),
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
held = task("The dump taken")["ansible.builtin.assert"]["that"]
check("its check: a dump that ended 0 with the schema read holds; a failed dump, no result, or no schema - refused",
      [condition(held, _dump=d, _schema=s) for d, s in (({"rc": 0}, {"stdout": "26.5.7"}), ({"rc": 1}, {"stdout": "26.5.7"}),
                                                         ({}, {"stdout": "26.5.7"}), ({"rc": 0}, {"stdout": ""}))],
      [True, False, False, False])

# ── the order ──────────────────────────────────────────────────────────────────────────────────────────────────
stop, link = task("Keycloak stopped on every Pi"), task("The target installed")
s1, s2 = task("Started on the first Pi"), task("Then the others")
check("the order: schema read, dump and its check before anything stops; every Pi stopped before /opt/keycloak moves; "
      "the first started and serving before the others",
      (idx(reg("_schema")) < idx(dump) < idx(task("The dump taken")) < idx(stop) < idx(link) < idx(s1) < idx(reg("_first_up")) < idx(s2)),
      True)
check("  the steps that change anything skipped on a run taken forward",
      all("not _forward | bool" in str(t.get("when", "")) for t in (task("The target's tarball"), task("The target extracted"),
          reg("_schema"), dump, stop, link)), True)
check("  the symlink replaced, not nested (force: true on a link)", (link["ansible.builtin.file"]["state"], link["ansible.builtin.file"].get("force")), ("link", True))
check("  the first Pi's migration given Keycloak's database-lock wait (15 min)", reg("_first_up")["retries"] * reg("_first_up")["delay"] >= 900, True)
check("  a run without every Pi failing everywhere (any_errors_fatal)", play.get("any_errors_fatal"), True)

# ── the refusals elsewhere ─────────────────────────────────────────────────────────────────────────────────────
sps = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-services.yml"))[0]["tasks"]
g = next(t for t in sps if str(t.get("name", "")).startswith("Keycloak installed where missing"))
check("setup-pi-services: installed where missing or the same version - on; another, or one it cannot read - refused",
      [condition(g["ansible.builtin.assert"]["that"], _keycloak_installed={"stdout": s}, keycloak_version="26.5.7")
       for s in ("missing", "26.5.7", "26.8.2", "unknown")], [True, True, False, False])
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
print("keycloak-upgrade: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_KU
