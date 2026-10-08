#!/usr/bin/env python3
"""check-mode-lint.py - a playbook the upgrade preview runs in check mode reads no result check mode never made.

The preview (scripts/upgrade-step-playbooks.sh --check) runs a step's playbook lines with --check: shell, command,
script, raw and uri tasks are skipped there unless they say check_mode: false, and so is a task under `when: not
ansible_check_mode`. Their register then holds no stdout, rc or results, and a later task that reads one fails the
preview - step 37's did, three hours into a full run (2026-10-06), found by nothing before. This reads each play in
order, imports and static includes followed, as the preview runs it:

  - only the tasks the line's --tags select run (with their blocks' and includes' tags; `always` always, `never` only
    when selected); pre_tasks, tasks, post_tasks and handlers in that order;
  - an end_host reached only in check mode (under `when: ansible_check_mode`) ends the play for the preview;
  - a shell or command task check mode skips still registers rc 0 and an empty stdout (ansible-core 2.20): a read of
    it is named, `| default(...)` or not (default never applies - the empty value flows on); a raw, script or uri task
    skipped (raw: skipped alone; script: skipped, or changed with creates/removes), or a task skipped by its own
    condition, registers no such field: a read with `| default(...)` is fine; a read by subscript (r['stdout']) is a
    read;
  - an import's tasks take its tags, an include's do not (only its apply: tags) - and run only when the include does;
  - handlers run after each section (pre_tasks, tasks, post_tasks); an import or include the lint cannot follow (not
    found, its name templated) is named, never skipped unseen;
  - a read in a task that check mode skips itself is fine;
  - a block's and an include's own keywords (when, loop, vars) are read where they stand; a register lives on in its
    host's later plays and other hosts read it through hostvars (hostvars['h']['r'].stdout) - read across the
    playbook; a loop over a skipped looped register's results gets its items, each skipped - an item's field other
    than what a skipped item holds (item, skipped, skip_reason...) is a read, a with_together's part over them
    (item.0.f) too, and so is one read by index, as the first or last, by a filter or a json_query - the results
    written r.results or r['results'], the register by its name or through hostvars; strings are read as parsed (a
    subscript in double quotes, r["stdout"], as one in single).

Usage: scripts/check-mode-lint.py                    (every step's playbook lines, and the playbooks a deploy task
                                                     hands {{.CLI_ARGS}} - a --check preview; exit 1 naming each read)
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
EMPTY = {"shell", "command"}  # skipped in check mode, their register still holds rc 0, stdout '' (raw, script: none)
FINE = {"skipped", "changed", "failed", "skip_reason"}  # what a skipped task's register does hold
MODULE = re.compile(r"^(?:ansible\.builtin\.|ansible\.legacy\.)?([a-z_]+)$")
# a read given a default right after it: `| default(...)`
DEFAULTED = re.compile(r"\s*\|\s*default\b")
# Ansible's task keywords - every other key of a task is its module (or action)
KEYWORDS = {"name", "when", "register", "tags", "vars", "args", "loop", "loop_control", "become", "become_user",
            "become_method", "become_flags", "become_exe", "block", "rescue", "always", "notify", "listen",
            "environment", "delegate_to", "delegate_facts", "run_once", "changed_when", "failed_when", "retries",
            "delay", "until", "check_mode", "diff", "no_log", "ignore_errors", "ignore_unreachable", "throttle",
            "timeout", "async", "poll", "any_errors_fatal", "remote_user", "port", "connection", "module_defaults",
            "collections", "debugger", "local_action"}
SECTIONS = ("pre_tasks", "tasks", "post_tasks", "handlers")
# the order a play runs them in: handlers flushed after each of the others
RUN_ORDER = ("pre_tasks", "handlers", "tasks", "handlers", "post_tasks", "handlers")


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
        if m and k not in KEYWORDS and not k.startswith("with_"):
            return m.group(1)
    return ""


def tags_of(task):
    t = task.get("tags", [])
    return set(t if isinstance(t, list) else [t])


def selected(tags, select):
    """Whether a task of these tags runs under --tags `select` (None: every task)."""
    if select is not None and not (tags & (select | {"always"})):
        return False
    return "never" not in tags or bool(select and tags & select - {"never"})


def flat(tasks, base, conds=(), tags=frozenset(), seen=(), select=None):
    """(task, the conditions above it, its tags with its parents') in run order; imports and includes followed - an
    import's tasks with its tags, an include's with its apply: tags alone, and only when the include itself runs. One
    not followed (not found, its name templated) yields ({"__not_followed__": ref}, ...)."""
    for t in tasks or []:
        if not isinstance(t, dict):
            continue
        c, tg = list(conds) + whens(t), set(tags) | tags_of(t)
        if "block" in t:
            # the block's own keywords, read where it stands
            yield {"__head__": True, **{k: v for k, v in t.items() if k not in ("block", "rescue", "always")}}, \
                list(conds), tg
            for part in ("block", "rescue", "always"):
                yield from flat(t.get(part), base, c, tg, seen, select)
            continue
        mod = module(t)
        if mod in ("import_tasks", "include_tasks"):
            yield {"__head__": True, **{k: v for k, v in t.items() if not k.endswith(mod)}}, list(conds), tg
            ref = t[next(k for k in t if k.endswith(mod))]
            apply = (ref.get("apply") or {}) if isinstance(ref, dict) else {}
            ref = ref.get("file") if isinstance(ref, dict) else ref
            if mod == "include_tasks":
                if not selected(tg, select):
                    continue
                # its tasks take its parents' tags (the play's, its blocks') and apply:'s - never its own
                apply_tags = apply.get("tags", [])
                tg = set(tags) | set(apply_tags if isinstance(apply_tags, list) else [apply_tags])
            path = os.path.normpath(os.path.join(base, str(ref).replace("{{ playbook_dir }}", base)))
            if "{{" in path or not os.path.exists(path):
                yield {"__not_followed__": ref}, c, tg
            elif path not in seen:
                yield from flat(yaml.safe_load(open(path)), os.path.dirname(path), c, tg, seen + (path,), select)
            continue
        yield t, c, tg


def strings(node):
    """Every string of a task as parsed (keys aside) - a subscript's quotes as written, not as YAML would dump them."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings(v)


def name_of(reg):
    """Register `reg` as a template names it: reg, or hostvars[...]['reg']."""
    return rf"(?:(?<![\w.]){re.escape(reg)}|\[\s*['\"]{re.escape(reg)}['\"]\s*\])"


# a field as a template reads it: .f or ['f'] / ["f"]
FIELD = r"(?:\.([A-Za-z_]+)|\[\s*['\"]([A-Za-z_]+)['\"]\s*\])"
# a json_query over it (Ansible's, community.general's): the fields its query names
JSON_QUERY = r"\s*\|\s*(?:community\.general\.)?json_query\(\s*['\"]([^'\"]*)['\"]"


def query_fields(query):
    """The fields a JMESPath query reads - its names, a literal's aside."""
    return re.findall(r"[A-Za-z_]\w*", re.sub(r"`[^`]*`|'[^']*'", "", query))


def read_of(reg, text, field=None):
    """[(field, read with | default)] of register `reg` in `text`: reg.f, reg['f'], hostvars[...]['reg'].f, a
    json_query of it - with `field`, only reads of that field."""
    out, text = [], str(text)
    for m in re.finditer(name_of(reg) + FIELD, text):
        f = m.group(1) or m.group(2)
        if field is None or f == field:
            out.append((f, bool(DEFAULTED.match(text, m.end()))))
    for m in re.finditer(name_of(reg) + JSON_QUERY, text):
        for f in query_fields(m.group(1))[:1]:
            if field is None or f == field:
                out.append((f, False))
    return out


def item_reads(reg, text):
    """[(field, read with | default)] of the items of looped register `reg`'s results in `text`, read otherwise than as
    a loop's item: one by its index (reg.results[0].f, reg['results'][0]['f']) or as its first or last, each by a filter
    naming the field (map(attribute=...), selectattr, rejectattr, sum/sort/groupby/unique/min/max(attribute=...)), by a
    json_query, by a Jinja for over them - the register by its name or through hostvars."""
    text, out = str(text), []
    # its results as written: .results or ['results'], the register by its name or through hostvars
    res = name_of(reg) + r"(?:\.results|\[\s*['\"]results['\"]\s*\])"
    # one by its index, or its first or last
    for m in re.finditer(res + r"\[\s*-?\d+\s*\]" + FIELD, text):
        out.append((m.group(1) or m.group(2), bool(DEFAULTED.match(text, m.end()))))
    for m in re.finditer(r"\(\s*" + res + r"\s*\|\s*(?:first|last)\s*\)" + FIELD, text):
        out.append((m.group(1) or m.group(2), bool(DEFAULTED.match(text, m.end()))))
    for m in re.finditer(res + JSON_QUERY, text):
        out.extend((f, False) for f in query_fields(m.group(1)))
    # a json_query of the register itself over its results: results[*].f - the names after results its items'
    for m in re.finditer(name_of(reg) + JSON_QUERY, text):
        names = query_fields(m.group(1))
        if names[:1] == ["results"]:
            out.extend((f, False) for f in names[1:])
    for m in re.finditer(res + r"\s*\|\s*(?:(?:selectattr|rejectattr)\(\s*|(?:map|sum|sort|groupby|unique|min|max)"
                         r"\([^)]*?attribute\s*=\s*)['\"]([A-Za-z_]+)", text):
        out.append((m.group(1), False))
    for m in re.finditer(r"\{%-?\s*for\s+(\w+)\s+in\s+" + res + r"\b", text):
        out.extend(read_of(m.group(1), text[m.end():]))
    return out


def zip_parts(loop):
    """A loop's lists zipped together - `a | zip(b, c)`: [a, b, c] (the item's k-th part from the k-th); none: []."""
    m = re.search(r"\{\{(.*?)\|\s*zip\((.*)\)", loop, re.S)
    if not m:
        return []
    parts, depth, cur = [m.group(1)], 0, ""
    for ch in m.group(2):
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
            continue
        depth += (ch in "([{") - (ch in ")]}")
        cur += ch
    return parts + [cur]


def lint(path, select=None, text=None):
    """The reads of a result check mode never made, in the playbook at `path` (its text `text`, if given) run with
    --tags `select` (None: every task)."""
    out, base = [], os.path.dirname(os.path.abspath(path))
    # register -> (whether its fields are there, empty (EMPTY's) - else absent; whether its task looped: its results
    # then there, each item skipped alike); across the plays: a register lives on in its host's later plays, and the
    # others read it through hostvars
    skipped = {}
    for play in yaml.safe_load(text if text is not None else open(path)) or []:
        if not isinstance(play, dict) or not any(k in play for k in SECTIONS):
            continue
        for t, conds, tg in (x for k in RUN_ORDER for x in flat(play.get(k), base, whens(play), tags_of(play),
                                                                 select=select)):
            if "__not_followed__" in t:
                out.append(f"{path}: imports or includes {t['__not_followed__']} - not followed (not found, or its name "
                           f"templated): what it holds is unread")
                continue
            if not selected(tg, select):
                continue
            if module(t) == "meta" and "end_host" in str(t) and check_only(conds):
                break
            runs = not never_in_check(conds)  # a block's or an include's own when is read: its conditions are its parents'
            if runs:
                own = {k: v for k, v in t.items() if k not in ("register", "__head__")}
                if t.get("__head__"):
                    # a block's or an include's own when, as Ansible evaluates a list: in order, stopping at the first
                    # false - what follows `not ansible_check_mode` is never read in a preview, nor its vars or loop
                    # (rendered only once its when holds)
                    w = whens(t)
                    cut = next((i for i, c in enumerate(w) if never_in_check([c])), len(w))
                    own = {"when": w[:cut]} if cut < len(w) else dict(own, when=w)
                texts = list(strings(own))
                # its own register aside: a task check mode skips evaluates no until/failed_when on it
                reads = [(reg, empty, looped) for reg, (empty, looped) in sorted(skipped.items())
                         if reg != t.get("register")]
                # a loop over a skipped looped register's results: its items, each skipped alike (one not looped has no
                # results: that read is the one named)
                loop = str(t.get("loop", "")) + str(t.get("with_items", ""))
                over = [empty for reg, empty, looped in reads if looped and read_of(reg, loop, "results")]
                var = (t.get("loop_control") or {}).get("loop_var", "item")
                items = set()  # the names a skipped item goes by in this task
                if over:
                    reads.append((var, over[0], False))
                    items.add(var)
                # zipped with other lists: the item's part from its results (item[k], item.k)
                for k, part in enumerate(zip_parts(loop)):
                    hit = [empty for reg, empty, looped in reads if looped and read_of(reg, part, "results")]
                    if hit:
                        for name in (f"{var}[{k}]", f"{var}.{k}"):
                            reads.append((name, hit[0], False))
                            items.add(name)
                # with_together: its k-th list a skipped looped register's results - each item's k-th part (item.k)
                together = t.get("with_together")
                for k, part in enumerate(together if isinstance(together, list) else []):
                    hit = [empty for reg, empty, looped in reads if looped and read_of(reg, str(part), "results")]
                    if hit:
                        reads.append((f"{var}.{k}", hit[0], False))
                        items.add(f"{var}.{k}")
                for reg, empty, looped in reads:
                    fine = FINE | ({"item", "false_condition", "ansible_loop_var"} if reg in items else set()) \
                        | ({"results"} if looped else set())
                    hit = next((f for x in texts for f, defaulted in read_of(reg, x)
                                if f not in fine and (empty or not defaulted)), None)
                    # its items, each skipped alike: read by an index, a filter or a Jinja for - not as a loop's item
                    hit = hit or next((f"results[].{f}" for x in texts for f, defaulted in
                                       (item_reads(reg, x) if looped else [])
                                       if f not in FINE | {"item", "false_condition", "ansible_loop_var"}
                                       and (empty or not defaulted)), None)
                    if hit:
                        out.append(f"{path}: '{t.get('name')}' reads {reg}.{hit} - skipped in check mode")
            if "register" in t:
                looped = any(k in t for k in ("loop", "with_items", "with_dict", "with_list", "with_together"))
                if not runs:
                    skipped[t["register"]] = (False, looped)
                elif module(t) in SKIPPED and t.get("check_mode") is not False:
                    skipped[t["register"]] = (module(t) in EMPTY, looped)
                else:
                    skipped.pop(t["register"], None)
    return list(dict.fromkeys(out))  # a handler run after each section names a read once


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


def previewed_playbooks():
    """The playbooks a Taskfile task runs with the caller's arguments ({{.CLI_ARGS}}: a --check preview among them)."""
    tasks = yaml.safe_load(open(os.path.join(OPS, "Taskfile.yml")))["tasks"]
    out = set()
    for t in tasks.values():
        for c in (t or {}).get("cmds") or []:
            cmd = c.get("cmd", "") if isinstance(c, dict) else str(c)
            if "{{.CLI_ARGS}}" in cmd:
                out.update(re.findall(r"playbooks/([a-z0-9-]+\.yml)", cmd))
    return sorted(out)


def main():
    args = sys.argv[1:]
    if args:
        tags = args[args.index("--tags") + 1] if "--tags" in args else None
        lines = [(args[0], tags)]
    else:
        lines = step_lines() + [(os.path.join(PLAYBOOKS, p), None) for p in previewed_playbooks()]
    bad = [b for p, t in lines for b in lint(p, set(t.split(",")) if t else None)]
    print("\n".join(bad) or f"{len(lines)} playbook lines: no read of a result check mode skips")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
