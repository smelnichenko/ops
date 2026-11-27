#!/bin/bash
# Consul's way back: restore-consul.yml - every server in its run; its source (the running cluster's KV by default, the
# pre-upgrade snapshot when asked) and a run again's (the record's, never another kind); the version gone back to and its
# confirmation; its refusals before anything stops (no snapshot, the unit not reverted, not confirmed, the old binary
# gone, a snapshot that binary cannot read, nothing to go back from, a reboot scheduled, Postgres not one primary, the
# admin password not working, Patroni paused by someone else, a job holding a Consul lock); then, against stubs, what
# each step does - the export checked, the data directory set aside on a first run and on a run again (the state before
# always the record's), the import compared key by key, Patroni's stale keys deleted, the system id compared, exactly one
# Vault active, Patroni healthy, Postgres kept - and the order; then the copy's rehearsal (its modes, the switchover, no
# promotion, the task's sequence and cleanup).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_CWB'
import json, os, shutil, subprocess, sys, tempfile
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
work = tempfile.mkdtemp()
RP = yaml.safe_load(open("deploy/ansible/playbooks/restore-consul.yml"))[0]
V = RP["vars"]
def flat(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from flat(t.get(k))
R = list(flat(RP["tasks"]))
rt = lambda name: next(t for t in R if str(t.get("name", "")).startswith(name))
top = RP["tasks"]
blk = rt("The way back - from the first stop")
B_ = blk["block"]
bt = lambda name: next(t for t in B_ if str(t.get("name", "")).startswith(name))
bi = B_.index
PIS = {"pis": ["pi1", "pi2"]}
HOSTS = ["pi1", "pi2", "target"]
SNAP = "/var/backups/consul-upgrade/consul-20261127T010000Z-1.22.7.snap"
KV = "/var/backups/consul-upgrade/consul-20261127T020000Z-current-2.0.4.kv.json"
stub = os.path.join(work, "bin"); os.makedirs(stub)
def tool(name, body):
    p = os.path.join(stub, name)
    open(p, "w").write("#!/bin/bash\n" + body + "\n")
    os.chmod(p, 0o755)
def sh(cmd, stdin="", **env):
    return subprocess.run(["bash", "-c", cmd], input=stdin, capture_output=True, text=True,
                          env=dict(os.environ, PATH=stub + ":" + os.environ["PATH"], W=work, **env))

# ── every server, the source, a run again's record ───────────────────────────────────────────────────────────────
check("every server in the run: pi1, pi2 and ten (target) - on; one left out (--limit) - refused",
      [condition(rt("Every server in the run")["ansible.builtin.assert"]["that"], consul_servers=V["consul_servers"], ansible_play_hosts=h)
       for h in (HOSTS, ["target", "pi2", "pi1"], ["pi1", "pi2"])], [True, True, False])
check("  its servers as upgrade-consul.yml names them, the pin read from setup-consul.yml, Patroni's scope from setup-patroni.yml",
      (V["consul_servers"], yaml.safe_load(open("deploy/ansible/playbooks/upgrade-consul.yml"))[0]["vars"]["consul_servers"],
       "setup-consul.yml" in V["_setup"], "setup-patroni.yml" in V["patroni_scope"]), (["pi1", "pi2", "target"],) * 2 + (True, True))
src = rt("The source given")["ansible.builtin.assert"]["that"]
check("the source: current by default, snapshot when asked - anything else refused",
      [condition(src, **({} if m is None else {"consul_restore_from": m})) for m in (None, "current", "snapshot", "latest")],
      [True, True, True, False])
fields = rt("Its fields")["ansible.builtin.set_fact"]
REC = f"source={SNAP}\nhost=pi2\nfrom=2.0.4\naside=/var/lib/consul/data.pre-restore-T1\nrestored={os.path.basename(SNAP)}\n"
check("  a record's fields read (its source, its server, the version left, the state before's directory); none - empty",
      [tuple(render(fields[k], _record={"stdout": r}) for k in ("_rec_source", "_rec_host", "_rec_from", "_orig_aside")) for r in (REC, "")],
      [(SNAP, "pi2", "2.0.4", "/var/lib/consul/data.pre-restore-T1"), ("", "", "", "")])
one_src = rt("One source recorded across the servers")["ansible.builtin.assert"]["that"]
hv = lambda vals: {h: {"_rec_source": v} for h, v in zip(HOSTS, vals)}
check("  one source across the servers (or none, or some not yet written) - on; two different - refused",
      [condition(one_src, ansible_play_hosts=HOSTS, hostvars=hv(v)) for v in ((SNAP, SNAP, SNAP), ("", "", ""), (KV, "", KV), (KV, SNAP, KV))],
      [True, True, True, False])
mode = rt("The source, from the record or as given")
def mode_of(vals, given=None, asides=("", "", ""), hosts=("", "", "")):
    hvars = {h: {"_rec_source": v, "_orig_aside": a, "_rec_host": o} for h, v, a, o in zip(HOSTS, vals, asides, hosts)}
    rec = render(mode["vars"]["_recorded_source"], ansible_play_hosts=HOSTS, hostvars=hvars)
    anya = render(mode["vars"]["_set_aside_any"], ansible_play_hosts=HOSTS, hostvars=hvars)
    take = render(mode["vars"]["_take_up"], _recorded_source=rec, _set_aside_any=anya)
    e = {} if given is None else {"consul_restore_from": given}
    return tuple(str(render(mode["ansible.builtin.set_fact"][k], _recorded_source=rec, _take_up=take, ansible_play_hosts=HOSTS, hostvars=hvars, **e)).strip()
                 for k in ("_recorded", "_from_record", "_mode", "_recorded_host"))
A1 = ("/var/lib/consul/data.pre-restore-T1", "", "")
check("  a recorded snapshot taken up as it is; a recorded export only once the cluster it came from is gone (a directory set aside) - "
      "before that exported afresh; none - as given, current by default",
      [mode_of(("", "", "")), mode_of(("", "", ""), "snapshot"), mode_of((SNAP, "", SNAP), hosts=("pi1", "", "pi1")),
       mode_of((KV, KV, KV), "current", asides=A1, hosts=("pi2",) * 3), mode_of((KV, KV, KV)), mode_of((KV, KV, KV), "snapshot")],
      [("", "False", "current", ""), ("", "False", "snapshot", ""), (SNAP, "True", "snapshot", "pi1"), (KV, "True", "current", "pi2"),
       ("", "False", "current", ""), ("", "False", "snapshot", "")])
again = rt("A run again takes its source up")["ansible.builtin.assert"]["that"]
check("  a run again asking for the other kind - refused; the same kind, or none asked - on",
      [condition(again, _from_record=fr, _mode=m, **({} if g is None else {"consul_restore_from": g}))
       for fr, m, g in ((True, "snapshot", "current"), (True, "snapshot", "snapshot"), (True, "current", None), (False, "current", "snapshot"))],
      [False, True, True, True])

# ── the snapshot source ──────────────────────────────────────────────────────────────────────────────────────────
nw = rt("The newest snapshot on its server")
sd = os.path.join(work, "snaps"); os.makedirs(sd)
for n, t in (("consul-20261127T010000Z-1.22.7.snap", 1000), ("consul-20261126T010000Z-1.22.6.snap", 2000)):
    open(os.path.join(sd, n), "w").write("x"); os.utime(os.path.join(sd, n), (t, t))
newest = lambda: sh(render(nw["ansible.builtin.shell"]["cmd"], upgrade_dir=sd)).stdout.strip()
got_newest = newest()
for n in os.listdir(sd): os.remove(os.path.join(sd, n))
check("the newest snapshot by its name (its UTC time) - never by mtime; none - nothing; looked for only for a snapshot not recorded "
      "or given", (os.path.basename(got_newest), newest(), nw.get("when")),
      ("consul-20261127T010000Z-1.22.7.snap", "", "_mode == 'snapshot' and not _from_record | bool and consul_restore_snapshot is not defined"))
pick = rt("The snapshot restored - recorded, given, or the newest")
def chosen(newest_out, given=None, recorded=""):
    e = {} if given is None else {"consul_restore_snapshot": given}
    path = render(pick["vars"]["_snap_path"], _newest={"stdout": newest_out}, _recorded=recorded, _from_record=bool(recorded), **e)
    return (render(pick["ansible.builtin.set_fact"]["_snap"], _snap_path=path).strip(),
            render(pick["ansible.builtin.set_fact"]["_snap_version"], _snap_path=path).strip())
check("  recorded, else given, else the newest; its version from its name; a name not a snapshot's - no version",
      [chosen(SNAP), chosen(SNAP, "/x/consul-20261101T000000Z-1.22.5.snap"), chosen(SNAP, "/x/a.snap", "/r/consul-20261102T000000Z-1.22.4.snap"),
       chosen("/x/other.snap"), chosen("")],
      [(SNAP, "1.22.7"), ("/x/consul-20261101T000000Z-1.22.5.snap", "1.22.5"), ("/r/consul-20261102T000000Z-1.22.4.snap", "1.22.4"),
       ("/x/other.snap", ""), ("", "")])
known = rt("A snapshot and its version known")["ansible.builtin.assert"]["that"]
pin = rt("The unit reverted first")
check("  refused without a snapshot or a version, until the unit is reverted - the refusal naming the override for an earlier snapshot",
      ([condition(known, _snap=p, _snap_version=v) for p, v in ((SNAP, "1.22.7"), ("", "1.22.7"), (SNAP, ""))],
       [condition(pin["ansible.builtin.assert"]["that"], consul_version=k, _snap_version="1.22.7") for k in ("1.22.7", "2.0.4")],
       "consul_restore_snapshot=" in pin["ansible.builtin.assert"]["fail_msg"],
       [t.get("when") for t in (rt("A snapshot and its version known"), pin, rt("The snapshot there and readable"))]),
      ([True, False, False], [True, False], True, ["_mode == 'snapshot'"] * 3))
ins = rt("The snapshot there and readable by that binary")
check("  the snapshot read by the kept binary itself (consul snapshot inspect), on its server",
      (ins["ansible.builtin.command"]["argv"], ins.get("delegate_to")),
      (["/usr/local/bin/consul-{{ _to }}", "snapshot", "inspect", "{{ _snap }}"], "{{ _src_host }}"))

# ── the version gone back to, its confirmation, the kept binary ──────────────────────────────────────────────────
to = rt("The version gone back to")["ansible.builtin.set_fact"]
tv = lambda m, fr=False, rh="", **k: tuple(str(render(to[x], _mode=m, consul_version="1.22.7", _from_record=fr, _recorded_host=rh, **k)).strip()
                                          for x in ("_to", "_src_host", "_confirm_as"))
check("current: back to the pin, confirmed as consul-<pin>; snapshot: to its version, confirmed by its name; pi1 unless another given, "
      "a run again's server the recorded one",
      [tv("current"), tv("snapshot", _snap=SNAP, _snap_version="1.22.6"), tv("current", consul_restore_host="pi2"), tv("current", True, "pi2")],
      [("1.22.7", "pi1", "consul-1.22.7"), ("1.22.6", "pi1", os.path.basename(SNAP)), ("1.22.7", "pi2", "consul-1.22.7"), ("1.22.7", "pi2", "consul-1.22.7")])
conf = rt("Confirmed (-e confirm")["ansible.builtin.assert"]
check("  the confirmation as named - another, or none, refused; the refusal's text renders for either source",
      ([condition(conf["that"], _confirm_as="consul-1.22.7", **({} if c is None else {"confirm": c})) for c in ("consul-1.22.7", "consul-2.0.4", None)],
       ["Vault's secrets" in render(conf["fail_msg"], _mode="snapshot", _snap=SNAP, _to="1.22.7", _confirm_as="x"),
        "KV carried over" in render(conf["fail_msg"], _mode="current", _to="1.22.7", _confirm_as="consul-1.22.7")]),
      ([True, False, False], [True, True]))
srvchk = rt("The source's server in the run")["ansible.builtin.assert"]["that"]
check("  the source's server one of the run's - on a run again the recorded one, another given refused",
      [condition(srvchk, _src_host=h, ansible_play_hosts=HOSTS, _from_record=fr, **({} if g is None else {"consul_restore_host": g}))
       for h, fr, g in (("pi2", False, None), ("pi3", False, None), ("pi2", True, "pi2"), ("pi2", True, "pi1"), ("pi2", True, None))],
      [True, False, True, False, True])
rx = rt("A recorded export there and whole, and of this way back")
def rec_export(content, name, newest=None):
    d = os.path.join(work, "recx"); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    f = os.path.join(d, name); open(f, "w").write(content)
    if newest:
        open(os.path.join(d, newest), "w").write("x")
    return sh(render(rx["ansible.builtin.shell"]["cmd"], _recorded=f, export_ok_py=V["export_ok_py"], patroni_scope="pg", upgrade_dir=d,
                     restore_state=V["restore_state"])).returncode
WHOLE = json.dumps([{"key": "service/pg/initialize", "flags": 0, "value": "MQ=="}, {"key": "vault/core/keyring", "flags": 0, "value": "eA=="},
                    {"key": "vault/core/seal-config", "flags": 0, "value": "eQ=="}])
KVN = "consul-20261127T020000Z-current-2.0.4.kv.json"
check("  a recorded export checked before anything stops - whole and newer than the newest upgrade snapshot: on; not whole, or older "
      "(a record of an earlier way back), refused; only for a recorded export",
      ([rec_export(WHOLE, KVN, "consul-20261127T010000Z-1.22.7.snap"), rec_export(WHOLE, KVN), rec_export("[]", KVN) != 0,
        rec_export(WHOLE, KVN, "consul-20261128T010000Z-2.0.4.snap") != 0], rx.get("when"), rx.get("delegate_to")),
      ([0, 0, True, True], "_mode == 'current' and _from_record | bool", "{{ _src_host }}"))
kept = rt("Every server has it")["ansible.builtin.assert"]["that"]
check("  the kept binary there AND the version gone back to",
      [condition(kept, _kept=k, _to="1.22.7") for k in (
          {"rc": 0, "stdout_lines": ["Consul v1.22.7", "Revision abc"]}, {"rc": 0, "stdout_lines": ["Consul v2.0.4", "Revision abc"]},
          {"rc": 0, "stdout_lines": ["Revision abc", "Consul v1.22.7"]}, {"rc": 2, "stdout_lines": [], "stderr": "No such file"}, {})],
      [True, False, False, False, False])

# ── what is left, and whether there is anything to go back from ──────────────────────────────────────────────────
fr = rt("The version being left - the record's")["ansible.builtin.set_fact"]["_from"]
check("the version left: the record's (a run again - the agent then runs the old one), else what the agent runs; neither - none",
      [render(fr, _rec_from=r, _agent=a).strip() for r, a in (("2.0.4", {"status": 200, "json": {"Config": {"Version": "1.22.7"}}}),
                                                              ("", {"status": 200, "json": {"Config": {"Version": "2.0.4"}}}),
                                                              ("", {"status": -1, "msg": "refused"}))],
      ["2.0.4", "2.0.4", ""])
check("  none known on a server - refused", [condition(rt("The version being left known")["ansible.builtin.assert"]["that"], _from=f)
                                             for f in ("2.0.4", "")], [True, False])
rd = rt("Something to go back from, its KV readable")
tool("consul", 'echo "$*" >> "$W/consul.log"; case "$1 $2" in "kv export") [ -z "${NO_LEADER:-}" ] || { echo "No cluster leader" >&2; exit 1; }; cat "$W/kv.json" ;; esac')
open(os.path.join(work, "kv.json"), "w").write('[{"key": "a", "flags": 0, "value": "eA=="}]')
readable = lambda keys, **e: (open(os.path.join(work, "kv.json"), "w").write(json.dumps([{"key": k, "flags": 0, "value": "eA=="} for k in keys])),
                              sh(rd["ansible.builtin.shell"]["cmd"], **e))[1]
check("  the current source: the KV read through the leader before any stop - a cluster with no leader refused, a key the import "
      "would rename (a double or trailing slash, a dot segment) refused; only for a current source not taken yet",
      (readable(["a", "b/c"]).stdout.strip(), readable(["a"], NO_LEADER="1").returncode != 0,
       [readable([k]).returncode != 0 for k in ("a//b", "a/b/", "a/./b")], rd.get("when")),
      ("2", True, [True, True, True], "_mode == 'current' and not _from_record | bool"))
newer = rt("A newer version running somewhere")["ansible.builtin.assert"]["that"]
fh = lambda vals: {h: {"_from": v} for h, v in zip(HOSTS, vals)}
check("  something newer than the pin running (a partial upgrade counts) - on; every server on the pin - refused",
      [condition(newer, ansible_play_hosts=HOSTS, hostvars=fh(v), _to="1.22.7") for v in (("2.0.4",) * 3, ("1.22.7", "1.22.7", "2.0.4"), ("1.22.7",) * 3)],
      [True, True, False])
hr = rt("Whether an earlier run loaded this source here")["ansible.builtin.set_fact"]["_host_restored"]
ok_agent = {"status": 200, "json": {"Config": {"Version": "1.22.7"}}}
check("a run again after the load and the deletion (recorded, every agent on the version gone back to) takes up after them; "
      "not recorded, another source, or an agent elsewhere - from the start",
      [render(hr, _from_record=f, _recorded=SNAP, _record={"stdout": r}, _agent=a, _to="1.22.7") for f, r, a in (
          (True, REC, ok_agent), (True, REC.replace("restored=", "x="), ok_agent), (True, REC, {"status": 200, "json": {"Config": {"Version": "2.0.4"}}}),
          (False, REC, ok_agent), (True, REC, {"status": -1}))],
      [True, False, False, False, False])
rrec = rt("Whether it did on every server")["ansible.builtin.set_fact"]["_restored_recorded"]
recs = lambda *r: {h: {"_record": {"stdout": x}} for h, x in zip(HOSTS, r)}
check("a load named by every record (any agent answering or not) - recorded; on some only - not (a full load again is safe: nothing ran on it)",
      [render(rrec, _from_record=True, _recorded=SNAP, ansible_play_hosts=HOSTS, hostvars=recs(*v)) for v in ((REC,) * 3, (REC, REC.replace("restored=", "x="), REC))],
      [True, False])
check("  recorded on every server but an agent not on the version gone back to - refused (start it), never a second load",
      [condition(rt("A load every record names taken up only")["ansible.builtin.assert"]["that"], _restored_recorded=a, _restored_already=b)
       for a, b in ((True, True), (True, False), (False, False))], [True, False, True])
ra = rt("Whether it did on every server")["ansible.builtin.set_fact"]["_restored_already"]
check("  on every server - else from the start", [render(ra, ansible_play_hosts=HOSTS, hostvars={h: {"_host_restored": v} for h, v in zip(HOSTS, vals)})
                                                  for vals in ((True,) * 3, (True, False, True))], [True, False])

# ── the rest of the refusals ─────────────────────────────────────────────────────────────────────────────────────
check("a reboot scheduled on a server (ten's unattended-upgrades schedules one) - refused before anything stops",
      [condition(rt("None scheduled on any server")["ansible.builtin.assert"]["that"], _scheduled={"stat": {"exists": e}}) for e in (False, True)],
      [True, False])
one = rt("Exactly one primary, both Postgres running")["ansible.builtin.assert"]["that"]
roles = lambda a, b: {"pi1": {"_pg_role": a}, "pi2": {"_pg_role": b}}
P, S, DOWN = {"rc": 0, "stdout": "t"}, {"rc": 0, "stdout": "f"}, {"rc": 2, "stdout": "", "stderr": "no socket"}
check("Postgres named by itself: one primary and a running replica - on; two primaries, none, one down - refused",
      [condition(one, groups=PIS, hostvars=roles(a, b)) for a, b in ((P, S), (S, P), (P, P), (S, S), (P, DOWN))], [True, True, False, False, False])
check("  the primary's Pi the one out of recovery",
      [render(rt("The primary's Pi")["ansible.builtin.set_fact"]["_pg_primary"], groups=PIS, hostvars=roles(a, b)).strip() for a, b in ((P, S), (S, P))],
      ["pi1", "pi2"])
pw = rt("The admin password works on the primary now")
tool("psql", 'echo "$*" >> "$W/psql.log"; [ "$PGPASSWORD" = right ] || { echo "password authentication failed" >&2; exit 2; }; '
             'case "$*" in *"select 1"*) echo 1 ;; *) [ -n "${PSQL_NO:-}" ] && [[ "$*" == *"-p $PSQL_NO "* ]] && echo f || echo t ;; esac')
check("  the admin password proven on the primary's own port (not through HAProxy - Patroni may be stopped): right - on; wrong "
      "or empty - refused, never logged", ([sh(pw["ansible.builtin.shell"]["cmd"], p + "\n").returncode != 0 for p in ("right", "wrong", "")],
                                           "-p 5432" in pw["ansible.builtin.shell"]["cmd"], pw.get("no_log"), pw.get("when")),
      ([False, True, True], True, True, "inventory_hostname == _pg_primary"))
check("  no apostrophe in the Python the shell hands over in single quotes (it would end the quoting)",
      [n for n in ("export_ok_py", "healthy_py") if "'" in V[n]], [])
runs = rt("Whether any Patroni runs")["ansible.builtin.set_fact"]["_patroni_runs"]
act = lambda a, b: {"pi1": {"_patroni_active": {"stdout": a}}, "pi2": {"_patroni_active": {"stdout": b}}}
check("Patroni running on either Pi - a pause wanted; on neither (an earlier run of this play stopped it) - none",
      [render(runs, groups=PIS, hostvars=act(a, b)) for a, b in (("active", "active"), ("inactive", "active"), ("inactive", "failed"))], [True, True, False])
ours = rt("Whether this play paused it")["ansible.builtin.set_fact"]["_ours_paused"]
other = rt("Whether this play paused it")["ansible.builtin.set_fact"]["_other_marker"]
MK = lambda w: {"rc": 0, "stdout": f"{w} 2026-11-27T15:00:00Z ab12cd34"}
held = rt("This play's pause still holding")
check("  a marker of this play's taken up only while it holds everything paused (proven by the script before anything stops); another "
      "run's marker refused",
      ([render(other, _patroni_runs=True, _marker=m) for m in (MK("consul-way-back"), MK("setup-consul"), {"rc": 1, "stdout": ""})],
       held["ansible.builtin.script"]["cmd"].endswith("patroni-pause.py paused consul-way-back"), held.get("when"), held.get("delegate_to"),
       [condition(rt("No pause marker of another run's")["ansible.builtin.assert"]["that"], _other_marker=o) for o in (False, True)]),
      ([False, True, False], True, "_ours_paused | bool", "{{ _pg_primary }}", [True, False]))
pp = bt("Paused - the config and every member")
check("  right before Patroni stops, the pause proven (the config and every member) - stopped unpaused it would stop Postgres",
      (pp["ansible.builtin.script"]["cmd"].endswith("patroni-pause.py paused consul-way-back"), pp.get("when"), pp.get("delegate_to")),
      (True, "_patroni_runs | bool and not _restored_already | bool", "{{ _pg_primary }}"))
check("  a pause this play made (its marker) taken up - neither checked nor paused again; another's marker, or none - not ours",
      ([render(ours, _patroni_runs=True, _marker=m) for m in ({"rc": 0, "stdout": "consul-way-back 2026-11-27T15:00:00Z ab12cd34"},
                                                             {"rc": 0, "stdout": "setup-consul 2026-11-27T15:00:00Z ab12cd34"}, {"rc": 1, "stdout": ""})],
       rt("Patroni not paused already").get("when"), bt("Patroni paused").get("when")),
      ([True, False, False], "_patroni_runs | bool and not _ours_paused | bool",
       "_patroni_runs | bool and not _ours_paused | bool and not _restored_already | bool"))
pre_jobs = rt("None running - else nothing stopped")["ansible.builtin.assert"]["that"]
jobs = lambda *s: {"results": [{"item": "pi-tier0-backup", "stdout": s[0]}, {"item": "pi-restore-check", "stdout": s[1]}]}
check("a tier-0 backup or a restore check running (its Consul lock) - refused before anything stops, and read again once their "
      "timers are stopped (one could start in between)",
      ([condition(pre_jobs, _lock_jobs=j) for j in (jobs("inactive", "failed"), jobs("active", "inactive"), jobs("inactive", "activating"), {"results": [{"skipped": True}]})],
       [condition(bt("The jobs read again")["failed_when"], _lock_jobs_now={"stdout": s}) for s in ("active", "deactivating", "inactive")],
       bi(bt("Their timers stopped")) < bi(bt("The jobs read again")), V["consul_lock_jobs"]),
      ([True, False, False, True], [True, True, False], True, ["pi-tier0-backup", "pi-restore-check"]))
hk = rt("None but Patroni's and Vault's - else nothing stopped")
KVH = lambda *held: [{"Key": "service/pg/leader", "Session": "s1"}, {"Key": "service/pg/members/pi1", "Session": "s2"},
                     {"Key": "vault/core/lock", "Session": "s3"}, {"Key": "a/plain"}, {"Key": "b/empty", "Session": ""}] + [{"Key": k, "Session": "x"} for k in held]
hk_others = lambda kv: render(hk["vars"]["_held_others"], _held={"json": kv}, patroni_scope="pg")
check("keys held by sessions: Patroni's (leader, members) and Vault's allowed, a plain or unheld key ignored; any other lock (pi-restart, "
      "the tier-0 backup) refused - before anything stops, and again right before Consul stops",
      (hk_others(KVH()), hk_others(KVH("pi-restart/.lock", "pi-tier0-backup/.lock")),
       [condition(hk["ansible.builtin.assert"]["that"], _held_others=o) for o in ([], ["x"])],
       render(bt("None but Patroni's and Vault's (a lock taken since")["vars"]["_held_now_others"], _held_now={"json": KVH("caddy-turn/.lock")}, patroni_scope="pg"),
       bi(bt("None but Patroni's and Vault's (a lock taken since")) < bi(bt("Consul stopped on every server"))),
      ([], ["pi-restart/.lock", "pi-tier0-backup/.lock"], [True, False], ["caddy-turn/.lock"], True))
check("ten's unattended-upgrades: refused while it runs (it reboots ten after); its timer stopped in the block and started again where "
      "enabled", ([condition(rt("Unattended-upgrades not running on ten now")["failed_when"], _apt_upgrade={"stdout": x}) for x in ("active", "activating", "inactive")],
                  bt("Its timer stopped for the run")["ansible.builtin.systemd"], bt("Unattended-upgrades' timer on ten started again")["ansible.builtin.systemd"],
                  [condition(bt("Unattended-upgrades' timer on ten started again")["when"], inventory_hostname="target", groups=PIS, _apt_timer={"stdout": x})
                   for x in ("enabled", "disabled")]),
      ([True, True, False], {"name": "apt-daily-upgrade.timer", "state": "stopped"}, {"name": "apt-daily-upgrade.timer", "state": "started"}, [True, False]))
check("every read and refusal before the first stop (the block); after it only the closing message",
      (top.index(blk), "ansible.builtin.debug" in top[-1], len(top) > 20), (len(top) - 2, True, True))
check("  the reads that may fail (a binary gone, an agent down, Postgres down, Patroni stopped, no marker) never fail the play themselves",
      [rt(n).get("failed_when") for n in ("An earlier run's record here", "The binary of the version gone back to", "The agent here now",
                                          "Postgres running here", "Patroni running here", "The pause marker now")], [False] * 6)

# ── the export, the record, the set-aside ────────────────────────────────────────────────────────────────────────
ex = bt("The whole KV exported from the running cluster")
up = os.path.join(work, "up")
def export_run(content):
    open(os.path.join(work, "kv.json"), "w").write(content)
    r = sh(render(ex["ansible.builtin.shell"]["cmd"], upgrade_dir=up, _from="2.0.4", export_ok_py=V["export_ok_py"], patroni_scope="pg"))
    out = r.stdout.strip().splitlines()[-1:] if r.returncode == 0 else []
    return r.returncode, [os.path.basename(o) for o in out], [oct(os.stat(o).st_mode)[-3:] for o in out]
whole = [{"key": "service/pg/initialize", "flags": 0, "value": "MQ=="}, {"key": "vault/core/keyring", "flags": 0, "value": "eA=="},
         {"key": "vault/core/seal-config", "flags": 0, "value": "eQ=="}]
rc, names, modes = export_run(json.dumps(whole))
import base64
cfg = lambda d: {"key": "service/pg/config", "flags": 0, "value": base64.b64encode(json.dumps(d).encode()).decode()}
check("the export: the whole KV into the upgrade directory, named by its time and the version left, root's alone; checked - "
      "no keys, no Vault barrier, no Patroni cluster, a pause marker or Patroni paused in it (carried over), not JSON: failed",
      (rc, bool(names) and names[0].startswith("consul-") and names[0].endswith("-current-2.0.4.kv.json"), modes,
       [export_run(c)[0] != 0 for c in ("[]", json.dumps(whole[:1] + whole[2:]), json.dumps(whole[:1]), json.dumps(whole[1:]),
                                       json.dumps(whole + [{"key": "ansible/patroni-paused-by", "flags": 0, "value": "eA=="}]),
                                       json.dumps(whole + [cfg({"ttl": 30, "pause": True})]), "{cut")],
       export_run(json.dumps(whole + [cfg({"ttl": 30})]))[0]),
      (0, True, ["600"], [True] * 7, 0))
check("  taken once - not on a run again (its record's reused), not for a snapshot; on the source's server; after Vault stops, before "
      "Patroni's pause (no pause or marker in it)",
      (ex.get("when"), ex.get("delegate_to"), bi(bt("Neither started at a boot")) < bi(ex) < bi(bt("Patroni paused"))),
      ("_mode == 'current' and not _from_record | bool", "{{ _src_host }}", True))
sx = bt("The source this run loads")["ansible.builtin.set_fact"]["_src"]
check("  the source loaded: the record's, else the snapshot, else this export",
      [render(sx, _from_record=f, _recorded=r, _mode=m, _snap=SNAP, _export={"stdout_lines": [KV]}).strip() for f, r, m in (
          (True, "/r/x.kv.json", "current"), (False, "", "snapshot"), (False, "", "current"))], ["/r/x.kv.json", SNAP, KV])
fe, rec = bt("The export fetched to the controller"), bt("The source recorded")
cc = bt("The controller's copy")
check("  the export fetched off its server (the controller's directory 0700, the export 0600), the source recorded - one line, root's alone - "
      "on every server before Patroni stops",
      (fe["ansible.builtin.fetch"]["dest"], fe.get("when"), [(render(x["path"], backups_here="/b", _src=KV), x["mode"]) for x in cc["loop"]],
       cc.get("delegate_to"), rec["ansible.builtin.lineinfile"], rec.get("when"), "run_once" in rec, bi(rec) < bi(bt("Patroni stopped and off at a boot"))),
      ("{{ backups_here }}/", "_mode == 'current' and not _from_record | bool", [("/b", "0700"), ("/b/" + os.path.basename(KV), "0600")], "localhost",
       {"path": "{{ restore_state }}", "line": "{{ item.line }}", "regexp": "{{ item.regexp }}", "create": True, "mode": "0600"}, "not _from_record | bool", False, True))
check("  recorded with the source before any server stops: its server and the version left (a run again with Consul down reads them)",
      [(render(x["line"], _src=KV, _src_host="pi1", _from="2.0.4"), x["regexp"]) for x in rec["loop"]],
      [(f"source={KV}", "^source="), ("host=pi1", "^host="), ("from=2.0.4", "^from=")])
asd = bt("Its data directory set aside")["ansible.builtin.shell"]["cmd"]
data = os.path.join(work, "consul", "data"); st = os.path.join(work, "consul", "restore-consul.state")
def tree(d):
    return sorted(os.path.relpath(os.path.join(p, f), d) for p, _, fs in os.walk(d) for f in fs) if os.path.isdir(d) else None
def fill(d, files):
    os.makedirs(d, exist_ok=True)
    for f, v in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, f)), exist_ok=True)
        open(os.path.join(d, f), "w").write(v)
