#!/bin/bash
# Forgejo's config on the Pis (setup-pi-services.yml): no sign-up, no git over SSH and no keys file for the Pis' sshd -
# DISABLE_SSH alone left Forgejo writing it (a key added, the admin's resync) and its doctor's default checks failing on
# it missing (Forgejo 15's source, 2026-11-15) - the keys file removed; a narrow run (deploy:pi-services -- --tags
# forgejo-config) reaching every fact the config names; Forgejo's restart pending by content until it ran (a restart
# that failed or was refused left the old process, a re-run notifying nothing), its record written only after it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import configparser
import re
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import load, tasks  # noqa: E402
from templar import condition, render  # noqa: E402
import yaml  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def strings(v):
    if isinstance(v, dict):
        for x in v.values():
            yield from strings(x)
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
    elif isinstance(v, str):
        yield v
doc = load("deploy/ansible/playbooks/setup-pi-services.yml")
every = list(tasks(doc))
by = {t.get("name"): t for t in every}
tagged = lambda t: "forgejo-config" in (t.get("tags") or [])  # noqa: E731
CONFIG = "/var/lib/forgejo/custom/conf/app.ini"
UNIT = "/etc/systemd/system/forgejo.service"
cfg = [t for t in every if (t.get("ansible.builtin.copy") or {}).get("dest") == CONFIG]

# ── the settings, in the sections Forgejo reads them from ───────────────
text = cfg[0]["ansible.builtin.copy"]["content"] if len(cfg) == 1 else ""
plain = re.sub(r"(?m)^\s*\{%.*%\}\s*$\n?", "", re.sub(r"\{\{.*?\}\}", "X", text))
ini = configparser.RawConfigParser(strict=True)
ini.read_string("[top]\n" + plain)
get = lambda sec, key: ini.get(sec, key, fallback=None)  # noqa: E731
check("one config written; no sign-up ([service]), no git over SSH and no keys or principals file ([server])",
      (len(cfg), get("service", "DISABLE_REGISTRATION"), get("server", "DISABLE_SSH"),
       get("server", "SSH_CREATE_AUTHORIZED_KEYS_FILE"), get("server", "SSH_CREATE_AUTHORIZED_PRINCIPALS_FILE")),
      (1, "true", "true", "false", "false"))
check("none of them anywhere else (a [service] or [server] section given twice: the later one's word)",
      sorted(s for s in ini.sections() if s in ("service", "server")), ["server", "service"])
keys = by.get("Forgejo's SSH keys file gone") or {}
check("Forgejo's keys file for the Pis' sshd removed, on each Pi (no host limit), in the narrow run",
      ((keys.get("ansible.builtin.file") or {}).get("path"), (keys.get("ansible.builtin.file") or {}).get("state"),
       tagged(keys), "when" in keys, "delegate_to" in keys or "run_once" in keys),
      ("/var/lib/forgejo/.ssh/authorized_keys", "absent", True, False, False))

# ── the narrow run: the facts the config names, back through every task setting one ──────────────────────
NAME = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
def reads(x):
    return {n for st in strings(x) for e in re.findall(r"\{\{(.*?)\}\}|\{%(.*?)%\}", st, re.S)
            for part in e for n in NAME.findall(part)}
sets = {}
for t in every:
    sf = t.get("ansible.builtin.set_fact") or {}
    for n in ({t.get("register")} | set(sf if isinstance(sf, dict) else {})) - {None}:
        sets.setdefault(n, []).append(t)
need, todo = set(), (reads(cfg[0]) if cfg else set()) & set(sets)
while todo:
    n = todo.pop()
    need.add(n)
    for t in sets[n]:
        todo |= (reads({k: v for k, v in t.items() if k != "register"}) & set(sets)) - need
setters = [t for t in every if any(t in sets[n] for n in need)]
guards = [t for t in every if (t.get("ansible.builtin.assert") or t.get("ansible.builtin.fail")) and reads(t) & need]
cred = by.get("Its credentials are all there") or {}
check("the narrow run reaches every fact the config names (the database host among them), every task setting one and "
      "every guard reading one (the PgBouncer refusal); the config tagged, the credentials' check on every run",
      ("forgejo_db_host_effective" in need, bool(guards), [t.get("name") for t in setters + guards if not tagged(t)],
       bool(cfg) and tagged(cfg[0]), "always" in (cred.get("tags") or [])),
      (True, True, [], True, True))
# the names the check reads (bare expressions), and each secret the config names as the play maps it to the inventory
asserted = {n for e in cred["ansible.builtin.assert"]["that"] for n in NAME.findall(e)}
pvars = {k: v for p in doc for k, v in (p.get("vars") or {}).items()}
inv = lambda n: (reads(pvars[n]) or {n}) if n in pvars else {n}  # noqa: E731
check("the credentials' check refuses an empty JWT secret too (missing, each Pi made its own: a failover rejected "
      "Woodpecker's tokens) - and every secret the config names",
      sorted(n for n in reads(cfg[0]) if re.search(r"secret|token|password", n) and not inv(n) <= asserted), [])
check("an empty JWT secret refused, a set one passes",
      [condition(cred["ansible.builtin.assert"]["that"], **dict(
          {n: "x" for n in asserted if n not in ("default", "length")}, forgejo_jwt_secret=j)) for j in ("", "x")],
      [False, True])

