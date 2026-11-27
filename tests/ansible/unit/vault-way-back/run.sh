#!/bin/bash
# Vault's way back: restore-vault.yml - every Pi in its run, the export it restores (the newest on either Pi whatever the
# play's order, or the one given) and the version from its name, its refusals before anything stops (no export, the
# unit not reverted, not confirmed by name, the old binary gone, an export that is no Vault's), the import against a
# stubbed consul (vault/ emptied, the export imported, the keys counted against the export's), and the order; then what
# upgrade-vault.yml does before any version move (the root token working on each Pi - 2.x's break-glass -, both backups
# fetched off the Pi), backup-vault-keys.yml requiring the root token, and the copy's rehearsal (the Vagrant guard, its
# phases, its task's sequence and cleanup).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_VWB'
import json, os, subprocess, sys, tempfile
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
work = tempfile.mkdtemp()
RP = yaml.safe_load(open("deploy/ansible/playbooks/restore-vault.yml"))[0]
def flat(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from flat(t.get(k))
R = list(flat(RP["tasks"]))
rt = lambda name: next(t for t in R if str(t.get("name", "")).startswith(name))
reg = lambda r: next(t for t in R if t.get("register") == r)
idx = R.index
blk = rt("The restore - from the stop to one active")

# ── which export, and its version ────────────────────────────────────────────────────────────────────────────────
check("every Pi in the run: both - on; one left out (--limit) - refused",
      [condition(rt("Every Pi in the run")["ansible.builtin.assert"]["that"], ansible_play_hosts=h, groups={"pis": ["pi1", "pi2"]})
       for h in (["pi2", "pi1"], ["pi1"])], [True, False])
nw = rt("The newest export here")["ansible.builtin.shell"]["cmd"]
ed = os.path.join(work, "exports"); os.makedirs(ed)
for n, t in (("consul-20261127T010000Z-vault-1.21.4.vault-kv.json", 1000), ("consul-20261126T010000Z-vault-1.21.3.vault-kv.json", 2000)):
    open(os.path.join(ed, n), "w").write("[]"); os.utime(os.path.join(ed, n), (t, t))
newest = lambda: subprocess.run(["bash", "-c", render(nw, upgrade_dir=ed)], capture_output=True, text=True).stdout.strip()
got_newest = newest()
for n in os.listdir(ed): os.remove(os.path.join(ed, n))
check("the newest export on a Pi by its name (its UTC time) - never by mtime (one copied back is new to the Pi); none - nothing",
      (os.path.basename(got_newest), newest()), ("consul-20261127T010000Z-vault-1.21.4.vault-kv.json", ""))
pick = rt("The export restored")
def chosen(newest, given=None):
    hv = {h: {"inventory_hostname": h, "_newest": {"stdout": p}} for h, p in newest.items()}
    of = render(pick["vars"]["_newest_of"], ansible_play_hosts=list(newest), hostvars=hv)
    extra = {} if given is None else {"vault_restore_export": given[0], "vault_restore_host": given[1]}
    return (render(pick["ansible.builtin.set_fact"]["_export_path"], _newest_of=of, **extra),
            render(pick["ansible.builtin.set_fact"]["_export_host"], _newest_of=of, **extra))
A = "/var/backups/vault-upgrade/consul-20261126T010000Z-vault-1.21.3.vault-kv.json"
B = "/var/backups/vault-upgrade/consul-20261127T010000Z-vault-1.21.4.vault-kv.json"
check("the newest export on either Pi whatever the play's order, or the one given; none - empty (refused below)",
      [chosen({"pi1": A, "pi2": B}), chosen({"pi1": B, "pi2": A}), chosen({"pi1": A, "pi2": ""}),
       chosen({"pi1": A, "pi2": B}, ("/x/given.vault-kv.json", "pi1")), chosen({"pi1": "", "pi2": ""})],
      [(B, "pi2"), (B, "pi1"), (A, "pi1"), ("/x/given.vault-kv.json", "pi1"), ("", "")])
ver = lambda p: render(rt("Its version")["ansible.builtin.set_fact"]["_export_version"], _export_path=p).strip()
check("  the version an export ran, from its name; a name not an export's - none",
      [ver(A), ver(B), ver("/x/consul-20261127T010000Z-vault-2.2.2+ent.vault-kv.json"), ver("/x/other.json"), ver("")],
      ["1.21.3", "1.21.4", "2.2.2+ent", "", ""])
known = rt("An export, its Pi and its version known")["ansible.builtin.assert"]["that"]
check("refused before anything stops without an export, its Pi among the play's, or a version",
      [condition(known, _export_path=p, _export_host=h, _export_version=v, ansible_play_hosts=["pi1", "pi2"])
       for p, h, v in ((B, "pi1", "1.21.4"), ("", "pi1", "1.21.4"), (B, "pi3", "1.21.4"), (B, "pi1", ""))], [True, False, False, False])
pin = rt("The unit reverted first")["ansible.builtin.assert"]["that"]
conf = rt("Confirmed by naming the export")["ansible.builtin.assert"]["that"]
kept = rt("Every Pi has it")["ansible.builtin.assert"]["that"]
check("  refused until the unit is reverted, confirmed by the export's name, the kept binary there AND that version",
      ([condition(pin, vault_version=k, _export_version="1.21.4") for k in ("1.21.4", "2.2.2")],
       [condition(conf, _export_path=B, **({} if c is None else {"confirm": c})) for c in (os.path.basename(B), "other", None)],
       [condition(kept, _kept=k, _export_version="1.21.4") for k in (
           {"rc": 0, "stdout": "Vault v1.21.4 (abcdef), built 2026-11-01"}, {"rc": 0, "stdout": "Vault v2.2.2 (abc), built x"},
           {"rc": 2, "stdout": "", "stderr": "No such file"}, {})]),
      ([True, False], [True, False, False], [True, False, False, False]))
check("  the binary looked at as itself (its own version), the Consul agent's leader asked - both before anything stops",
      (rt("The export's version's binary kept here")["ansible.builtin.command"]["argv"],
       rt("The Consul agent there has a leader").get("delegate_to"),
       max(idx(rt("The export's version's binary kept here")), idx(rt("The Consul agent there has a leader"))) < idx(blk)),
      (["/usr/local/bin/vault-{{ _export_version }}", "version"], "{{ _export_host }}", True))
leader = rt("The Consul agent there has a leader")["failed_when"]
check("  no leader (an empty answer) - failed before the stop; a leader - on",
      [condition(leader, _consul_leader={"json": j}) for j in ("10.0.0.1:8300", "")], [False, True])

# ── the export checked where it lies, before anything stops ──────────────────────────────────────────────────────
ec = rt("The export there and whole")
def export_ok(content):
    p = os.path.join(work, "export.json")
    if content is None:
        p = os.path.join(work, "missing.json")
    else:
        open(p, "w").write(content)
    argv = [render(a, _export_path=p) for a in ec["ansible.builtin.command"]["argv"]]
    r = subprocess.run(argv, capture_output=True, text=True)
    return r.returncode, r.stdout.strip()
whole = [{"key": "vault/core/keyring", "flags": 0, "value": "eA=="}, {"key": "vault/core/seal-config", "flags": 0, "value": "eQ=="},
         {"key": "vault/logical/x", "flags": 0, "value": "eg=="}, {"key": "vault/core/lock", "flags": 3304740253564472344, "value": "bA=="}]
keys = json.dumps(whole)
rc_ok, n_ok = export_ok(keys)
check("the export: Vault's keys with its barrier - on, counted; empty, another prefix, no seal config or keyring, not JSON, or "
      "missing - refused",
      [(rc_ok, n_ok), export_ok("[]")[0] != 0, export_ok(json.dumps([{"key": "patroni/leader", "value": "x"}]))[0] != 0,
       export_ok(json.dumps([k for k in whole if k["key"] != "vault/core/seal-config"]))[0] != 0,
       export_ok(json.dumps([k for k in whole if k["key"] != "vault/core/keyring"]))[0] != 0,
       export_ok("{cut")[0] != 0, export_ok(None)[0] != 0], [(0, "4"), True, True, True, True, True, True])
check("  once, on the Pi holding it, before anything stops",
      (ec.get("run_once"), ec.get("delegate_to"), idx(ec) < idx(blk)), (True, "{{ _export_host }}", True))

# ── the import, consul stubbed: set aside, emptied, imported, compared key by key ────────────────────────────────
imp = reg("_imported")
cbin = os.path.join(work, "cbin"); os.makedirs(cbin); clog = os.path.join(work, "consul.log"); store = os.path.join(work, "kv.json")
with open(os.path.join(cbin, "consul"), "w") as f:
    f.write(f"""#!/bin/bash
echo "$*" >> {clog}
case "$1 $2" in
  "kv delete") [ "$3" = -recurse ] && [ "$4" = vault/ ] && echo '[]' > {store} ;;
  "kv import") [ -z "${{CONSUL_FAIL:-}}" ] || {{ echo "import refused" >&2; exit 1; }}; cp "${{3#@}}" {store}
               [ -z "${{CONSUL_LOSE:-}}" ] || python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d[0]["value"]="ZGlmZg=="; json.dump(d,open(sys.argv[1],"w"))' {store} ;;
  "kv export") [ "$3" = vault/ ] && cat {store} ;;
esac
""")
os.chmod(os.path.join(cbin, "consul"), 0o755)
aside_dir = os.path.join(work, "aside"); os.makedirs(aside_dir)
stale = [{"key": "vault/stale", "flags": 0, "value": "eg=="}] * 5
def import_run(**env):
    p = os.path.join(work, "export.json"); open(p, "w").write(keys)
    open(store, "w").write(json.dumps(stale))
    for x in os.listdir(aside_dir): os.remove(os.path.join(aside_dir, x))
    if os.path.exists(clog):
        os.remove(clog)
    cmd = render(imp["ansible.builtin.shell"]["cmd"], _export_path=p, upgrade_dir=aside_dir)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=dict(os.environ, PATH=cbin + ":" + os.environ["PATH"], **env))
    asides = os.listdir(aside_dir)
    aside = json.load(open(os.path.join(aside_dir, asides[0]))) if asides else None
    calls = [l.split()[1] for l in open(clog).read().splitlines()] if os.path.exists(clog) else []
    return r.returncode, r.stdout.strip().splitlines()[-1:] , calls, aside == stale, oct(os.stat(os.path.join(aside_dir, asides[0])).st_mode)[-3:] if asides else None