def aside_run(stamp):
    # not root here: the owner Consul's on the Pi, the moves the same
    cmd = render(asd, consul_data=data, restore_state=st, _stamp=stamp, _from="2.0.4").replace("-o consul -g consul ", "")
    return sh(cmd)
SERVER = {"node-id": "id-1", "raft/raft.db": "raft", "serf/local.keyring": "k1", "serf/remote.keyring": "k2"}
fill(data, SERVER); open(st, "w").write(f"source={KV}\n")
r1 = aside_run("T1")
first = (r1.returncode, r1.stdout.strip() == data + ".pre-restore-T1", tree(data), tree(data + ".pre-restore-T1"), open(st).read())
fill(data, {"raft/raft.db": "a failed run's new cluster"})
r2 = aside_run("T2")
second = (r2.returncode, r2.stdout.strip() == data + ".pre-restore-T1", tree(data + ".failed-restore-T2"), tree(data + ".pre-restore-T1"),
          open(os.path.join(data, "node-id")).read() if os.path.exists(os.path.join(data, "node-id")) else None)
check("the first set-aside: the data directory moved whole to .pre-restore-<time> and recorded (its directory, the version left), "
      "a new one holding only the node-id and the keyrings",
      first, (0, True, ["node-id", "serf/local.keyring", "serf/remote.keyring"], sorted(SERVER), f"source={KV}\naside={data}.pre-restore-T1\n"))
