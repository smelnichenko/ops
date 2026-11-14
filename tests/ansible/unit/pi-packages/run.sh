#!/bin/bash
# upgrade-pi-packages.yml: what it reads on a Pi (playbooks/scripts/pi-packages.py) and how its plays and one Pi's turn
# (tasks/pi-packages-node.yml) hold their tasks. The script against stubs answering as apt 3.0, dpkg, systemd 257,
# GlusterFS 11, Patroni 4.1, rpi-eeprom-update and Consul 1.20 do (read on the Pis, 2026-11-14), Consul's autopilot,
# Nexus's status and Forgejo's healthz from a local HTTP server: every verdict, its refusal and its "not read" - an
# answer not read is never a yes. The plays and the turn as Ansible evaluates them (its templar): the order (the VIP
# holder last, the second turn left for a later run on request), the refusals that change nothing first (a backup
# window, a tier-0 backup running, a mirror away, no room), the other Pi ready before anything is handed over, Nexus
# stopped before keepalived, a VIP not taken handed back, the reboot owed marked across a failure, every wait's until
# and retries, every read's check mode, the includes unconditional, apt's command the one its plan simulated, and
# keepalived and its timers started again whatever happens.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'kill "$(cat "$W/server.pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/state" "$W/heal" "$W/notfound" "$W/cond" "$W/modules" "$W/boot" "$W/tmp"
# apt-get: its output and exit from files, its arguments recorded (every call in apt.calls); an update answers from
# apt-update.out/.rc and leaves a list file in the directory it was given (Dir::State::Lists=)
cat > "$W/bin/apt-get" <<'STUB'
#!/bin/bash
echo "$*" >> "$W/apt.calls"
case " $* " in
  *" update "*) d=$(printf '%s\n' "$@" | sed -n 's/^Dir::State::Lists=//p')
    [ -z "$d" ] || touch "$d/deb.debian.org_dists_trixie_InRelease"
    cat "$W/apt-update.out" 2> /dev/null; exit "$(cat "$W/apt-update.rc" 2> /dev/null || echo 0)" ;;
