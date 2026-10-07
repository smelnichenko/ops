#!/bin/bash
# test-pi-rerun-guards.yml's read of keepalived's running router_id (its DATA signal to the main process), both plays'
# copies as the playbook holds them, systemctl and keepalived stubs, `kill` a shell function - nothing is signalled
# here: a running keepalived gets the DATA signal through systemd (systemctl kill --kill-whom=main: the unit's main
# process when it signals - a PID read first and signalled after could be another's once keepalived restarted in
# between) and its router_id is read; one not running is refused, nothing signalled.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# systemctl: keepalived active when RUNNING; `kill` recorded, keepalived's answer to DATA written
cat > "$W/bin/systemctl" <<'STUB'
#!/bin/bash
case "$1" in
  is-active) [ -n "${RUNNING:-}" ] ;;
  show) [ -n "${RUNNING:-}" ] && echo 4321 || echo 0 ;;
  kill) echo "SYSTEMCTL $*" >> "$W/calls"; printf ' Router ID = r1\n' > "$DATA" ;;
esac
STUB
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
    # a kill of a PID: recorded - none expected
    script = (f'kill() {{ echo "KILL $*" >> {W}/calls; }}\n'
              + plays[name]["vars"]["running_router_id"].replace("/tmp/keepalived.data", data))
    for running, want_rc, want_out, want_calls in (
            ("1", 0, "r1", "SYSTEMCTL kill --kill-whom=main -s 36 keepalived"), ("", 1, "not running", "")):
        open(os.path.join(W, "calls"), "w").close()
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"],
                                    RUNNING=running, DATA=data, W=W))
        calls = open(os.path.join(W, "calls")).read().strip()
        ok = (r.returncode != 0) == bool(want_rc) and want_out in r.stdout + r.stderr and calls == want_calls
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {name.split(' - ')[0]}, keepalived {'running' if running else 'stopped'}: "
              + ("its main process signalled by systemd, router_id read" if running else "refused, nothing signalled")
              + ("" if ok else f" (rc {r.returncode}, out {r.stdout + r.stderr!r}, calls {calls!r})"))
print("keepalived-data: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
