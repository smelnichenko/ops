#!/bin/bash
# No pipeline under pipefail ends in a grep that leaves at its first match (grep -q): the writer's next line is a
# SIGPIPE, it exits 141, and pipefail turns a match into "no match" - pi-restore-check's base backup found read as none,
# red one run in three in CI (2026-11-28; rclone, Go programs and a shell loop write a line at a time). The reader reads
# to the end instead (grep ... > /dev/null), or reads a here-string (grep -q ... <<< "$x": no writer to kill). Read in
# every shell script ops runs or installs: scripts/*.sh, the playbooks' files/*.sh and scripts/*.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import re' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_GREP_READS'
import glob, re

fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f"\n    got:  {got!r}\n    want: {want!r}"))


PIPEFAIL = re.compile(r"^\s*set\s+-[a-z]*o\s+pipefail|^\s*set\s+-o\s+pipefail", re.M)
# a pipe (never ||) into grep with -q among its options (alone or bundled: -qE, -Eq, -qxF)
EARLY = re.compile(r"(?<!\|)\|(?!\|)\s*grep(\s+-[a-zA-Z]+)*\s+-[a-zA-Z]*q[a-zA-Z]*\b")


def early_readers(text):
    """The logical lines (backslash continuations joined) of a pipefail script whose pipe ends in grep -q."""
    if not PIPEFAIL.search(text):
        return []
    out, logical = [], ""
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        logical += line.rstrip("\\") + " "
        if line.rstrip().endswith("\\"):
            continue
        if EARLY.search(logical):
            out.append(logical.strip())
        logical = ""
    return out


PF = "set -euo pipefail\n"
check("the rule: a pipe into grep -q (-qE, -Eq, a continued line) under pipefail named; ||, a file, a here-string, "
      "grep's to-the-end form and a script without pipefail not",
      [bool(early_readers(PF + "rclone lsf x | grep -qE '^a$' || exit 1\n")),
       bool(early_readers(PF + "x | grep -Eq a\n")),
       bool(early_readers(PF + "kubectl get x \\\n  | grep -q y\n")),
       bool(early_readers(PF + "a || grep -q b file\n")),
       bool(early_readers(PF + "grep -q b \"$f\"\n")),
       bool(early_readers(PF + "grep -q b <<< \"$x\"\n")),
       bool(early_readers(PF + "x | grep b > /dev/null\n")),
       bool(early_readers("x | grep -q b\n")),
       bool(early_readers(PF + "# x | grep -q b\n"))],
      [True, True, True, False, False, False, False, False, False])

# pi-restore-check.sh runs on the Pis (restore logic): its readers are fixed in a pull request of their own, behind a
# copy run - listed here until then, each one still needed
PENDING = {
    "deploy/ansible/playbooks/files/pi-restore-check.sh": 3,
}
files = sorted(glob.glob("scripts/*.sh") + glob.glob("deploy/ansible/playbooks/files/*.sh")
               + glob.glob("deploy/ansible/playbooks/scripts/*"))
found = {}
for f in files:
    try:
        text = open(f).read()
    except (UnicodeDecodeError, IsADirectoryError):
        continue
    if not text.startswith("#!") or "sh" not in text.splitlines()[0]:
        continue
    found[f] = early_readers(text)
bad = [f"{f}: {line[:140]}" for f, lines in found.items() if f not in PENDING for line in lines]
check(f"no shell script ops runs or installs ends a pipe in grep -q under pipefail ({len(found)} scripts read)", bad, [])
check("every pending one still there, as many as listed (a fixed one comes off the list)",
      {f: len(found.get(f, [])) for f in PENDING}, PENDING)
print("grep-reads-to-end: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
raise SystemExit(1 if fails else 0)
PY_GREP_READS
