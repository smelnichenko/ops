import json
import re
import sys

ALLOW_MARK = "# external-poll:"
_LONGRUN = "/home/sm/src/ops/bin/longrun"

_SLEEP = re.compile(r"\bsleep\s+(\d+(?:\.\d+)?)")
_SLEEP_MIN_SECONDS = 5
_SLEEP_TOTAL_SECONDS = 5

_LOOP = re.compile(r"\b(until|while|for)\b.{0,400}?\bdo\b.{0,400}?\bdone\b", re.S)

_SPUN_ON = re.compile(r"(\bsleep\b|pgrep|pidof|\bps\s)")

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
        sys.exit(0)

    if payload.get("tool_name") != "Bash":
        sys.exit(0)

    reason = verdict(payload.get("tool_input", {}).get("command", ""))
    if reason:
        deny(reason)
    sys.exit(0)

if __name__ == "__main__":
    main()
