#!/usr/bin/env python3
"""check-mode-lint.py - a playbook the upgrade preview runs in check mode reads no result check mode never made.

The preview (scripts/upgrade-step-playbooks.sh --check) runs a step's playbook lines with --check: shell, command,
script, raw and uri tasks are skipped there unless they say check_mode: false, and so is a task under `when: not
ansible_check_mode`. Their register then holds no stdout, rc or results, and a later task that reads one fails the
preview - step 37's did, three hours into a full run (2026-10-06), found by nothing before. This reads each play in
order, imports and static includes followed, as the preview runs it:

  - only the tasks the line's --tags select run (with their blocks' and includes' tags; `always` always);
  - an end_host reached only in check mode (under `when: ansible_check_mode`) ends the play for the preview;
  - a read of a skipped register is fine with `| default(...)`, or in a task that check mode skips itself.

Usage: scripts/check-mode-lint.py                    (every step's playbook lines; exit 1 naming each read)
       scripts/check-mode-lint.py <playbook> [--tags <t,...>]
"""
import os
import re
import subprocess
import sys

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAYBOOKS = os.path.join(OPS, "deploy", "ansible", "playbooks")
SKIPPED = {"shell", "command", "script", "raw", "uri"}
FINE = {"skipped", "changed", "failed", "skip_reason"}  # what a skipped task's register does hold
MODULE = re.compile(r"^(?:ansible\.builtin\.|ansible\.legacy\.)?([a-z_]+)$")


def whens(task):
    w = task.get("when", [])
    return [str(x) for x in (w if isinstance(w, list) else [w])]


def check_only(conditions):
    """Reached only in check mode: a condition naming ansible_check_mode, not negated."""
    return any("ansible_check_mode" in c and not re.search(r"not\s+ansible_check_mode", c) for c in conditions)


def never_in_check(conditions):
    return any(re.search(r"not\s+ansible_check_mode", c) for c in conditions)


def module(task):
    for k in task:
        m = MODULE.match(k)
        if m and k not in ("name", "when", "register", "tags", "vars", "args", "loop", "become", "block", "rescue",
                           "always", "notify", "environment", "delegate_to", "run_once", "changed_when",
                           "failed_when", "retries", "delay", "until", "check_mode", "no_log", "loop_control",
                           "ignore_errors", "diff", "throttle", "listen"):
            return m.group(1)
    return ""


def tags_of(task):
    t = task.get("tags", [])
    return set(t if isinstance(t, list) else [t])


def flat(tasks, base, conds=(), tags=frozenset(), seen=()):
    """(task, the conditions above it, its tags with its parents') in run order; imports/includes followed."""
    for t in tasks or []:
        if not isinstance(t, dict):
            continue
        c, tg = list(conds) + whens(t), set(tags) | tags_of(t)
        if "block" in t:
            for part in ("block", "rescue", "always"):
                yield from flat(t.get(part), base, c, tg, seen)
            continue
        mod = module(t)
        if mod in ("import_tasks", "include_tasks"):
            ref = t[next(k for k in t if k.endswith(mod))]
            ref = ref.get("file") if isinstance(ref, dict) else ref
            path = os.path.normpath(os.path.join(base, str(ref).replace("{{ playbook_dir }}", base)))
            if "{{" not in path and os.path.exists(path) and path not in seen:
                yield from flat(yaml.safe_load(open(path)), os.path.dirname(path), c, tg, seen + (path,))
            continue
        yield t, c, tg


def lint(path, select=None, text=None):
    """The reads of a result check mode never made, in the playbook at `path` (its text `text`, if given) run with
    --tags `select` (None: every task)."""
    out, base = [], os.path.dirname(os.path.abspath(path))
    for play in yaml.safe_load(text if text is not None else open(path)) or []:
        if not isinstance(play, dict) or "tasks" not in play:
            continue
        skipped = set()
        for t, conds, tg in flat(play["tasks"], base, whens(play), tags_of(play)):
            if select is not None and not (tg & (select | {"always"})):
                continue
            if module(t) == "meta" and "end_host" in str(t) and check_only(conds):
                break
            runs = not never_in_check(conds)
            if runs:
                body = yaml.safe_dump({k: v for k, v in t.items() if k != "register"}, width=10000)
                for reg in sorted(skipped):
                    for m in re.finditer(rf"\b{re.escape(reg)}\.([A-Za-z_]+)", body):
                        if m.group(1) not in FINE and not re.match(r"\s*\|\s*default\b", body[m.end():]):
                            out.append(f"{path}: '{t.get('name')}' reads {reg}.{m.group(1)} - skipped in check mode")
                            break
            if "register" in t:
                if not runs or (module(t) in SKIPPED and t.get("check_mode") is not False):
                    skipped.add(t["register"])
                else:
                    skipped.discard(t["register"])
    return out


def step_lines():
    """Every step's playbook lines: (playbook path, its --tags or None)."""
    steps = sorted(f[:-4] for f in os.listdir(os.path.join(OPS, "tests", "ansible", "upgrade", "steps"))
                   if f.endswith(".txt"))
    out = set()
    for s in steps:
        r = subprocess.run([os.path.join(OPS, "scripts", "upgrade-expected-inventory.py"), "--playbooks", s],
                           capture_output=True, text=True, check=True)
        for line in r.stdout.splitlines():
            words = line.split()
            tags = words[words.index("--tags") + 1] if "--tags" in words else None
            out.add((os.path.join(PLAYBOOKS, words[0]), tags))
    return sorted(out, key=str)


def main():
    args = sys.argv[1:]
    if args:
        tags = args[args.index("--tags") + 1] if "--tags" in args else None
        lines = [(args[0], tags)]
    else:
        lines = step_lines()
    bad = [b for p, t in lines for b in lint(p, set(t.split(",")) if t else None)]
    print("\n".join(bad) or f"{len(lines)} playbook lines: no read of a result check mode skips")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
