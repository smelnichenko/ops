#!/bin/bash
# Every curl a production playbook runs is bounded: its whole time (--max-time / -m), or a stall (--speed-time, with
# --speed-limit, for a transfer whose size sets its time - a 4 GiB backup part), or the task's own (Ansible's timeout:,
# a timeout(1) before it). curl's default is none: a connection that stalls - an answer never sent, a gateway holding
# it - held its task, an until's retries never reached, the play with it (review 7: 20 of 31 had no bound; setup-istio's
# --max-time removed, nothing failed).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import re
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
CURL = re.compile(r"(?<![\w-])curl\b")
BOUND = re.compile(r"--max-time\b|(^|[\s'\",])-[A-Za-z]*m['\",\s]*\d|--speed-time\b")
def unbounded(text):
    """The curls of a task's text with no bound of their own: each from its name to the end of its command (a pipe,
    a ; or & ends it; a line continuation joins), a timeout(1) before it counting."""
    text = re.sub(r"\\\n\s*", " ", text)
    out = []
    for line in text.splitlines():
        for m in CURL.finditer(line):
            seg = re.split(r"[|;&]", line[m.start():])[0]
            if not BOUND.search(seg) and not re.search(r"\btimeout\s+(-\S+\s+)*\d", line[:m.start()]):
                out.append(seg.strip()[:100])
    return out
forms = {"curl -s --max-time 30 https://x": [], "curl -sm 10 https://x": [], "curl -fsSL https://x": ["curl -fsSL https://x"],
         "curl -s -m 10 https://x": [], "curl -fsS --speed-limit 1024 --speed-time 60 -T f https://x": [],
         "timeout 60 curl -s https://x": [], "curl -s https://x | jq .": ["curl -s https://x"],
         "curl -s \\\n  --max-time 5 https://x": [], "x=$(curl -s https://x); curl --max-time 3 y": ["curl -s https://x)"]}
check("each curl read with its bound (or none): the whole time, a stall's, a timeout before it, across a continuation",
      {f: unbounded(f) for f in forms}, forms)
bad = []
for f in files("deploy/ansible"):
    for t in tasks(load(f)):
        if isinstance(t.get("timeout"), int):
            continue
        for mod, val in actions(t):
            if str(mod).split(".")[-1] not in ("shell", "command", "raw"):
                continue
            text = str(val.get("cmd", val.get("argv", val)) if isinstance(val, dict) else val)
            bad += [f"{f}: {t.get('name')}: {c}" for c in unbounded(text)]
check("every curl a production playbook runs bounded", len(bad), 0)
for b in bad:
    print("    " + b)
print("curl-bounded: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
