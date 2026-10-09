#!/bin/bash
# Keycloak's database URL, wherever a playbook writes it: the driver told to take any server (targetServerType=any).
# PgBouncer hands every client the startup parameters of its pool's first server connection and never reads them
# again; one that landed on the replica (HAProxy's servers start up, before their first check) reads in_hot_standby=on
# for good, and Keycloak's default, targetServerType=primary, refused every connection until PgBouncer restarted - the
# Pis' reboot left Keycloak down (Vagrant full run, 2026-10-08). HAProxy's /primary check is what picks the primary.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import re
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
from templar import condition  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
def strings(v):
    if isinstance(v, dict):
        for x in v.values():
            yield from strings(x)
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
    elif isinstance(v, str):
        yield v
# every URL a task writes into Keycloak's unit (a reader - a grep of the unit - carries no Environment=)
urls = {}
for f in files("deploy/ansible"):
    for t in tasks(load(f)):
        for _, value in actions(t):
            for s in strings(value):
                for u in re.findall(r"Environment=KC_DB_URL=([^\n]+)", s):
                    urls.setdefault(f.split("/")[-1], []).append(u)
check("the writers found: the unit's install and Patroni's port switch",
      sorted(urls), ["setup-patroni.yml", "setup-pi-services.yml"])
for f, found in sorted(urls.items()):
    for u in found:
        q = u.split("?", 1)[1] if "?" in u else ""
        check(f"{f}: {u} - the driver takes any server, no other server type",
              re.findall(r"(?:^|&)targetServerType=([^&\"']*)", q), ["any"])
# the copy given production's whole unit (tests/ansible/upgrade/production-state.yml), as read on both Pis
# 2026-10-08: its URL without a server type, its passwords inline, no EnvironmentFile, no /etc/keycloak, no restart
# stamp - its masked text (each password's value ***MASKED***) md5 80d478b8... on both; step 00 moves it. A copy
# given the URL alone ran step 00 green on a unit production does not have (the secrets file it needs was not there)
import hashlib  # noqa: E402
PROD_MASKED_MD5 = "80d478b881e8f4a768f6b58200eacaae"
ps = list(tasks(load("tests/ansible/upgrade/production-state.yml")))
unit = next((v.get("content") for t in ps for m, v in actions(t) if isinstance(v, dict)
             and v.get("dest") == "/etc/systemd/system/keycloak.service"), None)
masked = re.sub(r"(?m)^(Environment=KC_[A-Z_]*PASSWORD=).*$", r"\1***MASKED***", unit or "")
check("the copy's Keycloak unit is production's, masked md5 as read on both Pis",
      hashlib.md5(masked.encode()).hexdigest(), PROD_MASKED_MD5)
gone = sorted(str(x) for t in ps for m, v in actions(t) if isinstance(v, dict) and v.get("state") == "absent"
              for x in (t.get("loop") if v.get("path") == "{{ item }}" else [v.get("path")]))
check("the copy without /etc/keycloak and Keycloak's restart stamp, as production",
      gone, ["/etc/keycloak", "/var/lib/config-loaded/keycloak.sha256"])
# and systemd reads it so (daemon-reload, no restart): kept in memory, the playbook's unit named the removed file - a
# crash restart before step 00 failed "Failed to load environment files"
reload_ = [i for i, t in enumerate(ps) if (t.get("ansible.builtin.systemd") or t.get("ansible.builtin.systemd_service")
                                           or {}).get("daemon_reload") is True]
removal = max((i for i, t in enumerate(ps) if "/etc/keycloak" in str((t.get("ansible.builtin.file") or {}).get("path", ""))
               + str(t.get("loop", ""))), default=None)
check("the copy's systemd reloads production's unit after it and the removal, restarting nothing",
      (bool(reload_) and removal is not None and reload_[-1] > removal,
       [(ps[i].get("ansible.builtin.systemd") or ps[i].get("ansible.builtin.systemd_service")).get("state") for i in reload_]),
      (True, [None] * len(reload_)))
