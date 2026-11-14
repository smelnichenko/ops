#!/bin/bash
# upgrade-pi-packages.yml: what it reads on a Pi (playbooks/scripts/pi-packages.py) and the order of one Pi's turn
# (tasks/pi-packages-node.yml). The script against stubs answering as apt 3.0, systemd 257, GlusterFS 11, Patroni 4.1
# and Consul 1.20 do (their outputs read on pi1, 2026-11-14), Consul's autopilot and Nexus's status from a local HTTP
# server: the plan's packages and summary, a removal refused, apt's answer unread or its count off refused; the
# services a reboot must bring back - running and enabled, keepalived's own aside; each back, or not yet, or unread;
# Gluster mounted from fstab's volume and healed, or a brick away, entries to heal, a heal unread; Patroni healthy,
# a replica lagging or not streaming, the leader named; Consul's quorum to spare, or not, or unread; the VIP's Pi
# serving keepalived's services, or not holding the VIP, or a service down or not answering. The turn as Ansible
# evaluates it (its templar): the order (the VIP holder last), nothing to upgrade ends the Pi's turn, the handovers
# before apt's upgrade, the tier-0 lock read right before the reboot, keepalived started again where the run stopped it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'kill "$(cat "$W/server.pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/state" "$W/heal" "$W/notfound"
# apt-get: its output and exit from files, its arguments recorded
cat > "$W/bin/apt-get" <<'STUB'
#!/bin/bash
echo "$*" > "$W/apt.args"
cat "$W/apt.out" 2> /dev/null
exit "$(cat "$W/apt.rc" 2> /dev/null || echo 0)"
STUB
# systemctl: the running and the enabled lists from files; is-active a state a unit (state/<unit>, else inactive),
# non-zero while any is not active - as systemd's
cat > "$W/bin/systemctl" <<'STUB'
#!/bin/bash
[ ! -e "$W/systemctl.fail" ] || { echo "Failed to connect to bus" >&2; exit 1; }
case "$1" in
  list-units) cat "$W/active" ;;
  list-unit-files) cat "$W/enabled" ;;
  show) if [ -e "$W/notfound/${*: -1}" ]; then echo not-found; else echo loaded; fi ;;
  is-active) shift; rc=0
    for u in "$@"; do s=$(cat "$W/state/$u" 2> /dev/null || echo inactive); [ -e "$W/is-active.short" ] || echo "$s"
      [ "$s" = active ] || rc=3; done
    exit $rc ;;
  *) exit 1 ;;
esac
STUB
cat > "$W/bin/findmnt" <<'STUB'
#!/bin/bash
m=${*: -1}
src=$(awk -F= -v m="$m" '$1 == m {print $2}' "$W/mounts")
[ -n "$src" ] || exit 1
echo "$src"
STUB
cat > "$W/bin/gluster" <<'STUB'
#!/bin/bash
case "$*" in
  "volume list") cat "$W/volumes" ;;
  "volume heal "*" info summary") v=$3
    [ -e "$W/heal/$v" ] || { echo "Volume $v does not exist" >&2; exit 1; }
    cat "$W/heal/$v" ;;
  *) exit 1 ;;
