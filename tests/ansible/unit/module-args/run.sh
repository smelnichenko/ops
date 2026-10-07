#!/bin/bash
# Every task's module arguments are its module's own: each task of the repo's playbooks and test playbooks (dict
# arguments, args: included) against the options and aliases its module documents, read by Ansible's own plugin loader.
# An unsupported one fails only when the task runs: apt's download_only (dnf's, not apt's) stopped the full run of
# 2026-10-07 two hours in, at step 14. set_fact and add_host take any key and are not checked; a module this Ansible
# cannot load (a collection CI's image lacks: ansible.posix, behind ansible.builtin.mount's redirect) is ansible-lint's.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "module-args: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import glob, sys
import yaml
from ansible.plugins.loader import fragment_loader, init_plugin_loader, module_loader
from ansible.utils.plugin_docs import get_docstring
init_plugin_loader()
KEYWORDS = {"name", "when", "register", "tags", "vars", "args", "loop", "loop_control", "become", "become_user",
            "become_method", "become_flags", "become_exe", "block", "rescue", "always", "notify", "listen",
            "environment", "delegate_to", "delegate_facts", "run_once", "changed_when", "failed_when", "retries",
            "delay", "until", "check_mode", "diff", "no_log", "ignore_errors", "ignore_unreachable", "throttle",
            "timeout", "async", "poll", "any_errors_fatal", "remote_user", "port", "connection", "module_defaults",
            "debugger", "collections", "local_action"}
ANY_KEY = {"ansible.builtin.set_fact", "set_fact", "ansible.builtin.add_host", "add_host"}
cache = {}


def options(module):
    """The module's documented options and their aliases - None for no such module."""
    if module not in cache:
        found = module_loader.find_plugin_with_context(module)
        opts = None
        if found.resolved:
            opts = set()
            for k, v in ((get_docstring(found.plugin_resolved_path, fragment_loader)[0] or {}).get("options") or {}).items():
                opts.add(k)
                opts.update((v or {}).get("aliases") or [])
        cache[module] = opts
    return cache[module]


def tasks(node):
    if isinstance(node, list):
        for x in node:
            yield from tasks(x)
    elif isinstance(node, dict):
        yield node
        for k in ("tasks", "pre_tasks", "post_tasks", "handlers", "block", "rescue", "always"):
            yield from tasks(node.get(k))


def unsupported(task):
    """[(module, [keys its module does not document])] - modules this Ansible can load."""
    out = []
    for m in [k for k in task if k not in KEYWORDS and not str(k).startswith("with_") and k not in ANY_KEY]:
        args = dict(task[m]) if isinstance(task[m], dict) else {}
        if isinstance(task.get("args"), dict):
            args.update(task["args"])
        opts = options(m)
        if opts is None:
            continue
        extra = sorted(set(args) - opts - {"free_form", "_raw_params"})
        if extra:
            out.append((m, extra))
    return out


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got))))


# the check on fixtures: apt's download_only named, a documented alias accepted
check("apt with download_only: named", unsupported({"ansible.builtin.apt": {"name": "x", "download_only": True}}),
      [("ansible.builtin.apt", ["download_only"])])
check("apt with an alias (pkg) and update_cache: fine",
      unsupported({"ansible.builtin.apt": {"pkg": "x", "update_cache": True}}), [])
seen, bad = 0, []
for f in sorted(glob.glob("deploy/ansible/**/*.yml", recursive=True) + glob.glob("tests/ansible/**/*.yml", recursive=True)):
    if "/venv/" in f:
        continue
    try:
        doc = yaml.safe_load(open(f))
    except yaml.YAMLError:
        continue  # not YAML Ansible reads (a template)
    for t in tasks(doc):
        if "block" in t:
            continue
        seen += 1
        bad += [f"{f}: {t.get('name')}: {m}: {e}" for m, e in unsupported(t)]
check(f"every task's arguments its module's ({seen} tasks)", bad, [])
check("tasks found (the walk reaches them)", seen > 1500, True)
print("module-args: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