# production's unit only until step 00 is done: a full run from a later step (its copy built as the steps before it
# left production) gets the playbook's unit, as production has then - the play ends before writing it, after its guard
import os  # noqa: E402
kc_play = next((q for q in load("tests/ansible/upgrade/production-state.yml") if "Keycloak" in str(q.get("name"))), {})
kc_tasks = kc_play.get("tasks") or []
ends = [i for i, t in enumerate(kc_tasks) if (t.get("ansible.builtin.meta") or t.get("meta")) == "end_play"]
unit_at = next((i for i, t in enumerate(kc_tasks) for _, v in actions(t) if isinstance(v, dict)
                and v.get("dest") == "/etc/systemd/system/keycloak.service"), None)
end_when = kc_tasks[ends[0]].get("when", "false") if ends else "false"
step00 = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))[0]
check("production's Keycloak unit only until step 00 is done: ended for a run from a later step, before the unit",
      (len(ends), ends[0] < unit_at if ends and unit_at is not None else None,
       [condition(end_when, **({"upgrade_from": f} if f else {})) for f in (None, step00, "01-argocd-root-retry")]),
      (1, True, [False, False, True]))
check("step 00 runs the tagged playbook", any("playbook setup-pi-services.yml --tags keycloak-db-url" == l.strip()
                                              for l in open("tests/ansible/upgrade/steps/00-gluster-boot.txt")), True)
# step 00's tagged run (--tags keycloak-db-url) reaches everything the unit needs: the facts its URL is made of, the
# credentials' check, every file it names by EnvironmentFile=, the unit, its start and its restart - one left out is
# undefined there, or the unit names a file the run never wrote (production's Keycloak failed to start)
doc = load("deploy/ansible/playbooks/setup-pi-services.yml")
def expand(ts):
    """The tasks as run: a statically imported task file's in its place, each with the import's tags."""
    out = []
    for t in ts:
        ref = t.get("ansible.builtin.import_tasks")
        if ref:
            for x in tasks(load(os.path.join("deploy/ansible/playbooks", str(ref)))):
                out.append(dict(x, tags=list(t.get("tags") or []) + list(x.get("tags") or [])))
        else:
            out.append(t)
    return out
import os  # noqa: E402
every = expand(list(tasks(doc)))
tagged = lambda t: "keycloak-db-url" in (t.get("tags") or [])  # noqa: E731
# the facts derived, not listed: the names the unit's and its secrets file's templates read, back through every task
# that sets one (its register, its set_fact) to the names that task reads - a guard reading them (an assert, a fail:
# the PgBouncer check) belongs to the tagged run too
NAME = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
sets = {}
for t in every:
    sf = t.get("ansible.builtin.set_fact") or {}
    for n in ({t.get("register")} | set(sf if isinstance(sf, dict) else {})) - {None}:
        sets.setdefault(n, []).append(t)
def reads(x):
    return {n for st in strings(x) for e in re.findall(r"\{\{(.*?)\}\}|\{%(.*?)%\}", st, re.S)
            for part in e for n in NAME.findall(part)}
templates = [t for t in every for m, v in actions(t) if isinstance(v, dict)
             and v.get("dest") in ("/etc/systemd/system/keycloak.service", "/etc/keycloak/secrets.env")]
need, todo = set(), set().union(*(reads(t) for t in templates)) & set(sets)
while todo:
    n = todo.pop()
    need.add(n)
    for t in sets[n]:
        todo |= (reads({k: v for k, v in t.items() if k != "register"}) & set(sets)) - need
setters = [t for t in every if any(t in sets[n] for n in need)]
guards = [t for t in every if (t.get("ansible.builtin.assert") or t.get("ansible.builtin.fail"))
          and reads(t) & need]
check("the facts the unit needs derived (its URL's among them), every task setting one and every guard reading one tagged",
      ({"keycloak_db_host_effective", "_db_port", "_pgbouncer_state"} <= need, bool(guards),
       [t.get("name") for t in setters + guards if not tagged(t)]), (True, True, []))
unit_task = next(t for t in every if (t.get("ansible.builtin.copy") or {}).get("dest") == "/etc/systemd/system/keycloak.service")
named = re.findall(r"(?m)^EnvironmentFile=(?!-)(\S+)$", unit_task["ansible.builtin.copy"]["content"])
# started after what its database URL goes through - PgBouncer (6432, where it runs) as Patroni and HAProxy: at a
# boot it met no PgBouncer yet and failed its first connections
after = " ".join(re.findall(r"(?m)^After=(.*)$", unit_task["ansible.builtin.copy"]["content"])).split()
check("Keycloak's unit ordered after PgBouncer, Patroni and HAProxy",
      sorted({"pgbouncer.service", "patroni.service", "haproxy.service"} - set(after)), [])
