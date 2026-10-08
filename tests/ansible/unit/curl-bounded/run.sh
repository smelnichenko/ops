#!/bin/bash
# Every curl a production playbook runs is bounded: its whole time (--max-time / -m), or a stall (--speed-time, with
# --speed-limit, for a transfer whose size sets its time - a 4 GiB backup part), or the task's own (Ansible's timeout:,
# a timeout(1) before it). curl's default is none: a connection that stalls - an answer never sent, a gateway holding
# it - held its task, an until's retries never reached, the play with it (20 of 31 had no bound; setup-istio's
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
CURL = re.compile(r"(?<![\w./-])curl\b(?!')")
BOUND = re.compile(r"--max-time\b|(^|[\s'\",])-[A-Za-z]*m['\",\s]*\d|--speed-time\b")
def unbounded(text):
    """The curls of a task's text with no bound of their own: each from its name to the end of its command (a pipe,
    a ; or & ends it; a line continuation joins), a timeout(1) before it counting."""
    text = re.sub(r"\\\n\s*", " ", text)
    out = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):  # a comment's word
            continue
        for m in CURL.finditer(line):
            seg = re.split(r"[|;&]", line[m.start():])[0]
            if not BOUND.search(seg) and not re.search(r"\btimeout\s+(-\S+\s+)*\d", line[:m.start()]):
                out.append(seg.strip()[:100])
    return out
forms = {"curl -s --max-time 30 https://x": [], "curl -sm 10 https://x": [], "curl -fsSL https://x": ["curl -fsSL https://x"],
         "curl -s -m 10 https://x": [], "curl -fsS --speed-limit 1024 --speed-time 60 -T f https://x": [],
         "timeout 60 curl -s https://x": [], "curl -s https://x | jq .": ["curl -s https://x"],
         "  # curl's config, never its command line": [], "cfg={{ d }}/.store-credentials.curl": [],
         "curl -s \\\n  --max-time 5 https://x": [], "x=$(curl -s https://x); curl --max-time 3 y": ["curl -s https://x)"]}
check("each curl read with its bound (or none): the whole time, a stall's, a timeout before it, across a continuation",
      {f: unbounded(f) for f in forms}, forms)
bad = []
seen_vars, seen_scripts = set(), set()
for f in files("deploy/ansible"):
    doc = load(f)
    # a play's string vars (a script a task templates in: the mirror's probe) - each run by a task (the play's own)
    for p in (doc if isinstance(doc, list) else []):
        if isinstance(p, dict):
            for k, v in (p.get("vars") or {}).items():
                if isinstance(v, str):
                    bad += [f"{f}: vars {k}: {c}" for c in unbounded(v)]
                    if CURL.search(v):
                        seen_vars.add(k)
    for t in tasks(doc):
        if isinstance(t.get("timeout"), int):
            continue
        for mod, val in actions(t):
            m = str(mod).split(".")[-1]
            if m in ("shell", "command", "raw"):
                text = str(val.get("cmd", val.get("argv", val)) if isinstance(val, dict) else val)
                bad += [f"{f}: {t.get('name')}: {c}" for c in unbounded(text)]
            elif m in ("copy", "template") and isinstance(val, dict) and str(val.get("content", "")).startswith("#!"):
                # a script it writes (a timer's or a cron's run of it has no task timeout around it)
                bad += [f"{f}: {t.get('name')} (writes {val.get('dest')}): {c}" for c in unbounded(val["content"])]
                if CURL.search(val["content"]):
                    seen_scripts.add(str(val.get("dest")))
check("every curl a production playbook runs, templates in or writes as a script bounded", len(bad), 0)
# what it reads, found: the mirror's probe a task templates in, the scripts a timer and a cron run (a scan that
# finds none passes with nothing read)
check("the curls it reads found: the mirror's probe var, Caddy's wildcard sync, Vault's health check",
      ("_git_mirror_probe" in seen_vars, any("caddy-wildcard-sync" in x for x in seen_scripts),
       any("vault-health-check" in x for x in seen_scripts)), (True, True, True))
for b in bad:
    print("    " + b)
print("curl-bounded: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
