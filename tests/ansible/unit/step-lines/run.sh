#!/bin/bash
# scripts/upgrade-expected-inventory.py's step lines: a restore-undo image CNPG can take - name:tag, or
# name:tag@sha256:<digest> - and a bare digest refused (CNPG's webhook refuses it: it reads the major from the tag);
# a restore-undo image is the one the step starts from; barman-after-merge only with barman-check; every step file parses with the rules;
# a line two kinds match read as the first; the base -e name rule; the ClickHouse users/compat and restore-undo modes.
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

every = sorted(f[:-4] for f in os.listdir(inv.STEPS) if f.endswith(".txt"))
flagged = {}
for name in every:
    found = set()
    inv.parse(os.path.join(inv.STEPS, name + ".txt"), flags=found)
    for f in found:
        flagged.setdefault(f, []).append(name.split("-")[0])
# restarts judged as expected only where the step upgrades the control plane: a wiring that marks more lets their
# crash loops through
check("restarts-control-plane: the three kubeadm steps exactly", flagged.get("restarts-control-plane"),
      ["13", "42", "43"])
check("barman-after-merge: step 47 only", flagged.get("barman-after-merge"), ["47"])
# the PostgreSQL major a step moves the cluster to - its base backup must be taken on it (the old major's backups do not
# replay into the new one): 47's 18, none for the other barman-check steps (CNPG, its store)
check("pg-major: 47 moves to 18, 24 and 25 to none", [inv.pg_major(s) for s in ("47-postgres-18", "24-cnpg", "25-versitygw")],
      ["18", "", ""])

for name in sorted(f[:-4] for f in os.listdir(inv.STEPS) if f.endswith(".txt")):
    found = []
    try:
        inv.parse(os.path.join(inv.STEPS, name + ".txt"), undo=found)
        ok = True
    except SystemExit as e:
        ok = str(e)
    check(f"step {name} parses", ok, True)



def test_images_of(line):
    path = os.path.join(work, "96-t.txt")
    open(path, "w", encoding="utf-8").write(line + "\n")
    found = []
    try:
        inv.parse(path, test_images=found)
    except SystemExit as e:
        return "refused: " + str(e)[:40]
    return found


# a test-image line: an image name and tag in ASCII alone (\w is Unicode's otherwise - a look-alike letter would name
# an image no registry holds)
check("test-image: a name with a registry path and a tag", test_images_of("test-image git.pmon.dev/schnappy/site 1.2_3-a"),
      ["git.pmon.dev/schnappy/site 1.2_3-a"])
check("test-image: a non-ASCII letter in the name or the tag - not a test-image line",
      [str(test_images_of(l))[:8] for l in ("test-image git.pmon.dev/schnappy/sité 1", "test-image site 1é")],
      ["refused:", "refused:"])


def parsed(*lines, **collectors):
    """parse() of a step of `lines`: its changes (where dropped) and the collectors, or the refusal."""
    path = os.path.join(work, "95-p.txt")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    try:
        return [c[:2] for c in inv.parse(path, **collectors)], collectors
    except SystemExit as e:
        return "refused: " + str(e)[:40]


# a line two kinds match is the kind tried first: an argo-out-of-sync line with " => " in it names an app, no change;
# a "- " line with " => " in it is a change from "- <line>" - the table's order, not the line's look, decides
check("argo-out-of-sync before ' => ': an app, no change", parsed("argo-out-of-sync a => b", out_of_sync=[]),
      ([], {"out_of_sync": ["a => b"]}))
check("' => ' before '- ': a change, not a removal", parsed("- image a 1 => image a 2"), ([("- image a 1", "image a 2")], {}))
# a base -e name is a shell variable's: [A-Za-z_] then ASCII word characters - one character will do; a leading digit
# or a non-ASCII letter (\w is Unicode's otherwise) is no base line
check("base -e: a one-character name", parsed("base -e A=1", base=[]), ([], {"base": ["-e A=1"]}))
check("base -e: a leading digit or a non-ASCII letter - not a base line",
      [str(parsed(l, base=[]))[:8] for l in ("base -e 1A=1", "base -e aé=1")], ["refused:", "refused:"])
# a Collectors or its fields by keyword - given both, the keyword one would silently collect nothing
open(os.path.join(work, "94-e.txt"), "w").write("base -e A=1\n")
try:
    inv.parse(os.path.join(work, "94-e.txt"), inv.Collectors(), base=[])
    got = "parsed"
except TypeError as e:
    got = "TypeError: " + str(e)[:9]
check("parse(): a Collectors and keyword collectors - refused", got, "TypeError: parse(): ")

# the modes over a fixture of steps: ClickHouse's users and compatibility are the latest line up to the step (an
# earlier step's carries on), default,schnappy and nothing before the first; restore-undo the step's first line
fixture = os.path.join(work, "steps")
os.makedirs(fixture)
for name, lines in (("01-a", ["clickhouse-compat 24.8"]), ("02-b", ["clickhouse-users schnappy", "clickhouse-compat 25.8"]),
                    ("03-c", ["image pg 17 => image pg 18", "restore-undo one pg:17", "restore-undo two pg:17"]),
                    ("00-z", [])):
    open(os.path.join(fixture, name + ".txt"), "w").write("".join(l + "\n" for l in lines))
saved, inv.STEPS = inv.STEPS, fixture
names = sorted(f[:-4] for f in os.listdir(fixture))
try:
    check("--clickhouse-users: default,schnappy before the first line, then the latest up to the step",
          [inv.MODES["--clickhouse-users"](s, names) for s in names], ["default,schnappy", "default,schnappy",
                                                                       "schnappy", "schnappy"])
    check("--clickhouse-compat: nothing before the first line, then the latest up to the step",
          [inv.MODES["--clickhouse-compat"](s, names) for s in names], ["", "24.8", "25.8", "25.8"])
    check("--restore-undo: the step's first line", inv.MODES["--restore-undo"]("03-c", names), "one pg:17")
finally:
    inv.STEPS = saved
print("step-lines: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
