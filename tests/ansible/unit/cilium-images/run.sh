#!/bin/bash
# setup-kubeadm.yml pulls every image the new Cilium chart renders before Helm upgrades it (one node: an agent that
# cannot pull leaves every pod without a network) - the task as the playbook holds it, rendered by Ansible's templar,
# run against stubs: helm answering with a rendered chart, ctr recording each pull. Each image by its digest (the tag
# dropped where a digest follows), one without a digest by its tag, each once; nothing rendered refused; a pull that
# fails, or a chart not rendered, fails the task; the version and the values passed; an upgrade only (a release runs),
# where Cilium's tasks run, retried before it fails.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/helm" <<'STUB'
#!/bin/bash
echo "$*" > "$W/helm.args"
cat > "$W/helm.stdin"
[ ! -e "$W/helm.fail" ] || { echo "Error: chart not found" >&2; exit 1; }
cat "$W/rendered.yaml"
STUB
cat > "$W/bin/ctr" <<'STUB'
#!/bin/bash
echo "$*" >> "$W/ctr.calls"
[ "${*: -1}" != "$(cat "$W/ctr.fail" 2> /dev/null)" ] || { echo "ctr: failed to resolve" >&2; exit 1; }
STUB
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def tasks(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k))
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-kubeadm.yml"))[0]
every = list(tasks(play["tasks"]))
t = next((x for x in every if (x.get("name") or "").startswith("Cilium's images for the new chart pulled first")), None)
check("the pull task present", t is not None, True)
if t is None:
    sys.exit(1)
install = next(i for i, x in enumerate(every) if (x.get("name") or "") == "Install Cilium via Helm")
check("pulled before Helm's upgrade, right before it", every.index(t) + 1, install)
check("an upgrade only (a release runs), where Cilium's tasks run, retried",
      ([condition(t["when"], _cilium_release={"stdout": s}) for s in ('[{"name":"cilium"}]', "[]")], t.get("tags"),
       "_cilium_images.rc == 0" in str(t.get("until")), int(t.get("retries", 0)) >= 3), ([True, False], ["cilium"], True, True))
sh = t["ansible.builtin.shell"]
cmd = render(sh["cmd"], cilium_version="1.20.4")
check("the chart's values passed on stdin", sh.get("stdin"), "{{ cilium_values | to_nice_yaml }}")
D = "sha256:" + "a" * 64
E = "sha256:" + "b" * 64
RENDERED = f"""spec:
  containers:
    - image: "quay.io/cilium/cilium:v1.20.4@{D}"
    - image: quay.io/cilium/operator-generic:v1.20.4@{E}
    - image: "quay.io/cilium/hubble-relay:v1.20.4"
    - image: "quay.io/cilium/cilium:v1.20.4@{D}"
    - image: "docker.io/library/busybox:1.36"
"""
def run(rendered, **flags):
    for f in ("ctr.calls", "helm.fail", "ctr.fail"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    open(os.path.join(W, "rendered.yaml"), "w").write(rendered)
    for f, v in flags.items():
        open(os.path.join(W, f.replace("_", ".")), "w").write(v)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, input="cluster: {}\n",
                       env={**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "W": W})
    calls = open(os.path.join(W, "ctr.calls")).read().splitlines() if os.path.exists(os.path.join(W, "ctr.calls")) else []
    return r.returncode, r.stdout, calls
rc, out, calls = run(RENDERED)
check("each Cilium image pulled once, by its digest where it has one, by its tag where not; another registry's aside",
      (rc, sorted(calls)), (0, sorted([f"-n k8s.io images pull quay.io/cilium/cilium@{D}",
                                       f"-n k8s.io images pull quay.io/cilium/hubble-relay:v1.20.4",
                                       f"-n k8s.io images pull quay.io/cilium/operator-generic@{E}"])))
check("the chart rendered at the new version, its values read from stdin",
      (open(os.path.join(W, "helm.args")).read().split()[:4], "--version" in open(os.path.join(W, "helm.args")).read(),
       "1.20.4" in open(os.path.join(W, "helm.args")).read().split(), open(os.path.join(W, "helm.stdin")).read()),
      (["template", "cilium", "cilium/cilium", "--version"], True, True, "cluster: {}\n"))
rc, out, calls = run("spec: {}\n")
check("no Cilium image rendered - refused, nothing pulled", (rc, "REFUSED" in out, calls), (1, True, []))
rc, out, calls = run(RENDERED, ctr_fail=f"quay.io/cilium/operator-generic@{E}")
check("a pull that fails fails the task (before Helm changes anything)", rc != 0, True)
rc, out, calls = run(RENDERED, helm_fail="")
check("the chart not rendered fails the task, nothing pulled", (rc != 0, calls), (True, []))
print("cilium-images: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
