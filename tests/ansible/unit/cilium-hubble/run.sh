#!/bin/bash
# The Cilium agents' Hubble check after the copy's VMs boot (tests/ansible/copy/tasks/cilium-hubble.yml): its shell as
# Ansible renders it, against a stub kubectl - Hubble Ok at once; an agent still starting (no Hubble line yet); the
# 2026-11-20 failure (Hubble's port still held at the agent's start) cured by one restart of its pod; the same failure
# after the restart failing the run; a state that never turns Ok failing at its deadline (by time, not a count); an API
# server refusing its first connections; and the readiness playbook running it after the node is Ready.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
# the agents' pod: cilium-a, cilium-b after one deletion. REFUSALS: the first n calls refused (a starting API server).
# STARTING: the first n status reads have no Hubble line. FAIL_A / FAIL_B: that pod's Hubble failed to start.
# OTHER: every pod's Hubble in another state that never turns Ok
n=$(( $(cat "$W/n" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$W/n"; echo "$*" >> "$W/args"
if [ "$n" -le "${REFUSALS:-0}" ]; then
  echo "The connection to the server 192.168.56.10:6443 was refused - did you specify the right host or port?" >&2; exit 1
fi
pod=$(cat "$W/pod" 2> /dev/null || echo cilium-a)
case "$*" in
  *" get pods "*) echo "$pod" ;;
  *" delete pod "*) echo "$*" >> "$W/deleted"; echo cilium-b > "$W/pod"; echo "pod \"$pod\" deleted" ;;
  *" exec "*)
    reads=$(( $(cat "$W/reads" 2> /dev/null || echo 0) + 1 )); echo "$reads" > "$W/reads"
    echo "KVStore:                 Disabled"
    if [ "$reads" -le "${STARTING:-0}" ]; then exit 0; fi
    if [ -n "${OTHER:-}" ]; then echo "Hubble:                  Warning observer not ready"; exit 0; fi
    if { [ "$pod" = cilium-a ] && [ -n "${FAIL_A:-}" ]; } || { [ "$pod" = cilium-b ] && [ -n "${FAIL_B:-}" ]; }; then
      echo "Hubble:                  Warning failed to initialize hubble server: failed to apply option: listen tcp :4244: bind: address already in use   Metrics: Disabled"
    else
      echo "Hubble:                  Ok              Current/Max Flows: 4095/4095 (100.00%), Flows/s: 21.07   Metrics: Disabled"
    fi
    echo "Cluster health:          1/1 reachable" ;;
  *) echo "unexpected kubectl $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, re, subprocess, sys, time
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render
W = os.environ["W"]
task = yaml.safe_load(open("tests/ansible/copy/tasks/cilium-hubble.yml"))[0]
shell = task["ansible.builtin.shell"]
fails = 0
def run(env, seconds=3, delay=0.1):
    script = render(shell, cilium_hubble_seconds=seconds, cilium_hubble_delay=delay)
    for f in ("n", "args", "pod", "deleted", "reads"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    t0 = time.monotonic()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    deleted = open(os.path.join(W, "deleted")).read().splitlines() if os.path.exists(os.path.join(W, "deleted")) else []
    return r, deleted, time.monotonic() - t0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f" ({detail})"))
def changed(r):
    return condition(task["changed_when"], _hubble={"stdout": r.stdout})
r, deleted, _ = run({})
check("Hubble Ok at once: done, nothing restarted, nothing changed", r.returncode == 0 and not deleted and not changed(r)
      and "Hubble Ok on every agent" in r.stdout, f"rc {r.returncode}, {deleted}: {r.stdout}{r.stderr}")
r, deleted, _ = run({"STARTING": "2"})
check("an agent still starting (no Hubble line): asked again, Ok", r.returncode == 0 and not deleted,
      f"rc {r.returncode}: {r.stdout}{r.stderr}")
r, deleted, _ = run({"FAIL_A": "1"})
check("Hubble failed to start (its port held): the agent's pod deleted once, Ok after, said and changed",
      r.returncode == 0 and len(deleted) == 1 and "delete pod cilium-a" in deleted[0] and "--wait=true" in deleted[0]
      and "restarting cilium-a" in r.stdout and "restarted once: cilium-a" in r.stdout and changed(r),
      f"rc {r.returncode}, {deleted}: {r.stdout}{r.stderr}")
r, deleted, _ = run({"FAIL_A": "1", "FAIL_B": "1"})
check("the same failure after the restart: fails, saying so, restarted only once",
      r.returncode == 1 and len(deleted) == 1 and "failed to start again" in r.stdout, f"rc {r.returncode}, {deleted}: {r.stdout}{r.stderr}")
r, deleted, el = run({"OTHER": "1"}, seconds=2, delay=0.2)
check("a state that never turns Ok: fails at its deadline, saying what it read, nothing restarted",
      r.returncode == 1 and el < 6 and not deleted and "observer not ready" in r.stdout, f"rc {r.returncode}, {el:.1f} s: {r.stdout}{r.stderr}")
r, deleted, _ = run({"REFUSALS": "2"})
check("the API server refusing its first two connections: asked again, Ok", r.returncode == 0 and not deleted,
      f"rc {r.returncode}: {r.stdout}{r.stderr}")
# the budget is time, not a count of tries: refusals for most of it (each fails at once) still end Ok
r, deleted, _ = run({"REFUSALS": "15"}, seconds=4, delay=0.15)
check("refusals for most of the deadline: a time budget, not a count", r.returncode == 0, f"rc {r.returncode}: {r.stdout}{r.stderr}")
args = open(os.path.join(W, "args")).read() if os.path.exists(os.path.join(W, "args")) else ""
check("each call bounded (--request-timeout), the admin kubeconfig", all("--request-timeout=" in a and "/etc/kubernetes/admin.conf" in a
      for a in args.splitlines() if a), args)
check("the shipped deadline and delay, on the boot clock", "cilium_hubble_seconds | default(600)" in shell
      and "cilium_hubble_delay | default(5)" in shell and "/proc/uptime" in shell)
# the readiness playbook runs it once the node is Ready (an agent is read through the API server)
docs = yaml.safe_load(open("tests/ansible/copy/vms-ready.yml"))
imports = [t.get("ansible.builtin.import_tasks") for p in docs for t in p.get("tasks", [])]
check("vms-ready.yml runs it after the node is Ready", "tasks/cilium-hubble.yml" in imports and "tasks/node-ready.yml" in imports
      and imports.index("tasks/cilium-hubble.yml") > imports.index("tasks/node-ready.yml"), f"imports {imports}")
print("cilium-hubble: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
