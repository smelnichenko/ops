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
R = yaml.safe_load(open("deploy/ansible/playbooks/restore-vault.yml"))[0]["tasks"]
rt = lambda name: next(t for t in R if str(t.get("name", "")).startswith(name))
reg = lambda r: next(t for t in R if t.get("register") == r)
idx = R.index

# ── which export, and its version ────────────────────────────────────────────────────────────────────────────────
check("every Pi in the run: both - on; one left out (--limit) - refused",
      [condition(rt("Every Pi in the run")["ansible.builtin.assert"]["that"], ansible_play_hosts=h, groups={"pis": ["pi1", "pi2"]})
       for h in (["pi2", "pi1"], ["pi1"])], [True, False])
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
check("  refused until the unit is reverted (the pin the export's version), confirmed by its file name, the old binary on every Pi",
      ([condition(pin, vault_version=k, _export_version="1.21.4") for k in ("1.21.4", "2.2.2")],
       [condition(conf, _export_path=B, **({} if c is None else {"confirm": c})) for c in (os.path.basename(B), "other", None)],
       [condition(kept, _kept={"stat": st}) for st in ({"executable": True}, {"exists": False}, {})]),
      ([True, False], [True, False, False], [True, False, False]))

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
keys = json.dumps([{"key": "vault/core/keyring", "flags": 0, "value": "eA=="}, {"key": "vault/logical/x", "flags": 0, "value": "eQ=="}])
rc_ok, n_ok = export_ok(keys)
check("the export: Vault's keys - on, counted; empty, another prefix, not JSON, or missing - refused",
      [(rc_ok, n_ok), export_ok("[]")[0] != 0, export_ok(json.dumps([{"key": "patroni/leader", "value": "x"}]))[0] != 0,
       export_ok("{cut")[0] != 0, export_ok(None)[0] != 0], [(0, "2"), True, True, True, True])
check("  once, on the Pi holding it, before anything stops",
      (ec.get("run_once"), ec.get("delegate_to"), idx(ec) < idx(rt("Vault stopped on every Pi"))), (True, "{{ _export_host }}", True))

# ── the import, consul stubbed ───────────────────────────────────────────────────────────────────────────────────
imp = reg("_imported")
cbin = os.path.join(work, "cbin"); os.makedirs(cbin); clog = os.path.join(work, "consul.log"); store = os.path.join(work, "kv.json")
with open(os.path.join(cbin, "consul"), "w") as f:
    f.write(f'''#!/bin/bash
echo "$*" >> {clog}
case "$1 $2" in
  "kv delete") [ "$3" = -recurse ] && [ "$4" = vault/ ] && echo '[]' > {store} ;;
  "kv import") [ -z "${{CONSUL_FAIL:-}}" ] || {{ echo "import refused" >&2; exit 1; }}; cp "${{3#@}}" {store} ;;
  "kv export") [ "$3" = vault/ ] && cat {store} ;;
esac
''')
os.chmod(os.path.join(cbin, "consul"), 0o755)
def import_run(**env):
    p = os.path.join(work, "export.json"); open(p, "w").write(keys)
    open(store, "w").write(json.dumps([{"key": "vault/stale", "value": "eg=="}] * 5))
    if os.path.exists(clog):
        os.remove(clog)
    cmd = render(imp["ansible.builtin.shell"]["cmd"], _export_path=p)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=dict(os.environ, PATH=cbin + ":" + os.environ["PATH"], **env))
    return r.returncode, r.stdout.strip(), [l.split()[1] for l in open(clog).read().splitlines()] if os.path.exists(clog) else []
check("the import: vault/ emptied, the export imported, the keys counted after (as many as the export's) - a failed import fails",
      [import_run(), import_run(CONSUL_FAIL="1")[0] != 0], [(0, "2", ["delete", "import", "export"]), True])
check("  once, on the Pi holding the export, its failure its own (the check after it refuses, Vault left stopped)",
      (imp.get("run_once"), imp.get("delegate_to"), imp.get("failed_when")), (True, "{{ _export_host }}", False))
held = rt("The keys restored")["ansible.builtin.assert"]["that"]
check("  its check: ended 0 with the export's count - holds; failed, no result, or another count - refused",
      [condition(held, _imported=i, _export_keys={"stdout": "2"}) for i in ({"rc": 0, "stdout": "2\n"}, {"rc": 1, "stdout": "2"}, {}, {"rc": 0, "stdout": "1"})],
      [True, False, False, False])
