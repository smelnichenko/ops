#!/bin/bash
# Consul's way back: restore-consul.yml - every server in its run, the snapshot it restores (the newest on pi1 by name,
# or the one given) and the version from its name, its refusals before anything stops (no snapshot, the unit not
# reverted, not confirmed by name, the old binary gone, a snapshot that binary cannot read, Postgres not one primary,
# Patroni paused already, a job holding a Consul lock), the data directory set aside (its node-id and keyring carried
# over, nothing deleted), Patroni's stale keys deleted against a stubbed consul (its leader and members alone), and the
# order - Patroni paused then stopped, Vault stopped, Consul replaced, the snapshot restored, Patroni started on the
# primary first, Vault unsealed; then the copy's rehearsal (the Vagrant guard, its phases, its task's sequence and cleanup).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_CWB'
import os, subprocess, sys, tempfile
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
def flat(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from flat(t.get(k))
R = list(flat(RP["tasks"]))
rt = lambda name: next(t for t in R if str(t.get("name", "")).startswith(name))
idx = R.index
blk = rt("The restore - from the first stop")
PIS = {"pis": ["pi1", "pi2"]}

# ── which snapshot, and its version ──────────────────────────────────────────────────────────────────────────────
check("every server in the run: pi1, pi2 and ten (target) - on; one left out (--limit) - refused",
      [condition(rt("Every server in the run")["ansible.builtin.assert"]["that"], consul_servers=["pi1", "pi2", "target"], ansible_play_hosts=h)
       for h in (["pi1", "pi2", "target"], ["target", "pi2", "pi1"], ["pi1", "pi2"])], [True, True, False])
check("  its servers as upgrade-consul.yml names them, the pin read from setup-consul.yml, Patroni's scope from setup-patroni.yml",
      (RP["vars"]["consul_servers"], yaml.safe_load(open("deploy/ansible/playbooks/upgrade-consul.yml"))[0]["vars"]["consul_servers"],
       "setup-consul.yml" in RP["vars"]["_setup"], "setup-patroni.yml" in RP["vars"]["patroni_scope"]),
      (["pi1", "pi2", "target"], ["pi1", "pi2", "target"], True, True))
nw = rt("The newest snapshot on pi1")
sd = os.path.join(work, "snaps"); os.makedirs(sd)
for n, t in (("consul-20261127T010000Z-1.22.7.snap", 1000), ("consul-20261126T010000Z-1.22.6.snap", 2000)):
    open(os.path.join(sd, n), "w").write("x"); os.utime(os.path.join(sd, n), (t, t))
newest = lambda: subprocess.run(["bash", "-c", render(nw["ansible.builtin.shell"]["cmd"], upgrade_dir=sd)], capture_output=True, text=True).stdout.strip()
got_newest = newest()
for n in os.listdir(sd): os.remove(os.path.join(sd, n))
check("the newest snapshot by its name (its UTC time) - never by mtime; none - nothing; read on pi1 (where upgrade-consul leaves it)",
      (os.path.basename(got_newest), newest(), nw.get("delegate_to")), ("consul-20261127T010000Z-1.22.7.snap", "", "pi1"))
pick = rt("The snapshot restored - the one given")
A = "/var/backups/consul-upgrade/consul-20261127T010000Z-1.22.7.snap"
def chosen(newest_out, given=None):
    path = render(pick["vars"]["_snap_path"], _newest={"stdout": newest_out}, **({} if given is None else {"consul_restore_snapshot": given}))
    return (render(pick["ansible.builtin.set_fact"]["_snap"], _snap_path=path).strip(),
            render(pick["ansible.builtin.set_fact"]["_snap_version"], _snap_path=path).strip())
check("  the newest, or the one given; its version from its name; a name not a snapshot's - no version; none - empty",
      [chosen(A), chosen(A, "/x/consul-20261101T000000Z-1.22.5.snap"), chosen("/x/other.snap"), chosen("")],
      [(A, "1.22.7"), ("/x/consul-20261101T000000Z-1.22.5.snap", "1.22.5"), ("/x/other.snap", ""), ("", "")])
known = rt("A snapshot and its version known")["ansible.builtin.assert"]["that"]
pin = rt("The unit reverted first")["ansible.builtin.assert"]["that"]
conf = rt("Confirmed by naming the snapshot")["ansible.builtin.assert"]["that"]
kept = rt("Every server has it")["ansible.builtin.assert"]["that"]
check("refused before anything stops without a snapshot or a version, until the unit is reverted, confirmed by the snapshot's "
      "name, and the kept binary there AND that version",
      ([condition(known, _snap=p, _snap_version=v) for p, v in ((A, "1.22.7"), ("", "1.22.7"), (A, ""))],
       [condition(pin, consul_version=k, _snap_version="1.22.7") for k in ("1.22.7", "2.0.4")],
       [condition(conf, _snap=A, **({} if c is None else {"confirm": c})) for c in (os.path.basename(A), "other", None)],
       [condition(kept, _kept=k, _snap_version="1.22.7") for k in (
           {"rc": 0, "stdout": "Consul v1.22.7\nRevision abc", "stdout_lines": ["Consul v1.22.7", "Revision abc"]},
           {"rc": 0, "stdout": "Consul v2.0.4\nRevision abc", "stdout_lines": ["Consul v2.0.4", "Revision abc"]},
           {"rc": 0, "stdout": "Revision abc\nConsul v1.22.7", "stdout_lines": ["Revision abc", "Consul v1.22.7"]},
           {"rc": 2, "stdout": "", "stdout_lines": [], "stderr": "No such file"}, {})]),
      ([True, False, False], [True, False], [True, False, False], [True, False, False, False, False]))
ins = rt("The snapshot there and readable by that binary")
check("  the snapshot read by the kept binary itself (consul snapshot inspect), on pi1, before anything stops",
      (rt("The snapshot's version's binary kept here")["ansible.builtin.command"]["argv"], ins["ansible.builtin.command"]["argv"],
       ins.get("delegate_to"), max(idx(rt("The snapshot's version's binary kept here")), idx(ins)) < idx(blk)),
      (["/usr/local/bin/consul-{{ _snap_version }}", "version"],
       ["/usr/local/bin/consul-{{ _snap_version }}", "snapshot", "inspect", "{{ _snap }}"], "pi1", True))

# ── Postgres's primary, Patroni and the Consul-locked jobs - read before anything stops ──────────────────────────
one = rt("Exactly one primary, both Postgres running")["ansible.builtin.assert"]["that"]
roles = lambda a, b: {"pi1": {"_pg_role": a}, "pi2": {"_pg_role": b}}
P, S, DOWN = {"rc": 0, "stdout": "t"}, {"rc": 0, "stdout": "f"}, {"rc": 2, "stdout": "", "stderr": "no socket"}
check("Postgres named by itself: one primary and a running replica - on; two primaries, none, one down - refused",
      [condition(one, groups=PIS, hostvars=roles(a, b)) for a, b in ((P, S), (S, P), (P, P), (S, S), (P, DOWN))],
      [True, True, False, False, False])
prim = rt("The primary's Pi")["ansible.builtin.set_fact"]["_pg_primary"]
check("  the primary's Pi the one out of recovery",
      [render(prim, groups=PIS, hostvars=roles(a, b)).strip() for a, b in ((P, S), (S, P))], ["pi1", "pi2"])
check("  read through the local socket as postgres (Patroni may be stopped by an earlier run), never failing the read itself",
      ("runuser -u postgres -- psql -w -h /var/run/postgresql" in rt("Postgres running here")["ansible.builtin.shell"]["cmd"],
       rt("Postgres running here").get("failed_when"), idx(rt("Exactly one primary")) < idx(blk)), (True, False, True))
runs = rt("Whether any Patroni runs")["ansible.builtin.set_fact"]["_patroni_runs"]
act = lambda a, b: {"pi1": {"_patroni_active": {"stdout": a}}, "pi2": {"_patroni_active": {"stdout": b}}}
check("Patroni running on either Pi - the pause wanted; on neither (an earlier run of this play stopped it) - no pause",
      [render(runs, groups=PIS, hostvars=act(a, b)) for a, b in (("active", "active"), ("inactive", "active"), ("inactive", "failed"))],
      [True, True, False])
pchk, pause = rt("Patroni not paused already"), rt("Patroni paused - stopped next")
check("  not paused already (someone's maintenance) checked before anything stops; the pause this run's marker; both only where it runs",
      (pchk["ansible.builtin.script"]["cmd"].endswith("patroni-pause.py check"), idx(pchk) < idx(blk),
       pause["ansible.builtin.script"]["cmd"].endswith("patroni-pause.py pause consul-way-back"), pchk.get("when"), pause.get("when"),
       pchk.get("delegate_to"), pause.get("delegate_to")),
      (True, True, True, "_patroni_runs | bool", "_patroni_runs | bool", "{{ _pg_primary }}", "{{ _pg_primary }}"))
lj = rt("No job holding a Consul lock here now")
check("a tier-0 backup or a restore check running (its Consul lock) - refused before anything stops; idle or failed - on",
      ([condition(lj["failed_when"], _lock_jobs={"stdout": s}) for s in ("active", "activating", "deactivating", "inactive", "failed")],
       RP["vars"]["consul_lock_jobs"], idx(lj) < idx(blk)),
      ([True, True, True, False, False], ["pi-tier0-backup", "pi-restore-check"], True))

# ── the data directory set aside, nothing deleted ────────────────────────────────────────────────────────────────
asd = rt("Its data directory set aside")["ansible.builtin.shell"]["cmd"]
data = os.path.join(work, "consul", "data")
def aside_run():
    os.makedirs(os.path.join(data, "raft"), exist_ok=True); os.makedirs(os.path.join(data, "serf"), exist_ok=True)
    for f, v in (("node-id", "id-1"), ("raft/raft.db", "raft"), ("serf/local.keyring", "k1"), ("serf/remote.keyring", "k2")):
        open(os.path.join(data, f), "w").write(v)
    side = data + ".pre-restore-x"
    # not root here: the owner Consul's on the Pi, the moves the same
    r = subprocess.run(["bash", "-c", render(asd, consul_data=data, _aside=side).replace("-o consul -g consul ", "")], capture_output=True, text=True)
    listing = lambda d: sorted(os.path.relpath(os.path.join(p, f), d) for p, _, fs in os.walk(d) for f in fs)
    return r.returncode, listing(data), listing(side), open(os.path.join(data, "node-id")).read() if os.path.exists(os.path.join(data, "node-id")) else None
check("each server's data directory set aside whole (never deleted), a new one holding only its node-id and gossip keyring",
      aside_run(), (0, ["node-id", "serf/local.keyring", "serf/remote.keyring"],
                    ["node-id", "raft/raft.db", "serf/local.keyring", "serf/remote.keyring"], "id-1"))
check("  no rm anywhere in it; the time it is set aside under one for every server (run_once)",
      (" rm " not in " " + asd, rt("The time the data directories are set aside under").get("run_once")), (True, True))

# ── Patroni's stale keys, consul stubbed: its leader and members deleted, the rest kept ──────────────────────────
dk = rt("Patroni's leader and member keys from the snapshot deleted")
cbin = os.path.join(work, "cbin"); os.makedirs(cbin); clog = os.path.join(work, "consul.log")
open(os.path.join(cbin, "consul"), "w").write(f'#!/bin/bash\necho "$*" >> {clog}\n')
os.chmod(os.path.join(cbin, "consul"), 0o755)
r = subprocess.run(["bash", "-c", render(dk["ansible.builtin.shell"]["cmd"], patroni_scope="schnappy-postgres")], capture_output=True, text=True,
                   env=dict(os.environ, PATH=cbin + ":" + os.environ["PATH"]))
check("the snapshot's Patroni leader key and member keys deleted - its initialize, config and history kept - once, on pi1",
      (r.returncode, open(clog).read().splitlines(), dk.get("run_once"), dk.get("delegate_to")),
      (0, ["kv delete service/schnappy-postgres/leader", "kv delete -recurse service/schnappy-postgres/members/"], True, "pi1"))

# ── the order inside the block, and its rescue ───────────────────────────────────────────────────────────────────
B_ = blk["block"]
bt = lambda name: next(t for t in B_ if str(t.get("name", "")).startswith(name))
bi = B_.index
order = ["Their timers stopped", "Patroni paused", "Patroni stopped on both Pis", "Postgres still running on both",
         "Vault stopped on both Pis", "Neither started at a boot", "Consul stopped on every server", "Its data directory set aside",
         "The kept binary back", "Started - a new cluster", "The new cluster - three voters", "The snapshot restored",
         "After it - three voters", "Each agent on the snapshot's version", "Patroni's leader and member keys",
         "Patroni started on the primary's Pi first", "It holds the leader key", "Then on the replica", "The cluster healthy",
         "The primary answering through HAProxy", "Vault and its unseal enabled again", "Vault started", "Unsealed by the Pi's own script",
         "Vault unsealed - active or standby", "Each Vault sees a leader", "Exactly one Vault active", "The Consul-locked jobs' timers started again"]
check("the block: the jobs' timers off, Patroni paused THEN stopped (Postgres kept), Vault stopped and off at a boot, Consul "
      "stopped, set aside, the kept binary, a new cluster, the snapshot, healthy, Patroni's stale keys gone, the primary's Patroni "
      "first, the replica, the database through HAProxy, Vault unsealed, the timers back",
      [bi(bt(n)) for n in order] == sorted(bi(bt(n)) for n in order), True)
check("  Patroni started on the primary's Pi alone first, the replica after; the primary holding the leader key between",
      (bt("Patroni started on the primary's Pi first").get("when"), bt("It holds the leader key").get("when"),
       bt("Then on the replica").get("when")),
      ("inventory_hostname == _pg_primary", "inventory_hostname == _pg_primary",
       "inventory_hostname in groups['pis'] and inventory_hostname != _pg_primary"))
lk = bt("It holds the leader key")["until"]
check("  the leader key the primary's (its value its name); another Pi's, or none yet - not yet",
      [condition(lk, _leader_key={"status": s, "content": c}, _pg_primary="pi1") for s, c in ((200, "pi1"), (200, "pi1\n"), (200, "pi2"), (404, ""))],
      [True, True, False, False])
fresh, after = bt("The new cluster - three voters")["until"], bt("After it - three voters")["until"]
srv = lambda voters, leaders: [{"Voter": i < voters, "Leader": i < leaders, "Healthy": True} for i in range(3)]
check("  the new cluster: three voters and a leader (autopilot may still call it unhealthy); after the restore, healthy as well",
      ([condition(fresh, _fresh={"status": s, "json": {"Servers": srv(v, l), "Healthy": False}}) for s, v, l in ((429, 3, 1), (200, 2, 1), (200, 3, 0))],
       [condition(fresh, _fresh={"status": -1})],
       [condition(after, _after={"status": s, "json": {"Servers": srv(3, 1), "Healthy": h}}) for s, h in ((200, True), (429, False), (200, False))]),
      ([True, False, False], [False], [True, False, False]))
check("  the kept binary the snapshot's version's; the restore and both health reads on pi1, once",
      (bt("The kept binary back")["ansible.builtin.copy"]["src"], bt("The snapshot restored")["ansible.builtin.command"]["argv"],
       [bt(n).get("delegate_to") for n in ("The new cluster - three voters", "The snapshot restored", "After it - three voters")]),
      ("/usr/local/bin/consul-{{ _snap_version }}", ["consul", "snapshot", "restore", "{{ _snap }}"], ["pi1"] * 3))
pg = bt("Postgres still running on both")["ansible.builtin.shell"]["cmd"]
check("  after Patroni stopped: the primary still out of recovery, the replica still in it",
      [render(pg, inventory_hostname=h, _pg_primary="pi1").count(f'= "{w}"') for h, w in (("pi1", "t"), ("pi2", "f"))], [1, 1])
check("  Vault and its unseal off at a boot meanwhile, on again after; the timers started again only where they ran",
      (bt("Neither started at a boot")["loop"], bt("Neither started at a boot")["ansible.builtin.systemd"]["enabled"],
       bt("Vault and its unseal enabled again")["loop"], bt("Vault and its unseal enabled again")["ansible.builtin.systemd"]["enabled"],
       [condition(bt("The Consul-locked jobs' timers started again")["when"], item={"stdout": s}) for s in ("active", "inactive")],
       [condition(bt("Their timers stopped")["when"], item=i) for i in ({"stdout": "active"}, {"skipped": True})]),
      (["vault-unseal", "vault"], False, ["vault", "vault-unseal"], True, [True, False], [True, False]))
resc = render(blk["rescue"][0]["ansible.builtin.fail"]["msg"], ansible_failed_task={"name": "The snapshot restored"},
              ansible_failed_result={"msg": "boom"}, _aside="/var/lib/consul/data.pre-restore-x", _snap=A, _pg_primary="pi1",
              consul_data="/var/lib/consul/data")
check("  the rescue: where it failed, Postgres unmanaged and which is the primary, the set-aside directories and the untouched "
      "snapshot named, run it again with the same confirm, or forward again (put each directory back, the new binary, the "
      "primary's Patroni first)",
      [x in resc for x in ('"The snapshot restored"', "boom", "unmanaged", "pi1 the primary", "/var/lib/consul/data.pre-restore-x", A,
                           "task deploy:consul:way-back again", "Forward again", "on pi1 first", "REFUSED" not in resc and "FAILED")],
      [True] * 10)
done = render(rt("Restored - and what to run again")["ansible.builtin.debug"]["msg"], _snap_version="1.22.7",
              ansible_play_hosts=["pi1", "pi2", "target"], _snap=A, _aside="/var/lib/consul/data.pre-restore-x", _pg_primary="pi1",
              groups=PIS, hostvars={"pi1": {"_vault_leader": {"json": {"leader_address": "https://10.0.0.1:8200"}}}})
check("the end names what to run again (the rotated tokens back stale in Vault, preview environments, External Secrets, "
      "Patroni's dynamic settings) and where the old data lies",
      [x in done for x in ("task deploy:ci-bot", "task deploy:argocd-reader", "preview environments", "force-sync", "edit-config",
                           "/var/lib/consul/data.pre-restore-x")], [True] * 6)
check("  a run without every server failing everywhere (any_errors_fatal)", RP.get("any_errors_fatal"), True)

# ── the copy's rehearsal ─────────────────────────────────────────────────────────────────────────────────────────
CW = yaml.safe_load(open("tests/ansible/copy/consul-way-back-check.yml"))
check("the rehearsal behind the Vagrant guard first (it guards every host), then the servers' play, then External Secrets' on the node",
      (CW[0].get("ansible.builtin.import_playbook"), len(CW), CW[1].get("hosts"), CW[2].get("hosts")),
      ("../vagrant-only-play.yml", 3, "pi1,pi2,target", "target"))
C = CW[1]["tasks"]
ct = lambda name: next(t for t in C if str(t.get("name", "")).startswith(name))
first_chk = C[0]["ansible.builtin.assert"]["that"]
check("  a phase and a marker name required (the task's, one per run)",
      [condition(first_chk, **v) for v in ({"phase": "verify", "marker": "way-back-20261127T010000Z"}, {"phase": "x", "marker": "way-back-1Z"},
                                          {"phase": "before"}, {"phase": "before", "marker": "{{ lookup('pipe','date') }}"})],
      [True, False, False, False])
check("  before: a newer target required; verify: the first marker kept with its value, the second lost; each agent on the pin",
      ([condition(ct("Before - a newer version")["ansible.builtin.assert"]["that"], consul_version="1.22.7", **({} if k is None else {"consul_to": k}))
        for k in ("2.0.4", "1.22.7", None)],
       [condition(ct("Verify - the marker from before there")["ansible.builtin.assert"]["that"], marker="way-back-1Z", _markers={"stdout_lines": m},
                  _value={"stdout": v}) for m, v in ((["way-back/way-back-1Z-before"], "before\n"),
                                                      (["way-back/way-back-1Z-after", "way-back/way-back-1Z-before"], "before"),
                                                      ([], ""), (["way-back/way-back-1Z-before"], "after"))],
       "_self.json.Config.Version == consul_version" in ct("Before and verify - each agent on the pin")["until"]),
      ([True, False, False], [True, False, False, False], True))
check("  verify: Patroni healthy, the database writable through each Pi's HAProxy (a transaction id), one Vault active",
      ("patronictl" in ct("Verify - Patroni healthy")["ansible.builtin.shell"]["cmd"],
       "txid_current()" in ct("Verify - the database writable")["ansible.builtin.shell"]["cmd"] and "-p 5000" in ct("Verify - the database writable")["ansible.builtin.shell"]["cmd"],
       [condition(ct("Verify - exactly one Vault active")["ansible.builtin.assert"]["that"], groups=PIS,
                  hostvars={"pi1": {"_vault": {"status": a}}, "pi2": {"_vault": {"status": b}}}) for a, b in ((200, 429), (429, 429), (200, 200))]),
      (True, True, [True, False, False]))
check("  cleanup: both markers deleted by their prefix", ct("Cleanup - both markers gone")["ansible.builtin.command"]["argv"],
      ["consul", "kv", "delete", "-recurse", "way-back/{{ marker }}-"])
E = CW[2]["tasks"]
et = lambda name: next(t for t in E if str(t.get("name", "")).startswith(name))
synced = et("Verify - refreshed after that and Ready")["until"]
check("  External Secrets: its store Ready; an ExternalSecret force-synced now, refreshed AFTER the force and Ready",
      ([condition(synced, _since={"stdout_lines": ["2026-11-27T10:00:00Z"]}, _synced={"stdout": o})
        for o in ("2026-11-27T10:00:05Z True", "2026-11-27T09:59:00Z True", "2026-11-27T10:00:05Z False", "")],
       all(t.get("when") == "phase == 'verify'" for t in E)),
      ([True, False, False, False], True))
task_cmd = open("Taskfile.yml").read().split("  test:copy:consul-way-back:")[1].split("\n\n")[0]
seq = [l.strip() for l in task_cmd.splitlines() if l.strip().startswith("pb ")]
check("  the task: before, production's upgrade-consul.yml to the target, after, production's restore-consul.yml with the upgrade's "
      "snapshot confirmed, verify, cleanup - each production playbook behind the Vagrant guard, secrets kept out, cleanup on failure too",
      ([("phase=" + l.split("phase=")[1].split()[0]) if "phase=" in l else l.split()[2].split("/")[-1] for l in seq],
       all("vagrant-only-play.yml" in l for l in seq if "playbooks/" in l), "env -i" in task_cmd,
       "trap 'pb \"$C\" -e phase=cleanup -e marker=\"$M\"' EXIT" in task_cmd and "trap - EXIT" in task_cmd, "consul-way-back-confirm" in task_cmd),
      (["phase=before", "upgrade-consul.yml", "phase=after", "restore-consul.yml", "phase=verify", "phase=cleanup"], True, True, True, True))
print("consul-way-back: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_CWB