check("  a run again: the failed run's new directory moved aside as a failed one, the state before still the recorded one, the node-id "
      "carried from it", second, (0, True, ["node-id", "raft/raft.db", "serf/local.keyring", "serf/remote.keyring"], sorted(SERVER), "id-1"))
for d in (data, data + ".pre-restore-T1", data + ".failed-restore-T2"):
    shutil.rmtree(d, ignore_errors=True)
fill(data, SERVER); open(st, "w").write(f"source={KV}\naside={data}.pre-restore-T1\n")
r5 = aside_run("T5")
check("  a run cut short between recording the set-aside and the move: the move made on the run again, no failed directory",
      (r5.returncode, tree(data + ".pre-restore-T1"), os.path.exists(data + ".failed-restore-T5")), (0, sorted(SERVER), False))
for d in (data, data + ".pre-restore-T1"):
    shutil.rmtree(d, ignore_errors=True)
fill(data + ".pre-restore-T1", {k: v for k, v in SERVER.items() if k != "serf/remote.keyring"})
open(st, "w").write(f"source={KV}\naside={data}.pre-restore-T1\nfrom=2.0.4\n")
r3 = aside_run("T4")
check("  a run again after one that failed with the data directory moved and none made (the node-id check): the new one made, no failed "
      "directory; a state before without remote.keyring (a server may have none) - its node-id and local keyring alone",
      (r3.returncode, tree(data), os.path.exists(data + ".failed-restore-T4")), (0, ["node-id", "serf/local.keyring"], False))
