#!/usr/bin/env python3
"""pi-packages.py - what upgrade-pi-packages.yml reads on a Pi (ansible.builtin.script, root, the Pi's own python3).
Each command prints its verdict and exits 0 for yes, 1 for no - and 1 for an answer it could not read, said so: never
taken for a yes.

  plan           apt's upgrade as the playbook runs it (upgrade --with-new-pkgs: held packages stay, nothing removed),
                 simulated: "<package> <installed> -> <candidate>" a line ("new" for one not installed yet), then
                 "PLAN <n> upgraded, <n> new, <n> kept back". Refused: a removal planned, apt's summary not read, or
                 its packages not the number it says
  services       the services a reboot must bring back: running now and enabled - keepalived's own aside (they follow
                 the VIP: its notify_lib.sh's SERVICES) - one a line, then "SERVICES <n>"
  back UNIT...   each running again: "BACK <n>", or "NOT YET <unit> <state>, ..."
  gluster        every Gluster volume of fstab mounted from itself, every volume's bricks connected with nothing to
                 heal: "HEALED <volumes>", or what is not
  patroni [--leader NAME]
                 one leader running, every other member streaming with no replay lag, and - named - the leader that
                 one: "HEALTHY <members>", or "NOT HEALTHY <members>"
  consul         Consul's servers as a Pi's reboot needs them: autopilot healthy, one loss tolerated, three healthy
                 voters: "QUORUM HOLDS <servers>", or "NO QUORUM TO SPARE <servers>"
  serving VIP    this Pi holds the VIP and serves keepalived's own services (each running, its health URL answering):
                 "SERVING <vip> <units>", or what is missing

The paths and the Consul address from the environment, for the unit harness (tests/ansible/unit/pi-packages).
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

PATRONI_CONFIG = os.environ.get("PATRONI_CONFIG", "/etc/patroni/patroni.yml")
NOTIFY_LIB = os.environ.get("KEEPALIVED_NOTIFY_LIB", "/etc/keepalived/notify_lib.sh")
FSTAB = os.environ.get("FSTAB", "/etc/fstab")
CONSUL = os.environ.get("CONSUL_HTTP_ADDR", "http://127.0.0.1:8500")

SUMMARY = re.compile(r"^(\d+) upgraded, (\d+) newly installed, (\d+) to remove and (\d+) not upgraded\.$", re.M)
# "Inst <pkg> [<installed>] (<candidate> <archive> [<arch>])" - no [<installed>] for a package new to the Pi
INST = re.compile(r"^Inst (\S+) (?:\[([^\]]+)\] )?\((\S+) ", re.M)
REMV = re.compile(r"^Remv (\S+)", re.M)


class NotRead(Exception):
    """An answer not read: the verdict is no, said as that."""


def run(cmd, timeout=120, check=True):
    """The command's output - its exit judged when check (a failure is an answer not read), else the whole result."""
    # C locale: apt's and systemd's words are the ones parsed here
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env={**os.environ, "LC_ALL": "C"})
    except subprocess.TimeoutExpired:
        raise NotRead(f"{' '.join(cmd)} did not answer in {timeout} s") from None
    except OSError as e:
        raise NotRead(f"{' '.join(cmd)}: {e}") from None
    if not check:
        return r
    if r.returncode != 0:
        raise NotRead(f"{' '.join(cmd)} failed (rc {r.returncode}): {(r.stderr or r.stdout).strip()[-300:]}")
    return r.stdout


def plan(_args):
    out = run(["apt-get", "-s", "-q", "upgrade", "--with-new-pkgs"], timeout=300)
    summary = SUMMARY.findall(out)
    if len(summary) != 1:
        raise NotRead("apt-get -s upgrade: its summary line not found")
    upgraded, new, remove, kept = (int(x) for x in summary[0])
    removals = REMV.findall(out)
    if remove or removals:
        print(f"REFUSED: the upgrade would remove {remove} package(s): {' '.join(removals) or '(not listed)'}")
        return 1
    inst = INST.findall(out)
    if len(inst) != upgraded + new or sum(1 for _, old, _ in inst if not old) != new:
        raise NotRead(f"apt-get -s upgrade: {len(inst)} packages listed, its summary says {upgraded} upgraded, {new} new")
    for pkg, old, cand in inst:
        print(f"{pkg} {old or 'new'} -> {cand}")
    print(f"PLAN {upgraded} upgraded, {new} new, {kept} kept back")
    return 0