writers = {f: [t for t in every for m, v in actions(t) if isinstance(v, dict) and v.get("dest") == f] for f in named}
check("every file the unit names by EnvironmentFile= written by a tagged task, its directory too",
      (bool(named), {f: [tagged(t) for t in w] for f, w in writers.items()},
       [tagged(t) for t in every for m, v in actions(t) if isinstance(v, dict) and v.get("state") == "directory"
        and any(f.startswith(str(v.get("path")) + "/") for f in named)]),
      (True, {f: [True] for f in named}, [True]))
check("the unit, its start, Keycloak's wait tagged; the credentials' check on every run (always: another tag's run "
      "wrote an empty secret - step 25's --tags versitygw)",
      ([tagged(t) for t in (unit_task, next(t for t in every if t.get("name") == "Enable and start Keycloak"),
                            next(t for t in every if t.get("name") == "Wait for Keycloak"))],
       "always" in (next(t for t in every if t.get("name") == "Its credentials are all there").get("tags") or [])),
      ([True] * 3, True))
# its restart pending by content (tasks/restart-pending.yml: a restart that failed or was refused stays pending and the
# next run makes it - a handler fired once and a re-run left the old process running), the Pi without the VIP first
# (only the VIP's Caddy serves logins: the other's restart costs nothing, and a unit that does not start is found there),
# never in a preview (which wrote neither file)
check("no handler restarts Keycloak, nothing notifies one",
      ([t.get("name") for p in doc for t in p.get("handlers") or [] if "Keycloak" in str(t.get("name"))],
       [t.get("name") for t in every if "Keycloak" in str(t.get("notify", ""))]), ([], []))
pend = next((t for t in every if "restart-pending.yml" in str(t.get("ansible.builtin.include_tasks"))), None)
rec = next((t for t in every if "restart-recorded.yml" in str(t.get("ansible.builtin.include_tasks"))), None)
check("its restart pending by its unit and secrets file, recorded after - both tagged, in no preview",
      (pend is not None and sorted((pend.get("vars") or {}).get("loaded_files") or []) ==
       sorted(["/etc/systemd/system/keycloak.service"] + named) and tagged(pend), rec is not None and tagged(rec),
       [condition(x.get("when", True), ansible_check_mode=True) for x in (pend or {}, rec or {})]),
      (True, True, [False, False]))
restarts = [t for t in every if str(t.get("name", "")).startswith("Keycloak restarted where pending")]
check("three restarts: where Keycloak does not serve (nothing to lose there), then the Pi without the VIP, then the "
      "one with it - each tagged, one Pi at a time (no VIP on either, or on both: the same task on both at once)",
      ([str(t.get("name", "")).split(" - ")[1][:18] for t in restarts], len(restarts),
       [tagged(t) for t in restarts], [t.get("throttle") for t in restarts]),
      (["a Pi where it does", "the Pi without the", "the Pi with the VI"], 3, [True] * 3, [1] * 3))
# a Keycloak this run started (down before) serving before any restart: the other Pi's restart guard reads one still
# starting as down, and refuses - the waits after the restarts come too late for it
start = next(t for t in every if t.get("name") == "Enable and start Keycloak")
waits = [t for t in every if (t.get("ansible.builtin.uri") or {}).get("url") == "http://127.0.0.1:8080/realms/master"
         and t.get("until") and restarts and every.index(start) < every.index(t) < every.index(restarts[0])]
w = waits[0] if waits else {}
check("a Keycloak this run started waited for before any restart: tagged, only where it started now, in no preview, "
      "its 200 alone ends it (not a refused connection, a 503 while it starts, no answer), for 240 s",
      (len(waits), bool(w) and tagged(w),
       [condition(w.get("when", True), ansible_check_mode=cm, **{start.get("register", "_s"): {"changed": ch}})
        for cm, ch in ((False, True), (False, False), (True, True))],
       [condition(w.get("until", "false"), **{w.get("register", "_r"): r})
        for r in ({"status": 200}, {"status": -1}, {"status": 503}, {})],
       int(w.get("retries", 0)) * int(w.get("delay", 0)) >= 240),
      (1, True, [True, False, False], [True, False, False, False], True))