for gone in ("node-id", "serf/local.keyring"):
    for d in (data, data + ".pre-restore-T1", data + ".failed-restore-T2", data + ".pre-restore-T3"):
        shutil.rmtree(d, ignore_errors=True)
    fill(data, {k: v for k, v in SERVER.items() if k != gone}); open(st, "w").write(f"source={KV}\n")
    r = aside_run("T3")
    check(f"  a state before without its {gone} - failed (a new id would clash with the catalog; an empty keyring reads consul.hcl's)",
          (r.returncode != 0, f"{gone} missing" in r.stderr), (True, True))
check("  no rm anywhere in it; its time one for every server", (" rm " not in " " + asd, bt("The time this run sets directories aside").get("run_once")),
      (True, True))

# ── the load: the snapshot restored, or the export imported and compared ─────────────────────────────────────────
rs, im = bt("The snapshot restored (the snapshot source)"), bt("The export imported and compared key by key")
check("the snapshot source restores the snapshot, the current one imports the export - one or the other, never both; both on the "
      "source's server, and not on a run again after the load",
      (rs["ansible.builtin.command"]["argv"], rs.get("when"), im.get("when"), rs.get("delegate_to"), im.get("delegate_to")),
      (["consul", "snapshot", "restore", "{{ _src }}"], "_mode == 'snapshot' and not _restored_already | bool",
       "_mode == 'current' and not _restored_already | bool", "{{ _src_host }}", "{{ _src_host }}"))
tool("consul", 'echo "$*" >> "$W/consul.log"; case "$1 $2" in '
               '"kv import") [[ "$3" == @* ]] || { echo "Failed to decode data: invalid character" >&2; exit 1; }; cp "${3#@}" "$W/store.json"; '
               '[ -z "${LOSE:-}" ] || sed -i "s/MQ==/ZGlmZg==/" "$W/store.json"; [ -z "${FLAGS:-}" ] || sed -i "s/\\"flags\\": 0/\\"flags\\": 9/" "$W/store.json" ;; '
               '"kv export") cat "$W/store.json" ;; "kv delete") ;; '
               '"kv get") [ "$3" = service/pg/initialize ] && echo "${DCS_ID:-7300}" ;; esac')
src_file = os.path.join(work, "export.json"); open(src_file, "w").write(json.dumps(whole))
imp = lambda **e: sh(render(im["ansible.builtin.shell"]["cmd"], _src=src_file), **e)
check("  the import (its file as @<path> - a bare argument is data to consul) compared key by key with the export - a value or "
      "flags that came out different fail, never counted as loaded",
      (imp().stdout.strip(), imp(LOSE="1").returncode != 0, imp(FLAGS="1").returncode != 0), ("3", True, True))
dk = bt("Patroni's leader, member and failover keys deleted")
open(os.path.join(work, "consul.log"), "w").close()
r = sh(render(dk["ansible.builtin.shell"]["cmd"], patroni_scope="pg"))
check("Patroni's leader, member and failover keys deleted - its initialize, config and history kept - once, on the source's server",
      (r.returncode, open(os.path.join(work, "consul.log")).read().splitlines(), dk.get("run_once"), dk.get("delegate_to")),
      (0, ["kv delete service/pg/leader", "kv delete -recurse service/pg/members/", "kv delete service/pg/failover"], True, "{{ _src_host }}"))
check("  the load and the deletion recorded after both (a run again takes up after them)",
      (bt("The load and the deletion recorded")["ansible.builtin.lineinfile"]["line"], bi(dk) < bi(bt("The load and the deletion recorded"))),
      ("restored={{ _src | basename }}", True))
