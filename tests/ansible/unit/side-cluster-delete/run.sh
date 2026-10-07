#!/bin/bash
# tests/ansible/upgrade/tasks/side-cluster-delete.yml's shell as the task file holds it (rendered by Ansible's templar,
# its poll cut to 0.1 s), kubectl a stub: a side cluster's pods and volumes gone after its delete pass - at once, or
# after a while (a pod still terminating when the foreground delete returned failed the run once, read a single time);
# its delete call failing (the API server a moment away) asked again until one reaches the cluster, never after;
# still there at the bound fails, naming them; a read failing is read again (one failed get ended the run), failing
# to the bound fails, saying why. The four places that remove a side cluster use it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# the cluster's pods go only once a delete call reached it - DELETE_FAIL_FOR=<n>: the first n delete calls fail (the API
# server a moment away); get pods,pvc: "pod/x" until then, and for the first LEFT_FOR calls; GET_FAIL_FOR=<n>: the API
# server not answering the first n reads
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
case "$*" in
  *delete*) d=$(( $(cat "$W/d" 2> /dev/null || echo 0) + 1 )); echo $d > "$W/d"
    [ "$d" -gt "${DELETE_FAIL_FOR:-0}" ] || { echo "the server is currently unable to handle the request" >&2; exit 1; }
    touch "$W/deleted"; exit 0 ;;
  *"get pods,pvc"*)
    n=$(( $(cat "$W/n" 2> /dev/null || echo 0) + 1 )); echo $n > "$W/n"
    [ "$n" -gt "${GET_FAIL_FOR:-0}" ] || { echo "connection refused" >&2; exit 1; }
    # a read that answers and logs besides (an aggregated API down: discovery's line on stderr)
    [ -z "${STDERR_NOTE:-}" ] || echo "E1008 memcache.go:265] couldn't get resource list for metrics.k8s.io/v1beta1" >&2
    if [ ! -e "$W/deleted" ] || [ "$n" -le "${LEFT_FOR:-0}" ]; then echo pod/side-1; fi ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
task = yaml.safe_load(open("tests/ansible/upgrade/tasks/side-cluster-delete.yml"))[0]
script = render(task["ansible.builtin.shell"],
                side_kubectl="kubectl -n ns", side_cluster="side", side_gone_seconds=1, side_poll=0.1)
fails = 0
for name, env, want_rc, words in (("gone at once", {}, 0, ""),
                                  ("a pod still terminating, gone after a while; the delete asked once",
                                   {"LEFT_FOR": "3"}, 0, ""),
                                  ("still there at the bound: fails, naming it", {"LEFT_FOR": "999"}, 1, "pod/side-1"),
                                  ("kubectl failing once (the API server a moment away), then gone: passes",
                                   {"GET_FAIL_FOR": "1"}, 0, ""),
                                  ("kubectl failing to the bound: fails, saying so", {"GET_FAIL_FOR": "999"}, 1,
                                   "connection refused"),
                                  ("gone, the read logging on stderr besides: passes - the log is no leftover",
                                   {"STDERR_NOTE": "1"}, 0, ""),
                                  ("the delete's own call failing once (an API blip): asked again, gone: passes",
                                   {"DELETE_FAIL_FOR": "1"}, 0, ""),
                                  ("the delete failing to the bound: fails, naming what is left",
                                   {"DELETE_FAIL_FOR": "999"}, 1, "pod/side-1")):
    for f in ("n", "d", "deleted"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    asked = int(open(os.path.join(W, "d")).read()) if os.path.exists(os.path.join(W, "d")) else 0
    # asked again while its calls fail; once one reached the cluster, never again
    fail_for = int(env.get("DELETE_FAIL_FOR", 0))
    once = asked == fail_for + 1 if fail_for < 100 else asked > 1
    ok = min(r.returncode, 1) == want_rc and words in r.stdout + r.stderr and once
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f" (rc {r.returncode}, {asked} deletes: {r.stdout}{r.stderr})"))
# the read as bash reads it (its continuation joined), up to its redirection
get = task["ansible.builtin.shell"].replace("\\\n", " ").split("get pods,pvc")[1].split("2>")[0] \
    if "get pods,pvc" in task["ansible.builtin.shell"] else ""
check_get = "--request-timeout=" in get
fails += not check_get
print(f"{'PASS' if check_get else 'FAIL'} each read bounded (--request-timeout): a hung one outlived the bound")
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
