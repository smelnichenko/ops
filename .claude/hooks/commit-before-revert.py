import json
import os
import re
import shlex
import subprocess
import sys

ALLOW_MARK = "# discard-uncommitted:"

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
                if "--" not in args:
                    continue
                args = args[args.index("--") + 1:]
            else:
                args = [a for a in args if not a.startswith("-")]
            out.extend(a for a in args if a and not a.startswith("-"))
    return out

def dirty(paths, cwd):
    if not paths:
        return []
    try:
        r = subprocess.run(["git", "status", "--porcelain", "--"] + paths,
                           cwd=cwd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
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