sid = bt("The keys' cluster the one Postgres runs")["ansible.builtin.shell"]["cmd"]
tool("runuser", 'echo "${PG_ID:-7300}"')
check("  the keys' cluster (initialize) the system Postgres runs - the same: on; another (a Postgres rebuilt since) - failed before "
      "Patroni starts", ([sh(render(sid, patroni_scope="pg"), PG_ID=p).returncode for p in ("7300", "9999")],
                         bi(bt("The keys' cluster")) < bi(bt("Patroni started on the primary's Pi first"))), ([0, 1], True))

# ── the order and what each step does ────────────────────────────────────────────────────────────────────────────
order = ["The Consul-locked jobs' timers - enabled", "Their timers stopped", "Unattended-upgrades' timer on ten - enabled", "Its timer stopped for the run",
         "The jobs read again", "Vault stopped on both Pis",
         "Neither started at a boot", "The whole KV exported", "The source this run loads", "The export fetched", "The source recorded",
         "Patroni paused", "Paused - the config and every member", "Patroni stopped and off at a boot", "Postgres still running on both",
         "The keys held by sessions, right before", "None but Patroni's and Vault's (a lock taken since", "Consul stopped on every server",
         "Its data directory set aside", "The kept binary back", "Started - a new cluster", "The new cluster - three voters",
         "The snapshot restored (the snapshot source)", "The export imported", "After it - three voters", "Each agent on the version",
         "Patroni's leader, member and failover keys", "The load and the deletion recorded", "The keys' cluster", "Vault and its unseal enabled",
         "Vault started", "Unsealed by the Pi's own script", "Vault unsealed - active or standby", "Exactly one Vault active",
         "The root token works", "Patroni on at a boot again", "Patroni started on the primary's Pi first", "It holds the leader key",
         "Then on the replica", "The cluster healthy", "Not paused", "No pause marker left", "The primary answering through HAProxy",
         "The Consul-locked jobs' timers started again", "Unattended-upgrades' timer on ten started again", "The record removed"]
check("the block: timers off and the jobs read again, Vault stopped (before the export), the source taken and recorded, Patroni paused "
      "THEN stopped (Postgres kept), Consul replaced, the keys loaded, healthy, Patroni's stale keys gone, the system id, Vault back "
      "(before Patroni - it needs nothing of it), the primary's Patroni first, not paused, the database through HAProxy, the timers, "
      "the record gone", [bi(bt(n)) for n in order] == sorted(bi(bt(n)) for n in order), True)
skipped = ["Vault stopped on both Pis", "Neither started at a boot", "Patroni paused", "Patroni stopped and off at a boot", "Postgres still running on both",
           "Consul stopped on every server", "The time this run sets directories aside", "Its data directory set aside", "The kept binary back",
           "Started - a new cluster", "The new cluster - three voters", "The snapshot restored (the snapshot source)", "The export imported",
           "Patroni's leader, member and failover keys", "The load and the deletion recorded", "Paused - the config and every member",
           "The keys held by sessions, right before", "None but Patroni's and Vault's (a lock taken since"]
check("  a run again after the load: every stop, the set-aside and the load itself skipped (never a second load); the health reads, "
      "Vault, Patroni and the checks run", ([n for n in skipped if "not _restored_already | bool" not in str(bt(n).get("when"))],
                                            [n for n in order if n not in skipped and "_restored_already" in str(bt(n).get("when"))]), ([], []))
units = {n: (bt(n).get("ansible.builtin.systemd") or {}) for n in (
    "Patroni stopped and off at a boot", "Vault stopped on both Pis", "Neither started at a boot", "Consul stopped on every server",
    "Started - a new cluster", "Patroni on at a boot again", "Patroni started on the primary's Pi first", "Then on the replica",
    "Vault and its unseal enabled again", "Vault started", "Unsealed by the Pi's own script", "Their timers stopped",
    "The Consul-locked jobs' timers started again")}
check("  each unit the step names, to the state it names - and only where it runs",
      {n: (u.get("name"), u.get("state"), u.get("enabled"), str(bt(n).get("when")).split(" and not _restored_already")[0]) for n, u in units.items()},
      {"Patroni stopped and off at a boot": ("patroni", "stopped", False, "inventory_hostname in groups['pis']"),
       "Vault stopped on both Pis": ("vault", "stopped", None, "inventory_hostname in groups['pis']"),
       "Neither started at a boot": ("{{ item }}", None, False, "inventory_hostname in groups['pis']"),
       "Consul stopped on every server": ("consul", "stopped", None, "not _restored_already | bool"),
       "Started - a new cluster": ("consul", "started", None, "not _restored_already | bool"),
       "Patroni on at a boot again": ("patroni", None, True, "inventory_hostname in groups['pis']"),
       "Patroni started on the primary's Pi first": ("patroni", "started", None, "inventory_hostname == _pg_primary"),
       "Then on the replica": ("patroni", "started", None, "inventory_hostname in groups['pis'] and inventory_hostname != _pg_primary"),
       "Vault and its unseal enabled again": ("{{ item }}", None, True, "inventory_hostname in groups['pis']"),
       "Vault started": ("vault", "started", None, "inventory_hostname in groups['pis']"),
       "Unsealed by the Pi's own script": ("vault-unseal", "restarted", None, "inventory_hostname in groups['pis']"),
       "Their timers stopped": ("{{ item }}.timer", "stopped", None, "inventory_hostname in groups['pis']"),
       "The Consul-locked jobs' timers started again": ("{{ item.item }}.timer", "started", None, "item.stdout | default('') == 'enabled'")})
check("  the unseal bounded (420 s); the kept binary the version gone back to, copied on the server itself; the new directory Consul's",
      (bt("Unsealed by the Pi's own script").get("timeout"), bt("The kept binary back")["ansible.builtin.copy"]["src"],
       bt("The kept binary back")["ansible.builtin.copy"].get("remote_src"), "install -d -o consul -g consul -m 0755 {{ consul_data }} {{ consul_data }}/serf" in asd),
      (420, "/usr/local/bin/consul-{{ _to }}", True, True))
check("  the timers judged by whether they are enabled (a run again after one that stopped them still starts them)",
      (bt("The Consul-locked jobs' timers - enabled")["ansible.builtin.command"]["argv"][:2],
       [condition(bt("The Consul-locked jobs' timers started again")["when"], item=i) for i in ({"stdout": "enabled"}, {"stdout": "disabled"}, {"skipped": True})]),
      (["systemctl", "is-enabled"], [True, False, False]))
lk = bt("It holds the leader key")["until"]
check("  the leader key the primary's (its value its name); another Pi's, or none yet - not yet",
      [condition(lk, _leader_key={"status": s, "content": c}, _pg_primary="pi1") for s, c in ((200, "pi1"), (200, "pi1\n"), (200, "pi2"), (404, ""))],
      [True, True, False, False])
fresh, after = bt("The new cluster - three voters")["until"], bt("After it - three voters")["until"]
srv = lambda voters, leaders: [{"Voter": i < voters, "Leader": i < leaders, "Healthy": True} for i in range(3)]
check("  the new cluster: three voters and a leader (autopilot may still call it unhealthy); after the load, healthy as well",
      ([condition(fresh, _fresh={"status": s, "json": {"Servers": srv(v, l), "Healthy": False}}) for s, v, l in ((429, 3, 1), (200, 2, 1), (200, 3, 0))],
       [condition(fresh, _fresh={"status": -1})],
       [condition(after, _after={"status": s, "json": {"Servers": srv(3, 1), "Healthy": h}}) for s, h in ((200, True), (429, False), (200, False))]),
      ([True, False, False], [False], [True, False, False]))
check("  each agent on the version gone back to - else failed",
      [condition(bt("Each agent on the version")["failed_when"], _self_after={"json": {"Config": {"Version": v}}}, _to="1.22.7") for v in ("1.22.7", "2.0.4")],
      [False, True])
pg = bt("Postgres still running on both")["ansible.builtin.shell"]["cmd"]
tool("runuser", 'echo "$PG_ANSWER"')
check("  after Patroni stopped: the primary still out of recovery and the replica in it - the other way round fails",
      [sh(render(pg, inventory_hostname=h, _pg_primary="pi1"), PG_ANSWER=a).returncode for h, a in (("pi1", "t"), ("pi2", "f"), ("pi1", "f"), ("pi2", "t"))],
      [0, 0, 1, 1])
vh = bt("Vault unsealed - active or standby")
check("Vault: unsealed (200 active, 429 standby - 503 sealed, 501 uninitialised, 500 no)",
      [condition(vh["until"], _vault={"status": c}) for c in (200, 429, 503, 501, 500)], [True, True, False, False, False])
oa = bt("Exactly one Vault active, both read together")
tool("vault", '[ -n "${VAULT_CACERT:-}" ] || { echo "x509: certificate signed by unknown authority" >&2; exit 2; }; '
              'if [ "$1" = status ]; then a=${VAULT_ADDR#https://}; a=${a%:8200}; case " ${ACTIVE:-} " in *" $a "*) s=true ;; *) s=false ;; esac; '
              'echo "{\\"is_self\\": $s, \\"sealed\\": false}"; exit 0; fi; '
              '[ "$1 $2" = "token lookup" ] || exit 9; t=${VAULT_TOKEN:-$(cat "$HOME/.vault-token" 2> /dev/null)}; [ "$t" = hvs.root ] || { echo "permission denied" >&2; exit 2; }; '
              'echo "{\\"data\\": {\\"policies\\": ${POLICIES:-[\\"root\\"]}, \\"expire_time\\": ${EXPIRE:-null}}}"')
