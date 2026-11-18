#!/bin/bash
# No playbook ignores an error it never looks at: a task with failed_when: false (or ignore_errors) must register its
# result and use it after (a probe: rc read by a later when/assert). 2026-11-18 found four that did not - the seed's
# retired-path delete (a Forbidden or a sealed Vault passed), backup-vault-keys' lock-down (a failed chmod left the unseal
# keys readable), create-environment's KV mount, host hardening's module unloads. Then those fixes, as Ansible
# evaluates them (tests/ansible/unit/templar.py): an unload refused for a builtin is no failure, one in use is; the
# root token locked down only when the fetch brought it, the unseal keys always.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=$(command -v python3)
"$PY" -c 'import yaml, jinja2, ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_IGNORED_ERRORS'
import glob, os, re, sys
import yaml
ops = sys.argv[1]
sys.path.insert(0, os.path.join(ops, "tests", "ansible", "unit"))
from templar import condition, render, as_loaded
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def walk(ts):
    for t in ts or []:
        if not isinstance(t, dict):
            continue
        yield t
        for k in ("block", "rescue", "always", "tasks", "pre_tasks", "post_tasks", "handlers"):
            yield from walk(t.get(k))
def tasks(path):
    doc = yaml.safe_load(open(os.path.join(ops, path)))
    return list(walk(doc if isinstance(doc, list) else []))
def task(path, prefix):
    return next(t for t in tasks(path) if str(t.get("name", "")).startswith(prefix))
def ignores(t):
    fw = t.get("failed_when")
    return fw is False or str(fw).strip().lower() == "false" or t.get("ignore_errors") in (True, "true", "yes")

# I01: every ignored failure is a probe - registered, its result read again in the same file
bad = []
for f in sorted(glob.glob(os.path.join(ops, "deploy/ansible/playbooks/**/*.yml"), recursive=True)):
    rel = os.path.relpath(f, ops)
    try:
        ts = tasks(rel)
    except yaml.YAMLError:
        continue  # not a task file (a Jinja template): ansible-lint loads those
    text = open(f).read()
    for t in ts:
        if not ignores(t):
            continue
        reg = t.get("register")
        if not reg or len(re.findall(r"\b%s\b" % re.escape(reg), text)) < 2:
            bad.append("%s: %r" % (rel, t.get("name")))
check("I01 no task ignores a failure it never reads (failed_when: false / ignore_errors without a used register)", bad, [])

# I02: host hardening's unloads - a builtin's refusal passes (the blacklist keeps it off), one in use fails, success passes
hh = "deploy/ansible/playbooks/setup-host-hardening.yml"
unloads = [t for t in tasks(hh) if str(t.get("name", "")).startswith("Unload ")]
check("I02 four unload tasks, each registering _unload", [t.get("register") for t in unloads], ["_unload"] * 4)
for t in unloads:
    fw = t["failed_when"]
    got = (condition(fw, _unload={"failed": True, "msg": "modprobe: FATAL: Module bluetooth is builtin."}),
           condition(fw, _unload={"failed": True, "msg": "modprobe: FATAL: Module btusb is in use."}),
           condition(fw, _unload={"failed": True, "msg": "[Errno 2] No such file or directory: '/lib/modules/6.12.0/modules.builtin'"}),
           condition(fw, _unload={"changed": True, "failed": False}),
           condition(fw, _unload={"changed": False}))
    check("I02 %s: builtin passes; in use, modules.builtin unreadable fail; unloaded / not loaded pass" % t["name"], got,
          (False, True, True, False, False))
check("I02 the bluetooth leaves unloaded before its core, those holding it after bluetoothd ran among them",
      all(m in unloads[0]["loop"] for m in ("bnep", "rfcomm", "hidp", "hci_uart", "btusb")), True)

# I03: backup-vault-keys' lock-down - the unseal keys always 0600 (no failure excused), the root token only when fetched
bk = "deploy/ansible/playbooks/backup-vault-keys.yml"
lds = [t for t in tasks(bk) if str(t.get("name", "")).startswith("Lock down the local backup")]
check("I03 the lock-down excuses no failure (its directory, its files)", [("failed_when" in t, "ignore_errors" in t) for t in lds], [(False, False)] * 2)
res = lambda keys, token: {"results": [{"item": "unseal-keys", "stat": {"exists": keys, **({"path": "/r/unseal-keys"} if keys else {})}},
                                       {"item": "root-token", "stat": {"exists": token, **({"path": "/r/root-token"} if token else {})}}]}
files = lambda keys, token: [render(lds[1]["ansible.builtin.file"]["path"], item=i) for i in render(lds[1]["loop"], _backup_files=res(keys, token))]
check("I03 the directory 0700, the files 0600", (lds[0]["ansible.builtin.file"]["mode"], lds[1]["ansible.builtin.file"]["mode"]), ("0700", "0600"))
check("I03 the root token fetched: the unseal keys and the root token locked down", files(True, True), ["/r/unseal-keys", "/r/root-token"])
check("I03 no root token: the unseal keys alone", files(True, False), ["/r/unseal-keys"])
ak = task(bk, "The unseal keys are in the local backup")["ansible.builtin.assert"]["that"]
check("I03 no unseal keys after the fetch: failed; in check mode (the fetch brings nothing) said, not failed",
      (condition(ak, _backup_files=res(False, False), ansible_check_mode=False), condition(ak, _backup_files=res(False, False), ansible_check_mode=True),
       condition(ak, _backup_files=res(True, False), ansible_check_mode=False)), (False, True, True))

# I04: the seed's retired-path delete and create-environment's KV mount excuse nothing
for path, prefix in (("deploy/ansible/playbooks/seed-vault-secrets.yml", "Delete retired vault path"),
                     ("deploy/ansible/playbooks/create-environment.yml", "Ensure KV secrets engine is mounted")):
    t = task(path, prefix)
    check("I04 %s excuses no failure" % prefix, ("failed_when" in t, "ignore_errors" in t), (False, False))

print("ignored-errors: " + ("ALL-PASS" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY_IGNORED_ERRORS
