#!/bin/bash
# forgejo-doctor.yml (task deploy:forgejo:orphans): Forgejo's orphaned package blobs counted from the doctor's own line
# (output it cannot read fails, never taken for none), removed only at the count a preview showed and given back, under
# a lock on the package blobs' table held over the doctor's runs (an upload in flight is a file no row refers to: its
# row and its file written in one transaction - Forgejo 15's source, 2026-11-15), and read again: none left.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import re
import subprocess
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import load  # noqa: E402
from templar import condition, render, trust_as_template  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = load("deploy/ansible/playbooks/forgejo-doctor.yml")[0]
pv = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in play["vars"].items()}
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
ts = list(walk(play["tasks"]))
by = {t.get("name"): t for t in ts}
names = [t.get("name") for t in play["tasks"]]
R = lambda t, **kw: render(t, **dict(pv, **kw))  # noqa: E731
# the doctor's lines as it prints them (each check's step: " - [<level>] ..."): production's of 2026-11-14, a store
# with none, an empty store, --fix's, and what it prints when it cannot reach its database (exit 0)
ORPHANS = " - [W] Found 21/7005 (494 MiB/654 GiB) orphaned package blob(s)"
NONE = " - [I] Found 7005 (654 GiB) package blob(s)"
EMPTY = " - [I] Found 0 (0 B) package blob(s)"
DELETED = " - [I] Deleted 21/21 orphaned package blob(s)"
NODB = "Error whilst initializing the database: dial tcp 127.0.0.1:6432: connect: connection refused"

# ── the read: bounded, as Forgejo's user, in its home, in a preview too ─────────────────────────────────
read = by["The orphaned package blobs Forgejo's doctor finds"]
argv = R(read["ansible.builtin.command"]["argv"])
check("the doctor's read: bounded (timeout, then killed), its storage-packages check alone with production's config, "
      "as forgejo in its home, a read in a preview too",
      (list(argv[:4]), argv[4:], read.get("become_user"), read["ansible.builtin.command"].get("chdir"),
       read.get("check_mode"), read.get("changed_when")),
      (["timeout", "--kill-after=30s", "8m", "/usr/local/bin/forgejo"],
       ["doctor", "check", "--run", "storage-packages", "--config", "/var/lib/forgejo/custom/conf/app.ini"],
       "forgejo", "/var/lib/forgejo", False, False))
count = by["How many - read from the doctor's own line, or the play fails"]
def counted(out):
    reg = {"stdout": out}
    return (condition(count.get("failed_when", False), **dict(pv, _before=reg)),
            str(R(count["ansible.builtin.set_fact"]["forgejo_orphans_before"], _before=reg)).strip())
check("the count from the doctor's own line: 21 of production's, 0 with none or an empty store; what it prints "
      "without its database, nothing or another check's lines fail - never read as none",
      [counted(o) for o in (ORPHANS, NONE, EMPTY)] + [counted(o)[0] for o in (NODB, "", " - [I] OK")],
      [(False, "21"), (False, "0"), (False, "0"), True, True, True])

# ── the count given back: the preview's, or nothing removed ─────────────────────────────────────────────
given = by["The count to remove given back - the preview's"]
check("removed only at the count given back (-e forgejo_orphans_expected=N, a string or a number): none given or "
      "another count refused; asked only with orphans found, never in a preview",
      ([condition(given["ansible.builtin.assert"]["that"], **dict(pv, forgejo_orphans_before="21", **e))
        for e in ({}, {"forgejo_orphans_expected": "20"}, {"forgejo_orphans_expected": "21"},
                  {"forgejo_orphans_expected": 21})],
       [condition(given["when"], forgejo_orphans_before=b, ansible_check_mode=c)
        for b, c in (("21", False), ("0", False), ("21", True))]),
      ([False, False, True, True], [True, False, False]))

# ── the removal: under the lock, counted again, removed at the count given, read again ──────────────────
rm = by["Removed by Forgejo's doctor under the lock - counted again, removed at the count given, read again"]
blk = by["Removed under the lock at the count given, none left"]
sh = rm["ansible.builtin.shell"]
script = str(R(sh["cmd"], forgejo_orphans_expected="21"))
lines = [x.strip() for x in script.splitlines()]
at = lambda pre: next((i for i, x in enumerate(lines) if x.startswith(pre)), -1)  # noqa: E731
bang = [i for i, x in enumerate(lines) if x.startswith("\\!")]
fix = next((i for i in bang if lines[i].endswith("--fix")), -1)
check("the database password on stdin (no_log), never in the environment; psql stops at its first error, asks for "
      "no password (-w), to the primary (HAProxy 127.0.0.1:5000), as Forgejo's user; never in a preview",
      (str(rm.get("ansible.builtin.shell", {}).get("stdin")), rm.get("no_log"), "environment" in rm,
       "read -r PGPASSWORD" in script, re.search(r"psql .*-v ON_ERROR_STOP=1", script) is not None, " -w " in script,
       "-h 127.0.0.1 -p 5000" in script, rm.get("become_user"),
       [condition(blk["when"], forgejo_orphans_before=b, ansible_check_mode=c)
        for b, c in (("21", False), ("0", False), ("21", True))], "when" in rm),
      ("{{ _db_password }}", True, False, True, True, True, True, "forgejo", [True, False, False], False))
