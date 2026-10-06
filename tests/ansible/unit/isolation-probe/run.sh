#!/bin/bash
# isolate-cluster.yml's proof that production is out of reach - the node's probe and the pod's - run as the playbook
# holds them (rendered with Jinja; kubectl and curl stubs, the pod's script run here). Only a connect that never
# completed is "blocked": curl exit 28 with no connect made. A connect that completed and then stalled (curl's
# --connect-timeout covers the TLS handshake, -m the rest: exit 28 too), a refusal, an answer - each fails the proof.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "isolation-probe: no python3 with jinja2 and yaml (PATH, repo venv)"; exit 2; }
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, tests/ansible/upgrade/isolate-cluster.yml > /dev/null 2>&1 \
  || { echo "FAIL isolate-cluster.yml does not load"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# curl: production's VIP answers as CURL ("<exit> <connects>"), anything else succeeds; -w's format is honoured
cat > "$W/bin/curl" <<'STUB'
#!/bin/sh
url= fmt=
while [ $# -gt 0 ]; do case "$1" in -w) fmt=$2; shift ;; https://*) url=$1 ;; esac; shift; done
case "$url" in
  https://192.168.11.5:*) set -- $CURL; [ -z "$fmt" ] || printf '%s' "$fmt" | sed "s/%{num_connects}/$2/"; exit "$1" ;;
  *) [ -z "$fmt" ] || printf '%s' "$fmt" | sed "s/%{num_connects}/1/"; exit 0 ;;
esac
STUB
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/sh
case "$1" in
  create) echo "kind: Namespace" ;;
  apply) cat > /dev/null ;;
  get) printf Running ;;
  exec) while [ "$1" != -- ]; do shift; done; shift; exec "$@" ;;
esac
STUB
chmod +x "$W"/bin/*
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
tasks = {t.get("name"): t for p in yaml.safe_load(open("tests/ansible/upgrade/isolate-cluster.yml"))
         for t in p.get("tasks", [])}
ctx = {"kubectl": os.path.join(W, "bin", "kubectl"), "production_vip": "192.168.11.5", "vagrant_vip": "192.168.56.5"}
fails = 0
def run(name, curl):
    t = tasks[name]
    script = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(t["ansible.builtin.shell"]).render(**ctx)
    r = subprocess.run([t["args"]["executable"], "-c", script], capture_output=True, text=True, env=dict(
        os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], CURL=curl))
    reg = {"rc": r.returncode, "stdout": r.stdout.strip()}
    return bool(jinja2.Environment().compile_expression(t["failed_when"])(**{t["register"]: reg})), reg
for name in ("Prove it - the node cannot reach production's VIP",
             "Prove it - a pod cannot reach production's VIP, and can reach the Vagrant VIP"):
    who = "node" if "node" in name else "pod"
    for curl, want_fail, what in (("28 0", False, "no connect, timed out: blocked"),
                                  ("28 1", True, "connected, then timed out: not blocked"),
                                  ("7 0", True, "refused: not blocked"),
                                  ("0 1", True, "answered: not blocked")):
        failed, reg = run(name, curl)
        ok = failed == want_fail
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {who}: {what}" + ("" if ok else f"\n  {reg}"))
print("isolation-probe: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
