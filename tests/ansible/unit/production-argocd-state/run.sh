#!/bin/bash
# The copy's Argo CD as production's until the first step that runs setup-argocd.yml on ten (31): the copy's build
# installs today's - the Application health check (the root waiting for each sync wave's apps Healthy) and the root's
# sync retries - which production has not had since 2026-10-01 (read on ten 2026-10-09: no such key in argocd-cm, no
# retry on the root). Without them steps 01-30 were proven with waves production does not wait on (the Scylla operator
# Healthy before its Manager moved, steps 15, 18, 21). tests/ansible/upgrade/production-argocd-state.yml takes both
# away right after the build's setup-argocd.yml, for a run from before that step - and sets ten's own Job health check
# (read on ten) in place of today's.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export W
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import json, os, re, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import actions  # noqa: E402
from templar import condition, render  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


steps = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
first = next(s for s in steps if re.search(r"(?m)^playbook setup-argocd\.yml",
                                            open(f"tests/ansible/upgrade/steps/{s}.txt").read()))
path = "tests/ansible/upgrade/production-argocd-state.yml"
play = (yaml.safe_load(open(path)) if os.path.exists(path) else [{}])[0]
tasks = play.get("tasks") or []
ends = [i for i, t in enumerate(tasks) if t.get("ansible.builtin.meta") == "end_play"]
before = steps[steps.index(first) - 1]
check(f"guarded first, then only for a run from before {first} (the first step running setup-argocd on ten)",
      ([i for i, t in enumerate(tasks) if "vagrant-only" in str(t.get("ansible.builtin.import_tasks", ""))][:1], ends[:1],
       [condition(tasks[ends[0]].get("when", "false"), **({"upgrade_from": f} if f else {}))
        for f in (None, steps[0], first, steps[steps.index(first) + 1])] if ends else None),
      ([0], [1], [False, False, False, True]))
text = json.dumps(tasks)
key = re.search(r"resource\.customizations\.health\.argoproj\.io_Application",
                open("deploy/ansible/playbooks/setup-argocd.yml").read())
check("argocd-cm without the Application health check setup-argocd installs",
      (bool(key), '"op": "remove", "path": "/data/resource.customizations.health.argoproj.io_Application"' in text
       or "/data/resource.customizations.health.argoproj.io_Application" in text), (True, True))
check("the root Application without its sync retries", "/spec/syncPolicy/retry" in text, True)
# the Job health check too (setup-argocd's Degrades a Job only once Kubernetes failed it; ten's at its first failed pod,
# a hook's sync failed with it): ten's own, read from ten - not a copy of it kept here - and set on the copy. Read, and
# refused empty, before anything is changed (a failed read left the copy half changed, the removes then refused a re-run);
# the removes skip a key already gone; the patch adds (it also sets a missing key). Tagged job-health: set only after the
# build's settle and its smoke (the cold k6 hook judged by ten's check failed the build at random, 2026-10-10)
job_key = "resource.customizations.health.batch_Job"
read = next((t for t in tasks if "production_ssh" in str(t.get("ansible.builtin.command", ""))), {})
argv = [str(a) for a in (read.get("ansible.builtin.command") or {}).get("argv", [])]
reg = read.get("register", "_none")
asserts = [t for t in tasks if "ansible.builtin.assert" in t and read and tasks.index(t) > tasks.index(read)]
patch = next((t for t in tasks if f"/data/{job_key}" in json.dumps(t)), {})
ops = (patch.get("kubernetes.core.k8s_json_patch") or {}).get("patch") or [{}]
writes = [i for i, t in enumerate(tasks) if "k8s_json_patch" in json.dumps(t)]
check("ten's Job health read on ten (ssh batch, bounded; sudo never asking), from here, read-only",
      (job_key in open("deploy/ansible/playbooks/setup-argocd.yml").read(), argv[:1], "{{ production_ssh }}" in argv,
       "BatchMode=yes" in argv, any(a.startswith("ConnectTimeout=") for a in argv), "-n" in argv[argv.index("sudo"):][:2]
       if "sudo" in argv else False, read.get("delegate_to"), read.get("become"), read.get("changed_when")),
      (True, ["ssh"], True, True, True, True, "localhost", False, False))
