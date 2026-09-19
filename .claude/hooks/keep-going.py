import json
import pathlib
import re
import sys

STATE = pathlib.Path.home() / ".claude" / "queue" / ".block-counts.json"

def allow():
    sys.exit(0)

_EVIDENCE = re.compile(r"(#\d+|\b[0-9a-f]{7,40}\b|VERIFIED:)")

def _heading(line):
    return line.startswith("#") and (len(line) == 1 or line[1] in "# \t")

def parse_queue(text):
    items = []
    for line in text.splitlines():
        t = line.strip()
        if t.startswith("- [") and len(t) > 4 and t[4] == "]":
            items.append([t[3], t[5:].strip()])
        elif (items and items[-1] is not None and t
                and not _heading(t) and not t.startswith("*")):
            items[-1][1] += " " + t
        elif _heading(t):
            items.append(None)
    items = [i for i in items if i]

    opened = []
    for mark, body in items:
        head = body.split(".")[0][:90]
        if mark.lower() == "x":
            if not _EVIDENCE.search(body):
                opened.append(head + "   <-- marked done with no evidence (PR, sha or VERIFIED:)")
        else:
            opened.append(head)
    return opened

def main():
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}

    queue = pathlib.Path("/home/sm/src/radar/TODO.keepgoing")
    if not queue.exists():
        allow()

    open_items = parse_queue(queue.read_text())
    if not open_items:
        allow()

    session = data.get("session_id", "?")
    state = {}
    if STATE.exists():
        try:
            state = json.loads(STATE.read_text())
        except ValueError:
            state = {}
    prev = state.get(session)
    if not isinstance(prev, dict):
        prev = {}
    n = 1 if len(open_items) < prev.get("open", 10 ** 9) else prev.get("n", 0) + 1
    state[session] = {"n": n, "open": len(open_items)}
    STATE.write_text(json.dumps(state))

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
            "or 'VERIFIED: <how>'. A '- [x]' citing nothing is counted as STILL OPEN and you "
            "will be stopped here again.\n"
            "There is no 'blocked' mark. Work that is waiting on hardware, the operator or "
            "traffic stays OPEN with the reason written in its body — before deciding it is "
            "waiting, check whether the data you need already exists somewhere you have not "
            "looked."
        ),
    }))
    sys.exit(0)

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"keep-going hook error, allowing stop: {exc}", file=sys.stderr)
        sys.exit(0)
