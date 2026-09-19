#!/usr/bin/env python3
"""PreToolUse hook: refuse `git checkout --` / `git restore` over UNCOMMITTED work.

A revert check means breaking a mechanism deliberately, re-running the tests to prove some test
fails, then putting the file back. Putting it back is `git checkout -- <file>`, which restores the
file to HEAD — so if the mechanism being proven is ITSELF uncommitted, the restore deletes the real
work along with the sabotage. The tests just passed, so nothing looks wrong, and what gets committed
is the tests without the code they defend.

There is already a memory rule about this ("commit or copy aside BEFORE a revert check"). On
2026-09-19 it was violated THREE times in one session:

  * the RTTY page_damage fitting — committed the two tests with the mechanism gone; the full gate
    caught it 16 minutes later;
  * the Ft8Passenger hand-off seam — restored over, so the test file referenced a method that no
    longer existed;
  * and the first of the two was itself reported to the operator as done.

Three violations of a rule I had already written down is the evidence that a memory is the wrong
instrument for it. This is the enforced version.

Refuses when a restore names a path that currently has uncommitted changes. Everything else — a
restore of an unmodified path, a checkout of a branch, `git checkout -b` — passes untouched.

Escape hatch, to be typed on purpose when the discard is the actual intent:
`# discard-uncommitted: <why>`.

Run the tests beside it: `python3 commit-before-revert-test.py`.
"""
import json
import os
import re
import shlex
import subprocess
import sys

ALLOW_MARK = "# discard-uncommitted:"

# `git checkout -- a b`, `git checkout HEAD -- a`, `git restore a`, `git restore --source=X a`.
_RESTORE = re.compile(r"\bgit\s+(?:-C\s+\S+\s+)?(checkout|restore)\b")


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def restored_paths(command):
    """The paths a git restore/checkout in this command would overwrite, if any."""
    out = []
    for piece in command.split("&&"):
        for stmt in piece.split(";"):
            if not _RESTORE.search(stmt):
                continue
            try:
                words = shlex.split(stmt)
            except ValueError:
                continue
            if "git" not in words:
                continue
            words = words[words.index("git"):]
            sub = "checkout" if "checkout" in words else "restore"
            args = words[words.index(sub) + 1:]
            if sub == "checkout":
                # Only the pathspec form discards work. `git checkout -b x`, `git checkout main`
                # and `git checkout -` do not.
                if "--" not in args:
                    continue
                args = args[args.index("--") + 1:]
            else:
                args = [a for a in args if not a.startswith("-")]
            out.extend(a for a in args if a and not a.startswith("-"))
    return out


def dirty(paths, cwd):
    """Which of these paths git reports as modified or staged right now."""
    if not paths:
        return []
    try:
        r = subprocess.run(["git", "status", "--porcelain", "--"] + paths,
                           cwd=cwd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []  # cannot tell: never block on our own failure
    out = []
    for line in r.stdout.splitlines():
        if line[:2].strip() and not line.startswith("??"):
            out.append(line[3:].strip())
    return out


def verdict(command, cwd):
    if not command or ALLOW_MARK in command:
        return None
    paths = restored_paths(command)
    if not paths:
        return None
    lost = dirty(paths, cwd)
    if not lost:
        return None
    return (
        "This would DISCARD uncommitted work:\n  " + "\n  ".join(lost) + "\n\n"
        "`git checkout --` restores to HEAD, so a revert check run on an uncommitted mechanism "
        "deletes the mechanism along with the sabotage — the tests still pass, nothing looks "
        "wrong, and what gets committed is the tests without the code they defend. That happened "
        "three times on 2026-09-19.\n"
        "Commit the mechanism first (or copy the file aside), THEN sabotage and restore.\n"
        f"If discarding really is the intent, say so on purpose: `{ALLOW_MARK} <why>`."
    )


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)
    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    reason = verdict(payload.get("tool_input", {}).get("command", ""),
                     payload.get("cwd") or os.getcwd())
    if reason:
        deny(reason)
    sys.exit(0)


if __name__ == "__main__":
    main()
