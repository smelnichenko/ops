#!/usr/bin/env python3
"""PreToolUse hook: refuse hand-rolled waiting, because the waiting tool already exists.

`/home/sm/src/ops/bin/longrun` was built on the operator's instruction ("can you develop waiting
tool and use it, once and forever?"). It runs the long thing in the background and NOTIFIES on
completion with PASS/FAIL, elapsed time and the names of failing tests. Nothing needs to poll it.

It was then ignored anyway. On 2026-09-19 the same session launched builds with longrun and
immediately polled their results with `sleep`, `cat` loops and `until ! pgrep ...` — and two of
those waiters never exited at all, because `pgrep -f` matches the waiting shell's OWN command line,
which contains the pattern. They spun until killed while the build had long since finished. The
operator: "well, you are ignoring the waiting tool you wrote", and then "how can I make you use
it?" — a memory had already been written about this and had not worked. This hook is the answer:
a rule that is enforced rather than remembered.

Refuses, with the reason, any Bash command that:
  - sleeps as a way of waiting (`sleep 30`, and chains of short sleeps), or
  - spins on a process or a file (`until ...`, `while ...` around pgrep/grep/test), or
  - polls the same task output repeatedly.

Allows: sleeps INSIDE a poll loop of a genuinely external thing that longrun cannot run
(a CI run, a remote queue) — those name their subject, so the escape hatch is explicit and has to
be typed on purpose: put `# external-poll: <what>` in the command.
"""
import json
import re
import sys

ALLOW_MARK = "# external-poll:"

# A bare sleep used as a wait. Not `sleep 0.2` inside a tight retry of something local.
_SLEEP = re.compile(r"(^|[;&|]\s*|\bdo\s+)sleep\s+(\d+(?:\.\d+)?)", re.M)
_SLEEP_MIN_SECONDS = 5

# Spinning on a condition.
_SPIN = re.compile(r"\b(until|while)\b[^\n;]{0,200}?\b(pgrep|pidof|ps\s|test\s+-|grep)\b", re.S)

# longrun exists and is the answer.
_LONGRUN = "/home/sm/src/ops/bin/longrun"


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)  # never block on a payload we cannot read

    if payload.get("tool_name") != "Bash":
        sys.exit(0)

    command = payload.get("tool_input", {}).get("command", "")
    if not command or ALLOW_MARK in command:
        sys.exit(0)

    # Launching longrun is exactly what this hook wants to see.
    if _LONGRUN in command and not _SPIN.search(command):
        sys.exit(0)

    spin = _SPIN.search(command)
    if spin:
        deny(
            "Hand-rolled wait loop. Use the waiting tool instead:\n"
            f"  {_LONGRUN} <label> <cmd...>   with run_in_background: true\n"
            "It notifies on completion with PASS/FAIL, elapsed time and failing test names, so "
            "there is nothing to spin on. Two of these loops never exited at all on 2026-09-19 "
            "because `pgrep -f` matched the waiting shell's own command line.\n"
            "If this really is an EXTERNAL thing longrun cannot run (a CI run, a remote queue), "
            f"say so on purpose by putting `{ALLOW_MARK} <what>` in the command."
        )

    for _, seconds in _SLEEP.findall(command):
        if float(seconds) >= _SLEEP_MIN_SECONDS:
            deny(
                f"`sleep {seconds}` is waiting by hand. Use the waiting tool instead:\n"
                f"  {_LONGRUN} <label> <cmd...>   with run_in_background: true\n"
                "Then WAIT for its notification — do not sleep, re-cat the output file, or chain "
                "shorter sleeps to get under this rule.\n"
                f"For something genuinely external, put `{ALLOW_MARK} <what>` in the command."
            )

    sys.exit(0)


if __name__ == "__main__":
    main()