# the VIP's restart only with both Pis still in the play: one dropped by an earlier failure leaves the VIP's first
# and alone (the peer guard passes on the old Keycloak still serving there)
both = next((t for t in every if "ansible_play_hosts_all" in str(t.get("ansible.builtin.assert", ""))), None)
check("both Pis still in the play before the VIP's restart: checked between the two, tagged; one dropped - refused",
      (both is not None and len(restarts) == 3 and every.index(restarts[1]) < every.index(both) < every.index(restarts[2]),
       both is not None and tagged(both),
       [condition((both or {}).get("ansible.builtin.assert", {}).get("that", "false"), ansible_play_hosts=h,
                  ansible_play_hosts_all=["pi1", "pi2"]) for h in (["pi1", "pi2"], ["pi1"])]),
      (True, True, [True, False]))
# setup-patroni moves its database port: the same restart, both Pis in one play (its own play is one Pi at a time -
# it restarted pi1, the VIP's, first, with no guard, no stamp: the next setup-pi-services restarted both again)
pat = load("deploy/ansible/playbooks/setup-patroni.yml")
pat_every = list(tasks(pat))
imp = [i for i, q in enumerate(pat) if any("keycloak-restart.yml" in str(t.get("ansible.builtin.import_tasks", ""))
                                          for t in q.get("tasks") or [])]
recon = next((i for i, q in enumerate(pat) if "Reconfigure Forgejo + Keycloak" in str(q.get("name"))), None)
check("setup-patroni: no Keycloak handler or notify; the shared restart in a play of both Pis after its reconfigure",
      ([t.get("name") for t in pat_every if "Keycloak" in str(t.get("notify", "")) or t.get("name") == "Restart Keycloak"],
       len(imp) == 1 and recon is not None and imp[0] > recon and not pat[imp[0]].get("serial")
       and str(pat[imp[0]].get("hosts")) in ("pi1,pi2", "pis")), ([], True))
