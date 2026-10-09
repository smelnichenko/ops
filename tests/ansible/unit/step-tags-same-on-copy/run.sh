#!/bin/bash
# The copy runs setup-kubeadm with platform_by_argo off (production: on). A step's tagged playbook line must then run
# the same tasks on both: no task under a tag a step's line runs (or under no tag at all - tagged runs skip those)
# depends on platform_by_argo. The tags read from the step files; the playbook's blocks walked with their tags.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_STC'
import glob, re, sys, yaml
lines = [l.split(None, 1)[1].strip() for f in glob.glob("tests/ansible/upgrade/steps/*.txt") for l in open(f)
         if l.startswith("playbook setup-kubeadm.yml")]
tags = {t for l in lines for m in re.finditer(r"--tags (\S+)", l) for t in m.group(1).split(",")}
def walk(ts, inherited=()):
    for t in ts or []:
        if isinstance(t, dict):
            tg = list(inherited) + list(t.get("tags") or [])
            yield t, tg
            for k in ("block", "rescue", "always"):
                yield from walk(t.get(k), tg)
bad = []
for pl in yaml.safe_load(open("deploy/ansible/playbooks/setup-kubeadm.yml")):
    for t, tg in walk(pl.get("tasks")):
        if (set(tg) & tags or "always" in tg) and "platform_by_argo" in str(t.get("when", "")):
            bad.append(f"{t.get('name')} ({', '.join(sorted(set(tg) & (tags | {'always'})))})")
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
check("the steps' setup-kubeadm tags read (local-path, gateway-api, cilium among them)",
      {"local-path", "gateway-api", "cilium"} <= tags, True)
check("no task a step's tagged line runs depends on platform_by_argo", bad, [])
print("step-tags-same-on-copy: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_STC