def keepalived_services():
    """keepalived's own services: [(unit, health URL)] - its notify_lib.sh's SERVICES table
    (<unit> <data dir> <health URL> <timeout> <interval> a row); none without keepalived."""
    if not os.path.exists(NOTIFY_LIB):
        return []
    # sourced as keepalived's handlers source it (it defines functions and SERVICES, runs nothing)
    out = run(["bash", "-c", '. "$1" && printf "%s\\n" "$SERVICES"', "notify_lib", NOTIFY_LIB])
    rows = [line.split() for line in out.splitlines() if line.split()]
    if any(len(r) != 5 for r in rows):
        raise NotRead(f"{NOTIFY_LIB}: a SERVICES row not <unit> <dir> <url> <timeout> <interval>")
    return [(r[0] + ".service", r[2]) for r in rows]


def unit_names(*args):
    out = run(["systemctl", *args, "--type=service", "--no-legend", "--plain", "--no-pager"])
    return {line.split()[0] for line in out.splitlines() if line.split()}


def services(_args):
    running = unit_names("list-units", "--state=active")
    enabled = unit_names("list-unit-files", "--state=enabled")
    found = sorted((running & enabled) - {unit for unit, _ in keepalived_services()})
    if not found:
        raise NotRead("no service running and enabled - systemd's lists not read as such")
    for unit in found:
        print(unit)
    print(f"SERVICES {len(found)}")
    return 0


def back(units):
    if not units:
        raise NotRead("back: no unit named")
    # is-active exits non-zero while any is not active - its states are the answer, one a line in the units' order
    r = run(["systemctl", "is-active", *units], timeout=60, check=False)
    states = r.stdout.split()
    if len(states) != len(units):
        raise NotRead(f"systemctl is-active: {len(states)} states for {len(units)} units ({r.stderr.strip()[-200:]})")
    not_yet = [f"{u} {s}" for u, s in zip(units, states) if s != "active"]
    if not_yet:
        print("NOT YET " + ", ".join(not_yet))
        return 1
    print(f"BACK {len(units)}")
    return 0


def fstab_volumes():
    vols = []
    with open(FSTAB) as f:
        for line in f:
            fields = line.split()
            if len(fields) >= 3 and not fields[0].startswith("#") and fields[2] == "glusterfs":
                vols.append((fields[0], fields[1]))
    return vols


def heal_summary(volume):
    """[(brick, status, total entries)] from `gluster volume heal <v> info summary`."""
    bricks = []
    for line in run(["gluster", "volume", "heal", volume, "info", "summary"]).splitlines():
        line = line.strip()
        if line.startswith("Brick "):
            bricks.append([line[len("Brick "):], None, None])
        elif bricks and line.startswith("Status:"):
            bricks[-1][1] = line.split(":", 1)[1].strip()
        elif bricks and line.startswith("Total Number of entries:"):
            bricks[-1][2] = line.split(":", 1)[1].strip()
    if not bricks:
        raise NotRead(f"gluster volume heal {volume} info summary: no brick in its answer")
    return bricks


def gluster(_args):
    bad = []
    mounts = fstab_volumes()
    for src, mnt in mounts:
        # findmnt reads the mount table - no stat of the mount point, which a hung client never answers
        now = run(["findmnt", "-rn", "-o", "SOURCE", "--mountpoint", mnt], timeout=30, check=False).stdout.strip()
        now = now or "nothing"
        if now != src:
            bad.append(f"{mnt} mounted from {now}, fstab {src}")
    volumes = run(["gluster", "volume", "list"]).split()
    if not volumes:
        raise NotRead("gluster volume list: no volume")
    for v in volumes:
        for brick, status, total in heal_summary(v):
            if status != "Connected" or total != "0":
                bad.append(f"{v} {brick} {status or 'no status'}, {total if total is not None else '?'} to heal")
    if bad:
        print("NOT HEALED " + "; ".join(bad))
        return 1
    print(f"HEALED {' '.join(volumes)} ({len(mounts)} mounted)")
    return 0


