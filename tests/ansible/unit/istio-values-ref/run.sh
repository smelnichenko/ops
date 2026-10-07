#!/bin/bash
# setup-istio.yml's and setup-kubeadm.yml's Istio values, read from infra by git show, as the playbooks hold them: the
# directory and ref reach the shell quoted (one argument each, whatever they hold), and with the default ref (main) the
# local main must be origin's - one behind (CD pushed meanwhile) or ahead (commits never pushed) installed other values
# than production runs - refused; equal passes. Run on throwaway repos (an origin and its clone).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare -b main "$W/origin.git"
git clone -q "$W/origin.git" "$W/infra" 2> /dev/null
git -C "$W/infra" commit -q --allow-empty -m a && git -C "$W/infra" push -q origin main
W=$W "$PY" - <<'PY'
import os, shlex, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
W = os.environ["W"]
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {detail}"))
for f in ("deploy/ansible/playbooks/setup-istio.yml", "deploy/ansible/playbooks/setup-kubeadm.yml"):
    tasks = [t for p in yaml.safe_load(open(f)) for b in p.get("tasks") or [] for t in [b] + (b.get("block") or [])]
    looks = [t for t in tasks if "git -C" in str(t.get("kubernetes.core.helm", {}).get("values", ""))]
    hostile = "/x; touch " + os.path.join(W, "pwned")
    hostile_ref = "main; touch " + os.path.join(W, "pwned-ref") + "; echo"  # the path appended after it goes to echo
    for t in looks:
        expr = t["kubernetes.core.helm"]["values"].split("lookup('ansible.builtin.pipe', ", 1)[1]
        expr = expr.rsplit(") | from_yaml", 1)[0]
        # each rendered command run as the pipe lookup runs it - through a shell: a name that broke out of its quotes
        # runs its touch (checked at the end)
        cmd = render("{{ " + expr + " }}", infra_dir=hostile, infra_values_ref="main")
        check(f"{f}: {t['name']}: the directory one argument", shlex.split(cmd)[2] == hostile, cmd)
        subprocess.run(["bash", "-c", cmd], capture_output=True)
        cmd = render("{{ " + expr + " }}", infra_dir="/infra", infra_values_ref=hostile_ref)
        check(f"{f}: {t['name']}: the ref one argument", shlex.split(cmd)[4].startswith(hostile_ref + ":"), cmd)
        subprocess.run(["bash", "-c", cmd], capture_output=True)
    sync = [t for t in tasks if str(t.get("name", "")).startswith("Infra's local main is origin's")]
    check(f"{f}: the local main checked against origin's", len(sync) == 1, [t.get("name") for t in tasks][:5])
    if not sync:
        continue
    # run with the default ref only (a branch under test is read as it is), and before the values are read
    ran = [condition(sync[0].get("when", True), infra_values_ref=r, platform_by_argo=False)
           for r in ("main", "upgrade/x")]
    check(f"{f}: run with ref main, not with another", ran == [True, False], ran)
    check(f"{f}: before the installs that read the values",
          all(tasks.index(sync[0]) < tasks.index(t) for t in looks) and bool(looks), [t["name"] for t in looks])
    script = render(sync[0]["ansible.builtin.shell"], infra_dir=os.path.join(W, "infra"))
    git = lambda *a: subprocess.run(["git", "-C", os.path.join(W, "infra"), *a], check=True, capture_output=True)
    run = lambda: subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    check(f"{f}: main as origin's: passes", run().returncode == 0)
    git("commit", "-q", "--allow-empty", "-m", "local")
    check(f"{f}: a commit never pushed: refused", run().returncode != 0)
    git("reset", "-q", "--hard", "origin/main")
    other = os.path.join(W, "other")
    subprocess.run(["git", "clone", "-q", os.path.join(W, "origin.git"), other], check=True, capture_output=True)
    subprocess.run(["git", "-C", other, "commit", "-q", "--allow-empty", "-m", "cd"], check=True, capture_output=True)
    subprocess.run(["git", "-C", other, "push", "-q", "origin", "main"], check=True, capture_output=True)
    check(f"{f}: origin's main moved on (CD): refused", run().returncode != 0)
    git("pull", "-q", "--ff-only", "origin", "main")
    subprocess.run(["rm", "-rf", other], check=True)
check("nothing ran from the directory's name or the ref's", not os.path.exists(os.path.join(W, "pwned"))
      and not os.path.exists(os.path.join(W, "pwned-ref")))
print("istio-values-ref: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
