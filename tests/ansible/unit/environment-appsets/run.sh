#!/bin/bash
# An environment's ApplicationSets as production has them: generators of git directories since 2026-04-10
# (clusters/production/schnappy-*-<chart>) - an environment is listed by its own directories, nothing to edit. Both
# create-environment (scripts/update-appsets.py) and destroy-environment (its Phase 2) edited a list generator and
# failed there (KeyError 'list'); a list one is still edited, another shape refused. destroy-environment takes only an
# environment create-environment made: its directories exactly -apps, -data, -mesh (production's infra has -data and
# -mesh - its removal deleted the Argo application with its finalizer; production's own -realtime besides).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYEAS'
import copy, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
GIT = {"apiVersion": "argoproj.io/v1alpha1", "kind": "ApplicationSet", "metadata": {"name": "x", "namespace": "argocd"},
       "spec": {"generators": [{"git": {"repoURL": "u", "revision": "main",
                                        "directories": [{"path": "clusters/production/schnappy-*-CHART"}]}}],
                "template": {}}}
LIST = {"apiVersion": "argoproj.io/v1alpha1", "kind": "ApplicationSet", "metadata": {"name": "x", "namespace": "argocd"},
        "spec": {"generators": [{"list": {"elements": [{"env": "old"}]}}], "template": {}}}
def tree(shape):
    d = os.path.join(W, shape)
    os.makedirs(os.path.join(d, "argocd", "apps"), exist_ok=True)
    for chart in ("data", "apps", "mesh"):
        doc = copy.deepcopy(GIT if shape == "git" else LIST)
        if shape == "git":
            doc["spec"]["generators"][0]["git"]["directories"][0]["path"] = f"clusters/production/schnappy-*-{chart}"
        if shape == "other":
            doc["spec"]["generators"] = [{"matrix": {}}]
        open(os.path.join(d, "argocd", "apps", f"schnappy-{chart}-envs.yaml"), "w").write(yaml.safe_dump(doc))
    return d
def files(d):
    return {f: open(os.path.join(d, "argocd", "apps", f)).read() for f in sorted(os.listdir(os.path.join(d, "argocd", "apps")))}
# create: scripts/update-appsets.py
res = {}
for shape in ("git", "list", "other"):
    d = tree(shape)
    before = files(d)
    r = subprocess.run([sys.executable, "deploy/ansible/playbooks/scripts/update-appsets.py", d, "pr1", "schnappy-pr1",
                        "schnappy-pr1"], capture_output=True, text=True)
    after = files(d)
    res[shape] = (r.returncode, after == before,
                  all("pr1" in after[f] for f in after) if shape == "list" else None)
check("create: git directories - nothing edited, 0; a list - the environment added; another shape - refused",
      res, {"git": (0, True, None), "list": (0, False, True), "other": (1, True, None)})
# destroy: its Phase 2 script, as the playbook holds it
book = yaml.safe_load(open("deploy/ansible/playbooks/destroy-environment.yml"))[0]
t = next(t for t in book["tasks"] if t.get("name") == "Remove env from ApplicationSets")
sh = t["ansible.builtin.shell"]
res = {}
for shape in ("git", "list", "other"):
    d = tree(shape + "-d")
    if shape != "git":
        for f in os.listdir(os.path.join(d, "argocd", "apps")):
            doc = copy.deepcopy(LIST if shape == "list" else LIST)
            doc["spec"]["generators"][0]["list"]["elements"].append({"env": "pr1"})
            if shape == "other":
                doc["spec"]["generators"] = [{"matrix": {}}]
            open(os.path.join(d, "argocd", "apps", f), "w").write(yaml.safe_dump(doc))
    before = files(d)
    script = render(sh if isinstance(sh, str) else sh["cmd"], cluster_dir=d, env_name="pr1", env_ns="schnappy-pr1")
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    after = files(d)
    res[shape] = (r.returncode, after == before, all("pr1" not in after[f] for f in after) if shape == "list" else None)
check("destroy: git directories - nothing edited, 0; a list - the environment removed; another shape - refused",
      res, {"git": (0, True, None), "list": (0, False, True), "other": (1, True, None)})
# destroy takes only an environment create-environment made: exactly -apps, -data, -mesh
guard = next((t for t in book.get("pre_tasks") or [] if "exactly" in str(t.get("name", ""))), None)
reg = next((t.get("register") for t in book.get("pre_tasks") or [] if "ansible.builtin.find" in t), "_none")
def refused(dirs, env_ns):
    found = {"files": [{"path": f"/c/{x}"} for x in dirs]}
    return condition((guard or {}).get("when", "true"), env_ns=env_ns, **{reg: found})
check("destroy: production's infra (-data, -mesh), production's own (-realtime besides), none: refused; a made one: on",
      [refused(["schnappy-infra-data", "schnappy-infra-mesh"], "schnappy-infra"),
       refused(["schnappy-production-apps", "schnappy-production-data", "schnappy-production-mesh",
                "schnappy-production-realtime"], "schnappy-production"),
       refused([], "schnappy-pr1"),
       refused(["schnappy-pr1-apps", "schnappy-pr1-data", "schnappy-pr1-mesh"], "schnappy-pr1")],
      [True, True, True, False])
print("environment-appsets: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYEAS
