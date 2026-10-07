#!/bin/bash
# Every Postgres client a playbook or a test playbook runs over TCP (psql, pg_dump, pg_dumpall, pg_restore, createdb,
# dropdb, vacuumdb, pg_basebackup with -h, a postgres:// URI, host=, a .pgpass or PGHOST; continuation lines joined;
# an argument array P=(-h ...) the same) says -w:
# Ansible runs a task on a terminal, and a client with no password - an empty one, a .pgpass that does not match - asks
# for one there and waits for good (the Keycloak restore in the full run of 2026-10-07 15:11). With -w it fails at once.
# A connection through the local socket as postgres (sudo -u postgres) asks nothing and is not named.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import glob, re, sys
# pg_isready authenticates nothing - it never asks for a password
CLIENT = re.compile(r"\b(psql|pg_dump|pg_dumpall|pg_restore|createdb|dropdb|vacuumdb|pg_basebackup)\b")
OVER_TCP = re.compile(r"(^|\s)-h\s|PGPASSFILE=|\bPGHOST\b|postgres(ql)?://|\bhost=")
# a client's connection arguments kept in an array (P=(-h ...)) and passed as "${P[@]}"
ARGS = re.compile(r"^\s*\w+=\([^)]*-h\s")
bad, seen = [], 0
for f in sorted(glob.glob("deploy/ansible/**/*.yml", recursive=True) + glob.glob("tests/ansible/**/*.yml",
                                                                                   recursive=True)):
    if "/venv/" in f:
        continue
    # a command continued over lines (a trailing backslash) read as one, at its first line's number
    lines, n0, joined = [], None, ""
    for n, line in enumerate(open(f), 1):
        joined, n0 = (joined + " " + line.strip() if joined else line.rstrip("\n")), (n0 or n)
        if not joined.rstrip().endswith("\\"):
            lines.append((n0, joined))
            joined, n0 = "", None
    for n, line in lines:
        code = line.split(" # ")[0]
        if line.lstrip().startswith("#") or "sudo -u postgres" in code:
            continue
        if (CLIENT.search(code) and OVER_TCP.search(code)) or ARGS.search(code):
            seen += 1
            if not re.search(r"(^|[\s(])-w(\s|$|\))", code):
                bad.append(f"{f}:{n}: {code.strip()[:100]}")
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    detail = "\n  ".join(map(str, got)) if isinstance(got, list) else f"got {got}, want {want}"
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + detail))
check(f"every client over TCP never prompts: -w ({seen} calls)", bad, [])
check("the calls found (the scan reaches them)", seen >= 5, True)
print("pg-no-prompt: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
