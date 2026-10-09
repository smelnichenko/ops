#!/bin/bash
# ansible-core renders an assert's fail_msg even when the assert passes: one naming a register its task may have skipped
# (a `when`, or a block's) fails the play on that path - setup-vault-cleanup-policy.yml's did on a first install (full
# run 14's build, 2026-10-10). Every such expression gives the value a default.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_FMD'
import glob, re, sys, yaml
def walk(ts, chain=()):
    """Each task with its chain of conditions: its blocks' `when`s, then its own."""
    for t in ts or []:
        if isinstance(t, dict):
            c = chain + ((str(t["when"]),) if "when" in t else ())
            yield t, c
            for k in ("block", "rescue", "always"):
                yield from walk(t.get(k), c)
bad, asserts = [], 0
files = [f for f in glob.glob("deploy/ansible/**/*.yml", recursive=True) + glob.glob("tests/ansible/**/*.yml", recursive=True)
         if "/venv/" not in f and "/collections/" not in f]
for f in files:
    try:
        doc = yaml.safe_load(open(f))
    except yaml.YAMLError:
        continue
    if not isinstance(doc, list):
        continue
    plays = doc if all(isinstance(p, dict) and ("tasks" in p or "hosts" in p) for p in doc) else [{"tasks": doc}]
    for pl in plays:
        tasks = list(walk(pl.get("tasks")))
        # a register may be missing where the assert runs: its task has a condition the assert's chain does not
        regs = {t["register"]: c for t, c in tasks if t.get("register")}
        for t, chain in tasks:
            maybe = {n for n, c in regs.items() if c and tuple(chain[:len(c)]) != c}
            a = t.get("ansible.builtin.assert") or {}
            msg = str(a.get("fail_msg", ""))
            if not msg:
                continue
            asserts += 1
            for expr in re.findall(r"{{(.*?)}}", msg):
                for name in set(re.findall(r"\b(_\w+)\.", expr)) & maybe:
                    if "default" not in expr:
                        bad.append(f"{f}: {t.get('name')}: {name} in '{{{{{expr}}}}}'")
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
check("asserts with a message read", asserts > 50, True)
check("no fail_msg names a register its task may have skipped without a default", bad, [])
print("fail-msg-defined: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_FMD