rc, last, calls, kept_aside, mode = import_run()
check("the import: vault/ as it stood set aside first (root's alone), then emptied, the export imported, compared with it - "
      "the count said",
      (rc, last, calls, kept_aside, mode), (0, ["4"], ["export", "delete", "import", "export"], True, "600"))
check("  a failed import fails; an import that came out different (a value) fails - never counted as restored",
      [import_run(CONSUL_FAIL="1")[0] != 0, import_run(CONSUL_LOSE="1")[0] != 0], [True, True])
check("  once, on the Pi holding the export, its failure the play's (the rescue says where Vault was left)",
      (imp.get("run_once"), imp.get("delegate_to"), "failed_when" in imp), (True, "{{ _export_host }}", False))

# ── the order inside the block, and its rescue ───────────────────────────────────────────────────────────────────
B_ = blk["block"]
bt = lambda name: next(t for t in B_ if str(t.get("name", "")).startswith(name))
bi = B_.index
check("the block: stopped, both off at a boot, the kept binary back BEFORE the import, the import, both enabled again, "
      "started, unsealed, health on the export's version, one leader, the root token proven on the restored keys",
      bi(bt("Vault stopped on every Pi")) < bi(bt("Neither started at a boot")) < bi(bt("The kept binary back first"))
      < bi(imp) < bi(bt("Both enabled again")) < bi(bt("Started")) < bi(bt("Unsealed by the Pi's own script"))
      < bi(bt("Unsealed, on the export's version")) < bi(bt("Exactly one active")) < bi(bt("The root token works on the restored keys")),
      True)
