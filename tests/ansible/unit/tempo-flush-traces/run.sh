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
answer = lambda span, rc=0: {"rc": rc, "stdout": '{"batches": [{"scopeSpans": [{"spans": [{"name": "%s"}]}]}]}' % span}
# each held check, as Ansible evaluates its until: its own span's name in a good answer - not a failed read with it,
# not the other trace's
check("each found held before it is kept - its own span in a good answer", [
    [condition(t["until"], **{t["register"]: a}) for a in (answer(v["push_name"]), answer(v["push_name"], rc=1),
                                                           answer(other))]
    for t, (_, v), other in zip(held, pushes, ("upgrade-postflush", "upgrade-preflush"))],
      [[True, False, False]] * 2)
keep = next(t for t in flush if "ansible.builtin.copy" in t)
ids = {"_trace": "a" * 32, "_after": "b" * 32, "_after_at": "1000"}
path = os.path.join(W, "ids")
open(path, "w").write(render(keep["ansible.builtin.copy"]["content"], **ids))
verify = next(t for t in play["tasks"] if t.get("when") == "mode == 'verify'" and "loop" in t)
items = render(verify["loop"], id_file=path)
check("verify looks up every trace pushed, each by its ID", sorted(i.split()[0] for i in items),
      sorted(render(v["push_trace_id"], **ids) for _, v in pushes))
reg = verify["register"]
spans = [i.split()[1] for i in items]
check("each passes only with its own span's name in the answer - not with the other trace's",
      [(condition(verify["until"], item=i, **{reg: answer(i.split()[1])}),
        condition(verify["until"], item=i, **{reg: answer(next(x for x in spans if x != i.split()[1]))}))
       for i in items], [(True, False)] * 2)
# the second trace proves flush_all_on_shutdown only if Tempo 2 stopped while it still held it: within its
# max_block_duration (5 min) of the push - later, Tempo 2 wrote it to the store itself. Tempo is replaced by Recreate:
# its new pod is made after the old one stopped
lived = next((t for t in play["tasks"] if "stopped within" in t.get("name", "")), None)
check("verify judges how long Tempo 2 lived after the second trace", lived is not None and lived.get("when") ==
      "mode == 'verify'", True)
if lived:
    import subprocess
    os.makedirs(os.path.join(W, "bin"), exist_ok=True)
    open(os.path.join(W, "bin", "kubectl"), "w").write('#!/bin/bash\necho "$MADE"\n')
    os.chmod(os.path.join(W, "bin", "kubectl"), 0o755)
    sh = lived["ansible.builtin.shell"]
    sh = render(sh if isinstance(sh, str) else sh["cmd"], kubeconfig="k", id_file=path, mode="verify")
    env = {k: str(render(str(v), id_file=path)) for k, v in (lived.get("environment") or {}).items()}
    def made_after(seconds):
        made = __import__("datetime").datetime.fromtimestamp(1000 + seconds, __import__("datetime").timezone.utc)
        r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True, env=dict(
            os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], MADE=made.strftime("%Y-%m-%dT%H:%M:%SZ"),
            **env))
        return r.returncode
    check("Tempo 2 replaced 100 s after the second trace: proven; 400 s after: not proven, fails",
          [made_after(100), min(made_after(400), 1)], [0, 1])
print("tempo-flush-traces: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYTFT
