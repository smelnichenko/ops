#!/usr/bin/env python3
"""Tests for use-longrun.py, written after the first cut shipped with four real holes.

The first version was "tested" by echoing four payloads at it, all of which it happened to handle.
Then, in the session it was meant to police, a loop written `until [ -f x ]; do sleep 2; done`
sailed through and hung for two minutes. The operator: "your waiting hook test was crap".

So these are the cases that version got WRONG, plus the ones it got right, plus the ones it must
never fire on. Run: python3 use-longrun-test.py
"""
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location(
    "use_longrun", pathlib.Path(__file__).with_name("use-longrun.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

LONGRUN = "/home/sm/src/ops/bin/longrun"

DENY = [
    # --- the four holes the first cut had ---
    ("bracket condition, not `test`",
     "until [ -f /tmp/x ]; do sleep 2; done"),
    ("a for-loop poll, the shape that prompted the hook",
     "for i in $(seq 60); do pgrep -f Gradle; sleep 20; done"),
    ("chained short sleeps, the documented bypass",
     "sleep 3; sleep 3; sleep 3; cat out"),
    ("sleep after &&, which the anchored regex missed",
     "./build.sh && sleep 30 && cat out"),
    # --- what it did already catch ---
    ("a bare long sleep", "sleep 120; cat out"),
    ("a while-loop on pgrep", "while pgrep -f Gradle; do sleep 10; done"),
    ("until on a grep", "until grep -q DONE log; do sleep 5; done"),
    ("watch", "watch -n 5 ls /tmp"),
    ("a sleep inside a subshell", "(sleep 60); echo done"),
    ("exactly at the one-sleep threshold", "sleep 5"),
]

ALLOW = [
    # --- must never fire ---
    ("launching longrun, the whole point", f"{LONGRUN} gate ./gradlew clean check"),
    ("the explicit external escape hatch",
     "sleep 300  # external-poll: forgejo CI run"),
    ("a short sleep, e.g. letting a daemon settle", "sleep 2; curl localhost:8090/api/state"),
    ("short sleeps well under the total", "sleep 1; foo; sleep 1"),
    ("no sleep at all", "./gradlew test --tests '*FooTest'"),
    ("a for-loop that is NOT a poll",
     "for f in *.java; do echo $f; done"),
    ("a bounded walk over a fixed list that greps — this blocked real work on 2026-09-19",
     "for c in TrackProperties HistoryProperties; do grep -rc $c src/ ; done"),
    ("the same shape with a command substitution",
     "for f in $(ls *.java); do grep -n class $f; done"),
    ("a loop that curls a fixed list of hosts", "for h in a b; do curl -s $h; done"),
    ("EDITING THIS HOOK — it mentions every trigger word",
     "python3 -c \"print('until while for pgrep test - grep sleep watch')\""),
    ("a command merely naming sleep without calling it",
     "grep -rn 'sleep' src/ | head"),
    ("git log that happens to contain the word while",
     "git log --oneline --grep='while' | head"),
]


def run():
    bad = 0
    for label, command in DENY:
        if hook.verdict(command) is None:
            print(f"  MISSED (should deny): {label}\n      {command}")
            bad += 1
    for label, command in ALLOW:
        reason = hook.verdict(command)
        if reason is not None:
            print(f"  FALSE POSITIVE (should allow): {label}\n      {command}")
            bad += 1
    total = len(DENY) + len(ALLOW)
    print(f"{total - bad}/{total} cases correct" if bad else f"all {total} cases correct")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(run())