check("  off at a boot: the unseal too (it would pull vault in - Requires=), on again after; the binary the export's",
      (bt("Neither started at a boot")["loop"], bt("Neither started at a boot")["ansible.builtin.systemd"]["enabled"],
       bt("Both enabled again")["loop"], bt("Both enabled again")["ansible.builtin.systemd"]["enabled"],
       bt("The kept binary back first")["ansible.builtin.copy"]["src"]),
      (["vault-unseal", "vault"], False, ["vault", "vault-unseal"], True, "/usr/local/bin/vault-{{ _export_version }}"))
resc = render(blk["rescue"][0]["ansible.builtin.fail"]["msg"], ansible_failed_task={"name": "Started"},
              ansible_failed_result={"msg": "boom"}, _imported={"stdout_lines": ["/b/pre-restore-x.vault-kv.json", "4"]},
              _export_host="pi1", _export_path=B)
check("  the rescue: where it failed, the set-aside copy and the untouched export named, run it again with the same confirm, "
      "never deploy:vault-pi meanwhile (its init would overwrite the keys)",
      [x in resc for x in ('"Started"', "boom", "/b/pre-restore-x.vault-kv.json", B, "task deploy:vault:way-back again",
                           "never task deploy:vault-pi", "REFUSED" not in resc and "FAILED")],
      [True] * 7)