esac
echo "$*" > "$W/apt.args"
cat "$W/apt.out" 2> /dev/null
exit "$(cat "$W/apt.rc" 2> /dev/null || echo 0)"
STUB
cat > "$W/bin/dpkg" <<'STUB'
#!/bin/bash
[ "$*" = "--audit" ] || exit 2
cat "$W/dpkg-audit.out" 2> /dev/null; exit 0
STUB
# systemctl: the running and the enabled lists from files; is-active a state a unit (state/<unit>, else inactive),
# non-zero while any is not active - as systemd's
cat > "$W/bin/systemctl" <<'STUB'
#!/bin/bash
[ ! -e "$W/systemctl.fail" ] || { echo "Failed to connect to bus" >&2; exit 1; }
case "$1" in
  list-units) cat "$W/active" ;;
  list-unit-files) cat "$W/enabled" ;;
  show) u=${*: -1}
    case " $* " in
      *" --value "*) if [ -e "$W/notfound/$u" ]; then echo not-found; else echo loaded; fi ;;
      *) cat "$W/cond/$u" 2> /dev/null || printf 'ConditionResult=yes\nConditionTimestampMonotonic=0\n' ;;
    esac ;;
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
[ ! -e "$W/slow" ] || sleep 5
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
cat > "$W/check_services.sh" <<'STUB'
#!/bin/bash
exit "$(cat "$W/check.rc" 2> /dev/null || echo 0)"
STUB
cat > "$W/rpi-eeprom-update" <<'STUB'
#!/bin/bash
echo "$*" >> "$W/eeprom.calls"
cat "$W/eeprom.out"
STUB
chmod +x "$W/bin"/* "$W/check_services.sh" "$W/rpi-eeprom-update"
# Consul's autopilot health and Nexus's status: a local server, its answers from files (a process of its own)
cat > "$W/server.py" <<'SERVER'
import http.server, os, sys
W = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = {"/v1/operator/autopilot/health": "consul", "/nexus": "nexus", "/forgejo": "forgejo"}.get(self.path)
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
       "FSTAB": os.path.join(W, "fstab"), "CONSUL_HTTP_ADDR": f"http://127.0.0.1:{PORT}", "VIP": "192.168.11.5",
       "KEEPALIVED_CHECK": os.path.join(W, "check_services.sh"), "FORGEJO_HEALTH": f"http://127.0.0.1:{PORT}/forgejo",
       "MODULES_DIR": os.path.join(W, "modules"), "KERNEL_RELEASE": "6.18.50+rpt-rpi-2712",
       "BOOT_FIRMWARE": os.path.join(W, "boot"), "RPI_EEPROM_UPDATE": os.path.join(W, "rpi-eeprom-update"),
       "PI_PACKAGES_LISTS_PARENT": os.path.join(W, "tmp")}
def run(*args, env=None):
    r = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True, env=env or ENV, timeout=60)
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
put("apt.out", APT.replace("2 upgraded, 1 newly installed", "3 upgraded, 0 newly installed").format(kept=0))
check("plan: a package new to the Pi where its summary says none new - not read", run("plan")[1].startswith("NOT READ"), True)
put("apt.out", APT.format(kept=0)); put("apt.rc", "100")
check("plan: apt exiting non-zero though its summary printed - not read (its exit judged)",
      run("plan")[1].startswith("NOT READ"), True)
gone("apt.rc")
put("apt.out", APT.format(kept=2).replace("The following packages will be upgraded:",
    "The following packages have been kept back:\n  libcamera0.7 rpicam-apps-core\nThe following packages will be upgraded:"))
check("plan: what apt keeps back named", [x for x in run("plan")[1].splitlines() if x.startswith(("KEPT", "PLAN"))],
      ["KEPT BACK libcamera0.7 rpicam-apps-core", "PLAN 2 upgraded, 1 new, 2 kept back"])
put("apt.out", APT.format(kept=0))
put("dpkg-audit.out", "The following packages are only half configured, probably due to problems configuring them:\n"
    " libfoo1  a library\n")
rc, out = run("plan")
check("plan: dpkg's audit not clean (a package half-installed) - refused, said", (rc, out.startswith("REFUSED: dpkg")),
      (1, True))
gone("dpkg-audit.out", "apt.calls")
rc, out = run("plan", "--fresh")
calls = open(os.path.join(W, "apt.calls")).read().splitlines()
lists = [a.split("=", 1)[1] for a in calls[0].split() if a.startswith("Dir::State::Lists=")]
check("plan --fresh: the lists read into a directory of its own, apt's binary caches not written, then simulated there",
      (rc, len(calls), "update" in calls[0].split(), "Dir::Cache::pkgcache=" in calls[0].split(),
       "Dir::Cache::srcpkgcache=" in calls[0].split(), bool(lists) and lists[0].startswith(os.path.join(W, "tmp")),
       calls[1].split()[:2], f"Dir::State::Lists={lists[0] if lists else '?'}" in calls[1].split(),
       calls[1].split()[-2:]),
      (0, 2, True, True, True, True, ["-s", "-q"], True, ["upgrade", "--with-new-pkgs"]))
check("plan --fresh: its directory gone after", os.listdir(os.path.join(W, "tmp")), [])
put("apt-update.rc", "100")
rc, out = run("plan", "--fresh")
check("plan --fresh: the lists not read - not read, its directory gone all the same",
      (out.startswith("NOT READ"), os.listdir(os.path.join(W, "tmp"))), (True, []))
gone("apt-update.rc")
check("plan: an argument it does not take - not read", run("plan", "--stale")[1].startswith("NOT READ"), True)

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
put("active", "getty@tty1.service loaded active running Getty\nfoo@bar.service loaded active running Foo\n"
    "consul.service loaded active running Consul\n")
put("enabled", "getty@.service enabled enabled\nconsul.service enabled enabled\n")
check("services: an instance by its template's enablement (getty@tty1 by getty@.service) - one of a template not enabled "
      "aside", run("services")[1].splitlines(), ["consul.service", "getty@tty1.service", "SERVICES 2"])

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
put("state/vault.service", "inactive")
put("cond/vault.service", "ConditionResult=no\nConditionTimestampMonotonic=4242\n")
check("back: one its own start condition skipped at this boot (a first-boot unit) - back, said",
      run("back", "consul.service", "vault.service"), (0, "BACK 2 (vault.service skipped by its start condition)"))
put("cond/vault.service", "ConditionResult=no\nConditionTimestampMonotonic=0\n")
check("back: one not tried yet (no condition checked) - not yet", run("back", "consul.service", "vault.service"),
      (1, "NOT YET vault.service inactive"))
gone("cond/vault.service"); put("state/vault.service", "active")

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
put("fstab", open(os.path.join(W, "fstab")).read() + "#localhost:/old-data /mnt/old glusterfs defaults 0 0\n")
check("gluster: a commented-out glusterfs line not judged", run("gluster"), (0, "HEALED forgejo-data nexus-data (2 mounted)"))
PATH_NO_TOOLS = {**ENV, "PATH": os.path.join(W, "tmp")}
check("gluster: its command missing - not read", run("gluster", env=PATH_NO_TOOLS)[1].startswith("NOT READ"), True)
put("slow", "")
rc, out = run("gluster", env={**ENV, "PI_PACKAGES_TIMEOUT": "1"})
check("gluster: its command not answering in time - not read, said", (rc, "did not answer" in out), (1, True))
gone("slow")

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
members(("pi1", "Leader", "stopped", None), ("pi2", "Replica", "streaming", 0))
check("patroni: the leader not running (stopped)", run("patroni")[0], 1)
members(("pi1", "Leader", "running", None), ("pi2", "Replica", "streaming", 0))
rc, out = run("patroni", "--candidate", "pi2")
check("patroni: an argument it does not take - not read, named (its JSON healthy)", (rc, "--candidate" in out), (1, True))
put("patroni.json", "not json")
check("patroni: patronictl's answer not JSON - not read", run("patroni")[1].startswith("NOT READ"), True)

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
autopilot(200, True, 1, [server("pi1"), server("pi2", False), server("target")])
check("consul: a server unhealthy though the whole reads healthy", run("consul")[0], 1)
autopilot(200, False, 1, THREE)
check("consul: the whole unhealthy though every server reads healthy", run("consul")[0], 1)
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
# two of keepalived's services: the second judged too
put("notify_lib.sh", 'SERVICES="\nnexus /mnt/data/nexus http://127.0.0.1:%s/nexus 180 10\n'
    'other /mnt/data/other http://127.0.0.1:%s/nexus 60 10\n"\n' % (PORT, PORT))
put("state/other.service", "failed")
rc, out = run("serving", "192.168.11.5", "nexus.service", "other.service")
check("serving: the second unit down - not serving, named", (rc, "other.service failed" in out), (1, True))
put("state/other.service", "active")
check("serving: both running and answering", run("serving", "192.168.11.5", "nexus.service", "other.service")[0], 0)
put("notify_lib.sh", good_lib)

# ── standby ──
put("state/keepalived", "active"); put("check.rc", "0"); put("forgejo.status", "200")
FORGEJO_OK = {"status": "pass", "checks": {"cache:ping": [{"status": "pass"}], "database:ping": [{"status": "pass"}]}}
put("forgejo.json", json.dumps(FORGEJO_OK))
check("standby: keepalived running, its check passing, Forgejo's database reached", run("standby"), (0, "STANDBY"))
put("state/keepalived", "inactive")
rc, out = run("standby")
check("standby: keepalived not running - not standby, named", (rc, "keepalived inactive" in out), (1, True))
put("state/keepalived", "active"); put("check.rc", "1")
rc, out = run("standby")
check("standby: keepalived's own check failing - not standby", (rc, "check_services.sh fails" in out), (1, True))
put("check.rc", "0")
check("standby: no keepalived check on the host - not standby",
      run("standby", env={**ENV, "KEEPALIVED_CHECK": os.path.join(W, "none.sh")})[0], 1)
put("forgejo.json", json.dumps({**FORGEJO_OK, "checks": {"database:ping": [{"status": "fail"}]}}))
rc, out = run("standby")
check("standby: Forgejo up, its database not reached - not standby", (rc, "database ['fail']" in out), (1, True))
put("forgejo.json", json.dumps({"status": "pass", "checks": {}}))
check("standby: Forgejo's database not checked at all - not standby", run("standby")[0], 1)
put("forgejo.json", json.dumps(FORGEJO_OK)); put("forgejo.status", "503")
check("standby: Forgejo's healthz answering 503 - not standby", run("standby")[0], 1)
put("forgejo.status", "200")
check("standby: Forgejo unreachable - not standby",
      run("standby", env={**ENV, "FORGEJO_HEALTH": "http://127.0.0.1:1/x"})[0], 1)

# ── idle ──
put("state/nexus.service", "inactive")
check("idle: not running", run("idle", "nexus.service"), (0, "IDLE nexus.service"))
put("state/nexus.service", "failed")
check("idle: failed is not running either", run("idle", "nexus.service")[0], 0)
for st in ("active", "activating", "deactivating"):
    put("state/nexus.service", st)
    check(f"idle: {st} - running, named", run("idle", "nexus.service"), (1, f"RUNNING nexus.service {st}"))
check("idle: no unit (a Pi without keepalived's own) - idle", run("idle"), (0, "IDLE (no keepalived service of its own)"))
put("is-active.short", "")
check("idle: states not one a unit - not read", run("idle", "nexus.service")[1].startswith("NOT READ"), True)
gone("is-active.short"); put("state/nexus.service", "active")

# ── kernel ──
for d in ("6.12.75+rpt-rpi-2712", "6.12.75+rpt-rpi-v8", "6.18.50+rpt-rpi-2712", "6.18.60+rpt-rpi-v8"):
    os.makedirs(os.path.join(W, "modules", d), exist_ok=True)
check("kernel: the newest of its flavour running (a newer of another flavour aside)", run("kernel"),
      (0, "BOOTED 6.18.50+rpt-rpi-2712"))
os.makedirs(os.path.join(W, "modules", "6.18.60+rpt-rpi-2712"))
check("kernel: a newer of its flavour installed - not booted", run("kernel"),
      (1, "NOT BOOTED 6.18.60+rpt-rpi-2712: running 6.18.50+rpt-rpi-2712"))
os.makedirs(os.path.join(W, "modules", "6.18.100+rpt-rpi-2712"))
check("kernel: versions compared as numbers (6.18.100 after 6.18.60)", run("kernel")[1],
      "NOT BOOTED 6.18.100+rpt-rpi-2712: running 6.18.50+rpt-rpi-2712")
check("kernel: the running one not installed - not read",
      run("kernel", env={**ENV, "KERNEL_RELEASE": "6.1.0+rpt-rpi-2712"})[1].startswith("NOT READ"), True)

# ── boot ──
check("boot: no /boot/firmware (the Vagrant copy)", run("boot", env={**ENV, "BOOT_FIRMWARE": os.path.join(W, "nope")}),
      (0, "BOOT FILES none"))
put("boot/config.txt", "arm_64bit=1\n")
rc, out = run("boot", "--min-free", "1")
import hashlib
check("boot: config.txt hashed, cmdline.txt absent said, the room shown",
      (rc, out.splitlines()[0], out.splitlines()[1].startswith("FREE ")),
      (0, "BOOT FILES config.txt=" + hashlib.sha256(b"arm_64bit=1\n").hexdigest() + " cmdline.txt=absent", True))
rc, out = run("boot", "--min-free", "999999999")
check("boot: less room than asked - refused", (rc, "REFUSED" in out), (1, True))
check("boot: an argument it does not take - not read", run("boot", "--min-free")[1].startswith("NOT READ"), True)

# ── bootloader ──
check("bootloader: no rpi-eeprom-update (the Vagrant copy)",
      run("bootloader", "check", env={**ENV, "RPI_EEPROM_UPDATE": os.path.join(W, "nope")}), (0, "NO BOOTLOADER UPDATER"))
put("eeprom.out", "BOOTLOADER: up to date\n   CURRENT: Fri Sep 25\n    LATEST: Fri Sep 25\n")
check("bootloader check: up to date", run("bootloader", "check"), (0, "BOOTLOADER UP TO DATE"))
put("eeprom.out", "*** UPDATE AVAILABLE ***\nBOOTLOADER: update available\n")
check("bootloader check: an update not flashed - not up to date", run("bootloader", "check")[0], 1)
gone("eeprom.calls"); put("eeprom.out", "EEPROM updates pending. Please reboot to apply the update.\n")
rc, out = run("bootloader", "stage")
check("bootloader stage: rpi-eeprom-update -a", (rc, open(os.path.join(W, "eeprom.calls")).read().split()), (0, ["-a"]))
check("bootloader: an argument it does not take - not read", run("bootloader", "flash")[1].startswith("NOT READ"), True)
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
check("every play stops both Pis on a failure (any_errors_fatal)", [p.get("any_errors_fatal") for p in book], [True] * 4)
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
def script(t):
    v = t.get("ansible.builtin.script")
    return v["cmd"] if isinstance(v, dict) else (v or "")
def verb(t):
    """The pi-packages.py verb a task runs, rendered with the script's path P."""
    c = script(t)
    return render(c, pi_packages="P", playbook_dir="PB", keepalived_vip="V", pi_packages_vip_units=[],
                  ansible_check_mode=False, _other_pi="O", hostvars={"O": {"pi_packages_vip_units": [],
                  "pi_packages_services": []}}, pi_packages_services=[], ansible_play_hosts=[]).split()[1:2] if \
        c.startswith("{{ pi_packages }}") else []
first = book[0]["tasks"]
def find(tasks, pred, what):
    t = next((x for x in walk(tasks) if pred(x)), None)
    check(f"present: {what}", t is not None, True)
    return t or {}
# the first play: every check before anything changes, each a read in a preview too
for v_ in ("patroni", "consul", "gluster", "services", "vip-units"):
    t = find(first, lambda x, v_=v_: verb(x) == [v_], f"the first play's {v_}")
    check(f"the first play's {v_}: a read in a preview too", t.get("check_mode"), False)
pause = find(first, lambda x: script(x).endswith("patroni-pause.py check"), "the first play's not-paused check")
check("the first play's not-paused check: a read in a preview too", pause.get("check_mode"), False)
vault1 = find(first, lambda x: "ansible.builtin.uri" in x and "sys/health" in x["ansible.builtin.uri"]["url"],
              "the first play's Vault unsealed")
check("the first play's Vault: unsealed only (200, 429)", vault1.get("ansible.builtin.uri", {}).get("status_code"), [200, 429])
two = find(first, lambda x: (x.get("name") or "").startswith("Both Pis in the run"), "both Pis in the run")
check("both Pis in the run: both, and only both",
      [condition(two["ansible.builtin.assert"]["that"], ansible_play_hosts=h, groups={"pis": ["pi1", "pi2"]})
       for h in (["pi1", "pi2"], ["pi2", "pi1"], ["pi1"], ["pi1", "pi2", "pi3"])], [True, True, False, False])
win = find(first, lambda x: (x.get("name") or "").startswith("Not in a backup window"), "the backup window refusal")
check("the backup windows refused (UTC 01:50-04:00, 05:20-05:50), their edges in",
      [condition(win["ansible.builtin.assert"]["that"], _now=n) for n in
       ("01:49", "01:50", "03:00", "04:00", "04:01", "05:19", "05:20", "05:50", "05:51", "12:00")],
      [True, False, False, False, True, True, False, False, True, True])
check("the backup windows overridable (-e pi_packages_quiet_windows)",
      condition(win["ansible.builtin.assert"]["that"], _now="03:00", pi_packages_quiet_windows=[]), True)
order = find(first, lambda x: "ansible.builtin.group_by" in x, "the order")["ansible.builtin.group_by"]["key"]
check("the order: the VIP's holder last, the other first",
      [render(order, inventory_hostname=h, pi_vip_holder="pi1") for h in ("pi1", "pi2")],
      ["pi_packages_turn_2", "pi_packages_turn_1"])
rec = find(first, lambda x: "pi_packages_services" in (x.get("ansible.builtin.set_fact") or {}), "the services recorded")
sf = rec["ansible.builtin.set_fact"]
SERV = {"stdout_lines": ["consul.service\r", "vault.service", "SERVICES 2"]}
check("the services recorded from the read (its count line aside) - no reboot owed",
      (render(sf["pi_packages_services"], _services=SERV, _owed_mark={"stat": {"exists": False}}),
       render(sf["pi_packages_reboot_owed"], _owed_mark={"stat": {"exists": False}})),
      (["consul.service", "vault.service"], False))
import base64
OWED = {"content": base64.b64encode(json.dumps({"services": ["consul.service", "keepalived.service"]}).encode()).decode()}
check("a reboot owed: its Pi judged by the services that run recorded, not by what runs now",
      (render(sf["pi_packages_services"], _services=SERV, _owed_mark={"stat": {"exists": True}}, _owed_raw=OWED),
       render(sf["pi_packages_reboot_owed"], _owed_mark={"stat": {"exists": True}})),
      (["consul.service", "keepalived.service"], True))
units = find(first, lambda x: "pi_packages_vip_units" in (x.get("ansible.builtin.set_fact") or {}), "the keepalived units recorded")
check("the keepalived units recorded from the read",
      render(units["ansible.builtin.set_fact"]["pi_packages_vip_units"],
             _vip_units={"stdout_lines": ["nexus.service\r", "VIP UNITS 1"]}), ["nexus.service"])
owed_path = render(find(first, lambda x: "pi_packages_owed_path" in (x.get("ansible.builtin.set_fact") or {}),
                        "where an owed reboot is marked")["ansible.builtin.set_fact"]["pi_packages_owed_path"])
check("the owed reboot's mark kept across reboots (not /run, not /tmp)", owed_path.startswith("/var/lib/"), True)
for p in book[1:3]:
    check(f"{p['hosts']}: the turn's tasks", [t.get("ansible.builtin.include_tasks") for t in p["tasks"]][-1:],
          ["tasks/pi-packages-node.yml"])
later = next(t for t in book[2]["tasks"] if t.get("ansible.builtin.meta") == "end_play")
check("pi_packages_turns=1 leaves the second Pi for a later run; by default both",
      [condition(later["when"], **v) for v in ({"pi_packages_turns": 1}, {"pi_packages_turns": "1"}, {"pi_packages_turns": 2},
                                              {})], [True, True, False, False])

# one Pi's turn
node = yaml.safe_load(open("deploy/ansible/playbooks/tasks/pi-packages-node.yml"))
every = list(walk(node))
def at(pred, what):
    i = next((i for i, t in enumerate(every) if pred(t)), None)
    check(f"the turn has {what}", i is not None, True)
    return i if i is not None else -1
def name(prefix):
    return lambda t: (t.get("name") or "").startswith(prefix)
def inc(f):
    return lambda t: t.get("ansible.builtin.include_tasks") == f
def argv(t):
    c = t.get("ansible.builtin.command")
    return c.get("argv", []) if isinstance(c, dict) else []
I = {
    "update": at(lambda t: (t.get("ansible.builtin.apt") or {}).get("update_cache") is True, "the lists read anew"),
    "plan": at(lambda t: verb(t) == ["plan"] and t.get("register") == "_plan", "the plan"),
    "end": at(lambda t: t.get("ansible.builtin.meta") == "end_host", "an end for a Pi with nothing to do"),
    "lock": at(inc("tier0-backup-lock.yml"), "the early tier-0 lock read"),
    "download": at(lambda t: "-d" in argv(t), "the downloads"),
    "boot1": at(lambda t: t.get("register") == "_boot_before", "the boot files before"),
    "oback": at(lambda t: verb(t) == ["back"] and t.get("delegate_to"), "the other Pi serving"),
    "ostandby": at(lambda t: verb(t) == ["standby"] and t.get("delegate_to") == "{{ _other_pi }}", "the other Pi ready"),
    "units": at(name("The other Pi has every keepalived service"), "the other Pi's keepalived services"),
    "switch": at(lambda t: "switchover" in str(t.get("ansible.builtin.command")), "Patroni's switchover"),
    "led": at(lambda t: t.get("register") == "_led", "the new leader waited for"),
    "db": at(lambda t: t.get("register") == "_db_both", "Forgejo's database on both Pis"),
    "vault": at(inc("vault-step-down.yml"), "Vault's handover"),
    "holder": at(inc("pi-vip-holder.yml"), "the VIP's holder read"),
    "conv": at(lambda t: (t.get("ansible.builtin.systemd_service") or {}).get("name") == "keepalived-converge.timer"
               and (t.get("ansible.builtin.systemd_service") or {}).get("state") == "stopped", "the converge timer stopped"),
    "ustop": at(name("Keepalived's own services stopped here first"), "keepalived's services stopped first"),
    "uidle": at(lambda t: t.get("register") == "_stopped_here", "them gone"),
    "kstop": at(lambda t: (t.get("ansible.builtin.systemd_service") or {}) == {"name": "keepalived", "state": "stopped"},
                "keepalived stopped"),
    "took": at(lambda t: t.get("register") == "_took_vip", "the other Pi taking the VIP"),
    "mark": at(lambda t: "ansible.builtin.copy" in t, "the reboot owed marked"),
    "leader1": at(inc("consul-leader-off.yml"), "Consul's handover before apt"),
    "apt": at(lambda t: "upgrade" in argv(t) and "-d" not in argv(t), "apt's upgrade"),
    "boot2": at(lambda t: t.get("register") == "_boot_after", "the boot files after"),
    "bootcmp": at(name("Its config.txt and cmdline.txt as before"), "the boot files compared"),
    "stage": at(lambda t: verb(t) == ["bootloader"] and "stage" in script(t), "the bootloader staged"),
    "still": at(lambda t: t.get("register") == "_still_vip", "the VIP still on the other Pi"),
    "stilled": at(lambda t: t.get("register") == "_still_led", "the other Pi still leading"),
    "vaultnot": at(name("Its Vault not the active one"), "its Vault not active"),
    "leader2": max(i for i, t in enumerate(every) if inc("consul-leader-off.yml")(t)),
    "tier0": at(inc("tier0-backup-stopped.yml"), "the tier-0 backup kept off"),
    "reboot": at(lambda t: "ansible.builtin.reboot" in t, "the reboot"),
    "back": at(lambda t: t.get("register") == "_back", "every service back"),
    "kernel": at(lambda t: verb(t) == ["kernel"], "the kernel booted"),
    "eeprom": at(lambda t: verb(t) == ["bootloader"] and "check" in script(t), "the bootloader up to date"),
    "vaultback": at(lambda t: t.get("register") == "_vault_back", "its Vault unsealed"),
    "consulback": at(lambda t: t.get("register") == "_consul_back", "Consul caught up"),
    "there": at(lambda t: t.get("register") == "_vip_there", "the VIP still on the other Pi after"),
    "idle": at(lambda t: t.get("register") == "_idle_here", "keepalived's services idle here"),
    "healed": at(lambda t: t.get("register") == "_healed", "Gluster healed"),
    "pback": at(lambda t: t.get("register") == "_patroni_back", "Patroni healthy"),
    "standby": at(lambda t: t.get("register") == "_standby_here", "this Pi ready to take the VIP"),
    "left": at(lambda t: t.get("register") == "_left", "nothing left to upgrade"),
    "unmark": at(lambda t: (t.get("ansible.builtin.file") or {}).get("state") == "absent", "the mark removed"),
}
ORDER = ["update", "plan", "end", "lock", "download", "boot1", "oback", "ostandby", "units", "switch", "led", "db", "vault",
         "holder", "conv", "ustop", "uidle", "kstop", "took", "mark", "leader1", "apt", "boot2", "bootcmp", "stage",
         "still", "stilled", "vaultnot", "leader2", "tier0", "reboot", "back", "kernel", "eeprom", "vaultback",
         "consulback", "there", "idle", "healed", "pback", "standby", "left", "unmark"]
check("the turn in order: nothing to do ends it; the refusals that change nothing; the other Pi ready; the switchover, "
      "Vault's, the VIP's (Nexus stopped first); marked; apt; the boot files; re-checked; the reboot; every check; unmarked",
      [k for k, n in zip(ORDER, ORDER[1:]) if not I[k] < I[n]], [])
check("the tier-0 backup kept off right before the reboot", I["tier0"] + 1, I["reboot"])
tier0_file = yaml.safe_load(open("deploy/ansible/playbooks/tasks/tier0-backup-stopped.yml"))
check("the tier-0 file: its timer stopped, then its lock read - the last task",
      (tier0_file[-1].get("ansible.builtin.include_tasks"), "failed_when" in tier0_file[0]), ("tier0-backup-lock.yml", False))
check("the includes unconditional (their tasks' own conditions decide)",
      [every[i].get("ansible.builtin.include_tasks") for i in (I["lock"], I["vault"], I["holder"], I["leader1"],
       I["leader2"], I["tier0"]) if "when" in every[i]], [])
check("nothing to upgrade and no reboot owed ends the Pi's turn - only that",
      [condition(every[I["end"]]["when"], pi_packages_done=d, pi_packages_reboot_owed=o) for d, o in
       (("0 upgraded, 0 new, 0 kept back", False), ("0 upgraded, 0 new, 2 kept back", False),
        ("0 upgraded, 0 new, 0 kept back", True), ("0 upgraded, 1 new, 0 kept back", False),
        ("10 upgraded, 0 new, 0 kept back", False))], [True, True, False, False, False])
check("the lists read anew - not in a preview",
      [condition(every[I["update"]]["when"], ansible_check_mode=c) for c in (False, True)], [True, False])
check("the plan from fresh lists in a preview, the Pi's own otherwise - a read in a preview too",
      ([render(script(every[I["plan"]]), pi_packages="P", ansible_check_mode=c) for c in (True, False)],
       every[I["plan"]].get("check_mode")), (["P plan --fresh", "P plan"], False))
plan_args = ["-s", "-q", "upgrade", "--with-new-pkgs"]  # what the plan's stub was called with (above)
check("apt's upgrade the command its plan simulated (-s -q aside), the lock waited for, the Pi's config files kept",
      argv(every[I["apt"]]), ["apt-get", "-y", "-q", "-o", "DPkg::Lock::Timeout=600", "-o", "Dpkg::Options::=--force-confdef",
                              "-o", "Dpkg::Options::=--force-confold"] + plan_args[2:])
check("the downloads the same upgrade, -d", argv(every[I["download"]]),
      ["apt-get", "-d", "-y", "-q", "-o", "DPkg::Lock::Timeout=600"] + plan_args[2:])
check("the switchover: from this Pi to the other, unasked",
      render(every[I["switch"]]["ansible.builtin.command"], inventory_hostname="pi1", _other_pi="pi2").split(),
      "patronictl -c /etc/patroni/patroni.yml switchover --leader pi1 --candidate pi2 --force".split())
check("the switchover only where Patroni leads",
      [condition(every[I["switch"]]["when"], _patroni_here={"json": {"role": r}}) for r in ("primary", "master", "replica")],
      [True, True, False])
check("the new leader waited for: the other Pi, where Patroni led here, not in a preview",
      (render(script(every[I["led"]]), pi_packages="P", _other_pi="O").split(),
       [condition(every[I["led"]]["when"], _patroni_here={"json": {"role": r}}, ansible_check_mode=c)
        for r, c in (("primary", False), ("replica", False), ("primary", True))]),
      (["P", "patroni", "--leader", "O"], [True, False, False]))
check("Forgejo's database checked on both Pis after the leadership moved", every[I["db"]].get("loop"), "{{ groups['pis'] }}")
check("the other Pi's checks run there",
      [every[I[k]].get("delegate_to") for k in ("oback", "ostandby", "took", "still", "there")], ["{{ _other_pi }}"] * 5)
check("the other Pi judged by the services it ran when the run began, this Pi after its reboot by its own",
      (render(script(every[I["oback"]]), pi_packages="P", _other_pi="O",
              hostvars={"O": {"pi_packages_services": ["a.service", "b.service"]}}).split(),
       render(script(every[I["back"]]), pi_packages="P", pi_packages_services=["c.service"]).split()),
      (["P", "back", "a.service", "b.service"], ["P", "back", "c.service"]))
check("the other Pi must have every keepalived service this Pi has",
      [condition(every[I["units"]]["ansible.builtin.assert"]["that"], _other_pi="O", pi_packages_vip_units=m,
                 hostvars={"O": {"pi_packages_vip_units": o}}) for m, o in
       ((["nexus.service"], ["nexus.service"]), ([], ["nexus.service"]), ([], []), (["nexus.service"], []))],
      [True, True, True, False])
vipblk = next(t for t in node if "block" in t and every[I["kstop"]] in list(walk(t["block"])) and "rescue" not in t)
inner = next(t for t in walk(vipblk["block"]) if "rescue" in t)
check("the VIP's handover only where this Pi holds it",
      [condition(inner["when"], pi_vip_holder="pi1", inventory_hostname=h) for h in ("pi1", "pi2")], [True, False])
check("keepalived's services stopped here, each of this Pi's", every[I["ustop"]].get("loop"), "{{ pi_packages_vip_units }}")
check("the other Pi must serve this Pi's keepalived services",
      render(script(every[I["took"]]), pi_packages="P", keepalived_vip="V", pi_packages_vip_units=["nexus.service"]).split(),
      ["P", "serving", "V", "nexus.service"])
rescue = inner.get("rescue") or []
check("a VIP not taken: keepalived started here, the other's restarted (the VIP back here), served here, refused",
      ([(t.get("ansible.builtin.systemd_service") or {}).get("state") for t in rescue[:2]], rescue[1:2] and
       rescue[1].get("delegate_to"), verb(rescue[2]) if len(rescue) > 2 else [], "ansible.builtin.fail" in rescue[-1]),
      (["started", "restarted"], "{{ _other_pi }}", ["serving"], True))
mark = every[I["mark"]]["ansible.builtin.copy"]
check("the mark holds the services the run began with",
      json.loads(render(mark["content"], pi_packages_services=["consul.service", "vault.service"]))["services"],
      ["consul.service", "vault.service"])
check("the mark where the first play reads it, removed at the turn's end",
      (mark["dest"], every[I["unmark"]]["ansible.builtin.file"]["path"]), ("{{ pi_packages_owed_path }}",) * 2)
same = ["BOOT FILES config.txt=a cmdline.txt=b", "FREE 400 MB"]
check("the boot files compared before the reboot: the same passes, a change refuses",
      [condition(every[I["bootcmp"]]["ansible.builtin.assert"]["that"], _boot_before={"stdout_lines": same},
                 _boot_after={"stdout_lines": a_}) for a_ in
       (["BOOT FILES config.txt=a cmdline.txt=b"], ["BOOT FILES config.txt=c cmdline.txt=b"])], [True, False])
check("the room asked for before the upgrade", render(script(every[I["boot1"]]), pi_packages="P").split(),
      ["P", "boot", "--min-free", "100"])
check("its Vault not the active one before the reboot (standby or sealed)",
      every[I["vaultnot"]]["ansible.builtin.uri"]["status_code"], [429, 503])
# reads of what the handover and the reboot did are kept out of a preview, which did neither (the copy's preview
# failed on "the VIP still on the other Pi" in the holder's turn, 2026-11-14)
check("the handover's results not read in a preview: the VIP on the other Pi, keepalived's services idle here",
      [condition(every[I[k]].get("when", "true"), ansible_check_mode=c) for k in ("there", "idle") for c in (False, True)],
      [True, False, True, False])
check("the reboot waits for the Pi long enough (900 s)", every[I["reboot"]]["ansible.builtin.reboot"]["reboot_timeout"], 900)
# every wait: its until on its own result, enough tries
WAITS = {"led": ("_led", 24), "db": ("_db_both", 12), "uidle": ("_stopped_here", 24), "took": ("_took_vip", 72),
         "still": ("_still_vip", 6), "stilled": ("_still_led", 6), "back": ("_back", 60), "vaultback": ("_vault_back", 36),
         "consulback": ("_consul_back", 30), "there": ("_vip_there", 12), "idle": ("_idle_here", 60),
         "healed": ("_healed", 60), "pback": ("_patroni_back", 24), "standby": ("_standby_here", 24)}
check("every wait: until on its own result, at least its tries",
      [k for k, (reg, n) in WAITS.items() if every[I[k]].get("register") != reg or reg not in str(every[I[k]].get("until"))
       or int(every[I[k]].get("retries", 0)) < n], [])
check("the other Pi taken over within Nexus's start (5 min)", int(every[I["took"]]["retries"]) * int(every[I["took"]]["delay"])
      >= 300, True)
# every read a read in a preview too - or kept out of one where it waits on what a preview did not do
reads = [t for t in every if script(t) and t.get("changed_when") is False]
check("every read either a read in a preview too, or kept out of one",
      [t["name"] for t in reads if t.get("check_mode") is not False and "not ansible_check_mode" not in str(t.get("when"))],
      [])
st = vipblk.get("always") or []
def started(unit):
    return next((t for t in st if (t.get("ansible.builtin.systemd_service") or {}) == {"name": unit, "state": "started"}), None)
k, c, z = started("keepalived"), started("keepalived-converge.timer"), started("pi-tier0-backup.timer")
check("whatever happens: keepalived started again where the VIP was handed over, the converge and tier-0 timers where "
      "they ran",
      (k is not None and [condition(k["when"], pi_vip_holder="pi1", inventory_hostname=h) for h in ("pi1", "pi2")],
       c is not None and [condition(c["when"], _converge_timer=v) for v in
                          ({"status": {"ActiveState": "active"}}, {"status": {"ActiveState": "inactive"}}, {})],
       z is not None and [condition(z["when"], _tier0_timer=v) for v in
                          ({"status": {"ActiveState": "active"}}, {"status": {"ActiveState": "inactive"}}, {})]),
      ([True, False], [True, False, False], [True, False, False]))
check("the block holds the handover, apt's upgrade and the reboot (a failure there still starts them again)",
      all(every[I[k]] in list(walk(vipblk["block"])) for k in ("kstop", "apt", "reboot")), True)
check("nothing left to upgrade: only a plan of nothing passes",
      [condition(every[I["left"]]["failed_when"], _left={"rc": r, "stdout_lines": o}) for r, o in
       ((0, ["PLAN 0 upgraded, 0 new, 0 kept back\r"]), (0, ["x 1 -> 2", "PLAN 1 upgraded, 0 new, 0 kept back"]),
        (1, ["NOT READ: x"]))], [False, True, True])

# after both turns
final = book[3]["tasks"]
srv = find(final, lambda x: verb(x) == ["serving"], "the run's end: the VIP's Pi serving")
check("after the run: the VIP's Pi serves what either Pi had, on that Pi, waited for",
      (render(script(srv), pi_packages="P", keepalived_vip="V", ansible_play_hosts=["pi1", "pi2"],
              hostvars={"pi1": {"pi_packages_vip_units": ["nexus.service"]}, "pi2": {"pi_packages_vip_units": []}}).split(),
       [condition(srv["when"], inventory_hostname=h, pi_vip_holder="pi1") for h in ("pi1", "pi2")],
       "_serving.rc == 0" in str(srv.get("until")), int(srv.get("retries", 0)) >= 40),
      (["P", "serving", "V", "nexus.service"], [True, False], True, True))
idl = find(final, lambda x: verb(x) == ["idle"], "the run's end: keepalived's services idle on the other Pi")
check("after the run: keepalived's services idle on the Pi without the VIP, waited for",
      ([condition(idl["when"], inventory_hostname=h, pi_vip_holder="pi1") for h in ("pi1", "pi2")],
       "_idle.rc == 0" in str(idl.get("until"))), ([False, True], True))
for v_ in ("patroni", "standby"):
    t = find(final, lambda x, v_=v_: verb(x) == [v_], f"the run's end: {v_}")
    check(f"the run's end: {v_} a read in a preview too", t.get("check_mode"), False)
msg = find(final, lambda x: "ansible.builtin.debug" in x, "the run's last line")
check("the run's last line: each Pi's plan, the VIP's Pi, Patroni",
      " ".join(render(msg["ansible.builtin.debug"]["msg"], ansible_check_mode=False, ansible_play_hosts=["pi1", "pi2"],
                      hostvars={"pi1": {"pi_packages_done": "3 upgraded, 0 new, 0 kept back"},
                                "pi2": {"pi_packages_done": "0 upgraded, 0 new, 0 kept back"}},
                      pi_vip_holder="pi2", _patroni_after={"stdout_lines": ["HEALTHY pi2 Leader running\r"]}).split()),
      "pi1: 3 upgraded, 0 new, 0 kept back; pi2: 0 upgraded, 0 new, 0 kept back; the VIP on pi2; HEALTHY pi2 Leader running")
print("pi-packages: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