one_active = lambda act: sh(render(oa["ansible.builtin.shell"]["cmd"], groups=PIS, hostvars={"pi1": {"ansible_host": "10.0.0.4"}, "pi2": {"ansible_host": "10.0.0.6"}}),
                            ACTIVE=act).returncode
check("  exactly one Vault active, both Pis read together and again until one says so (a carried lock frees in under a minute): "
      "one - on; none, or both - not yet", ([one_active(a) for a in ("10.0.0.4", "10.0.0.6", "", "10.0.0.4 10.0.0.6")],
                                           oa.get("retries"), oa.get("until"), oa.get("run_once")), ([0, 0, 1, 1], 24, "_one_active.rc == 0", True))
rtk = bt("The root token works")
def token_run(content, **env):
    tf = os.path.join(work, "root-token")
    if os.path.exists(tf):
        os.remove(tf)
    if content is not None:
        open(tf, "w").write(content)
    cmd = render(rtk["ansible.builtin.shell"]["cmd"], vault_api="https://127.0.0.1:8200").replace("/etc/vault-unseal/root-token", tf)
    home = os.path.join(work, "home"); os.makedirs(home, exist_ok=True)
    open(os.path.join(home, ".vault-token"), "w").write("hvs.root")  # a token helper's file that would answer for a missing one
    return sh(cmd, HOME=home, **env).returncode
check("  the root token proven on Vault now (the token store carried - a snapshot's may predate it), never logged: a root token "
      "that never expires - on; another token, not root, one that expires, an empty or missing file - failed",
      ([token_run("hvs.root"), token_run("hvs.other") != 0, token_run("hvs.root", POLICIES='["default"]') != 0,
        token_run("hvs.root", EXPIRE='"2026-12-01T00:00:00Z"') != 0, token_run("") != 0, token_run(None) != 0], rtk.get("no_log"),
       "/etc/vault-unseal/root-token" in rtk["ansible.builtin.shell"]["cmd"]), ([0, True, True, True, True, True], True, True))
hp = V["healthy_py"]
health = lambda m: subprocess.run(["python3", "-c", hp], input=json.dumps(m), capture_output=True, text=True).returncode
LD = {"Member": "pi1", "Role": "Leader", "State": "running"}
check("Patroni healthy: a leader running and the replica streaming with no lag - a lagging, stopped or missing replica, no leader, "
      "or two - not", [health(m) for m in ([LD, {"Member": "pi2", "Role": "Replica", "State": "streaming", "Replay Lag": 0}],
                                          [LD, {"Member": "pi2", "Role": "Replica", "State": "streaming", "Replay Lag": 4096}],
                                          [LD, {"Member": "pi2", "Role": "Replica", "State": "stopped", "Replay Lag": 0}], [LD],
                                          [{"Member": "pi2", "Role": "Replica", "State": "streaming", "Replay Lag": 0}], [LD, dict(LD, Member="pi2")])],
      [0, 1, 1, 1, 1, 1])
check("  not paused after (its own check), no marker left - else failed",
      (bt("Not paused")["ansible.builtin.script"]["cmd"].endswith("patroni-pause.py check"),
       [condition(bt("No pause marker left")["failed_when"], _marker_after={"rc": r}) for r in (0, 1)]), (True, [True, False]))
hx = bt("The primary answering through HAProxy")
tool("systemctl", 'echo "${BOUNCER:-disabled}"')
open(os.path.join(work, "psql.log"), "w").close()
hxr = lambda **e: sh(render(hx["ansible.builtin.shell"]["cmd"], primary_through_proxies=V["primary_through_proxies"]), "right\n", **e).returncode
r_ok = hxr(BOUNCER="enabled")
ports_seen = sorted({l.split("-p ")[1].split()[0] for l in open(os.path.join(work, "psql.log")).read().splitlines()})
check("  the primary through HAProxy (:5000) and PgBouncer (:6432, where enabled - a failed one is no skip) - a standby on either "
      "fails; the password on stdin, never logged",
      (r_ok, ports_seen, hxr(BOUNCER="enabled", PSQL_NO="6432"), hxr(PSQL_NO="5000"), hx.get("no_log"), hx["ansible.builtin.shell"].get("stdin")),
      (0, ["5000", "6432"], 1, 1, True, "{{ postgres_admin_password }}"))

# ── more of what each step does ──────────────────────────────────────────────────────────────────────────────
hl = bt("The cluster healthy - a leader running")
tool("patronictl", 'echo "$PATRONI_LIST"')
def healthy_run(members):
    return sh(render(hl["ansible.builtin.shell"]["cmd"], patronictl="patronictl -c x", healthy_py=V["healthy_py"]), PATRONI_LIST=json.dumps(members)).returncode
check("the cluster's health read through patronictl's own list and judged - a healthy one on; a lagging replica, or none, failed",
      [healthy_run(m) for m in ([LD, {"Member": "pi2", "Role": "Replica", "State": "streaming", "Replay Lag": 0}],
                                [LD, {"Member": "pi2", "Role": "Replica", "State": "streaming", "Replay Lag": 9}], [LD])], [0, 1, 1])
lkt = bt("It holds the leader key")
check("  the leader key read raw (its value the member's name, not Consul's JSON)",
      (lkt["ansible.builtin.uri"]["url"].endswith("/leader?raw"), lkt["ansible.builtin.uri"].get("return_content")), (True, True))
tl = bt("The Consul-locked jobs' timers started again")
check("  the timers started again over every timer read (enabled or not), the record removed at the end",
      (render(tl["loop"], _lock_timers={"results": [{"item": "pi-tier0-backup", "stdout": "enabled"}, {"item": "pi-restore-check", "stdout": "disabled"}]}),
       bt("The record removed")["ansible.builtin.file"]),
      ([{"item": "pi-tier0-backup", "stdout": "enabled"}, {"item": "pi-restore-check", "stdout": "disabled"}], {"path": "{{ restore_state }}", "state": "absent"}))
check("  the play on the three servers; Postgres's role the local server's own answer (not in recovery = the primary); Vault's standby "
      "an answer (429), not a failure; the kept binary asked its version, copied over /usr/local/bin/consul; the pause on the primary's Pi",
      (RP["hosts"], "'select not pg_is_in_recovery()'" in rt("Postgres running here")["ansible.builtin.shell"]["cmd"],
       bt("Vault unsealed - active or standby")["ansible.builtin.uri"]["status_code"], rt("The binary of the version gone back to")["ansible.builtin.command"]["argv"],
       bt("The kept binary back")["ansible.builtin.copy"]["dest"], bt("Patroni paused").get("delegate_to")),
      ("pi1,pi2,target", True, [200, 429], ["/usr/local/bin/consul-{{ _to }}", "version"], "/usr/local/bin/consul", "{{ _pg_primary }}"))
check("  a record of another source's load is no load of this one",
      render(hr, _from_record=True, _recorded=SNAP, _record={"stdout": REC.replace(os.path.basename(SNAP), "consul-20261101T000000Z-1.22.5.snap")}, _agent=ok_agent, _to="1.22.7"),
      False)
# the controller's copies: upgrade-consul.yml's snapshot and this export, one directory per inventory, the operator's alone, ignored by git
U = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-consul.yml"))[0]
UT = U["tasks"]
ut = lambda name: next(t for t in UT if str(t.get("name", "")).startswith(name))
uf, ul = ut("The snapshot fetched to the controller"), ut("The controller's copy the operator's alone")
check("upgrade-consul: the snapshot fetched off pi1 to the controller after it is taken and before any server restarts, the directory "
      "0700 and the file 0600 there",
      (uf["ansible.builtin.fetch"], uf.get("when"), UT.index(ut("The whole state's snapshot first")) < UT.index(uf) < UT.index(ut("One at a time")),
       [render(x["mode"]) for x in ul["loop"]], [render(x["path"], backups_here="/b", _snapshot={"stdout": "/s/consul-x-1.22.7.snap"}) for x in ul["loop"]],
       ul.get("delegate_to"), ul.get("become"), ul.get("when")),
      ({"src": "{{ _snapshot.stdout }}", "dest": "{{ backups_here }}/", "flat": True, "fail_on_missing": True}, "inventory_hostname == 'pi1'", True,
       ["0700", "0600"], ["/b", "/b/consul-x-1.22.7.snap"], "localhost", False, "inventory_hostname == 'pi1' and not ansible_check_mode"))
here = lambda vars_, inv: render(vars_["backups_here"], playbook_dir="/o/deploy/ansible/playbooks", inventory_file=inv)
check("  both playbooks' controller directory the same, one per inventory (the copy's never beside production's); git ignores it",
      ([here(v, "/o/deploy/ansible/inventory/production.yml") for v in (U["vars"], V)], here(V, "/o/deploy/ansible/inventory/vagrant.yml"),
       "deploy/ansible/vars/consul-upgrade-backups/" in open(".gitignore").read().splitlines()),
      (["/o/deploy/ansible/playbooks/../vars/consul-upgrade-backups/production"] * 2, "/o/deploy/ansible/playbooks/../vars/consul-upgrade-backups/vagrant", True))
check("  restore-consul: the export fetched off its server, flat, failing when missing",
      (bt("The export fetched to the controller")["ansible.builtin.fetch"], bt("The export fetched to the controller").get("delegate_to")),
      ({"src": "{{ _src }}", "dest": "{{ backups_here }}/", "flat": True, "fail_on_missing": True}, "{{ _src_host }}"))

# ── the rescue and the end ───────────────────────────────────────────────────────────────────────────────────────
resc = lambda **v: render(blk["rescue"][0]["ansible.builtin.fail"]["msg"], ansible_failed_task={"name": "The export imported"},
                          ansible_failed_result={"msg": "boom"}, _pg_primary="pi1", consul_data="/var/lib/consul/data", _from="2.0.4",
                          _src_host="pi1", restore_state=V["restore_state"], pause_marker=V["pause_marker"], **v)