done = render(rt("Restored - and what to run again")["ansible.builtin.debug"]["msg"], _export_version="1.21.4",
              ansible_play_hosts=["pi1", "pi2"], _export_path=B, _imported={"stdout_lines": ["/b/a.json", "4"]},
              _leader={"json": {"leader_address": "https://10.0.0.1:8200"}})
check("the end names what to run again (the rotated tokens back stale in Vault, preview environments, External Secrets)",
      [x in done for x in ("task deploy:ci-bot", "task deploy:argocd-reader", "preview environments", "force-sync", "4 keys")], [True] * 5)
check("  a run without every Pi failing everywhere (any_errors_fatal)", RP.get("any_errors_fatal"), True)

# ── upgrade-vault.yml: the root token and the backups off the Pi before any version move ─────────────────────────
U = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-vault.yml"))[0]["tasks"]
ut = lambda name: next(t for t in U if str(t.get("name", "")).startswith(name))
rtk = next(t for t in U if t.get("register") == "_root_token")
check("upgrade-vault: the root token tried with vault token lookup, its output never logged, its failure the check's",
      ("vault token lookup" in rtk["ansible.builtin.shell"]["cmd"], "/etc/vault-unseal/root-token" in rtk["ansible.builtin.shell"]["cmd"],
       rtk.get("no_log"), rtk.get("failed_when")), (True, True, True, False))
vbin = os.path.join(work, "vbin"); os.makedirs(vbin)
with open(os.path.join(vbin, "vault"), "w") as f:
    f.write('#!/bin/bash\n[ "$1 $2" = "token lookup" ] || exit 9\nt=${VAULT_TOKEN:-$(cat "$HOME/.vault-token" 2> /dev/null)}\n'
            '[ "$t" = hvs.good ] || { echo "permission denied" >&2; exit 2; }\n'
            'echo "{\\"data\\": {\\"policies\\": ${POLICIES:-[\\"root\\"]}, \\"expire_time\\": ${EXPIRE:-null}}}"\n')
os.chmod(os.path.join(vbin, "vault"), 0o755)
home = os.path.join(work, "home"); os.makedirs(home)
open(os.path.join(home, ".vault-token"), "w").write("hvs.good")  # a token helper's file that would answer for a missing one
def token_run(content, **env):
    tf = os.path.join(work, "root-token")
    if os.path.exists(tf):
        os.remove(tf)
    if content is not None:
        open(tf, "w").write(content)
    cmd = render(rtk["ansible.builtin.shell"]["cmd"], vault_api="https://127.0.0.1:8200").replace("/etc/vault-unseal/root-token", tf)
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                          env=dict({k: v for k, v in os.environ.items() if k != "VAULT_TOKEN"}, PATH=vbin + ":" + os.environ["PATH"],
                                   HOME=home, **env)).returncode