if len(restarts) == 3:
    vip_task = next(t for t in every if "keepalived_vip" in str(t.get("ansible.builtin.command", "")))
    vip_reg = vip_task.get("register")
    # whether Keycloak serves here, read on both Pis before any restart: a Pi where it does not restarts first - its
    # restart takes nothing down, and the other Pi's guard then finds it serving (the VIP on neither, pi1 went first and
    # refused, its peer's Keycloak on the replica's own Postgres until restarted: a full run's build, 2026-10-08)
    sv = next((t for t in every[every.index(vip_task):every.index(restarts[0])]
               if (t.get("ansible.builtin.uri") or {}).get("url") == "http://127.0.0.1:8080/realms/master"), None)
    serves_reg = (sv or {}).get("register", "_none")
    check("whether Keycloak serves here read before the restarts: tagged, in a preview too, failing nothing",
          (sv is not None and tagged(sv), (sv or {}).get("check_mode"),
           sv is not None and condition(sv.get("failed_when", "true"), **{serves_reg: {"status": -1}})),
          (True, False, False))
    V = "2: eth0 inet 10.0.0.5/32"
    def runs(t, pending, vip, serves=True, check_mode=False):
        return condition(t.get("when", True), ansible_check_mode=check_mode,
                         _restart_pending={"stdout_lines": [pending, "h"]}, **{vip_reg: {"stdout": vip}},
                         **{serves_reg: {"status": 200 if serves else -1}})
    check("where it does not serve first (the VIP's or not), then serving without the VIP, then serving with it; only "
          "where pending; none in a preview",
          [[runs(t, "pending", "", False), runs(t, "pending", V, False), runs(t, "pending", ""), runs(t, "pending", V),
            runs(t, "current", "", False), runs(t, "pending", "", False, True)] for t in restarts],
          [[True, True, False, False, False, False], [False, False, True, False, False, False],
           [False, False, False, True, False, False]])
    # the restart's own script: a file the unit names missing - refused, nothing restarted; the peer not serving while
    # this one does - refused; else restarted and serving
    import os, subprocess, tempfile  # noqa: E401,E402
    from templar import render  # noqa: E402
    W = tempfile.mkdtemp()
    os.makedirs(os.path.join(W, "bin"))
    open(os.path.join(W, "bin", "systemctl"), "w").write('#!/bin/bash\necho "systemctl $*" >> "$W/calls"\n')
    open(os.path.join(W, "bin", "curl"), "w").write(
        '#!/bin/bash\ncase "$*" in *127.0.0.1*) [ -z "${HERE_DOWN:-}" ] || grep -q "restart keycloak" "$W/calls" ;;\n'
        '*) [ -z "${PEER_DOWN:-}" ] ;; esac\n')  # here: serving once restarted
    for b in ("systemctl", "curl"):
        os.chmod(os.path.join(W, "bin", b), 0o755)
    def restart(t, have_file=True, **env):
        sh = t["ansible.builtin.shell"]
        script = render(sh if isinstance(sh, str) else sh["cmd"], inventory_hostname="pi1", peer_ip="10.0.0.2")
        u = os.path.join(W, "keycloak.service")
        f = os.path.join(W, "secrets.env")
        open(u, "w").write(f"[Service]\nEnvironmentFile={f}\nEnvironmentFile=-{W}/optional.env\n")
        if have_file:
            open(f, "w").write("KC_DB_PASSWORD=x\n")
        elif os.path.exists(f):
            os.remove(f)
        open(os.path.join(W, "calls"), "w").close()
        r = subprocess.run(["bash", "-c", script.replace("/etc/systemd/system/keycloak.service", u)],
                           capture_output=True, text=True, timeout=60,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
        return r.returncode, "REFUSED" in r.stderr, "systemctl restart keycloak" in open(os.path.join(W, "calls")).read()
    check("its restart: the unit's secrets file missing - refused, nothing restarted (an optional one's absence fine); "
          "the peer down while this serves - refused; else restarted",
          [restart(restarts[0], have_file=False), restart(restarts[0], PEER_DOWN="1"), restart(restarts[0])],
          [(1, True, False), (1, True, False), (0, False, True)])
    # the order as a run makes it: each restart task Pi by Pi (throttle: pi1, then pi2), its own script on what serves
    # at that moment - a Pi refused leaves the play
    def simulate(serving, vip, pending):
        serving, play, log = dict(serving), ["pi1", "pi2"], []
        facts = {h: {"_restart_pending": {"stdout_lines": ["pending" if h in pending else "current", "h"]},
                     vip_reg: {"stdout": V if h in vip else ""}, serves_reg: {"status": 200 if serving[h] else -1}}
                 for h in play}
        for t in every[every.index(restarts[0]):every.index(restarts[-1]) + 1]:
            if t in restarts:
                for h in list(play):
                    if not condition(t.get("when", True), ansible_check_mode=False, **facts[h]):
                        continue
                    peer = "pi2" if h == "pi1" else "pi1"
                    env = dict({"HERE_DOWN": "1"} if not serving[h] else {}, **({"PEER_DOWN": "1"} if not serving[peer] else {}))
                    rc, _, restarted = restart(t, **env)
                    if rc == 0 and restarted:
                        serving[h] = True
                        log.append(f"{h} restarted")
                    else:
                        play.remove(h)
                        log.append(f"{h} refused")
            elif t is both and play and not condition(t["ansible.builtin.assert"]["that"], ansible_play_hosts=play,
                                                      ansible_play_hosts_all=["pi1", "pi2"]):
                log.append("both refused")
                play = []
        return log
    check("the order as a run makes it: pi2 not serving, the VIP on neither (the build) - pi2 first, then pi1; both "
          "serving - the one without the VIP first; the VIP's not serving - it first; the VIP on neither, both serving - "
          "one at a time; this one serving, the other down and nothing pending there - refused",
          [simulate({"pi1": True, "pi2": False}, set(), {"pi1", "pi2"}),
           simulate({"pi1": True, "pi2": True}, {"pi1"}, {"pi1", "pi2"}),
           simulate({"pi1": False, "pi2": True}, {"pi1"}, {"pi1", "pi2"}),
           simulate({"pi1": True, "pi2": True}, set(), {"pi1", "pi2"}),
           simulate({"pi1": True, "pi2": False}, {"pi1"}, {"pi1"})],
          [["pi2 restarted", "pi1 restarted"], ["pi2 restarted", "pi1 restarted"], ["pi1 restarted", "pi2 restarted"],
           ["pi1 restarted", "pi2 restarted"], ["pi1 refused"]])
# before the unit names the secrets file: the database password it gives (as systemd reads an EnvironmentFile - quotes,
# backslashes) is the one Keycloak runs with now (production's inline Environment=, read from the running process), by
# hash, neither said nor on a command line; a Keycloak not running has nothing to compare. A different one: refused,
# the unit not written (pi2's Keycloak crash-looped on it, both units on disk naming it)
same = next((t for t in every if "systemd-run" in str(t.get("ansible.builtin.shell", ""))), None)
check("the password compared before the unit is written, tagged, never in a preview",
      (same is not None and every.index(same) < every.index(unit_task) and every.index(same) >
       min(i for i, t in enumerate(every) for m, v in actions(t) if isinstance(v, dict)
           and v.get("dest") == "/etc/keycloak/secrets.env"),
       same is not None and tagged(same), condition((same or {}).get("when", True), ansible_check_mode=True)),
      (True, True, False))
if same:
    import os, subprocess, tempfile  # noqa: E401,E402
    from templar import render  # noqa: E402
    S = tempfile.mkdtemp()
    os.makedirs(os.path.join(S, "bin"))
    # systemctl: the running Keycloak's PID (a process this test started with that environment), 0 when none;
    # systemd-run: the variable as an EnvironmentFile gives it (KEY=VALUE, the value's quotes stripped)
    open(os.path.join(S, "bin", "systemctl"), "w").write('#!/bin/bash\necho "${KC_PID:-0}"\n')
    open(os.path.join(S, "bin", "systemd-run"), "w").write(
        '#!/bin/bash\nf=""; for a; do case $a in EnvironmentFile=*) f=${a#EnvironmentFile=};; esac; done\n'
        'v=$(sed -n "s/^KC_DB_PASSWORD=//p" "$f"); v=${v#\\"}; v=${v%\\"}; printf "%s\\n" "$v"\n')
    for b in ("systemctl", "systemd-run"):
        os.chmod(os.path.join(S, "bin", b), 0o755)
    sh = same["ansible.builtin.shell"]
    script = render(sh if isinstance(sh, str) else sh["cmd"], inventory_hostname="pi1")
    def compare(running, file_value):
        f = os.path.join(S, "secrets.env")
        open(f, "w").write(f"KC_DB_PASSWORD={file_value}\n")
        proc = subprocess.Popen(["sleep", "30"], env={"KC_DB_PASSWORD": running}) if running is not None else None
        try:
            r = subprocess.run(["bash", "-c", script.replace("/etc/keycloak/secrets.env", f)], capture_output=True,
                               text=True, timeout=30, env=dict(os.environ, PATH=os.path.join(S, "bin") + ":" +
                                                               os.environ["PATH"], KC_PID=str(proc.pid) if proc else "0"))
        finally:
            if proc:
                proc.kill()
                proc.wait()
        reg = same.get("register", "_r")
        res = {"rc": r.returncode, "stdout": r.stdout.strip(), "stdout_lines": r.stdout.split()}
        failed = condition(same.get("failed_when", "false"), **{reg: res}) if "failed_when" in same else r.returncode != 0
        return failed, "pw" in (r.stdout + r.stderr)
    check("the same password: on; another (systemd read the file's quotes away): refused; Keycloak not running: on; "
          "the password itself never said",
          [compare("pw", "pw"), compare("pw", '"pw2"'), compare(None, "pw")], [(False, False), (True, False), (False, False)])
# step 00 says what it costs and how it is undone
text = open("tests/ansible/upgrade/steps/00-gluster-boot.txt").read()
check("step 00's outage names logins down while the VIP's Keycloak restarts; its abort puts the old URL back, "
      "PgBouncer restarted first", ("auth.pmon.dev" in text and "VIP" in text,
                                    bool(re.search(r"abort:.*\n(#.*\n)*?#.*pgbouncer", text, re.I))), (True, True))
# one URL's query on every writer: two that differ restart Keycloak on each other's every run
check("the same query from every writer", len({u.split("?", 1)[-1] for found in urls.values() for u in found}), 1)
print("keycloak-db-url: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
