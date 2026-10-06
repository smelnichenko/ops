#!/bin/bash
# storage-check.yml's last check - the PersistentVolume and its directory gone - run as the playbook holds it (rendered
# with Jinja), kubectl a stub: the volume listed reads 1, gone reads 0, and kubectl failing fails the check - it read 0,
# "gone", when the API server did not answer. Its delete step stops at the first delete that fails.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "storage-check-gone: no python3 with jinja2 and yaml (PATH, repo venv)"; exit 2; }
# the playbook as Ansible loads it first: a free-form shell block it cannot split (a quote in a comment) never runs
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, tests/ansible/upgrade/storage-check.yml > /dev/null 2>&1 \
  || { echo "FAIL tests/ansible/upgrade/storage-check.yml does not load:"; "$AP" --syntax-check -i localhost, tests/ansible/upgrade/storage-check.yml 2>&1 | grep -A2 ERROR; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/sh
echo "kubectl $*" >> "$CALLS"
case "${KUBECTL:-}" in
  fail) echo "The connection to the server was refused" >&2; exit 1 ;;
  fail-first) case "$*" in *"delete pod"*) exit 1 ;; esac ;;
  listed) echo "persistentvolume/pvc-1" ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
tasks = {t["name"]: t for t in yaml.safe_load(open("tests/ansible/upgrade/storage-check.yml"))[0]["tasks"]}
ctx = {"kubectl": os.path.join(W, "bin", "kubectl"), "kubeconfig": "/k", "check_name": "c",
       "_read": {"stdout_lines": ["Succeeded", "x pvc-1"]}, "_pv_path": {"stdout": os.path.join(W, "gone")}}
fails = 0
def run(name, mode):
    t = tasks[name]
    cmd = t["ansible.builtin.shell"]
    script = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(cmd).render(**ctx)
    calls = os.path.join(W, "calls")
    open(calls, "w").close()
    shell = (t.get("args") or {}).get("executable", "/bin/sh")
    r = subprocess.run([shell, "-c", script], capture_output=True, text=True, env=dict(
        os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], KUBECTL=mode, CALLS=calls))
    return r.returncode, r.stdout.splitlines(), open(calls).read().splitlines()
def case(name, ok, detail):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
GONE = "The PersistentVolume and its directory are gone"
rc, out, _ = run(GONE, "listed")
case("the volume still listed: pv 1", rc == 0 and out[:1] == ["pv 1"], (rc, out))
rc, out, _ = run(GONE, "")
case("the volume gone: pv 0", rc == 0 and out == ["pv 0", "dir 0"], (rc, out))
rc, out, _ = run(GONE, "fail")
case("kubectl failing: the check fails, not 'gone'", rc != 0 and "pv 0" not in out, (rc, out))
rc, out, calls = run("Delete the pods and the volume", "fail-first")
case("the pods' delete failing: stops there", rc != 0 and not any("delete pvc" in c for c in calls), (rc, calls))
print("storage-check-gone: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