# ── Forgejo's restart pending by content, recorded only once it ran ─────────────────────────────────────
pend = by.get("Forgejo's restart pending here - its unit and config against the ones it last loaded") or {}
inc = pend.get("ansible.builtin.include_tasks") or {}
pv = pend.get("vars") or {}
check("its restart pending by its unit and config (tasks/restart-pending.yml), in the narrow run, in no preview, after "
      "the config and the unit are written and Forgejo started (a Forgejo started now: current)",
      (inc.get("file"), (inc.get("apply") or {}).get("tags"), tagged(pend), pv.get("loaded_service"),
       pv.get("loaded_files"), [condition(pend.get("when", True), ansible_check_mode=c) for c in (False, True)],
       min(every.index(t) for t in every if t is pend) > max(every.index(t) for t in every if (t.get(
           "ansible.builtin.copy") or {}).get("dest") in (CONFIG, UNIT) or t.get("name") == "Enable and start Forgejo"),
       [str(render(pv["loaded_started_now"], _forgejo_start={"status": {"ActiveState": s}})).strip()
        for s in ("inactive", "active")]),
      ("tasks/restart-pending.yml", ["forgejo-config"], True, "forgejo", [UNIT, CONFIG], [True, False], True,
       ["True", "False"]))
go = by.get("Forgejo restarted where pending") or {}
rec = by.get("Forgejo's unit and config recorded as loaded - found current") or {}
check("pending: Restart Forgejo notified (guarded, one Pi at a time); current: recorded now - neither in a preview",
      (go.get("notify"), tagged(go), [condition(go.get("when"), ansible_check_mode=c, _restart_pending={
          "stdout_lines": [s, "h"]}) for c, s in ((False, "pending"), (False, "current"), (True, "pending"))],
       (rec.get("ansible.builtin.include_tasks") or {}).get("file"), tagged(rec), (rec.get("vars") or {}).get("loaded_hash"),
       [condition(rec.get("when"), ansible_check_mode=c, _restart_pending={"stdout_lines": [s, "h"]})
        for c, s in ((False, "current"), (False, "pending"), (True, "current"))]),
      ("Restart Forgejo", True, [True, False, False], "tasks/restart-recorded.yml", True,
       "{{ _restart_pending.stdout_lines[1] }}", [True, False, False]))
# the record after a restart: a handler listening to Restart Forgejo, defined after it (handlers run in their order) -
# a restart that failed ends that Pi's run before it; in every playbook that restarts Forgejo
for f in ("setup-pi-services.yml", "setup-patroni.yml"):
    hs = [h for p in load("deploy/ansible/playbooks/" + f) for h in p.get("handlers") or []]
    hn = [h.get("name") for h in hs]
    r = [h for h in hs if h.get("listen") == "Restart Forgejo"]
    check(f"{f}: Forgejo's record written by a handler listening to Restart Forgejo, after the restart, on any tag's run, "
          "in no preview (it restarted nothing)",
          (len(r), r and (r[0].get("ansible.builtin.include_tasks") or {}).get("file"),
           r and ((r[0].get("ansible.builtin.include_tasks") or {}).get("apply") or {}).get("tags"),
           "Restart Forgejo" in hn and bool(r) and hn.index(r[0].get("name")) > hn.index("Restart Forgejo"),
           [condition(r[0].get("when", True), ansible_check_mode=c) for c in (False, True)] if r else None),
          (1, "tasks/forgejo-recorded.yml", ["always"], True, [True, False]))
fr = load("deploy/ansible/playbooks/tasks/forgejo-recorded.yml")
check("tasks/forgejo-recorded.yml: the files as Forgejo now runs them (started on them just now), their hash recorded",
      ([(t.get("ansible.builtin.include_tasks"), (t.get("vars") or {}).get("loaded_service")) for t in fr],
       (fr[0].get("vars") or {}).get("loaded_files"), (fr[0].get("vars") or {}).get("loaded_started_now"),
       (fr[1].get("vars") or {}).get("loaded_hash")),
      ([("restart-pending.yml", "forgejo"), ("restart-recorded.yml", "forgejo")], [UNIT, CONFIG], True,
       "{{ _restart_pending.stdout_lines[1] }}"))

# ── the Taskfile: the narrow run, and the orphans' playbook its own task ────────────────────────────────
tf = yaml.safe_load(open("Taskfile.yml"))["tasks"]
cmds = lambda n: [c if isinstance(c, str) else c.get("cmd", "") for c in tf[n].get("cmds", [])]  # noqa: E731
check("deploy:pi-services passes its arguments on (-- --tags forgejo-config); deploy:forgejo:orphans runs the "
      "doctor's playbook on production with them, the inventory's secrets read (.env)",
      ([c.endswith("playbooks/setup-pi-services.yml {{.CLI_ARGS}}") for c in cmds("deploy:pi-services")],
       cmds("deploy:forgejo:orphans"), tf["deploy:forgejo:orphans"].get("dotenv")),
      ([True], ["venv/bin/ansible-playbook -i inventory/production.yml playbooks/forgejo-doctor.yml {{.CLI_ARGS}}"],
       ["../../.env"]))
sys.exit(1 if fails else 0)
PYCHECK
rc=$?
[ "$rc" = 0 ] && echo "forgejo-config: ALL-PASS" || echo "forgejo-config: FAILED"
exit "$rc"