esac
STUB
cat > "$W/bin/patronictl" <<'STUB'
#!/bin/bash
[ "$*" = "-c $PATRONI_CONFIG list -f json" ] || { echo "unexpected: $*" >&2; exit 2; }
cat "$W/patroni.json"
STUB
cat > "$W/bin/ip" <<'STUB'
#!/bin/bash
[ "$*" = "-o -4 addr show to $VIP/32" ] || { echo "unexpected: $*" >&2; exit 2; }
cat "$W/ip.out" 2> /dev/null
STUB
chmod +x "$W/bin"/*
# Consul's autopilot health and Nexus's status: a local server, its answers from files (a process of its own)
cat > "$W/server.py" <<'SERVER'
import http.server, os, sys
W = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = {"/v1/operator/autopilot/health": "consul", "/nexus": "nexus"}.get(self.path)
        if not name:
            self.send_response(404); self.end_headers(); return
        status = int(open(os.path.join(W, name + ".status")).read())
        body = open(os.path.join(W, name + ".json"), "rb").read() if os.path.exists(os.path.join(W, name + ".json")) else b"{}"
        self.send_response(status); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port))
os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
"$PY" "$W/server.py" "$W" & echo $! > "$W/server.pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "pi-packages: the local server did not start"; exit 1; }
W=$W PORT=$(cat "$W/port") PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import json, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
W, PORT = os.environ["W"], os.environ["PORT"]
SCRIPT = "deploy/ansible/playbooks/scripts/pi-packages.py"
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def put(name, text):
    with open(os.path.join(W, name), "w") as f:
        f.write(text)
def gone(*names):
    for n in names:
        if os.path.exists(os.path.join(W, n)):
            os.remove(os.path.join(W, n))
ENV = {**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "W": W,
       "PATRONI_CONFIG": os.path.join(W, "patroni.yml"), "KEEPALIVED_NOTIFY_LIB": os.path.join(W, "notify_lib.sh"),
       "FSTAB": os.path.join(W, "fstab"), "CONSUL_HTTP_ADDR": f"http://127.0.0.1:{PORT}", "VIP": "192.168.11.5"}
def run(*args):
    r = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True, env=ENV, timeout=60)
    return r.returncode, r.stdout.strip()

# ── plan ──
APT = """Reading package lists...
Calculating upgrade...
The following NEW packages will be installed:
  linux-image-6.18.60+rpt-rpi-2712
The following packages will be upgraded:
  haproxy postgresql-17
2 upgraded, 1 newly installed, 0 to remove and {kept} not upgraded.
Inst haproxy [3.0.11-1+deb13u3] (3.0.11-1+deb13u4 Debian-Security:13/stable-security [arm64])
Inst postgresql-17 [17.11-0+deb13u1] (17.12-0+deb13u1 Debian-Security:13/stable-security [arm64]) []
Inst linux-image-6.18.60+rpt-rpi-2712 (1:6.18.60-1+rpt1 Raspberry Pi Foundation:stable [arm64])
Conf haproxy (3.0.11-1+deb13u4 Debian-Security:13/stable-security [arm64])
"""
put("apt.out", APT.format(kept=0)); gone("apt.rc")
rc, out = run("plan")
check("plan: every package and the summary", (rc, out.splitlines()), (0, [
    "haproxy 3.0.11-1+deb13u3 -> 3.0.11-1+deb13u4", "postgresql-17 17.11-0+deb13u1 -> 17.12-0+deb13u1",
    "linux-image-6.18.60+rpt-rpi-2712 new -> 1:6.18.60-1+rpt1", "PLAN 2 upgraded, 1 new, 0 kept back"]))
check("plan: simulated, as the playbook upgrades (held packages stay, nothing removed)",
      open(os.path.join(W, "apt.args")).read().split(), ["-s", "-q", "upgrade", "--with-new-pkgs"])
put("apt.out", APT.format(kept=3))
check("plan: what apt keeps back counted", run("plan")[1].splitlines()[-1], "PLAN 2 upgraded, 1 new, 3 kept back")
put("apt.out", "Calculating upgrade...\n0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.\n")
check("plan: nothing to do", run("plan"), (0, "PLAN 0 upgraded, 0 new, 0 kept back"))
put("apt.out", APT.replace("2 upgraded, 1 newly installed, 0 to remove", "2 upgraded, 1 newly installed, 1 to remove")
    .format(kept=0) + "Remv libfoo1 [1.0-1]\n")
rc, out = run("plan")
check("plan: a removal refused, named", (rc, out.startswith("REFUSED"), "libfoo1" in out), (1, True, True))
put("apt.out", APT.format(kept=0) + "Remv libfoo1 [1.0-1]\n")
check("plan: a Remv line refused even when the summary says none", run("plan")[0], 1)
put("apt.out", "Reading package lists...\nE: Could not get lock\n"); put("apt.rc", "100")
rc, out = run("plan")
check("plan: apt failing - not read, never a plan", (rc, out.startswith("NOT READ")), (1, True))
gone("apt.rc"); put("apt.out", "Reading package lists...\n")
check("plan: no summary - not read", run("plan")[1].startswith("NOT READ"), True)
put("apt.out", APT.replace("2 upgraded", "3 upgraded").format(kept=0))
rc, out = run("plan")
check("plan: its packages not the number its summary says - not read", (rc, out.startswith("NOT READ")), (1, True))

# ── services ──
put("active", "consul.service loaded active running Consul\nnexus.service loaded active running Nexus\n"
    "user@1000.service loaded active running User\nvault.service loaded active running Vault\n"
    "cloud-final.service loaded active exited Cloud\n")
put("enabled", "consul.service enabled enabled\nnexus.service enabled enabled\nvault.service enabled enabled\n"
    "cloud-final.service enabled enabled\nhaproxy.service enabled enabled\n")
put("notify_lib.sh", 'vip_present() { true; }\nSERVICES="\nnexus /mnt/data/nexus http://127.0.0.1:%s/nexus 180 10\n"\n'
    'for_each_service() { :; }\n' % PORT)
rc, out = run("services")
check("services: running and enabled, keepalived's own (nexus) aside, not the one not enabled (user@1000), not the one "
      "enabled but stopped (haproxy)", (rc, out.splitlines()),
      (0, ["cloud-final.service", "consul.service", "vault.service", "SERVICES 3"]))
os.rename(os.path.join(W, "notify_lib.sh"), os.path.join(W, "notify_lib.away"))
check("services: no keepalived on the host - none set aside", "nexus.service" in run("services")[1], True)
os.rename(os.path.join(W, "notify_lib.away"), os.path.join(W, "notify_lib.sh"))
good_lib = open(os.path.join(W, "notify_lib.sh")).read()
put("notify_lib.sh", 'SERVICES="\nnexus /mnt/data/nexus\n"\n')
check("services: a keepalived row not as its table holds them - not read", run("services")[1].startswith("NOT READ"), True)
put("notify_lib.sh", "exit 3\n")
check("services: keepalived's table unreadable - not read", run("services")[1].startswith("NOT READ"), True)
put("notify_lib.sh", good_lib)
put("systemctl.fail", "")
check("services: systemd unread - not read", run("services")[1].startswith("NOT READ"), True)
gone("systemctl.fail")
put("active", "")
check("services: none found - not read (never 'nothing to bring back')", run("services")[1].startswith("NOT READ"), True)

# ── back ──
for u in ("consul.service", "vault.service"):
    put(f"state/{u}", "active")
check("back: every one running", run("back", "consul.service", "vault.service"), (0, "BACK 2"))
put("state/vault.service", "activating")
check("back: one still starting - not yet, named", run("back", "consul.service", "vault.service"),
      (1, "NOT YET vault.service activating"))
put("is-active.short", "")
check("back: states not one a unit - not read", run("back", "consul.service")[1].startswith("NOT READ"), True)
gone("is-active.short")
check("back: no unit named - not read", run("back")[1].startswith("NOT READ"), True)

# ── gluster ──
BRICK = "Brick {b}\nStatus: {s}\nTotal Number of entries: {n}\nNumber of entries in heal pending: {n}\n\n"
def heal(v, bricks):
    put(f"heal/{v}", "".join(BRICK.format(b=b, s=s, n=n) for b, s, n in bricks))
put("fstab", "# a comment glusterfs\nUUID=x / ext4 defaults 0 1\nlocalhost:/forgejo-data /mnt/forgejo glusterfs defaults 0 0\n"
    "localhost:/nexus-data /mnt/data glusterfs defaults 0 0\n")
put("mounts", "/mnt/forgejo=localhost:/forgejo-data\n/mnt/data=localhost:/nexus-data\n")
put("volumes", "forgejo-data\nnexus-data\n")
OK3 = [("192.168.11.4:/b", "Connected", 0), ("192.168.11.6:/b", "Connected", 0), ("192.168.11.2:/arbiter", "Connected", 0)]
heal("forgejo-data", OK3); heal("nexus-data", OK3)
check("gluster: mounted from fstab's volumes, every brick connected, nothing to heal", run("gluster"),
      (0, "HEALED forgejo-data nexus-data (2 mounted)"))
put("mounts", "/mnt/forgejo=localhost:/forgejo-data\n/mnt/data=localhost:/forgejo-data\n")
rc, out = run("gluster")
check("gluster: a volume mounted from another - named", (rc, "/mnt/data mounted from localhost:/forgejo-data" in out),
      (1, True))
put("mounts", "/mnt/forgejo=localhost:/forgejo-data\n")
rc, out = run("gluster")
check("gluster: one not mounted - named", (rc, "/mnt/data mounted from nothing" in out), (1, True))
put("mounts", "/mnt/forgejo=localhost:/forgejo-data\n/mnt/data=localhost:/nexus-data\n")
heal("nexus-data", OK3[:1] + [("192.168.11.6:/b", "Transport endpoint is not connected", "-")] + OK3[2:])
rc, out = run("gluster")
check("gluster: a brick away (the Pi still booting) - not healed, named", (rc, "192.168.11.6:/b Transport" in out),
      (1, True))
heal("nexus-data", OK3[:1] + [("192.168.11.6:/b", "Transport endpoint is not connected", 0)] + OK3[2:])
rc, out = run("gluster")
check("gluster: a brick not connected though its count reads 0 - not healed (the status judged, not the count alone)",
      (rc, "not connected" in out), (1, True))
heal("nexus-data", OK3[:1] + [("192.168.11.6:/b", "Connected", 3)] + OK3[2:])
rc, out = run("gluster")
check("gluster: entries to heal - not healed", (rc, "3 to heal" in out), (1, True))
heal("nexus-data", OK3)
os.remove(os.path.join(W, "heal", "nexus-data"))
check("gluster: a volume's heal unread - not read", run("gluster")[1].startswith("NOT READ"), True)
put("heal/nexus-data", "Launching heal operation\n")
check("gluster: a heal answer without bricks - not read", run("gluster")[1].startswith("NOT READ"), True)
heal("nexus-data", OK3); put("volumes", "")
check("gluster: no volume - not read", run("gluster")[1].startswith("NOT READ"), True)
put("volumes", "forgejo-data\nnexus-data\n")

# ── patroni ──
def members(*ms):
    put("patroni.json", json.dumps([dict(zip(("Member", "Role", "State", "Replay Lag"), m)) for m in ms]))
put("patroni.yml", "scope: pg\n")
members(("pi1", "Leader", "running", None), ("pi2", "Replica", "streaming", 0))
check("patroni: a leader, its replica streaming", run("patroni"), (0, "HEALTHY pi1 Leader running, pi2 Replica streaming"))
check("patroni: the leader the one named", run("patroni", "--leader", "pi1")[0], 0)
rc, out = run("patroni", "--leader", "pi2")
check("patroni: another leader than the one named - not healthy, said", (rc, "the leader wanted: pi2" in out), (1, True))
members(("pi1", "Leader", "running", None), ("pi2", "Replica", "streaming", 5))
check("patroni: a replica lagging", run("patroni")[0], 1)
members(("pi1", "Leader", "running", None), ("pi2", "Replica", "starting", 0))
check("patroni: a replica not streaming (its Postgres starting)", run("patroni")[0], 1)
members(("pi1", "Leader", "running", None))
check("patroni: no replica", run("patroni")[0], 1)
members(("pi1", "Replica", "streaming", 0), ("pi2", "Replica", "streaming", 0))
check("patroni: no leader", run("patroni")[0], 1)
put("patroni.json", "not json")
check("patroni: patronictl's answer not JSON - not read", run("patroni")[1].startswith("NOT READ"), True)
check("patroni: an argument it does not take - not read", run("patroni", "--candidate", "pi2")[1].startswith("NOT READ"), True)

# ── consul ──
def server(n, healthy=True, voter=True):
    return {"Name": n, "Healthy": healthy, "Voter": voter}
def autopilot(status, healthy, tolerance, servers):
    put("consul.status", str(status))
    put("consul.json", json.dumps({"Healthy": healthy, "FailureTolerance": tolerance, "Servers": servers}))
THREE = [server("pi1"), server("pi2"), server("target")]
autopilot(200, True, 1, THREE)
check("consul: three healthy voters, one loss tolerated", run("consul"),
      (0, "QUORUM HOLDS pi1 healthy, pi2 healthy, target healthy"))
autopilot(429, False, 0, [server("pi1"), server("pi2", False), server("target")])
rc, out = run("consul")
check("consul: a server away (autopilot's 429) - no quorum to spare, named", (rc, "pi2 unhealthy" in out), (1, True))
autopilot(200, True, 0, THREE)
check("consul: healthy but no loss tolerated", run("consul")[0], 1)
autopilot(200, True, 1, THREE[:2])
check("consul: two servers only", run("consul")[0], 1)
autopilot(200, True, 1, [server("pi1"), server("pi2", voter=False), server("target")])
check("consul: a non-voter", run("consul")[0], 1)
put("consul.status", "200"); put("consul.json", "<html>")
check("consul: an answer not its JSON - not read", run("consul")[1].startswith("NOT READ"), True)
ENV["CONSUL_HTTP_ADDR"] = "http://127.0.0.1:1"
check("consul: unreachable - not read", run("consul")[1].startswith("NOT READ"), True)
ENV["CONSUL_HTTP_ADDR"] = f"http://127.0.0.1:{PORT}"

# ── vip-units, serving ──
check("vip-units: keepalived's services installed here", run("vip-units"), (0, "nexus.service\nVIP UNITS 1"))
put("notfound/nexus.service", "")
check("vip-units: one its table names but this Pi lacks (the Vagrant copy's Nexus) - skipped, as keepalived skips it",
      run("vip-units"), (0, "VIP UNITS 0"))
gone("notfound/nexus.service")
os.rename(os.path.join(W, "notify_lib.sh"), os.path.join(W, "notify_lib.away"))
check("vip-units: no keepalived on the host - none", run("vip-units"), (0, "VIP UNITS 0"))
os.rename(os.path.join(W, "notify_lib.away"), os.path.join(W, "notify_lib.sh"))
put("ip.out", "2: eth0    inet 192.168.11.5/24 scope global secondary eth0\n")
put("state/nexus.service", "active"); put("nexus.status", "200")
check("serving: the VIP here, Nexus running and answering", run("serving", "192.168.11.5", "nexus.service"),
      (0, "SERVING 192.168.11.5 nexus.service"))
check("serving: no unit to serve (the Pi handing over had none) - the VIP alone", run("serving", "192.168.11.5"),
      (0, "SERVING 192.168.11.5 (no keepalived service to serve)"))
put("notfound/nexus.service", "")
rc, out = run("serving", "192.168.11.5", "nexus.service")
check("serving: a unit the Pi handing over had, not installed here - not serving (never skipped)",
      (rc, "nexus.service not installed" in out), (1, True))
gone("notfound/nexus.service")
check("serving: a unit keepalived's table does not name - not read",
      run("serving", "192.168.11.5", "caddy.service")[1].startswith("NOT READ"), True)
put("ip.out", "")
check("serving: the VIP not here", run("serving", "192.168.11.5", "nexus.service"), (1, "NO VIP 192.168.11.5 here"))
put("ip.out", "2: eth0    inet 192.168.11.50/24 scope global eth0\n")
check("serving: an address the VIP is the start of is not it", run("serving", "192.168.11.5")[0], 1)
put("ip.out", "2: eth0    inet 192.168.11.5/24 scope global secondary eth0\n")
put("state/nexus.service", "activating")
rc, out = run("serving", "192.168.11.5", "nexus.service")
check("serving: Nexus still starting - not serving, named", (rc, "nexus.service activating" in out), (1, True))
put("state/nexus.service", "active"); put("nexus.status", "503")
rc, out = run("serving", "192.168.11.5", "nexus.service")
check("serving: Nexus running, its status not answering yet - not serving", (rc, "not answering" in out), (1, True))
put("nexus.status", "200")

# ── the playbook and one Pi's turn, as Ansible evaluates them ──
book = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-pi-packages.yml"))
check("plays: both Pis checked and recorded, the non-holder's turn, the holder's, both after",
      [p["hosts"] for p in book], ["pis", "pi_packages_turn_1", "pi_packages_turn_2", "pis"])
order = next(t for t in book[0]["tasks"] if "ansible.builtin.group_by" in t)["ansible.builtin.group_by"]["key"]
check("the order: the VIP's holder last, the other first",
      [render(order, inventory_hostname=h, pi_vip_holder="pi1") for h in ("pi1", "pi2")],
      ["pi_packages_turn_2", "pi_packages_turn_1"])
check("every play stops both Pis on a failure (any_errors_fatal)", [p.get("any_errors_fatal") for p in book], [True] * 4)
for p in book[1:3]:
    check(f"{p['hosts']}: the turn's tasks", [t.get("ansible.builtin.include_tasks") for t in p["tasks"]],
          ["tasks/pi-packages-node.yml"])
node = yaml.safe_load(open("deploy/ansible/playbooks/tasks/pi-packages-node.yml"))
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
every = list(walk(node))
def at(pred, what):
    i = next((i for i, t in enumerate(every) if pred(t)), None)
    if i is None:
        check(f"the turn has {what}", False, True)
    return i
end = at(lambda t: (t.get("ansible.builtin.meta") == "end_host"), "an end for a Pi with nothing to upgrade")
switch = at(lambda t: "switchover" in str(t.get("ansible.builtin.command")), "Patroni's switchover")
vault = at(lambda t: t.get("ansible.builtin.include_tasks") == "vault-step-down.yml", "Vault's handover")
stop = at(lambda t: (t.get("ansible.builtin.systemd_service") or {}).get("state") == "stopped", "keepalived stopped")
took = at(lambda t: "serving" in str(t.get("ansible.builtin.script")), "the other Pi serving the VIP")
apt = at(lambda t: isinstance(t.get("ansible.builtin.command"), dict) and "upgrade" in t["ansible.builtin.command"]["argv"],
         "apt's upgrade")
leader = at(lambda t: t.get("ansible.builtin.include_tasks") == "consul-leader-off.yml", "Consul's handover")
tier0 = at(lambda t: t.get("ansible.builtin.include_tasks") == "tier0-backup-stopped.yml", "the tier-0 backup kept off")
boot = at(lambda t: "ansible.builtin.reboot" in t, "the reboot")
check("the turn in order: nothing to do ends it first; the switchover, Vault's handover, the VIP handed over and taken, "
      "then apt's upgrade, Consul's handover, the tier-0 backup kept off, the reboot at once",
      [end < switch < vault < stop < took < apt < leader < tier0, tier0 + 1 == boot], [True, True])
check("the tier-0 lock's read the last task of its file (the reboot follows it at once)",
      yaml.safe_load(open("deploy/ansible/playbooks/tasks/tier0-backup-stopped.yml"))[-1]["name"],
      "No tier-0 backup holding its Consul lock")
check("nothing to upgrade ends the Pi's turn - only that (a new package is something)",
      [condition(every[end]["when"], pi_packages_done=d) for d in
       ("0 upgraded, 0 new, 0 kept back", "0 upgraded, 0 new, 2 kept back", "0 upgraded, 1 new, 0 kept back",
        "10 upgraded, 0 new, 0 kept back")], [True, True, False, False])
check("the switchover only where Patroni leads",
      [condition(every[switch]["when"], _patroni_here={"json": {"role": r}}) for r in ("primary", "master", "replica")],
      [True, True, False])
check("the other Pi must serve what this Pi had - its own units, as the first play recorded them",
      render(every[took]["ansible.builtin.script"]["cmd"], pi_packages="P", keepalived_vip="V",
             pi_packages_vip_units=["nexus.service"]).split(), ["P", "serving", "V", "nexus.service"])
final = next(t for t in book[3]["tasks"] if "serving" in str(t.get("ansible.builtin.script")))
check("after the run: the VIP's Pi serves what either Pi had",
      render(final["ansible.builtin.script"]["cmd"], pi_packages="P", keepalived_vip="V", ansible_play_hosts=["pi1", "pi2"],
             hostvars={"pi1": {"pi_packages_vip_units": ["nexus.service"]}, "pi2": {"pi_packages_vip_units": []}}).split(),
      ["P", "serving", "V", "nexus.service"])
check("keepalived stopped only on the VIP's holder",
      [condition(every[stop]["when"], pi_vip_holder="pi1", inventory_hostname=h) for h in ("pi1", "pi2")], [True, False])
blk = next(t for t in node if "block" in t and every[boot] in list(walk(t["block"])))
start = next((t for t in blk.get("always") or [] if (t.get("ansible.builtin.systemd_service") or {}).get("name")
              == "keepalived"), None)
check("keepalived started again in the block's always - on the Pi whose VIP this run handed over, whatever happened",
      (start is not None and start["ansible.builtin.systemd_service"]["state"] == "started",
       condition((start or {}).get("when", "false"), pi_vip_holder="pi1", inventory_hostname="pi1"),
       condition((start or {}).get("when", "true"), pi_vip_holder="pi1", inventory_hostname="pi2")),
      (True, True, False))
took_when = every[took]["when"]
check("the other Pi's VIP waited for where this Pi held it (not in a preview, which stopped nothing)",
      [condition(took_when, pi_vip_holder="pi1", inventory_hostname=h, ansible_check_mode=c)
       for h, c in (("pi1", False), ("pi2", False), ("pi1", True))], [True, False, False])
led = next(t for t in every if "patroni --leader" in str(t.get("ansible.builtin.script")))
check("the new leader waited for where Patroni led here (not in a preview)",
      [condition(led["when"], _patroni_here={"json": {"role": r}}, ansible_check_mode=c)
       for r, c in (("primary", False), ("replica", False), ("primary", True))], [True, False, False])
check("the block holds the keepalived stop and apt's upgrade (a failure there still starts keepalived again)",
      all(every[i] in list(walk(blk["block"])) for i in (stop, apt, boot)), True)
print("pi-packages: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
