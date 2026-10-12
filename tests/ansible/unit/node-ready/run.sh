#!/bin/bash
# The node-Ready wait (tests/ansible/upgrade/tasks/node-ready.yml): its shell as Ansible renders it, against a stub
# kubectl and systemctl - an API server refusing its first connections (kubectl fails on them at once), a Node still
# showing the Ready it had before the kubelet restarted (its heartbeat older than the kubelet's start), a node that
# never becomes Ready (the deadline, by time, not a count of tries); and the two playbooks that wait on it use it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
# reads counted; REFUSALS: the first n refused (a starting API server); STALE_FOR: the first n answered with the
# heartbeat from before the kubelet's start; NOT_READY: Ready=False always
n=$(( $(cat "$W/n" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$W/n"; echo "$*" > "$W/args"
if [ "$n" -le "${REFUSALS:-0}" ]; then
  echo "The connection to the server 192.168.56.10:6443 was refused - did you specify the right host or port?" >&2; exit 1
fi
started=$(cat "$W/started")
if [ "$n" -le "$(( ${REFUSALS:-0} + ${STALE_FOR:-0} ))" ]; then hb=$(( started - 120 )); else hb=$(( started + 2 )); fi
status=True; [ -z "${NOT_READY:-}" ] || status=False
echo "kubeadm $status $(date -u -d @"$hb" +%Y-%m-%dT%H:%M:%SZ)"
STUB
cat > "$W/bin/systemctl" <<'STUB'
#!/bin/bash
case "$*" in *--timestamp=unix*) echo "@$(cat "$W/started")" ;; *) date -d @"$(cat "$W/started")" '+%a %Y-%m-%d %H:%M:%S %Z' ;; esac
STUB
chmod +x "$W/bin/kubectl" "$W/bin/systemctl"
W=$W "$PY" - <<'PY'
import os, re, subprocess, sys, time
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
task = yaml.safe_load(open("tests/ansible/upgrade/tasks/node-ready.yml"))[0]
shell = task["ansible.builtin.shell"]
fails = 0
def run(env, seconds=3, delay=0.1):
    script = render(shell, node_ready_seconds=seconds, node_ready_delay=delay)
    for f in ("n", "args"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    open(os.path.join(W, "started"), "w").write(str(int(time.time()) - 60))
    t0 = time.monotonic()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    reads = int(open(os.path.join(W, "n")).read()) if os.path.exists(os.path.join(W, "n")) else 0
    return r, reads, time.monotonic() - t0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f" ({detail})"))
r, reads, _ = run({})
check("Ready, its heartbeat after the kubelet's start: at once", r.returncode == 0 and reads == 1, f"rc {r.returncode}, {reads} reads")
r, reads, _ = run({"REFUSALS": "2"})
check("the API server refusing its first two connections: asked again, Ready", r.returncode == 0 and reads == 3,
      f"rc {r.returncode}, {reads} reads: {r.stdout}{r.stderr}")
r, reads, _ = run({"STALE_FOR": "2"})
check("the Ready from before the kubelet's restart: not taken, asked again", r.returncode == 0 and reads == 3,
      f"rc {r.returncode}, {reads} reads: {r.stdout}{r.stderr}")
r, reads, el = run({"NOT_READY": "1"}, seconds=2, delay=0.2)
check("never Ready: fails at its deadline, saying why", r.returncode == 1 and el < 6 and "Ready=False" in r.stdout,
      f"rc {r.returncode}, {el:.1f} s: {r.stdout}{r.stderr}")
# the budget is time, not a count of tries: refusals for most of it (each fails at once) still end Ready
r, reads, _ = run({"REFUSALS": "15"}, seconds=4, delay=0.15)
check("refusals for most of the deadline: a time budget, not a count", r.returncode == 0 and reads == 16,
      f"rc {r.returncode}, {reads} reads: {r.stdout}{r.stderr}")
args = open(os.path.join(W, "args")).read() if os.path.exists(os.path.join(W, "args")) else ""
check("each read bounded (--request-timeout)", "--request-timeout=" in args, args)
# the shipped defaults: 600 s on the boot clock, 5 s between reads
check("the shipped deadline and delay", "node_ready_seconds | default(600)" in shell and "node_ready_delay | default(5)" in shell
      and "/proc/uptime" in shell)
# the two playbooks that wait on a restarted node use it, and nothing waits on its own
for book, inc in (("tests/ansible/upgrade/vms-ready.yml", "tasks/node-ready.yml"),
                  ("tests/ansible/test-containerd-takeup.yml", "upgrade/tasks/node-ready.yml")):
    text = open(book).read()
    docs = yaml.safe_load(text)
    imports = [t.get("ansible.builtin.import_tasks") for p in docs for t in p.get("tasks", [])]
    check(f"{book} waits through node-ready.yml", inc in imports and not re.search(r"^[^#]*wait node", text, re.M),
          f"imports {imports}")
print("node-ready: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
