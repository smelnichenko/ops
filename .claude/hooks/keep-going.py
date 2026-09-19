#!/usr/bin/env python3
"""Stop hook: refuse to let a turn end while the work queue still has open items.

Memory could not fix this. Memory is advice, and it loses to the judgement it is arguing with
at the exact moment that judgement says "this looks finished". A Stop hook does not ask.

The queue is the definition of done, and it lives OUTSIDE the assistant's judgement:
  TODO.keepgoing at the root of the repository the working directory is in. ONE per project —
  for radar that is /home/sm/src/radar/TODO.keepgoing, and there is no second place to look.

  - [ ] open
  - [x] DONE, and it must carry EVIDENCE: a PR reference (#123), a commit sha, or "VERIFIED:".
  - [!] genuinely blocked. Still reported every time, never silently gone.

Closing an item is the one move the assistant can make unilaterally, so it is the one that needs a
check. 2026-09-14: an item was marked "- [x]" with a note whose own first words were "NOT DONE —
waiting on a scheduled broadcast", and the data needed to finish it was sitting in the station
database the whole time. The hook accepted it because it only counted "- [ ]" lines.

So: a "- [x]" whose text admits it is not done (NOT DONE, still, waiting on, blocked on, could
not, attempted, TODO) is treated as OPEN. And a "- [x]" with no evidence is treated as OPEN. If
the work is genuinely blocked, that is what "- [!]" is for, and it stays visible forever.

Safety, because a hook that always blocks is a runaway:
  * MAX_BLOCKS blocks WITHOUT PROGRESS, then it gives up and lets the turn end. Closing an item
    resets that count, so a session that is getting work done is never throttled — only one that
    is going round in circles.
  * any error in here allows the stop. Never wedge the session on a broken hook.

2026-09-15: stop_hook_active used to allow the stop unconditionally, documented as a safety. It
was the escape hatch that made the whole hook a one-shot. The real pattern it permitted:

    block once -> do some work -> write a closing summary -> stop, allowed.

Which is the exact failure the queue exists to prevent, and it is the one the user has now had to
name five times. MAX_BLOCKS is the runaway guard, it is progress-aware in a way stop_hook_active
can never be, and it terminates on its own — so the flag is recorded and no longer obeyed.
"""
import json
import os
import pathlib
import re
import sys

MAX_BLOCKS = 12
STATE = pathlib.Path.home() / ".claude" / "queue" / ".block-counts.json"


def allow():
    sys.exit(0)


def should_block(blocks_without_progress, max_blocks=None):
    """Block this stop?

    Deliberately NOT a function of stop_hook_active. Honouring that flag turned the hook into a
    one-shot: the first stop was refused and the very next one — the summary written after a
    little more work — went through. The progress-aware counter is the guard, and it lets the
    turn end after MAX_BLOCKS stops that closed nothing.
    """
    return blocks_without_progress <= (MAX_BLOCKS if max_blocks is None else max_blocks)


# Words that mean "I did not actually do this". A checked item saying any of them is not done.
_EXCUSES = re.compile(
    r"\b(not done|notdone|still needs|still open|waiting on|waiting for|blocked on|could not|"
    r"couldn.t|unable to|attempted|no traffic|gave up|deferred|todo|tbd)\b", re.I)
# What counts as evidence that an item really is finished.
_EVIDENCE = re.compile(r"(#\d+|\b[0-9a-f]{7,40}\b|VERIFIED:)")


def _heading(line):
    """A Markdown heading, which ends an item — but NOT a line that merely starts with '#'.

    2026-09-15: an item was reported as "marked done with no evidence" while its very next line
    began "#875 makes that constructor refuse them". A PR reference is the commonest thing to put
    at the start of a continuation line, and treating it as a heading truncated the body to its
    first line — so the evidence the hook was asking for could never be seen. The hook then
    blocked on an item that WAS properly closed, which is the failure that costs the most trust:
    it trains you to work around the tool rather than with it.

    A real heading is "#" followed by a space or another "#". "#875" is not one.
    """
    return line.startswith("#") and (len(line) == 1 or line[1] in "# \t")


def parse_queue(text):
    """Return (open items, blocked items). An item runs until the next item or a heading."""
    items = []
    for line in text.splitlines():
        t = line.strip()
        if t.startswith("- [") and len(t) > 4 and t[4] == "]":
            items.append([t[3], t[5:].strip()])
        elif (items and items[-1] is not None and t
                and not _heading(t) and not t.startswith("*")):
            items[-1][1] += " " + t          # continuation line of the current item
        elif _heading(t):
            items.append(None)               # a heading ends the current item
    items = [i for i in items if i]

    opened, blocked = [], []
    for mark, body in items:
        head = body.split(".")[0][:90]
        if mark == "!":
            blocked.append(head)
        elif mark == " ":
            opened.append(head)
        elif mark.lower() == "x":
            if _EXCUSES.search(body):
                opened.append(head + "   <-- marked done but the note says it is NOT")
            elif not _EVIDENCE.search(body):
                opened.append(head + "   <-- marked done with no evidence (PR, sha or VERIFIED:)")
    return opened, blocked


