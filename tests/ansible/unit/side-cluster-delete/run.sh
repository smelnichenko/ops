#!/bin/bash
# tests/ansible/upgrade/tasks/side-cluster-delete.yml's shell as the task file holds it (rendered with Jinja, its poll
# cut to 0.1 s), kubectl a stub: a side cluster's pods and volumes gone after its delete pass - at once, or after a
# while (a pod still terminating when the foreground delete returned failed the run once, read a single time); still
# there at the bound fails, naming them; kubectl failing fails. The four places that remove a side cluster use it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# get pods,pvc: "pod/x" for the first LEFT_FOR calls, then nothing; GET_FAIL=1: the API server not answering
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
case "$*" in
  *delete*) exit 0 ;;
  *"get pods,pvc"*)
    [ -z "${GET_FAIL:-}" ] || { echo "connection refused" >&2; exit 1; }
    n=$(( $(cat "$W/n" 2> /dev/null || echo 0) + 1 )); echo $n > "$W/n"
    [ "$n" -gt "${LEFT_FOR:-0}" ] || echo pod/side-1 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
task = yaml.safe_load(open("tests/ansible/upgrade/tasks/side-cluster-delete.yml"))[0]
script = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(task["ansible.builtin.shell"]).render(
    side_kubectl="kubectl -n ns", side_cluster="side", side_gone_seconds=1, side_poll=0.1)
fails = 0
for name, env, want_rc, words in (("gone at once", {}, 0, ""),
                                  ("a pod still terminating, gone after a while", {"LEFT_FOR": "3"}, 0, ""),
                                  ("still there at the bound: fails, naming it", {"LEFT_FOR": "999"}, 1, "pod/side-1"),
                                  ("kubectl failing: fails", {"GET_FAIL": "1"}, 1, "")):
    os.path.exists(os.path.join(W, "n")) and os.remove(os.path.join(W, "n"))
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    ok = min(r.returncode, 1) == want_rc and words in r.stdout + r.stderr
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f" (rc {r.returncode}: {r.stdout}{r.stderr})"))
# every place that removes a side cluster removes it so
users = {f: open(f).read().count("side-cluster-delete.yml") for f in
         ("tests/ansible/upgrade/tasks/wave0-pg-dump.yml", "tests/ansible/upgrade/restore-check.yml")}
left = {f: open(f).read().count("outlived its delete") for f in users}
ok = users == dict.fromkeys(users, 2) and left == dict.fromkeys(left, 0)
fails += not ok
print(f"{'PASS' if ok else 'FAIL'} the restore check and the Wave 0 dump remove their side clusters with it"
      + ("" if ok else f" ({users}, own checks left {left})"))
print("side-cluster-delete: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
