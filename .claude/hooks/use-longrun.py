#!/usr/bin/env python3
"""PreToolUse hook: refuse hand-rolled waiting, because the waiting tool already exists.

`/home/sm/src/ops/bin/longrun` was built on the operator's instruction ("can you develop waiting
tool and use it, once and forever?"). It runs the long thing in the background and NOTIFIES on
completion with PASS/FAIL, elapsed time and the names of failing tests. Nothing needs to poll it.

It was then ignored anyway. On 2026-09-19 the same session launched builds with longrun and
immediately polled their results with sleeps and spin loops -- and two of those waiters never
exited at all, because `pgrep -f` matches the waiting shell's OWN command line, which contains the
pattern. They spun until killed while the build had long since finished. The operator: "well, you
are ignoring the waiting tool you wrote", then "how can I make you use it?" -- a memory about this
already existed and had not worked. This hook is the answer: a rule enforced rather than remembered.

Its first cut was poor, and the operator said so ("your waiting hook test was crap"). What that
version got wrong, all found by testing it properly afterwards:

  * A loop written with `[ -f x ]` slipped straight through, because the condition alternatives
    listed `test -` but not `[`. The session then hung on exactly such a loop.
  * `for i in $(seq 60); do ...; sleep 20; done` was not a loop as far as the rule was concerned,
    which is absurd -- that shape is what prompted the hook.
  * `sleep 3; sleep 3; sleep 3` passed, while the denial message it would have printed says in so
    many words "do not chain shorter sleeps".
  * It matched any command CONTAINING the words, so editing this very file was refused.

Run the tests beside it: `python3 use-longrun-test.py`.
"""
import json
import re
import sys

ALLOW_MARK = "# external-poll:"
_LONGRUN = "/home/sm/src/ops/bin/longrun"

# Every sleep in the command, wherever it sits. Deliberately not anchored: the first cut anchored
# on start-of-line, ';' or 'do ', and so missed `x && sleep 30` and `(sleep 30)`.
_SLEEP = re.compile(r"\bsleep\s+(\d+(?:\.\d+)?)")
_SLEEP_MIN_SECONDS = 5     # one sleep this long is waiting by hand
_SLEEP_TOTAL_SECONDS = 5   # ...and so is a handful of short ones

# A REAL shell loop: the keyword, then a matching do...done. Requiring do/done is what keeps this
# from firing on a command that merely mentions the words -- such as one editing this file.
_LOOP = re.compile(r"\b(until|while|for)\b.{0,400}?\bdo\b.{0,400}?\bdone\b", re.S)

# What makes a loop a POLL rather than ordinary iteration: it either SLEEPS, or it asks about a
# PROCESS. The first cut also listed grep/curl/test/[ here, and that blocked real work the same day
# it shipped — a bounded walk over a fixed list that greps each entry is not waiting for anything.
# It also made this file uneditable from a shell, because the edit text carries the pattern.
_SPUN_ON = re.compile(r"(\bsleep\b|pgrep|pidof|\bps\s)")

# `watch` is a spin loop with a shorter spelling.
_WATCH = re.compile(r"(^|[;&|]\s*)watch\b")


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def verdict(command):
    """None when the command is fine, else the reason to refuse it."""
    if not command or ALLOW_MARK in command:
        return None

    loop = _LOOP.search(command)
    spins = bool(loop and _SPUN_ON.search(loop.group(0)))
    if spins or _WATCH.search(command):
        return (
            "Hand-rolled wait loop. Use the waiting tool instead:\n"
            f"  {_LONGRUN} <label> <cmd...>   with run_in_background: true\n"
            "It notifies on completion with PASS/FAIL, elapsed time and failing test names, so "
            "there is nothing to spin on. Two of these loops never exited at all on 2026-09-19 "
            "because `pgrep -f` matched the waiting shell's own command line.\n"
            "If this really is an EXTERNAL thing longrun cannot run (a CI run, a remote queue), "
            f"say so on purpose by putting `{ALLOW_MARK} <what>` in the command."
        )

    # A longrun launch is exactly what this hook wants to see, and it may legitimately carry a
    # short sleep of its own.
    if _LONGRUN in command:
        return None

    sleeps = [float(x) for x in _SLEEP.findall(command)]
    if not sleeps:
        return None
    longest, total = max(sleeps), sum(sleeps)
    if longest < _SLEEP_MIN_SECONDS and total < _SLEEP_TOTAL_SECONDS:
        return None
    how = (f"`sleep {longest:g}`" if longest >= _SLEEP_MIN_SECONDS
           else f"{total:g} s of sleep across {len(sleeps)} calls")
    return (
        f"{how} is waiting by hand. Use the waiting tool instead:\n"
        f"  {_LONGRUN} <label> <cmd...>   with run_in_background: true\n"
        "Then WAIT for its notification -- do not sleep, re-read the output file, or chain "
        "shorter sleeps to get under this rule.\n"
        f"For something genuinely external, put `{ALLOW_MARK} <what>` in the command."
    )


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)  # never block on a payload we cannot read

    if payload.get("tool_name") != "Bash":
        sys.exit(0)

    reason = verdict(payload.get("tool_input", {}).get("command", ""))
    if reason:
        deny(reason)
    sys.exit(0)


if __name__ == "__main__":
    main()
