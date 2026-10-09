#!/bin/bash
# isolate-cluster.yml's proof that production is out of reach - its VIP and every public address, the node's probe
# and the pod's - run as the playbook holds them (rendered by Ansible's templar; kubectl and curl stubs, the pod's
# script run here). Only a connect that never completed is "blocked": curl exit 28 with no connect made. A connect that
# completed and then stalled (curl's --connect-timeout covers the TLS handshake, -m the rest: exit 28 too), a refusal,
# an answer - each fails the proof; so does a public address reachable while the VIP is not (the second of two too),
# and so does the Vagrant VIP unreachable (the positive control: a node or pod with no network reads "blocked"
# everywhere).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "isolation-probe: no python3 with ansible and yaml (PATH, repo venv)"; exit 2; }
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, tests/ansible/upgrade/isolate-cluster.yml > /dev/null 2>&1 \
  || { echo "FAIL isolate-cluster.yml does not load"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# curl: production's VIP answers as CURL ("<exit> <connects>"), its public addresses as CURL_PUBLIC and CURL_PUBLIC2
# (else as CURL), the Vagrant VIP as VAGRANT (else it answers), anything else succeeds; -w's format is honoured
cat > "$W/bin/curl" <<'STUB'
#!/bin/sh
url= fmt=
while [ $# -gt 0 ]; do case "$1" in -w) fmt=$2; shift ;; https://* | telnet://*) url=$1 ;; esac; shift; done
# answer "<exit> <connects>": -w's format written with that connect count, then that exit
answer() { set -- $1; [ -z "$fmt" ] || printf '%s' "$fmt" | sed "s/%{num_connects}/$2/"; exit "$1"; }
case "$url" in
  https://192.168.11.5:*) answer "$CURL" ;;
  https://84.52.11.130:*) answer "${CURL_PUBLIC:-$CURL}" ;;
  https://84.52.11.131:*) answer "${CURL_PUBLIC2:-$CURL}" ;;
  https://192.168.56.5:*) answer "${VAGRANT:-0 1}" ;;
  telnet://192.168.56.21:22) answer "${PEER:-28 1}" ;;
  *) answer "0 1" ;;
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
# getent hosts <name>: the Vagrant VIP, or GETENT's address
cat > "$W/bin/getent" <<'STUB'
#!/bin/sh
echo "${GETENT:-192.168.56.5} $2"
STUB
chmod +x "$W"/bin/*
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
W = os.environ["W"]
tasks = {t.get("name"): t for p in yaml.safe_load(open("tests/ansible/upgrade/isolate-cluster.yml"))
         for t in p.get("tasks", [])}
ctx = {"kubectl": os.path.join(W, "bin", "kubectl"), "production_vip": "192.168.11.5", "vagrant_vip": "192.168.56.5",
       "production_public": ["84.52.11.130"]}
fails = 0
def run(name, curl, public=None, addresses=("84.52.11.130",), **env):
    t = tasks[name]
    c = dict(ctx, production_public=list(addresses))
    script = render(t["ansible.builtin.shell"], **c)
    r = subprocess.run([t["args"]["executable"], "-c", script], capture_output=True, text=True, env=dict(
        os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], CURL=curl,
        **({"CURL_PUBLIC": public} if public else {}), **env))
    reg = {"rc": r.returncode, "stdout": r.stdout.strip(), "stdout_lines": r.stdout.strip().splitlines()}
    return condition(t["failed_when"], **{t["register"]: reg}, **c), reg
probes = [n for n in tasks if (n or "").startswith(("Prove it - the node cannot reach production's VIP",
                                                    "Prove it - a pod cannot reach production's VIP"))]
fails += len(probes) != 2
print(f"{'PASS' if len(probes) == 2 else 'FAIL'} the node's probe and the pod's found ({len(probes)})")
for name in probes:
    who = "node" if "node" in name else "pod"
    for curl, want_fail, what in (("28 0", False, "no connect, timed out: blocked"),
                                  ("28 1", True, "connected, then timed out: not blocked"),
                                  ("7 0", True, "refused: not blocked"),
                                  ("0 1", True, "answered: not blocked")):
        failed, reg = run(name, curl)
        ok = failed == want_fail
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {who}: {what}" + ("" if ok else f"\n  {reg}"))
    for what, kw in (("the VIP blocked, the public address answering", {"public": "0 1"}),
                     ("two public addresses, the second answering", {"addresses": ("84.52.11.130", "84.52.11.131"),
                                                                     "CURL_PUBLIC2": "0 1"}),
                     ("everything blocked, the Vagrant VIP too (no network at all)", {"VAGRANT": "28 0"})):
        failed, reg = run(name, "28 0", **kw)
        fails += not failed
        print(f"{'PASS' if failed else 'FAIL'} {who}: {what}: no proof" + ("" if failed else f"\n  {reg}"))
    failed, reg = run(name, "28 0", addresses=("84.52.11.130", "84.52.11.131"))
    fails += failed
    print(f"{'PASS' if not failed else 'FAIL'} {who}: two public addresses, both blocked: blocked"
          + ("" if not failed else f"\n  {reg}"))
# isolate-pis.yml's probe on a Pi, the same rules, and its own positive control: the other Pi reached (a connect made)
pi = next(t for p in yaml.safe_load(open("tests/ansible/isolate-pis.yml")) for t in p.get("tasks") or []
          if str(t.get("name", "")).startswith("Prove it - the Pi resolves its names"))
pctx = {"pi_served_names": ["git"], "production_vip": "192.168.11.5", "production_public": ["84.52.11.130"],
        "keepalived_vip": "192.168.56.5", "peer": "192.168.56.21"}
def pi_run(curl, **env):
    script = render(pi["ansible.builtin.shell"], **pctx)
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=dict(
        os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], CURL=curl, **env))
    reg = {"rc": r.returncode, "stdout": r.stdout.strip(), "stdout_lines": r.stdout.strip().splitlines()}
    return condition(pi["failed_when"], _pi_probe=reg, **pctx), reg
for what, curl, env, want_fail in (("blocked, its names on the Vagrant VIP, the other Pi reached: passes", "28 0", {}, False),
                                   ("connected, then timed out: not blocked", "28 1", {}, True),
                                   ("the other Pi not reached (no network at all): fails", "28 0", {"PEER": "28 0"}, True),
                                   ("a name on production's VIP: fails", "28 0", {"GETENT": "192.168.11.5"}, True)):
    failed, reg = pi_run(curl, **env)
    ok = failed == want_fail
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} pi: {what}" + ("" if ok else f"\n  {reg}"))
# the guards' boot units: in place before any interface is up (nftables.service's own ordering) - After= alone let the
# network come up first, the copy reaching production until the rules loaded
import configparser
for book in ("tests/ansible/isolate-pis.yml", "tests/ansible/upgrade/isolate-cluster.yml"):
    unit = next(t["ansible.builtin.copy"]["content"] for pl in yaml.safe_load(open(book)) for t in pl.get("tasks") or []
                if str((t.get("ansible.builtin.copy") or {}).get("dest", "")).endswith("vagrant-isolate-production.service"))
    c = configparser.ConfigParser(strict=False)
    c.read_string(unit)
    u = c["Unit"]
    ok = (u.get("DefaultDependencies") == "no", "network-pre.target" in u.get("Wants", "").split(),
          "network-pre.target" in u.get("Before", "").split(), "network-pre.target" not in u.get("After", "").split())
    fails += ok != (True, True, True, True)
    print(f"{'PASS' if ok == (True, True, True, True) else 'FAIL'} {book}: its guard loads before the network "
          f"(DefaultDependencies=no, Wants= and Before=network-pre.target)" + ("" if all(ok) else f" - {ok}"))
print("isolation-probe: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
