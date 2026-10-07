#!/bin/bash
# The three playbooks that pause Patroni around their work (setup-consul, setup-patroni, upgrade-patroni) - their
# pause, resume and not-paused-already tasks as the files hold them, consul and patronictl stubs: each pause leaves a
# marker in Consul's KV naming the playbook and the time, put before the pause; each resume deletes it after; and a
# pause found by the next run names it - a Ctrl-C skips Ansible's always:, so a run cut short leaves the cluster paused
# (no failover) and, until now, a next run that could not tell it from someone's maintenance.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/kv"
cat > "$W/bin/consul" <<'STUB'
#!/bin/bash
echo "consul $*" >> "$W/calls"
[ "$1" = kv ] || exit 2
k=$W/kv/${3//\//_}
case "$2" in
  put) printf '%s' "$4" > "$k" ;;
  get) [ -e "$k" ] && cat "$k" && echo || { echo "Error! No key exists at: $3" >&2; exit 1; } ;;
  delete) rm -f "$k" ;;
esac
STUB
cat > "$W/bin/patronictl" <<'STUB'
#!/bin/bash
echo "patronictl $*" >> "$W/calls"
case "$*" in
  *"pause --wait"*) touch "$W/paused" ;;
  *"resume --wait"*) rm -f "$W/paused" ;;
  *list*) echo "+ Cluster: pg"; [ -e "$W/paused" ] && echo " Maintenance mode: on" ;;
esac
exit 0
STUB
chmod +x "$W/bin"/*
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
def tasks(items):
    for t in items or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k))
def text(t):
    for m in ("ansible.builtin.command", "ansible.builtin.shell"):
        a = t.get(m)
        if a is not None:
            return a if isinstance(a, str) else a.get("cmd", "")
    return ""
def sh(cmd, paused=False, marker=None):
    for f in os.listdir(os.path.join(W, "kv")):
        os.remove(os.path.join(W, "kv", f))
    open(os.path.join(W, "calls"), "w").close()
    if paused:
        open(os.path.join(W, "paused"), "w").close()
    elif os.path.exists(os.path.join(W, "paused")):
        os.remove(os.path.join(W, "paused"))
    if marker:
        open(os.path.join(W, "kv", "ansible_patroni-paused-by"), "w").write(marker)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"]))
    calls = open(os.path.join(W, "calls")).read().splitlines()
    kv = os.path.join(W, "kv", "ansible_patroni-paused-by")
    return r.returncode, r.stdout + r.stderr, calls, open(kv).read() if os.path.exists(kv) else None
for book in ("setup-consul", "setup-patroni", "upgrade-patroni"):
    all_tasks = [t for play in yaml.safe_load(open(f"deploy/ansible/playbooks/{book}.yml")) for t in tasks(play.get("tasks"))]
    pauses = [t for t in all_tasks if "pause --wait" in text(t) and "resume" not in text(t)]
    resumes = [t for t in all_tasks if "resume --wait" in text(t)]
    checks = [t for t in all_tasks if "Maintenance mode" in text(t) and "REFUSED" in text(t)]
    check(f"{book}: one pause, one resume, one not-paused check found", (len(pauses), len(resumes), len(checks)) == (1, 1, 1),
          (len(pauses), len(resumes), len(checks)))
    if not (pauses and resumes and checks):
        continue
    v = dict(patronictl="patronictl")
    rc, out, calls, kv = sh(render(text(pauses[0]), **v))
    order = [c.split()[0] + " " + c.split()[1] + (" " + c.split()[2] if c.startswith("consul") else "") for c in calls]
    check(f"{book}: the pause leaves a marker naming the playbook and its time, put before the pause",
          rc == 0 and kv is not None and book in kv and "Z" in kv and order[:2] == ["consul kv put", "patronictl pause"],
          (rc, out, calls, kv))
    rc, out, calls, kv = sh(render(text(resumes[0]), **v), paused=True, marker=f"{book} 2026-10-07T23:00:00Z")
    check(f"{book}: the resume resumes, then deletes the marker",
          rc == 0 and kv is None and not os.path.exists(os.path.join(W, "paused"))
          and [c.split()[1] for c in calls][:2] == ["resume", "kv"], (rc, out, calls, kv))
    rc, out, calls, kv = sh(render(text(checks[0]), **v), paused=True, marker=f"{book} 2026-10-07T23:00:00Z")
    check(f"{book}: paused, by a run cut short: refused, naming it", rc == 1 and "REFUSED" in out and
          f"{book} 2026-10-07T23:00:00Z" in out and "cut short" in out, (rc, out))
    rc, out, calls, kv = sh(render(text(checks[0]), **v), paused=True)
    check(f"{book}: paused, no marker (someone's maintenance): refused, no run named", rc == 1 and "REFUSED" in out
          and "cut short" not in out, (rc, out))
    rc, out, calls, kv = sh(render(text(checks[0]), **v))
    check(f"{book}: not paused: passes", rc == 0, (rc, out))
print("patroni-pause-marker: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