check("  the script: a root token that never expires - passes; the file missing or empty (never left to the CLI's token "
      "helper), a token Vault refuses, a non-root one, one that expires - each fails",
      [token_run("hvs.good"), token_run(None) != 0, token_run("") != 0, token_run("hvs.bad") != 0,
       token_run("hvs.good", POLICIES='["admin"]') != 0, token_run("hvs.good", EXPIRE='"2026-12-01T00:00:00Z"') != 0],
      [0, True, True, True, True, True])
tk = ut("The root token works on every Pi")["ansible.builtin.assert"]["that"]
check("  working - on; not (missing, revoked, sealed) - refused", [condition(tk, _root_token=r) for r in ({"rc": 0}, {"rc": 2}, {})], [True, False, False])
first_change = min(U.index(ut(n)) for n in ("The release, checked", "The running binary kept", "Consul's snapshot first", "The standby first"))
check("  checked before anything changes (the download, the kept binary, the snapshot, the first Pi)",
      U.index(ut("The root token works on every Pi")) < first_change, True)
fe = ut("Both backups fetched to the controller")
snap = "/var/backups/vault-upgrade/consul-20261127T010000Z-vault-1.21.4.snap"
check("  both backups fetched off the active Pi (the snapshot and the export), into the gitignored vars area, before the first Pi stops",
      ([render(x, _snapshot={"stdout": snap}) for x in fe["loop"]], fe["ansible.builtin.fetch"]["dest"], fe.get("when"),
       U.index(ut("Consul's snapshot first")) < U.index(fe) < U.index(ut("The standby first")),
       "deploy/ansible/vars/vault-upgrade-backups/" in open(".gitignore").read().splitlines()),
      ([snap, snap[:-len(".snap")] + ".vault-kv.json"], "{{ backups_here }}/", "_active | bool", True, True))
UP = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-vault.yml"))[0]
here = lambda inv: render(UP["vars"]["backups_here"], playbook_dir="/o/deploy/ansible/playbooks", inventory_file=inv)
lock = ut("The controller's copies the operator's alone")
check("  one directory per inventory (the copy's export never beside production's), the directory 0700 and both files 0600 "
      "on the controller",
      (here("/o/deploy/ansible/inventory/production.yml"), here("/o/deploy/ansible/inventory/vagrant.yml"),
       [render(x["mode"], _snapshot={"stdout": snap}) for x in lock["loop"]], lock.get("delegate_to"), U.index(fe) < U.index(lock) < U.index(ut("The standby first"))),
      ("/o/deploy/ansible/playbooks/../vars/vault-upgrade-backups/production", "/o/deploy/ansible/playbooks/../vars/vault-upgrade-backups/vagrant",
       ["0700", "0600", "0600"], "localhost", True))

# ── backup-vault-keys.yml: the root token required as the keys are ───────────────────────────────────────────────
K = yaml.safe_load(open("deploy/ansible/playbooks/backup-vault-keys.yml"))[0]["tasks"]
kb = next(t for t in K if str(t.get("name", "")).startswith("The unseal keys and the root token are in the local backup"))
both = lambda a, b, cm=False: condition(kb["ansible.builtin.assert"]["that"], ansible_check_mode=cm,
                                        _backup_files={"results": [{"item": "unseal-keys", "stat": {"exists": a}}, {"item": "root-token", "stat": {"exists": b}}]})
check("backup-vault-keys: both fetched - on; the root token or the keys missing - failed; check mode - said, not failed",
      [both(True, True), both(True, False), both(False, True), both(False, False, True)], [True, False, False, True])

# ── the copy's rehearsal ─────────────────────────────────────────────────────────────────────────────────────────
CW = yaml.safe_load(open("tests/ansible/copy/vault-way-back-check.yml"))
check("the rehearsal behind the Vagrant guard first (it guards every host), then the Pis' play, then External Secrets' on the node",
      (CW[0].get("ansible.builtin.import_playbook"), len(CW), CW[2].get("hosts")), ("../vagrant-only-play.yml", 3, "target"))
