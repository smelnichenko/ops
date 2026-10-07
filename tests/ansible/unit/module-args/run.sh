#!/bin/bash
# Every task's module arguments are its module's own: each task of the repo's playbooks and test playbooks (dict
# arguments, args: included) against the options and aliases its module documents, read by Ansible's own plugin loader.
# An unsupported one fails only when the task runs: apt's download_only (dnf's, not apt's) stopped the full run of
# 2026-10-07 two hours in, at step 14. set_fact and add_host take any key and are not checked. A module this Ansible
# cannot load fails too (skipped, a whole collection's tasks went unchecked wherever it was missing), and every
# collection a module resolves to (redirects followed: ansible.builtin.mount is ansible.posix's) is one
# deploy/ansible/requirements.yml installs.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "module-args: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import sys
import yaml
from ansible.plugins.loader import fragment_loader, init_plugin_loader, module_loader
from ansible.utils.plugin_docs import get_docstring
init_plugin_loader()
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
ANY_KEY = {"ansible.builtin.set_fact", "set_fact", "ansible.builtin.add_host", "add_host"}
cache, collections = {}, {}


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
            collections[module] = ".".join(found.resolved_fqcn.split(".")[:2])
        cache[module] = opts
    return cache[module]


def unsupported(task):
    """[(module, [keys its module does not document])] - modules this Ansible can load."""
    out = []
    for m, value in actions(task):
        if m in ANY_KEY:
            continue
        args = dict(value) if isinstance(value, dict) else {}
        if isinstance(task.get("args"), dict):
            args.update(task["args"])
        opts = options(m)
        if opts is None:
            out.append((m, ["no such module here"]))
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
for f in files():
    for t in tasks(load(f)):
        if "block" in t:
            continue
        seen += 1
        bad += [f"{f}: {t.get('name')}: {m}: {e}" for m, e in unsupported(t)]
check(f"every task's arguments its module's ({seen} tasks)", bad, [])
check("tasks found (the walk reaches them)", seen > 1500, True)
installed = {c["name"] for c in yaml.safe_load(open("deploy/ansible/requirements.yml"))["collections"]}
check("every module's collection installed by requirements.yml",
      sorted({f"{c} ({m})" for m, c in collections.items() if c != "ansible.builtin" and c not in installed}), [])
print("module-args: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