check("the lock (SHARE MODE on package_blob, bounded wait) taken in its transaction before the doctor runs at all; "
      "counted under it, --fix only in the branch where the count is the one given, after a statement proves the "
      "session (and its lock) alive; read again under it, a statement before; committed after; refused: rolled back",
      (at("BEGIN;") < at("SET LOCAL lock_timeout") < at("LOCK TABLE package_blob IN SHARE MODE;") < min(bang or [-1]),
       len(bang), at("\\if :SHELL_ERROR") < at("\\else") < fix < at("\\endif"),
       lines[fix - 2:fix] == ["SELECT 'the lock held';", "\\echo ==== removed"],
       lines[fix + 1:fix + 4] == ["SELECT 'the lock held';", "\\echo ==== read again", lines[bang[-1]]],
       lines[bang[-1] + 1] == "COMMIT;", at("ROLLBACK;") < at("\\else"), "==== REFUSED" in lines[at("\\if") + 1]),
      (True, 3, True, True, True, True, True, True))
# the count line under the lock run as psql's \! runs it (sh -c), the doctor replaced by its output: the count given
# found exits 0 (the --fix branch), any other count, none, or no line exits non-zero (SHELL_ERROR: refused)
counting = lines[bang[0]][2:].strip()
want = re.search(r"(?m)^export WANT=(.*)$", script)
doctor = re.search(r"(?m)^export DOCTOR=(.*)$", script)
def under_lock(out):
    # the doctor replaced by cat, its output on stdin; WANT as the script exports it (its quotes as sh reads them)
    env = "export WANT=" + want.group(1) + "; export DOCTOR=cat; "
    return subprocess.run(["sh", "-c", env + counting], input=out + "\n", capture_output=True,
                          text=True).returncode == 0
check("the doctor the script runs is the read's (bounded, the same check), the count it wants the one given",
      (doctor and subprocess.run(["sh", "-c", "eval set -- " + doctor.group(1) + "; printf '%s\\n' \"$@\""],
                                 capture_output=True, text=True).stdout.split(), bool(want) and "Found 21/" in want.group(1)),
      (list(argv), True))
check("under the lock: the doctor's count the one given (21) goes on to --fix; 20, 210, none, its failure refuse",
      [under_lock(o) for o in (ORPHANS, ORPHANS.replace("21/", "20/"), ORPHANS.replace("21/", "210/"), NONE, NODB)],
      [True, False, False, False, False])
parse = by["What the doctor removed, and read after - from its own lines"]["ansible.builtin.set_fact"]
done = by["Removed at the count given, none left"]
def judged(out, rc=0):
    reg = {"stdout": out, "rc": rc, "stdout_lines": out.splitlines(), "stderr_lines": []}
    # the removal fails on its own (psql's exit, a refusal) - else the assert judges what it removed and read after
    if condition(rm["failed_when"], **dict(pv, _removal=reg)):
        return False
    got = {k: R(v, _removal=reg) for k, v in parse.items()}
    return condition(done["ansible.builtin.assert"]["that"], **dict(pv, _removal=reg, forgejo_orphans_expected="21",
                                                                   **got))
ok = "\n".join(["==== counted under the lock", ORPHANS, "the lock held", "==== removed", DELETED, "the lock held",
                "==== read again", NONE])
check("judged from the doctor's own lines: 21 of 21 removed and none read after passes; refused, fewer removed than "
      "found, another count removed, an orphan read after, nothing read after, psql failing - each fails the play",
      [judged(ok), judged("==== counted under the lock\n" + ORPHANS.replace("21/", "22/")
                          + "\n==== REFUSED: the count under the lock is not the one given - nothing removed"),
       judged(ok.replace("Deleted 21/21", "Deleted 20/21")), judged(ok.replace("Deleted 21/21", "Deleted 22/22")),
       judged(ok.replace(NONE, ORPHANS.replace("21/", "1/"))), judged(ok.split("==== read again")[0]),
       judged(ok, rc=3)],
      [True, False, False, False, False, False, False])
check("the preview says how to remove them; the removal changes only where the doctor deleted",
      (str(R(by["The orphaned package blobs"]["ansible.builtin.debug"]["msg"], forgejo_orphans_before="21",
             ansible_check_mode=True)).endswith("-e forgejo_orphans_expected=21"),
       [condition(rm["changed_when"], **dict(pv, _removal={"stdout": o})) for o in (ok, "")]),
      (True, [True, False]))
resc = blk.get("rescue") or [{}]
msg = str(R((resc[0].get("ansible.builtin.fail") or {}).get("msg", ""), ansible_failed_task={"name": "x"},
            _removal={"rc": 3, "stdout_lines": ["==== counted under the lock", ORPHANS, "noise"],
                      "stderr_lines": ["psql: error: canceling statement due to lock timeout"]}))
check("any failure in it - the removal's own (its output hidden: the password on stdin), the judgement's - fails the "
      "play with what the doctor said and psql's error shown, nothing else of the output",
      (len(resc), "ansible.builtin.fail" in resc[0], ORPHANS.strip() in msg, "lock timeout" in msg, "noise" in msg),
      (1, True, True, True, False))
check("on the VIP's Pi alone, the steps in order",
      (names, [t.get("name") for t in blk.get("block") or []]),
      (["On the Pi holding the VIP alone", "The orphaned package blobs Forgejo's doctor finds",
        "How many - read from the doctor's own line, or the play fails", "The orphaned package blobs",
        "The count to remove given back - the preview's", "Removed under the lock at the count given, none left"],
       ["Removed by Forgejo's doctor under the lock - counted again, removed at the count given, read again",
        "What the doctor removed, and read after - from its own lines", "Removed at the count given, none left"]))
sys.exit(1 if fails else 0)
PYCHECK
rc=$?
[ "$rc" = 0 ] && echo "forgejo-doctor: ALL-PASS" || echo "forgejo-doctor: FAILED"
exit "$rc"