check("the order: every refusal before the stop; the stop before the import; the import checked before the binary moves; "
      "the binary before the start, the start before the unseal, then health and one leader",
      max(idx(rt(n)) for n in ("Every Pi in the run", "An export", "The unit reverted", "Confirmed", "Every Pi has it", "The export there"))
      < idx(rt("Vault stopped on every Pi")) < idx(imp) < idx(rt("The keys restored")) < idx(rt("The kept binary back"))
      < idx(rt("Started")) < idx(rt("Unsealed by the Pi's own script")) < idx(rt("Unsealed, on the export's version"))
      < idx(rt("Exactly one active")), True)
check("  the binary back is the export's version's, health waits for that version",
      (rt("The kept binary back")["ansible.builtin.copy"]["src"], "_export_version" in rt("Unsealed, on the export's version")["until"]),
      ("/usr/local/bin/vault-{{ _export_version }}", True))
check("  a run without every Pi failing everywhere (any_errors_fatal)",
      yaml.safe_load(open("deploy/ansible/playbooks/restore-vault.yml"))[0].get("any_errors_fatal"), True)

# ── upgrade-vault.yml: the root token and the backups off the Pi before any version move ─────────────────────────
U = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-vault.yml"))[0]["tasks"]
ut = lambda name: next(t for t in U if str(t.get("name", "")).startswith(name))
rtk = next(t for t in U if t.get("register") == "_root_token")
check("upgrade-vault: the root token tried with vault token lookup, its output never logged, its failure the check's",
      ("vault token lookup" in rtk["ansible.builtin.shell"]["cmd"], "/etc/vault-unseal/root-token" in rtk["ansible.builtin.shell"]["cmd"],
       rtk.get("no_log"), rtk.get("failed_when")), (True, True, True, False))
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
      ([snap, snap[:-len(".snap")] + ".vault-kv.json"], "{{ playbook_dir }}/../vars/vault-upgrade-backups/", "_active | bool", True, True))

# ── backup-vault-keys.yml: the root token required as the keys are ───────────────────────────────────────────────
K = yaml.safe_load(open("deploy/ansible/playbooks/backup-vault-keys.yml"))[0]["tasks"]
kb = next(t for t in K if str(t.get("name", "")).startswith("The unseal keys and the root token are in the local backup"))
both = lambda a, b, cm=False: condition(kb["ansible.builtin.assert"]["that"], ansible_check_mode=cm,
                                        _backup_files={"results": [{"item": "unseal-keys", "stat": {"exists": a}}, {"item": "root-token", "stat": {"exists": b}}]})
check("backup-vault-keys: both fetched - on; the root token or the keys missing - failed; check mode - said, not failed",
      [both(True, True), both(True, False), both(False, True), both(False, False, True)], [True, False, False, True])

# ── the copy's rehearsal ─────────────────────────────────────────────────────────────────────────────────────────
CW = yaml.safe_load(open("tests/ansible/copy/vault-way-back-check.yml"))
check("the rehearsal behind the Vagrant guard first", (CW[0].get("ansible.builtin.import_playbook"), len(CW)), ("../vagrant-only-play.yml", 2))
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
       [condition(ct("Verify - the secret from before there")["ansible.builtin.assert"]["that"], marker="way-back-1Z", _secrets={"stdout_lines": m})
        for m in (["way-back-1Z-before"], ["way-back-1Z-after", "way-back-1Z-before"], [])],
       "_health.json.version == vault_version" in ct("Before and verify - each Vault unsealed")["until"]),
      ([True, False, False], [True, False, False], True))
task_cmd = open("Taskfile.yml").read().split("  test:copy:vault-way-back:")[1].split("\n\n")[0]
seq = [l.strip() for l in task_cmd.splitlines() if l.strip().startswith("pb ")]
check("  the task: before, production's upgrade-vault.yml to the target, after, production's restore-vault.yml with the upgrade's export "
      "confirmed, verify, cleanup - each production playbook behind the Vagrant guard, secrets kept out, cleanup on failure too",
      ([("phase=" + l.split("phase=")[1].split()[0]) if "phase=" in l else l.split()[2].split("/")[-1] for l in seq],
       all("vagrant-only-play.yml" in l for l in seq if "playbooks/" in l), "env -i" in task_cmd,
       "trap 'pb \"$C\" $V -e phase=cleanup -e marker=\"$M\"' EXIT" in task_cmd and "trap - EXIT" in task_cmd, "vault-way-back-confirm" in task_cmd),
      (["phase=before", "upgrade-vault.yml", "phase=after", "restore-vault.yml", "phase=verify", "phase=cleanup"], True, True, True, True))
print("vault-way-back: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_VWB
