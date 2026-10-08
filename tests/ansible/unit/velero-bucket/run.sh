#!/bin/bash
# setup-velero.yml's legacy install (where Argo CD does not own Velero): its bucket made in the in-cluster MinIO by a
# one-off pod - as the playbook holds it, rendered by Ansible's templar, kubectl a stub. The pod's image exists and is
# pinned (MinIO withdrew its mc images on 2026-09-24: quay.io 401, docker.io gone); the keys come from the very Secret
# the MinIO Deployment reads, into the pod's environment - never on a command line (the node's /proc shows a
# container's); a failure fails the task (`|| true` hid every one, the withdrawn image's too); changed only when the
# bucket was made.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$W/kubectl-argv"
[ -z "${POD_FAILS:-}" ] || { echo "An error occurred (403) when calling the HeadBucket operation: Forbidden"; echo 'pod velero/minio-setup terminated (Error)' >&2; exit 1; }
echo "${POD_SAYS:-BUCKET CREATED}"
STUB
chmod +x "$W/bin/kubectl"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import json, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render, trust_as_template  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-velero.yml"))[0]
task = next(t for t in play["tasks"] if t.get("name") == "Create velero bucket in MinIO")
deploy = next(t for t in play["tasks"] if t.get("name") == "Deploy backup MinIO Deployment")
minio_secret = deploy["kubernetes.core.k8s"]["definition"]["spec"]["template"]["spec"]["containers"][0]["envFrom"][0][
    "secretRef"]["name"]
def trusted(x):
    """A playbook's values as Ansible's loader gives them: templates (2.19 renders only trusted text)."""
    if isinstance(x, dict):
        return {k: trusted(y) for k, y in x.items()}
    if isinstance(x, list):
        return [trusted(y) for y in x]
    return trust_as_template(x) if isinstance(x, str) else x
v = trusted({**play["vars"], **task["vars"]})
over = render("{{ pod_overrides | to_json }}", **v)
over = json.loads(over) if isinstance(over, str) else over
c = over["spec"]["containers"][0]
check("the image pinned by its digest, not MinIO's withdrawn mc", ("@sha256:" in c["image"], "minio/mc" in c["image"]),
      (True, False))
env = {e["name"]: e.get("valueFrom", {}).get("secretKeyRef") for e in c.get("env", [])}
check("the keys from the MinIO Deployment's own Secret, into the environment",
      [(env.get(k) or {}).get("name") for k in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY")], [minio_secret] * 2)
check("no key on a command line", any(x in json.dumps(c["command"]) for x in ("SECRET_ACCESS_KEY", "ROOT_PASSWORD",
                                                                                "ROOT_USER", "ACCESS_KEY_ID")), False)
sh = task["ansible.builtin.shell"]
sh = render(sh if isinstance(sh, str) else sh["cmd"], **v)
def run(**e):
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **e))
    reg = {"rc": r.returncode, "stdout": r.stdout, "stderr": r.stderr}
    return r.returncode, condition(task.get("changed_when", True), **{task.get("register", "_r"): reg})
check("made: passes, changed", run(), (0, True))
check("there already: passes, unchanged", run(POD_SAYS="BUCKET EXISTS"), (0, False))
rc, _ = run(POD_FAILS="1")
check("the pod failing (its image gone, the store refusing): the task fails", rc != 0, True)
print("velero-bucket: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