r1 = resc(_set_aside={"stdout_lines": ["/var/lib/consul/data.pre-restore-T1"]}, _orig_aside="", _src=KV, _recorded="")
r2 = resc(_orig_aside="/var/lib/consul/data.pre-restore-T1", _recorded=KV)
r0 = resc(_orig_aside="", _recorded="", _snap=SNAP)
check("  the way forward in full: the current directory moved aside (never deleted), the record deleted, the primary's Patroni first",
      [x in r1 for x in ("move /var/lib/consul/data aside (never delete it)", "/usr/local/bin/consul, delete /var/lib/consul/restore-consul.state, start Consul",
                         "(pi1 first)")], [True] * 3)
def messages(plays):
    """every assert's fail_msg and success_msg, rendered with the hostvars the copy check reads - a string each (a list of pairs
    is no message: the module refuses it whether or not the assertion holds - the Vault rehearsal's first run, 2026-11-27)"""
    out = []
    hv_ = {"pi1": {"_vault": {"status": 200}, "_pg_after": {"stdout": "t|3"}}, "pi2": {"_vault": {"status": 429}, "_pg_after": {"stdout": "f|3"}}}
    for play in plays[1:]:
        for t in play["tasks"]:
            a = t.get("ansible.builtin.assert")
            for k in ("fail_msg", "success_msg"):
                if a and k in a:
                    # the noted file's lookup as its content (a bare templar has no lookup plugins)
                    v = render(a[k].replace("lookup('ansible.builtin.file', pg_noted)", "'pi1 t|3'"), groups=PIS, hostvars=hv_, ansible_play_hosts=HOSTS, marker="way-back-1Z", mode="current", consul_version="1.22.7",
                               _markers={"stdout_lines": []}, _value={"stdout": ""}, _now="pi1 t|3", pg_noted="/dev/null", consul_to="2.0.4",
                               _want=["x"])
                    out.append((t["name"][:40], k, isinstance(v, str), type(v).__name__))
    return [o for o in out if not o[2]]
check("the rescue: where it failed, Postgres unmanaged and the primary, the untouched source, the state before (this run's set-aside, "
      "or the record's on a run again), run again, forward again in full (the directory back, the new binary, the pause resumed and "
      "its marker deleted, Vault enabled, the timers), never deploy:vault-pi",
      ([x in r1 for x in ('"The export imported"', "boom", "unmanaged", "pi1 the primary", KV, "/var/lib/consul/data.pre-restore-T1",
                          "task deploy:consul:way-back again", "Forward again", "/usr/local/lib/consul-2.0.4/consul", "patronictl resume",
                          "consul kv delete ansible/patroni-paused-by", "enable --now vault vault-unseal", "pi-tier0-backup.timer",
                          "Never task deploy:vault-pi", "the primary at the start", "do not start it before running again",
                          "apt-daily-upgrade.timer")],
       "/var/lib/consul/data.pre-restore-T1" in r2 and KV in r2, "not set aside yet" in r0 and SNAP in r0),
      ([True] * 17, True, True))
done = lambda m: render(rt("Back - and what to run again")["ansible.builtin.debug"]["msg"], _to="1.22.7", _from="2.0.4", _mode=m,
                        ansible_play_hosts=HOSTS, _src=KV if m == "current" else SNAP, _set_aside={"stdout_lines": ["/d.pre-restore-T1"]},
                        _orig_aside="", _pg_primary="pi1", _one_active={"stdout": "active: 10.0.0.4"})
check("the end names the primary and Vault's active", ["Patroni's leader pi1" in done("current"), "active: 10.0.0.4" in done("current")], [True, True])
check("the end: what was loaded and whether anything was lost; after a snapshot, what to run again (the rotated tokens back stale, "
      "preview environments, External Secrets, Patroni's settings) - after the current KV, nothing",
      ([x in done("snapshot") for x in ("everything written since lost", "task deploy:ci-bot", "task deploy:argocd-reader", "preview environments",
                                         "force-sync", "edit-config", "/d.pre-restore-T1")],
       ["nothing in the KV lost" in done("current"), "deploy:ci-bot" in done("current")]), ([True] * 7, [True, False]))
check("  a run without every server failing everywhere (any_errors_fatal)", RP.get("any_errors_fatal"), True)

# ── the copy's rehearsal ─────────────────────────────────────────────────────────────────────────────────────────
CW = yaml.safe_load(open("tests/ansible/copy/consul-way-back-check.yml"))
check("the rehearsal behind the Vagrant guard first (it guards every host), then the servers' play, then External Secrets' on the node",
      (CW[0].get("ansible.builtin.import_playbook"), len(CW), CW[1].get("hosts"), CW[2].get("hosts")), ("../vagrant-only-play.yml", 3, "pi1,pi2,target", "target"))
C = CW[1]["tasks"]
ct = lambda name: next(t for t in C if str(t.get("name", "")).startswith(name))
first_chk = C[0]["ansible.builtin.assert"]["that"]
check("  a phase, a marker name and a mode required (the task's)",
      [condition(first_chk, **v) for v in ({"phase": "verify", "marker": "way-back-20261127T010000Z"}, {"phase": "after", "marker": "way-back-1Z", "mode": "snapshot"},
                                          {"phase": "x", "marker": "way-back-1Z"}, {"phase": "before"}, {"phase": "before", "marker": "way-back-1Z", "mode": "both"})],
      [True, True, False, False, False])
check("  each phase's tasks run in that phase alone",
      sorted({str(t.get("when")).split(" and ")[0] for t in C[1:]}), ["phase == 'after'", "phase == 'before'", "phase == 'cleanup'", "phase == 'verify'",
                                                                      "phase in ['before', 'verify']"])
check("  before: a newer target required; after: the second marker written then",
      ([condition(ct("Before - a newer version")["ansible.builtin.assert"]["that"], consul_version="1.22.7", **({} if k is None else {"consul_to": k}))
        for k in ("2.0.4", "1.22.7", None)], ct("After - the marker from after")["ansible.builtin.command"]["argv"][-2:], ct("After - the marker from after").get("when")),
      ([True, False, False], ["way-back/{{ marker }}-after", "after"], "phase == 'after'"))
sw = ct("After - a switchover to the replica")["ansible.builtin.shell"]["cmd"]
tool("patronictl", 'echo "$*" >> "$W/patronictl.log"; case "$*" in *"list -f json"*) echo \'[{"Member": "pi1", "Role": "Leader", "State": "running"}, {"Member": "pi2", "Role": "Replica", "State": "streaming"}]\' ;; esac')
r = sh(render(sw, patronictl="patronictl -c x"))
check("  after: a switchover from the leader to the replica (the snapshot's leader key then names a Pi no longer the primary), "
      "waited on until the new primary serves", (r.stdout.strip(), "switchover --leader pi1 --candidate pi2 --force" in open(os.path.join(work, "patronictl.log")).read(),
                                                 "_switched.stdout" in ct("After - the new primary serving")["ansible.builtin.shell"]["cmd"]), ("pi2", True, True))
noted = render(ct("After - noted on the controller")["ansible.builtin.copy"]["content"], groups=PIS,
               hostvars={"pi1": {"_pg_before": {"stdout": "f|3"}}, "pi2": {"_pg_before": {"stdout": "t|3"}}})
same = ct("Verify - the same primary on the same timeline")
same_now = lambda a, b: render(same["vars"]["_now"], groups=PIS, hostvars={"pi1": {"_pg_after": {"stdout": a}}, "pi2": {"_pg_after": {"stdout": b}}}).strip()
check("  the primary and its timeline noted after the switchover, and the same wanted after the way back - a failover (another primary) "
      "or a promotion (another timeline) fails", (noted.strip(), same_now("f|3", "t|3"), same_now("t|4", "f|4"), same_now("f|3", "t|4"),
                                                  "lookup('ansible.builtin.file', pg_noted)" in same["ansible.builtin.assert"]["that"]),
      ("pi2 t|3", "pi2 t|3", "pi1 t|4", "pi2 t|4", True))
check("  the restore's confirmation: the pin's name for the current KV, the newest snapshot's for a snapshot",
      [render(ct("After - the restore's confirmation")["ansible.builtin.copy"]["content"], mode=m, consul_version="1.22.7", _newest={"stdout": SNAP}).strip()
       for m in ("current", "snapshot")], ["consul-1.22.7", os.path.basename(SNAP)])
mk = ct("Verify - the marker from before there")
want = lambda m: render(mk["vars"]["_want"], marker="way-back-1Z", mode=m)
check("  verify: the first marker kept with its value; the second kept for the current KV, gone for the snapshot",
      [condition(mk["ansible.builtin.assert"]["that"], marker="way-back-1Z", mode=m, _want=want(m), _markers={"stdout_lines": ms}, _value={"stdout": v})
       for m, ms, v in (("current", ["way-back/way-back-1Z-after", "way-back/way-back-1Z-before"], "before\n"), ("current", ["way-back/way-back-1Z-before"], "before"),
                        ("snapshot", ["way-back/way-back-1Z-before"], "before"), ("snapshot", ["way-back/way-back-1Z-after", "way-back/way-back-1Z-before"], "before"),
                        ("snapshot", ["way-back/way-back-1Z-before"], "after"))],
      [True, False, True, False, False])
tm = ct("Verify - the tier-0 backup and restore-check timers")["ansible.builtin.shell"]["cmd"]
tool("systemctl", 'case "$1 $2" in "is-enabled pi-tier0-backup.timer") echo "${E1:-enabled}" ;; "is-enabled pi-restore-check.timer") echo "${E2:-enabled}" ;; '
                  '"is-active pi-tier0-backup.timer") echo "${A1:-active}" ;; "is-active pi-restore-check.timer") echo "${A2:-active}" ;; esac')
