#!/usr/bin/env python3
"""Tests for commit-before-revert.py, against a real throwaway git repo.

Written first this time. The previous hook shipped with four holes because it was "tested" by
echoing a few payloads that happened to work, and the operator said so.

Run: python3 commit-before-revert-test.py
"""
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location(
    "cbr", pathlib.Path(__file__).with_name("commit-before-revert.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


def git(repo, *args):
    subprocess.run(["git", "-C", repo, *args], check=True,
                   capture_output=True, text=True)


def make_repo(tmp):
    git(tmp, "init", "-q")
    git(tmp, "config", "user.email", "t@t")
    git(tmp, "config", "user.name", "t")
    for name in ("mech.java", "test.java", "clean.java"):
        pathlib.Path(tmp, name).write_text("committed\n")
    git(tmp, "add", "-A")
    git(tmp, "commit", "-qm", "base")
    # mech.java and test.java now carry UNCOMMITTED work; clean.java does not.
    pathlib.Path(tmp, "mech.java").write_text("the mechanism, uncommitted\n")
    pathlib.Path(tmp, "test.java").write_text("its test, uncommitted\n")
    pathlib.Path(tmp, "untracked.java").write_text("never committed\n")
    return tmp


DENY = [
    ("the exact shape that lost work three times", "git checkout -- mech.java"),
    ("restore, the modern spelling", "git restore mech.java"),
    ("several paths, one of them dirty", "git checkout -- clean.java mech.java"),
    ("buried in a chain, as it always is in practice",
     "python3 -c 'patch()' && ./gradlew test -q ; git checkout -- mech.java"),
    ("restore with an explicit source", "git restore --source=HEAD test.java"),
    ("git -C pointing at the repo", "git -C . checkout -- mech.java"),
]

ALLOW = [
    ("a path with nothing to lose", "git checkout -- clean.java"),
    ("an untracked file is not committed work being discarded", "git checkout -- untracked.java"),
    ("switching branch is not a discard", "git checkout main"),
    ("creating a branch is not a discard", "git checkout -b feat/x"),
    ("going back is not a discard", "git checkout -"),
    ("the explicit escape hatch",
     "git checkout -- mech.java  # discard-uncommitted: the sweep is abandoned"),
    ("no git at all", "./gradlew test --tests '*FooTest'"),
    ("a commit, which is what the hook wants instead", "git add -A && git commit -m x"),
    ("the word checkout inside a message", "git commit -m 'note about checkout -- files'"),
]


def run():
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        repo = make_repo(tmp)
        for label, command in DENY:
            if hook.verdict(command, repo) is None:
                print(f"  MISSED (should deny): {label}\n      {command}")
                bad += 1
        for label, command in ALLOW:
            reason = hook.verdict(command, repo)
            if reason is not None:
                print(f"  FALSE POSITIVE (should allow): {label}\n      {command}")
                bad += 1
    total = len(DENY) + len(ALLOW)
    print(f"{total - bad}/{total} cases correct" if bad else f"all {total} cases correct")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(run())