def main():
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}

    cwd = pathlib.Path(data.get("cwd") or os.getcwd())

    # WALK UP to find the queue, do not demand it sit in the exact working directory.
    #
    # 2026-09-19: the hook went silent for most of a session and nobody noticed until the user
    # asked why. It had been reading a TODO.keepgoing inside a git worktree; the worktree was
    # deleted during ordinary branch cleanup, the file went with it, and from then on every stop
    # was allowed without a word. That was the visible half. The half that mattered more is that
    # `cd backend` was ALWAYS enough to disable it — a queue at a repo root was invisible from any
    # subdirectory, so the hook only worked when the working directory happened to be exactly
    # right. A guard that silently does nothing is worse than no guard: it is trusted.
    #
    # ONE QUEUE PER PROJECT. The key is the REPOSITORY, never the working directory: cwd-keyed
    # lookup gave radar three different queues — one for the repo root, one for backend/, one for
    # frontend/ — so which list of work existed depended on where the last `cd` landed. A project
    # has one definition of done.
    #
    # Bounded at the home directory so a stray file higher up cannot start governing every repo.
    home = pathlib.Path.home()
    root = None
    for d in [cwd, *cwd.parents]:
        if (d / ".git").exists():
            root = d
            break
        if d == home:
            break
    # ONE FILE. Not a list of candidates — the repo's TODO.keepgoing and nothing else. There used
    # to be a ~/.claude/queue/<slug>.md fallback beside it, which meant a project could have two
    # queues and the hook would silently pick whichever existed. For radar that is
    # /home/sm/src/radar/TODO.keepgoing, reachable from every directory in the repo.
    queue = (root or cwd) / "TODO.keepgoing"
    if not queue.exists():
        allow()

    open_items, blocked = parse_queue(queue.read_text())
    if not open_items:
        if blocked:
            print("keep-going: nothing open. Still blocked: " + "; ".join(blocked[:5]),
                  file=sys.stderr)
        allow()

    # The give-up counter measures being STUCK, not being busy. It resets whenever the number of
    # open items falls, so a session that keeps closing things is never throttled; only one that
    # blocks over and over against an unchanged queue runs out of patience.
    session = data.get("session_id", "?")
    state = {}
    if STATE.exists():
        try:
            state = json.loads(STATE.read_text())
        except ValueError:
            state = {}
    prev = state.get(session)
    if not isinstance(prev, dict):
        prev = {}  # a state file from an older format must not silently disable the hook
    n = 1 if len(open_items) < prev.get("open", 10 ** 9) else prev.get("n", 0) + 1
    state[session] = {"n": n, "open": len(open_items)}
    STATE.write_text(json.dumps(state))

    if not should_block(n):
        print(f"keep-going: {MAX_BLOCKS} blocks with no item closed; letting the turn end.",
              file=sys.stderr)
        allow()

    # Say the specific thing on a repeat. The generic message reads as boilerplate by the second
    # time, and the failure it is catching has a recognisable shape worth naming.
    repeat = ""
    if n >= 2:
        repeat = (
            f"\nThis is block {n} of this session with nothing closed. The shape to watch for: "
            "reaching a point where the work SUMMARISES well and treating that as a place to "
            "stop. A reporting point is not a stopping point. If you can name the next task — "
            "and the list below names it — that naming is the instruction to start it, not the "
            "sign-off.\n"
        )

    listed = "\n".join(f"  - {item}" for item in open_items[:10])
    more = "" if len(open_items) <= 10 else f"\n  ... and {len(open_items) - 10} more"
    print(json.dumps({
        "decision": "block",
        "reason": (
            f"The work queue ({queue}) still has {len(open_items)} open item(s). Do not end the "
            f"turn and do not summarise. Pick the FIRST one and start it now with a tool call.\n"
            f"{listed}{more}\n"
            f"{repeat}\n"
            "Closing an item needs EVIDENCE: mark it '- [x]' and cite a PR (#123), a commit sha, "
            "or 'VERIFIED: <how>'. A '- [x]' whose note admits it is not done, or that cites "
            "nothing, is counted as STILL OPEN and you will be stopped here again.\n"
            "If the work is genuinely blocked on hardware, the operator, or a dead external "
            "service, mark it '- [!]' and say which. That is reported every time rather than "
            "disappearing — before using it, check whether the data you need already exists "
            "somewhere you have not looked."
        ),
    }))
    sys.exit(0)


if __name__ == "__main__":
    # Guarded so parse_queue can be imported and tested without running the hook.
    try:
        main()
    except Exception as exc:  # never wedge the session
        print(f"keep-going hook error, allowing stop: {exc}", file=sys.stderr)
        sys.exit(0)