C = CW[1]["tasks"]
ct = lambda name: next(t for t in C if str(t.get("name", "")).startswith(name))
first_chk = C[0]["ansible.builtin.assert"]["that"]
check("  a phase and a marker name required (the task's, one per run)",
      [condition(first_chk, **v) for v in ({"phase": "before", "marker": "way-back-20261127T010000Z"}, {"phase": "x", "marker": "way-back-1Z"},
                                          {"phase": "before"}, {"phase": "before", "marker": "{{ lookup('pipe','date') }}"})],
      [True, False, False, False])
check("  before: a newer target required; verify: the first secret kept, the second lost, one active on the pin",
      ([condition(ct("Before - a newer version")["ansible.builtin.assert"]["that"], vault_version="1.21.4", **({} if k is None else {"vault_to": k}))
        for k in ("2.2.2", "1.21.4", None)],
       [condition(ct("Verify - the secret from before there")["ansible.builtin.assert"]["that"], marker="way-back-1Z", _secrets={"stdout_lines": m},
                  _value={"stdout": v}) for m, v in ((["way-back-1Z-before"], "before\n"), (["way-back-1Z-after", "way-back-1Z-before"], "before"),
                                                      ([], ""), (["way-back-1Z-before"], "after"))],
       "_health.json.version == vault_version" in ct("Before and verify - each Vault unsealed")["until"]),
      ([True, False, False], [True, False, False, False], True))
E = CW[2]["tasks"]
et = lambda name: next(t for t in E if str(t.get("name", "")).startswith(name))
synced = et("Verify - refreshed after that and Ready")["until"]
check("  External Secrets: its store Ready; an ExternalSecret force-synced now, refreshed AFTER the force and Ready - an older "
      "refresh, or not Ready, is no pass",
      ("vault-backend" in et("Verify - the ClusterSecretStore Ready")["ansible.builtin.command"]["argv"],
       "force-sync" in et("Verify - an ExternalSecret force-synced now")["ansible.builtin.shell"]["cmd"],
       [condition(synced, _since={"stdout_lines": ["2026-11-27T10:00:00Z"]}, _synced={"stdout": o})
        for o in ("2026-11-27T10:00:05Z True", "2026-11-27T09:59:00Z True", "2026-11-27T10:00:05Z False", "")],
       all(t.get("when") == "phase == 'verify'" for t in E)),
      (True, True, [True, False, False, False], True))
task_cmd = open("Taskfile.yml").read().split("  test:copy:vault-way-back:")[1].split("\n\n")[0]
seq = [l.strip() for l in task_cmd.splitlines() if l.strip().startswith("pb ")]
check("  the task: before, production's upgrade-vault.yml to the target, after, production's restore-vault.yml with the upgrade's export "
      "confirmed, verify, cleanup - each production playbook behind the Vagrant guard, secrets kept out, cleanup on failure too",
      ([("phase=" + l.split("phase=")[1].split()[0]) if "phase=" in l else l.split()[2].split("/")[-1] for l in seq],
       all("vagrant-only-play.yml" in l for l in seq if "playbooks/" in l), "env -i" in task_cmd,
       "trap 'pb \"$C\" $V -e phase=cleanup -e marker=\"$M\"' EXIT" in task_cmd and "trap - EXIT" in task_cmd, "vault-way-back-confirm" in task_cmd),
      (["phase=before", "upgrade-vault.yml", "phase=after", "restore-vault.yml", "phase=verify", "phase=cleanup"], True, True, True, True))
msgs = []
for t in C:
    a = t.get("ansible.builtin.assert")
    for k in ("fail_msg", "success_msg"):
        if a and k in a:
            v = render(a[k], ansible_play_hosts=["pi1", "pi2"], hostvars={"pi1": {"_health": {"status": 200}}, "pi2": {"_health": {"status": 429}}},
                       marker="way-back-1Z", vault_version="1.21.4", vault_to="2.2.2", _secrets={"stdout_lines": []}, _value={"stdout": ""})
            msgs.append((t["name"][:40], k, isinstance(v, str), type(v).__name__))
check("  every rehearsal assert's message renders to a string (a list of pairs is refused by the module even when the assertion "
      "holds - the first rehearsal, 2026-11-27)", [m for m in msgs if not m[2]], [])
print("vault-way-back: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_VWB
