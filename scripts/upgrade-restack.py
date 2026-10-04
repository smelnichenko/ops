#!/usr/bin/env python3
"""upgrade-restack.py - put the upgrade step branches in a new order (every step inside its support matrices).

Each step's change is the commits its branch upgrade/NN-<name> adds to the step branch before it in the same repo
(main for the first). Given the new order of step names, for each repo (../infra, ../platform) this:

  1. renames every branch upgrade/NN-<name> to upgrade-old/NN-<name> (kept, and out of the runner's sight - it reads
     refs/heads/upgrade/ only);
  2. re-creates the branches in the new order, numbered by position (upgrade/MM-<name>), each step's own commits
     cherry-picked onto the branch of the step before it in the new order (main for the first);
  3. stops at the first cherry-pick that does not apply cleanly, naming the step and the commit - nothing is forced.

and prints the git mv lines for the step files (tests/ansible/upgrade/steps/NN-<name>.txt -> MM-<name>.txt) - the step
files are renamed by hand, with their text, in the same change.

The working trees must be clean and on main; the script checks out main again at the end. Run it on clones first
(--repos <dir> <dir>). Same order, after a fix committed to an earlier step branch: scripts/upgrade-restack-in-place.sh.

Usage: scripts/upgrade-restack.py --order <file with one step name per line, new order> [--repos ../infra ../platform]
       [--dry-run]
"""
import argparse
import os
import re
import subprocess
import sys

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEPS = os.path.join(OPS, "tests", "ansible", "upgrade", "steps")


def git(repo, *args, check=True):
    out = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and out.returncode != 0:
        sys.exit(f"{repo}: git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--order", required=True)
    ap.add_argument("--repos", nargs="+", default=[os.path.join(OPS, "..", "infra"), os.path.join(OPS, "..", "platform")])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    order = [l.strip() for l in open(a.order) if l.strip() and not l.startswith("#")]
    bare = lambda n: n.split("-", 1)[1]
    by_bare = {bare(n): n for n in names}
    if sorted(map(bare, order)) != sorted(by_bare):
        sys.exit(f"the order must name every step once: missing {sorted(set(by_bare) - set(map(bare, order)))}, "
                 f"unknown {sorted(set(map(bare, order)) - set(by_bare))}")
    width = 2
    new_names = {by_bare[bare(o)]: f"{i:0{width}d}-{bare(o)}" for i, o in enumerate(order, 1)}

    for repo in a.repos:
        repo_name = os.path.basename(os.path.normpath(repo))
        if git(repo, "status", "--porcelain"):
            sys.exit(f"{repo_name}: uncommitted changes")
        if git(repo, "rev-parse", "--abbrev-ref", "HEAD") != "main":
            sys.exit(f"{repo_name}: not on main")
        heads = git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/upgrade/").split()
        old = {b[len("upgrade/"):]: b for b in heads if re.fullmatch(r"upgrade/\d\d-.+", b)}
        # each step's own commits: its branch minus the previous step branch (old order) in this repo
        own, prev = {}, "main"
        for name in names:
            if name in old:
                own[name] = git(repo, "rev-list", "--reverse", f"{prev}..{old[name]}").split()
                prev = old[name]
        print(f"== {repo_name}: {len(own)} step branches")
        plan, base = [], "main"
        for o in order:
            name = by_bare[bare(o)]
            if name in own:
                plan.append((name, new_names[name], base, own[name]))
                base = f"upgrade/{new_names[name]}"
        for name, new, base, commits in plan:
            print(f"   {name} -> upgrade/{new} on {base}: {len(commits)} commit(s)")
        if a.dry_run:
            continue
        for name in own:
            git(repo, "branch", "-m", old[name], f"upgrade-old/{name}")
        for name, new, base, commits in plan:
            git(repo, "checkout", "-q", "-b", f"upgrade/{new}", base)
            for c in commits:
                r = subprocess.run(["git", "-C", repo, "cherry-pick", "-x", c], capture_output=True, text=True)
                if r.returncode != 0:
                    sys.exit(f"{repo_name}: {name} -> upgrade/{new}: {c[:10]} does not apply on {base}:\n"
                             f"{r.stdout.strip()}\n{r.stderr.strip()}\n(resolve, or `git cherry-pick --abort` and"
                             f" reorder; the old branches are upgrade-old/*)")
        git(repo, "checkout", "-q", "main")
    print("== step files")
    for name in names:
        if new_names[name] != name:
            print(f"git mv tests/ansible/upgrade/steps/{name}.txt tests/ansible/upgrade/steps/{new_names[name]}.txt")


if __name__ == "__main__":
    main()