os.makedirs(os.path.join(os.environ["W"], "bin"), exist_ok=True)
for name, body in (("ssh", 'while [ "${1#-}" != "$1" ]; do shift 2; done\nshift\nexec sh -c "$*"'),
                   ("sudo", '[ "$1" = -n ] && shift\nexec "$@"'),
                   ("kubectl", 'for a in "$@"; do case "$a" in \'jsonpath={.data.resource\\.customizations\\.health\\.batch_Job}\') '
                               'printf TEN-LUA; exit 0 ;; esac; done\nexit 0')):
    open(os.path.join(os.environ["W"], "bin", name), "w").write("#!/bin/sh\n" + body + "\n")
    os.chmod(os.path.join(os.environ["W"], "bin", name), 0o755)
r = subprocess.run([render(a, **play.get("vars", {})) for a in argv], capture_output=True, text=True,
                   env=dict(os.environ, PATH=os.environ["W"] + "/bin:" + os.environ["PATH"])) if argv else None
check("read as ssh runs it (a remote shell parsing its words): the batch_Job key asked, its answer the stdout",
      (r.returncode, r.stdout) if r else None, (0, "TEN-LUA"))
that = asserts[0]["ansible.builtin.assert"]["that"] if asserts else "true"
check("an empty answer refused, a Lua passed",
      (condition(that, **{reg: {"stdout": " \n"}}), condition(that, **{reg: {"stdout": "TEN-LUA"}})), (False, True))
check("read and refused empty before anything is changed",
      bool(read) and bool(asserts) and bool(writes) and tasks.index(read) < tasks.index(asserts[0]) < min(writes), True)
check("the patch adds ten's answer to argocd-cm in argocd",
      ((patch.get("kubernetes.core.k8s_json_patch") or {}).get("kind"), (patch.get("kubernetes.core.k8s_json_patch") or {}).get("name"),
       ops[0].get("op"), render(str(ops[0].get("value", "")), **{reg: {"stdout": "TEN-LUA", "stderr": "E"}})),
      ("ConfigMap", "argocd-cm", "add", "TEN-LUA"))
removes = [t for t in tasks if '"op": "remove"' in json.dumps(t)]
check("each remove skips a key already gone (a re-run, or a copy without it)",
      [bool(t.get("when")) for t in removes], [True] * len(removes) if removes else [None])
tagged = lambda t: set(t.get("tags") or [])
check("the Job health's read, check and patch tagged job-health, the removes not; the guard and the end always",
      ([tagged(t) >= {"job-health"} for t in (read, asserts[0] if asserts else {}, patch)],
       [not tagged(t) & {"job-health"} for t in removes], "always" in tagged(tasks[0]), "always" in tagged(tasks[ends[0]]) if ends else None),
      ([True] * 3, [True] * len(removes), True, True))
argo = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:argo"]["cmds"]
cmds = [c.get("cmd", "") if isinstance(c, dict) else str(c) for c in argo]
at = [i for i, c in enumerate(cmds) if "production-argocd-state.yml" in c]
setup = [i for i, c in enumerate(cmds) if "playbooks/setup-argocd.yml" in c]
settle = [i for i, c in enumerate(cmds) if "argo-settled.yml" in c and "record_apps=true" in c]
smoke = [i for i, c in enumerate(cmds) if "vagrant-smoke.sh" in c]
check("run right after the build's setup-argocd.yml without the Job health, given the run's start",
      (len(at), at[:1] == [setup[0] + 1] if setup and at else None, "--skip-tags job-health" in (cmds[at[0]] if at else ""),
       "upgrade_from" in (cmds[at[0]] if at else "")), (2, True, True, True))
check("... and the Job health alone after the build's settle and its smoke, given the run's start",
      (len(at) == 2 and settle and smoke and at[1] > max(settle[0], smoke[-1]), "--tags job-health" in (cmds[at[1]] if len(at) > 1 else ""),
       "upgrade_from" in (cmds[at[1]] if len(at) > 1 else "")), (True, True, True))
print("production-argocd-state: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