check("  verify: the locked jobs' timers active again where enabled - one enabled and stopped fails; a disabled one stopped is fine",
      [sh(tm, **e).returncode for e in ({}, {"A2": "inactive"}, {"E2": "disabled", "A2": "inactive"})], [0, 1, 0])
check("  verify: Patroni healthy, not paused, no marker; the database writable through each Pi's HAProxy (a transaction id); one Vault active",
      ("patronictl" in ct("Verify - Patroni healthy")["ansible.builtin.shell"]["cmd"], ct("Verify - Patroni not paused")["ansible.builtin.script"]["cmd"].endswith("patroni-pause.py check"),
       [condition(ct("Verify - no pause marker left")["failed_when"], _marker_left={"rc": r}) for r in (0, 1)],
       "txid_current()" in ct("Verify - the database writable")["ansible.builtin.shell"]["cmd"] and "-p 5000" in ct("Verify - the database writable")["ansible.builtin.shell"]["cmd"],
       [condition(ct("Verify - exactly one Vault active")["ansible.builtin.assert"]["that"], groups=PIS,
                  hostvars={"pi1": {"_vault": {"status": a}}, "pi2": {"_vault": {"status": b}}}) for a, b in ((200, 429), (429, 429), (200, 200))]),
      (True, True, [True, False], True, [True, False, False]))
check("  cleanup: both markers deleted by their prefix", ct("Cleanup - both markers gone")["ansible.builtin.command"]["argv"],
      ["consul", "kv", "delete", "-recurse", "way-back/{{ marker }}-"])
E = CW[2]["tasks"]
et = lambda name: next(t for t in E if str(t.get("name", "")).startswith(name))
synced = et("Verify - refreshed after that and Ready")["until"]
check("  External Secrets: its store Ready; an ExternalSecret force-synced now, refreshed AFTER the force and Ready",
      ([condition(synced, _since={"stdout_lines": ["2026-11-27T10:00:00Z"]}, _synced={"stdout": o})
        for o in ("2026-11-27T10:00:05Z True", "2026-11-27T09:59:00Z True", "2026-11-27T10:00:05Z False", "")],
       all(t.get("when") == "phase == 'verify'" for t in E)), ([True, False, False, False], True))
task_cmd = open("Taskfile.yml").read().split("  test:copy:consul-way-back:")[1].split("\n\n")[0]
seq = [l.strip() for l in task_cmd.splitlines() if l.strip().startswith("pb ")]
check("  the task: before, production's upgrade-consul.yml to the target, after, production's restore-consul.yml from the mode's source "
      "with the confirmation the check wrote, verify, cleanup - each production playbook behind the Vagrant guard, secrets kept out, "
      "cleanup on failure too; the mode current unless asked, nothing else taken",
      ([("phase=" + l.split("phase=")[1].split()[0]) if "phase=" in l else l.split()[2].split("/")[-1] for l in seq],
       all("vagrant-only-play.yml" in l for l in seq if "playbooks/" in l), "env -i" in task_cmd,
       "trap 'pb \"$C\" -e phase=cleanup -e marker=\"$M\"' EXIT" in task_cmd and "trap - EXIT" in task_cmd,
       "consul_restore_from='{{.MODE}}'" in seq[3] and "consul-way-back-confirm" in seq[3], all("mode='{{.MODE}}'" in seq[i] for i in (0, 2, 4)),
       """MODE: '{{.MODE | default "current"}}'""" in task_cmd, '[ "{{.MODE}}" = current ] || [ "{{.MODE}}" = snapshot ]' in task_cmd),
      (["phase=before", "upgrade-consul.yml", "phase=after", "restore-consul.yml", "phase=verify", "phase=cleanup"], True, True, True, True, True, True, True))
phases = {t["name"]: str(t.get("when")).split(" and ")[0] for t in C[1:]}
check("  each copy-check task in its own phase",
      {n: phases[n] for n in phases if n.split(" - ")[0] in ("Before", "After", "Verify", "Cleanup", "Before and verify")}
      == {n: {"Before": "phase == 'before'", "After": "phase == 'after'", "Verify": "phase == 'verify'", "Cleanup": "phase == 'cleanup'",
              "Before and verify": "phase in ['before', 'verify']"}[n.split(" - ")[0]] for n in phases}, True)
check("  the markers: the one written before is the one verify reads, with the value it wants",
      (ct("Before - the marker from before")["ansible.builtin.command"]["argv"], ct("Verify - the value of the one from before")["ansible.builtin.command"]["argv"]),
      (["consul", "kv", "put", "way-back/{{ marker }}-before", "before"], ["consul", "kv", "get", "way-back/{{ marker }}-before"]))
sql = "select not pg_is_in_recovery(), (select timeline_id from pg_control_checkpoint())"
tlq = [ct(n)["ansible.builtin.shell"]["cmd"] for n in ("After - the primary and its timeline noted", "Verify - the primary and its timeline as noted")]
check("  the timeline read the same way both times - a checkpoint first (a promotion's control file lags its end-of-recovery checkpoint), "
      "then the role and the checkpoint's timeline", [("-qc checkpoint" in q and q.index("-qc checkpoint") < q.index(sql)) for q in tlq], [True, True])
tool("patronictl", 'echo "$PATRONI_LIST"')  # the list each case hands it
sw_wait = ct("After - the new primary serving")["ansible.builtin.shell"]["cmd"]
def settled_run(members):
    return sh(render(sw_wait, patronictl="patronictl -c x", _switched={"stdout": "pi2\n"}), PATRONI_LIST=json.dumps(members)).returncode
P2 = {"Member": "pi2", "Role": "Leader", "State": "running"}
check("  after the switchover: waited on until the new primary leads and the old one streams from it - else not yet",
      [settled_run(m) for m in ([P2, {"Member": "pi1", "Role": "Replica", "State": "streaming"}], [LD, {"Member": "pi2", "Role": "Replica", "State": "streaming"}],
                                [P2, {"Member": "pi1", "Role": "Replica", "State": "starting"}])], [0, 1, 1])
vp = ct("Verify - Patroni healthy")["ansible.builtin.shell"]["cmd"]
check("  verify: Patroni healthy read and judged - a leader running and the replica streaming on; no leader, or the replica stopped, failed",
      [sh(render(vp, patronictl="patronictl -c x"), PATRONI_LIST=json.dumps(m)).returncode for m in (
          [LD, {"Member": "pi2", "Role": "Replica", "State": "streaming"}], [{"Member": "pi2", "Role": "Replica", "State": "streaming"}],
          [LD, {"Member": "pi2", "Role": "Replica", "State": "stopped"}])], [0, 1, 1])
check("  verify: a standby Vault an answer (429); the marker looked for the one patroni-pause.py writes; the database's password on stdin; "
      "the noted file the one verify reads; the newest snapshot by name; the ExternalSecret forced the one read",
      (ct("Verify - Vault unsealed")["ansible.builtin.uri"]["status_code"], ct("Verify - no pause marker left")["ansible.builtin.command"]["argv"][-1] == V["pause_marker"],
       ct("Verify - the database writable")["ansible.builtin.shell"].get("stdin"), ct("After - noted on the controller")["ansible.builtin.copy"]["dest"],
       "pg_noted" in same["ansible.builtin.assert"]["that"], "LC_ALL=C sort" in ct("After - the newest snapshot")["ansible.builtin.shell"]["cmd"],
       "externalsecret vault-cleanup-token" in et("Verify - an ExternalSecret force-synced")["ansible.builtin.shell"]["cmd"]
       and "vault-cleanup-token" in et("Verify - refreshed after that")["ansible.builtin.command"]["argv"]),
      ([200, 429], True, "{{ postgres_admin_password }}", "{{ pg_noted }}", True, True, True))
def dry(*args):
    r = subprocess.run(["task", "--dry", "--yes", *args], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
rc_c, out_c = dry("test:copy:consul-way-back", "CONSUL_TO=2.0.4", "CONSUL_TO_SHA256=abc")
rc_s, out_s = dry("test:copy:consul-way-back", "CONSUL_TO=2.0.4", "CONSUL_TO_SHA256=abc", "MODE=snapshot")
rc_b, out_b = dry("test:copy:consul-way-back", "CONSUL_TO=2.0.4", "CONSUL_TO_SHA256=abc", "MODE=both")
rc_n, out_n = dry("test:copy:consul-way-back", "CONSUL_TO=2.0.4")
rc_p, out_p = dry("deploy:consul:way-back")
check("the tasks as task renders them: the copy's from the current KV unless MODE=snapshot, anything else refused, both its inputs required, "
      "set -euo pipefail, the copy's inventory, the target's checksum handed to the upgrade; production's on production's inventory and restore-consul.yml",
      (rc_c, "consul_restore_from='current'" in out_c and "-e mode='current'" in out_c, rc_s, "consul_restore_from='snapshot'" in out_s,
       rc_b != 0 and "MODE=current|snapshot" in out_b, rc_n != 0, "set -euo pipefail" in out_c, out_c.count("-i inventory/vagrant.yml") == 1 and "production.yml" not in out_c,
       """-e '{"consul_checksums": {"amd64": "abc"}}'""" in out_c, rc_p, "venv/bin/ansible-playbook -i inventory/production.yml playbooks/restore-consul.yml" in out_p,
       "\n    prompt: " in open("Taskfile.yml").read().split("  deploy:consul:way-back:")[1].split("\n\n")[0],
       "flock -n -E 75 ../../.copy/consul-way-back.lock venv/bin/ansible-playbook" in out_p),
      (0, True, 0, True, True, True, True, True, True, 0, True, True, True))
check("  every copy-check assert's message renders to a string", messages(CW), [])
print("consul-way-back: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_CWB
