#!/bin/bash
# scripts/upgrade-expected-inventory.py's step lines: a restore-undo image CNPG can take - name:tag, or
# name:tag@sha256:<digest> - and a bare digest refused (CNPG's webhook refuses it: it reads the major from the tag);
# a restore-undo image is the one the step starts from; barman-after-merge only with barman-check; every step file parses with the rules.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import importlib.machinery
import importlib.util
import os
import sys
import tempfile

loader = importlib.machinery.SourceFileLoader("inv", "scripts/upgrade-expected-inventory.py")
inv = importlib.util.module_from_spec(importlib.util.spec_from_loader("inv", loader))
loader.exec_module(inv)
fails = 0
work = tempfile.mkdtemp()
D = "sha256:" + "b1" * 32


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": got {got!r}, want {want!r}"))


def undo(line):
    """A step of `line` alone, but for the image change it starts from (when the image has a tag to start from)."""
    path = os.path.join(work, "99-x.txt")
    ref = line.split()[2].split("@")[0]
    name, _, tag = ref.rpartition(":") if "/" not in ref.rpartition(":")[2] else (ref, "", "")
    start = f"image {name} {tag} => image {name} new\n" if tag else ""
    open(path, "w").write(start + line + "\n")
    found = []
    try:
        inv.parse(path, undo=found)
    except SystemExit as e:
        return "refused: " + str(e)
    return found


check("name:tag", undo("restore-undo srv ghcr.io/cloudnative-pg/postgresql:17"),
      ["srv ghcr.io/cloudnative-pg/postgresql:17"])
check("name:tag@digest", undo(f"restore-undo srv ghcr.io/cloudnative-pg/postgresql:17@{D}"),
      [f"srv ghcr.io/cloudnative-pg/postgresql:17@{D}"])
check("a registry with a port, name:tag", undo("restore-undo srv localhost:5000/postgresql:17"),
      ["srv localhost:5000/postgresql:17"])
got = undo(f"restore-undo srv ghcr.io/cloudnative-pg/postgresql@{D}")
check("a bare digest: refused, saying why", (got[:8], "no tag" in str(got)), ("refused:", True))
got = undo("restore-undo srv localhost:5000/postgresql")
check("a registry with a port, no tag: refused", got[:8], "refused:")



def flags_of(*lines):
    path = os.path.join(work, "98-y.txt")
    open(path, "w").write("\n".join(lines) + "\n")
    found = set()
    try:
        inv.parse(path, flags=found)
    except SystemExit as e:
        return "refused: " + str(e)
    return sorted(found)


def undo_in_step(image):
    """A step moving postgresql 17 -> 18.6 whose restore-undo names `image`."""
    path = os.path.join(work, "97-z.txt")
    open(path, "w").write("image ghcr.io/cloudnative-pg/postgresql 17 => image ghcr.io/cloudnative-pg/postgresql 18.6\n"
                          f"restore-undo srv {image}\n")
    try:
        inv.parse(path)
        return "parsed"
    except SystemExit as e:
        return "refused: " + str(e)


check("restore-undo: the image the step starts from", undo_in_step(f"ghcr.io/cloudnative-pg/postgresql:17@{D}"), "parsed")
got = undo_in_step("ghcr.io/cloudnative-pg/postgresql:18.6")
check("restore-undo: the image the step moves to - refused", (got[:8], "starts from" in got), ("refused:", True))
got = undo_in_step("ghcr.io/cloudnative-pg/postgresql:16")
check("restore-undo: another tag - refused", got[:8], "refused:")


check("barman-after-merge with barman-check", flags_of("barman-check", "barman-after-merge"),
      ["barman-after-merge", "barman-check"])
got = flags_of("barman-after-merge")
check("barman-after-merge alone: refused (no base backup to take early)", (got[:8], "without barman-check" in got),
      ("refused:", True))

for name in sorted(f[:-4] for f in os.listdir(inv.STEPS) if f.endswith(".txt")):
    found = []
    try:
        inv.parse(os.path.join(inv.STEPS, name + ".txt"), undo=found)
        ok = True
    except SystemExit as e:
        ok = str(e)
    check(f"step {name} parses", ok, True)

print("step-lines: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
