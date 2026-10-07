#!/bin/bash
# test-pi-rerun-guards.yml's read of keepalived's running router_id (its DATA signal to the MainPID), both plays' copies
# as the playbook holds them, systemctl and keepalived stubs and `kill` a shell function - nothing is signalled here:
# a running keepalived gets the DATA signal and its router_id is read; one not running (MainPID 0) is refused, never
# `kill 0` - that signals the task's own process group, ending the module instead of saying keepalived is down.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
printf '#!/bin/sh\necho "$MAINPID"\n' > "$W/bin/systemctl"
printf '#!/bin/sh\necho 36\n' > "$W/bin/keepalived"
chmod +x "$W/bin"/*
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import yaml
W = os.environ["W"]
plays = {p["name"]: p for p in yaml.safe_load(open("tests/ansible/test-pi-rerun-guards.yml")) if "name" in p}
fails = 0
for name in ("Keepalived before - pi1 running a drifted router_id", "Keepalived after - reloaded, the VIP where it was"):
    data = os.path.join(W, "keepalived.data")
    # kill: recorded, and keepalived's answer to DATA written - no process signalled
    script = (f'kill() {{ echo "KILL $*" >> {W}/calls; printf " Router ID = r1\\n" > {data}; }}\n'
              + plays[name]["vars"]["running_router_id"].replace("/tmp/keepalived.data", data))
    for pid, want_rc, want_out, want_kill in (("4321", 0, "r1", "KILL -s 36 4321"),
                                             ("0", 1, "not running", "")):
        open(os.path.join(W, "calls"), "w").close()
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], MAINPID=pid))
        calls = open(os.path.join(W, "calls")).read().strip()
        ok = (r.returncode != 0) == bool(want_rc) and want_out in r.stdout + r.stderr and calls == want_kill
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {name.split(' - ')[0]}, MainPID {pid}: "
              + ("signalled, router_id read" if pid != "0" else "refused, nothing signalled")
              + ("" if ok else f" (rc {r.returncode}, out {r.stdout + r.stderr!r}, kill {calls!r})"))
print("keepalived-data: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
