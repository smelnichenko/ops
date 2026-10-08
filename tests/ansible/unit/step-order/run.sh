#!/bin/bash
# test:upgrade:step's commands in the order production's procedure takes them (scripts/upgrade-production.py merge):
# Wave 0, the images on the node (the copy's preload, production's pre-pull), then Tempo's flush - all before the
# step's commits reach Argo (the mirror push, production's merge) - then the settles. The pre-pull after the push let
# Argo's own poll start the rollout before it, which production never does.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYSO'
import sys
import yaml
cmds = [c.get("cmd", "") if isinstance(c, dict) else str(c)
        for c in yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:step"]["cmds"]]
def at(word):
    found = [i for i, c in enumerate(cmds) if word in c]
    return found[0] if found else None
idx = {w: at(w) for w in ("test:upgrade:wave0", "tempo-flush.yml -e mode=flush", "vagrant-preload-images.sh",
                          "prepull-images", "vagrant-gitops-mirror.py", "argo-settled.yml")}
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
check("each of them there", [k for k, v in idx.items() if v is None], [])
if all(v is not None for v in idx.values()):
    push = idx["vagrant-gitops-mirror.py"]
    check("Wave 0, Tempo's flush, the preload and the pre-pull before the push; the push before the first settle",
          [idx["test:upgrade:wave0"] < push, idx["tempo-flush.yml -e mode=flush"] < push,
           idx["vagrant-preload-images.sh"] < push, idx["prepull-images"] < push, push < idx["argo-settled.yml"]],
          [True] * 5)
    # Tempo flushed right before the push, as production's merge flushes after its pre-pull: a flush first left the
    # pre-pull's minutes of spans in Tempo 2's WAL, which Tempo 3 does not replay
    check("Tempo's flush after the preload and the pre-pull, right before the push",
          [idx["vagrant-preload-images.sh"] < idx["tempo-flush.yml -e mode=flush"],
           idx["prepull-images"] < idx["tempo-flush.yml -e mode=flush"], idx["tempo-flush.yml -e mode=flush"] + 1 == push],
          [True] * 3)
print("step-order: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYSO
