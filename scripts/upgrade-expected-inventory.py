#!/usr/bin/env python3
"""upgrade-expected-inventory.py - what the Vagrant copy must run after an upgrade step, and which refs make it.

A step is a file tests/ansible/upgrade/steps/NN-<name>.txt listing its inventory changes:

    # what the step upgrades and why
    <inventory line before> => <inventory line after>
    + <inventory line the step adds>
    - <inventory line the step removes>
    playbook <ops playbook> <arguments>       (a host-side change: run against the Vagrant inventory)

and a branch upgrade/NN-<name> in ../infra and/or ../platform carrying the change itself, each branch stacked on the
previous step's branch in the same repo (merged to main in this order at the production rollout).

Inventory: production's (tests/ansible/upgrade/prod-inventory.txt) with the changes of every step up to and including
the given one applied, in order. A change whose "before" line is not there at that point aborts: the step file is
stale, and applying it anyway would check nothing.

Playbooks (--playbooks): the playbook lines of the given step only. Unlike the refs they are not replayed: a Helm
install is not an "at least" operation, so replaying step 13's Cilium 1.19.8 after step 17 would downgrade Cilium.
A copy restored to an earlier snapshot is brought forward by running the steps in order - the inventory check fails
otherwise, since a skipped step's versions are missing. A version a playbook line sets with -e becomes the
playbook's default at the production rollout, not before.

Refs (--refs): for each repo, its highest upgrade/NN-* branch with NN up to the step's, else main - so a step that
changes only infra still mirrors platform with every earlier platform step. Aborts if a step branch does not contain
the previous one.

Usage: scripts/upgrade-expected-inventory.py <step, e.g. 01-apt-cacher-ng>           (prints the inventory)
       scripts/upgrade-expected-inventory.py --refs <step>                          (prints "<infra-ref> <platform-ref>")
       scripts/upgrade-expected-inventory.py --playbooks <step>                     (prints "<playbook> <arguments>" lines)
"""
import os
import re
import subprocess
import sys

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPGRADE = os.path.join(OPS, "tests", "ansible", "upgrade")
STEPS = os.path.join(UPGRADE, "steps")


def parse(path, playbooks=None):
    changes = []
    for n, raw in enumerate(open(path), 1):
        line = raw.strip()
        where = f"{os.path.basename(path)}:{n}"
        if not line or line.startswith("#"):
            continue
        if line.startswith("playbook "):
            if playbooks is not None:
                playbooks.append(line[len("playbook "):].strip())
        elif " => " in line:
            before, after = (x.strip() for x in line.split(" => "))
            changes.append((before, after, where))
        elif line.startswith("+ "):
            changes.append((None, line[2:].strip(), where))
        elif line.startswith("- "):
            changes.append((line[2:].strip(), None, where))
        else:
            sys.exit(f"{where}: not a step line: {line}")
    return changes


def ref(repo, step_no):
    """The repo's highest upgrade/NN-* branch with NN <= step_no, checked to stack on the one before; else main."""
    out = subprocess.run(["git", "-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/upgrade/"],
                         capture_output=True, text=True, check=True).stdout.split()
    branches = sorted((int(m.group(1)), b) for b in out if (m := re.fullmatch(r"upgrade/(\d\d)-.+", b)))
    numbers = [n for n, _ in branches]
    if len(numbers) != len(set(numbers)):
        sys.exit(f"{repo}: two upgrade branches share a number: {[b for _, b in branches]}")
    prev = "main"
    for n, b in branches:
        if n > step_no:
            break
        if subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", prev, b]).returncode != 0:
            sys.exit(f"{repo}: {b} does not contain {prev} - rebase it on the previous step's branch")
        prev = b
    return prev


def main():
    args = sys.argv[1:]
    mode = args[0] if args[:1] in (["--refs"], ["--playbooks"]) else None
    if mode:
        args = args[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    if args[0] not in names:
        sys.exit(f"no step {args[0]} (steps: {', '.join(names)})")
    if mode == "--playbooks":
        playbooks = []
        parse(os.path.join(STEPS, args[0] + ".txt"), playbooks)
        if playbooks:
            print("\n".join(playbooks))
        return
    if mode == "--refs":
        step_no = int(args[0][:2])
        print(ref(os.path.join(OPS, "..", "infra"), step_no), ref(os.path.join(OPS, "..", "platform"), step_no))
        return
    inventory = set(l.rstrip("\n") for l in open(os.path.join(UPGRADE, "prod-inventory.txt")) if l.strip())
    for name in names[:names.index(args[0]) + 1]:
        for before, after, where in parse(os.path.join(STEPS, name + ".txt")):
            if before is not None:
                if before not in inventory:
                    sys.exit(f"{where}: '{before}' is not in the inventory at this step - the step file is stale")
                inventory.discard(before)
            if after is not None:
                inventory.add(after)
    print("\n".join(sorted(inventory)))


if __name__ == "__main__":
    main()
