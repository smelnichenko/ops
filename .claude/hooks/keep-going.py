import json
import pathlib
import re
import subprocess
import sys

QUEUE = pathlib.Path("/home/sm/src/radar/TODO.keepgoing")
CURSOR = pathlib.Path.home() / ".claude" / "queue" / ".cursor"
PR = re.compile(r"#(\d+)")

def heading(line):
    return line.startswith("#") and (len(line) == 1 or line[1] in "# \t")

def parse_queue(text):
    items = []
    for line in text.splitlines():
        t = line.strip()
        if t.startswith("- [") and len(t) > 4 and t[4] == "]":
            items.append([t[5:].strip(), []])
        elif items and items[-1] is not None and t and not heading(t) and not t.startswith("*"):
            items[-1][1].append(t)
        elif heading(t):
            items.append(None)
    return [i for i in items if i]

def merged():
    out = subprocess.run(["git", "-C", str(QUEUE.parent), "log", "--oneline", "origin/main"],
                         capture_output=True, text=True, timeout=10)
    return set(PR.findall(out.stdout))

def open_items(text, done):
    return [(head, body) for head, body in parse_queue(text)
            if not (PR.findall(head) and all(n in done for n in PR.findall(head)))]

def main():
    if not QUEUE.exists():
        sys.exit(0)
    items = open_items(QUEUE.read_text(), merged())
    if not items:
        sys.exit(0)

    try:
        cursor = (int(CURSOR.read_text()) + 1) % len(items)
    except Exception:
        cursor = 0
    CURSOR.parent.mkdir(parents=True, exist_ok=True)
    CURSOR.write_text(str(cursor))

    head, body = items[cursor]
    print(json.dumps({
        "decision": "block",
        "reason": f"Next task, {cursor + 1} of {len(items)} open:\n\n{head}\n"
                  + "\n".join(f"  {ln}" for ln in body[:120])
                  + "\n\nIt closes when every PR in its FIRST line is merged to main, "
                    "or when you delete it from the queue.",
    }))
    sys.exit(0)

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"keep-going: {exc}", file=sys.stderr)
        sys.exit(0)