def patroni(args):
    leader_wanted = None
    if args[:1] == ["--leader"] and len(args) == 2:
        leader_wanted = args[1]
    elif args:
        raise NotRead(f"patroni: {' '.join(args)} - [--leader NAME] only")
    try:
        members = json.loads(run(["patronictl", "-c", PATRONI_CONFIG, "list", "-f", "json"]))
    except ValueError:
        raise NotRead("patronictl list -f json: not JSON") from None
    leaders = [m for m in members if m.get("Role") == "Leader" and m.get("State") == "running"]
    others = [m for m in members if m.get("Role") != "Leader"]
    ok = (len(leaders) == 1 and bool(others)
          and all(m.get("State") == "streaming" and m.get("Replay Lag", 1) == 0 for m in others)
          and (leader_wanted is None or leaders[0].get("Member") == leader_wanted))
    said = ", ".join(f"{m.get('Member')} {m.get('Role')} {m.get('State')}" for m in members)
    print(("HEALTHY " if ok else "NOT HEALTHY ") + said
          + ("" if ok or leader_wanted is None else f" (the leader wanted: {leader_wanted})"))
    return 0 if ok else 1


def consul(_args):
    try:
        with urllib.request.urlopen(CONSUL + "/v1/operator/autopilot/health", timeout=5) as r:
            body = r.read()
    except urllib.error.HTTPError as e:
        body = e.read()  # 429: unhealthy, its health in the body
    except (urllib.error.URLError, OSError) as e:
        raise NotRead(f"Consul's autopilot health not read: {e}") from None
    try:
        h = json.loads(body)
        servers = h["Servers"]
        ok = (h["Healthy"] and h["FailureTolerance"] >= 1 and len(servers) == 3
              and all(s["Healthy"] and s["Voter"] for s in servers))
        said = ", ".join(f"{s['Name']} {'healthy' if s['Healthy'] else 'unhealthy'}" for s in servers)
    except (ValueError, KeyError, TypeError):
        raise NotRead("Consul's autopilot health: not its JSON") from None
    print(("QUORUM HOLDS " if ok else "NO QUORUM TO SPARE ") + said)
    return 0 if ok else 1


def serving(args):
    if len(args) != 1:
        raise NotRead("serving: the VIP, one address")
    vip = args[0]
    if f" inet {vip}/" not in run(["ip", "-o", "-4", "addr", "show", "to", f"{vip}/32"]):
        print(f"NO VIP {vip} here")
        return 1
    rows = keepalived_services()
    missing = []
    for unit, url in rows:
        state = run(["systemctl", "is-active", unit], timeout=30, check=False).stdout.strip()
        if state != "active":
            missing.append(f"{unit} {state or 'unread'}")
            continue
        try:
            with urllib.request.urlopen(url, timeout=5):
                pass
        except (urllib.error.URLError, OSError) as e:
            missing.append(f"{unit} not answering {url} ({e})")
    if missing:
        print(f"NOT SERVING {vip}: " + ", ".join(missing))
        return 1
    print(f"SERVING {vip} {' '.join(u for u, _ in rows) or '(keepalived has no service of its own)'}")
    return 0


COMMANDS = {"plan": plan, "services": services, "back": back, "gluster": gluster, "patroni": patroni,
            "consul": consul, "serving": serving}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        print(f"usage: pi-packages.py {'|'.join(COMMANDS)} [args]")
        return 2
    try:
        return COMMANDS[argv[0]](argv[1:])
    except NotRead as e:
        print(f"NOT READ: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
