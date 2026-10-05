#!/usr/bin/env python3
"""upgrade-defaults.py - the playbook defaults each upgrade step moves, from its step file's default lines:

    default <file under ops>: <line before> => <line after>

(the lines compared stripped of their indentation, which the new one keeps; every line of the file equal to the old one
is replaced - at least one must be). A step's playbook lines pass its versions with -e; its default lines make them
the playbooks' defaults, so a playbook run without them - a rebuild between two steps, a DR - installs what production
then runs, not the baseline under a newer etcd.

  --apply <step>   the step's default lines into the ops working tree - production's defaults phase
                   (scripts/upgrade-production.py commits and pushes them)
  --lint           every step's default lines, in step order, onto the working tree's files: each old line there at
                   its turn
  --make-branch    the branch upgrade/defaults-at-targets made anew: main and one commit with every step's default
                   lines (no checkout - a temporary index); the targets build (test:upgrade:build-targets) runs it
  --show <commit> <steps...>  the files those steps' lines change, as they are at <commit> with the lines applied
                   (JSON: {path: content}) - what production's proof check compares the working tree with
"""
import json
import os
import re
import subprocess
import sys
import tempfile

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEPS = os.path.join(OPS, "tests", "ansible", "upgrade", "steps")
BRANCH = "upgrade/defaults-at-targets"
LINE = re.compile(r"default (\S+?): (.+?) => (.+)")


def step_names():
    return sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))


def default_lines(step):
    """[(path, old, new)] of the step file, in order."""
    out = []
    for raw in open(os.path.join(STEPS, step + ".txt")):
        line = raw.strip()
        if line.startswith("default "):
            m = LINE.fullmatch(line)
            if not m:
                sys.exit(f"{step}: not a default line: {line}")
            out.append(m.groups())
    return out


def apply(text, old, new, where):
    """`text` with every line equal to `old` (stripped) replaced by `new`, its indentation kept."""
    lines, hits = text.split("\n"), 0
    for i, line in enumerate(lines):
        if line.strip() == old:
            lines[i] = line[:len(line) - len(line.lstrip())] + new
            hits += 1
    if not hits:
        raise ValueError(f"{where}: no line '{old}'")
    return "\n".join(lines)


def git(*args, **kw):
    return subprocess.run(["git", "-C", OPS, *args], capture_output=True, text=True, check=True, **kw).stdout


def applied(read, steps):
    """{path: content} of the files `steps`' default lines change, `read(path)` giving the starting content."""
    files = {}
    for step in steps:
        for path, old, new in default_lines(step):
            if path not in files:
                files[path] = read(path)
            files[path] = apply(files[path], old, new, f"{step}: {path}")
    return files


def make_branch():
    files = applied(lambda p: git("show", f"main:{p}"), step_names())
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"))
        subprocess.run(["git", "-C", OPS, "read-tree", "main"], env=env, check=True)
        for path, content in files.items():
            blob = subprocess.run(["git", "-C", OPS, "hash-object", "-w", "--stdin"], input=content,
                                  capture_output=True, text=True, check=True).stdout.strip()
            mode = git("ls-tree", "main", "--", path).split()[0]
            subprocess.run(["git", "-C", OPS, "update-index", "--cacheinfo", f"{mode},{blob},{path}"], env=env,
                           check=True)
        tree = subprocess.run(["git", "-C", OPS, "write-tree"], env=env, capture_output=True, text=True,
                              check=True).stdout.strip()
    msg = ("upgrade: every playbook default at the upgrade's targets (merged at the rollout's end)\n\n"
           "Made by scripts/upgrade-defaults.py --make-branch from every step file's default lines.\n")
    commit = git("commit-tree", tree, "-p", "main", "-m", msg).strip()
    git("update-ref", f"refs/heads/{BRANCH}", commit)
    print(f"{BRANCH}: {commit[:10]} - main and {len(files)} files: {', '.join(sorted(files))}")


def main():
    a = sys.argv[1:]
    try:
        if a[:1] == ["--apply"] and len(a) == 2:
            for path, content in applied(lambda p: open(os.path.join(OPS, p)).read(), [a[1]]).items():
                with open(os.path.join(OPS, path), "w") as f:
                    f.write(content)
                print(f"{a[1]}: {path}")
        elif a == ["--lint"]:
            files = applied(lambda p: open(os.path.join(OPS, p)).read(), step_names())
            print(f"every step's default lines apply in order ({len(files)} files)")
        elif a == ["--make-branch"]:
            if git("rev-parse", "--abbrev-ref", "HEAD").strip() == BRANCH:
                sys.exit(f"REFUSED: {BRANCH} is checked out")
            make_branch()
        elif a[:1] == ["--show"] and len(a) >= 2:
            print(json.dumps(applied(lambda p: git("show", f"{a[1]}:{p}"), a[2:])))
        else:
            sys.exit(__doc__)
    except ValueError as e:
        sys.exit(f"REFUSED: {e}")


if __name__ == "__main__":
    main()
