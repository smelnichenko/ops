#!/bin/bash
# tests/ansible/upgrade/tempo-flush.yml as the file holds it (its expressions rendered by Ansible's templar): flush mode
# pushes a trace before the flush and one after it (what arrives until Tempo 2 stops - only its stop writes that to
# the store), each found held, and keeps both IDs with their spans' names; verify mode looks up every kept ID and
# passes on each only with its own span's name in the answer. Proving the first alone passed a Tempo 2 that lost all it
# took after the flush.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYTFT'
import os, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
from ansible.plugins.loader import init_plugin_loader  # noqa: E402
init_plugin_loader()  # lookups by their full names, as the CLI has them
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
play = yaml.safe_load(open("tests/ansible/upgrade/tempo-flush.yml"))[1]
flush = next(t for t in play["tasks"] if t.get("name") == "Flush")["block"]
names = [t.get("name", "") for t in flush]
at = next(i for i, t in enumerate(flush) if "tempo-flush.py" in str(t.get("ansible.builtin.script", "")))
pushes = [(i, t["vars"]) for i, t in enumerate(flush) if t.get("ansible.builtin.include_tasks") == "tasks/tempo-push.yml"]
check("a trace pushed before the flush and one after it",
      [(i < at, v["push_name"]) for i, v in pushes], [(True, "upgrade-preflush"), (False, "upgrade-postflush")])
held = [t for t in flush if "/proxy/api/traces/" in str(t.get("ansible.builtin.command", ""))]
check("each found held before it is kept", [any(v["push_name"] in str(t.get("until")) for t in held) for _, v in pushes],
      [True, True])
keep = next(t for t in flush if "ansible.builtin.copy" in t)
ids = {"_trace": "a" * 32, "_after": "b" * 32}
path = os.path.join(W, "ids")
open(path, "w").write(render(keep["ansible.builtin.copy"]["content"], **ids))
verify = next(t for t in play["tasks"] if t.get("when") == "mode == 'verify'")
items = render(verify["loop"], id_file=path)
check("verify looks up every trace pushed, each by its ID", sorted(i.split()[0] for i in items),
      sorted(render(v["push_trace_id"], **ids) for _, v in pushes))
answer = lambda span: {"rc": 0, "stdout": '{"batches": [{"scopeSpans": [{"spans": [{"name": "%s"}]}]}]}' % span}
reg = verify["register"]
check("each passes only with its own span's name in the answer",
      [(condition(verify["until"], item=i, **{reg: answer(i.split()[1])}),
        condition(verify["until"], item=i, **{reg: answer("someone-else")})) for i in items], [(True, False)] * 2)
print("tempo-flush-traces: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYTFT
