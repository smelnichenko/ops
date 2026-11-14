#!/usr/bin/env python3
"""pi-packages.py - what upgrade-pi-packages.yml reads on a Pi (ansible.builtin.script, root, the Pi's own python3).
Each command prints its verdict and exits 0 for yes, 1 for no - and 1 for an answer it could not read, said so: never
taken for a yes.

  plan [--fresh] apt's upgrade as the playbook runs it (upgrade --with-new-pkgs: held packages stay, nothing removed),
                 simulated: "<package> <installed> -> <candidate>" a line ("new" for one not installed yet), then
                 "PLAN <n> upgraded, <n> new, <n> kept back". --fresh: from package lists read now into a directory of
                 its own (a preview's - the Pi's own lists, and apt's caches, stay as they are). Refused: dpkg's audit
                 not clean (a package half-installed), a removal planned, apt's summary not read, or its packages not
                 the number it says
  services       the services a reboot must bring back: running now and enabled (an instance - foo@bar - by its
                 template's enablement) - keepalived's own aside (they follow the VIP: its notify_lib.sh's SERVICES) -
                 one a line, then "SERVICES <n>"
  back UNIT...   each running again - or skipped by its own start condition at this boot (a first-boot unit): "BACK
                 <n>", or "NOT YET <unit> <state>, ..." (one not tried yet is not yet)
  gluster        every Gluster volume of fstab mounted from itself, every volume's bricks connected with nothing to
                 heal: "HEALED <volumes>", or what is not
  patroni [--leader NAME]
                 one leader running, every other member streaming with no replay lag, and - named - the leader that
                 one: "HEALTHY <members>", or "NOT HEALTHY <members>"
  consul         Consul's servers as a Pi's reboot needs them: autopilot healthy, one loss tolerated, three healthy
                 voters: "QUORUM HOLDS <servers>", or "NO QUORUM TO SPARE <servers>"
  vip-units      keepalived's own services installed here (a unit its table names but this Pi lacks - the Vagrant
                 copy has no Nexus - is skipped by keepalived too): one a line, then "VIP UNITS <n>"
  standby        this Pi can take the VIP: keepalived running, keepalived's own check passing (its
                 check_services.sh: Forgejo, Keycloak, Patroni, versitygw), Forgejo's database reached (its healthz -
                 through PgBouncer and HAProxy to Patroni's leader): "STANDBY", or what is not
  idle [UNIT...] each one not running (keepalived's own, on a Pi not holding the VIP - one running beside the holder's
                 shares its data): "IDLE <units>", or "RUNNING <unit> <state>, ..."
  kernel         the kernel running is the newest of its flavour installed (a reboot took the upgrade's): "BOOTED
                 <release>", or "NOT BOOTED <newest>: running <release>"
  boot [--min-free MB]
                 /boot/firmware's config.txt and cmdline.txt (sha256 - a firmware or kernel package rewriting them is
                 compared before the reboot) and its free space: "BOOT FILES config.txt=<h> cmdline.txt=<h>", "FREE <n>
                 MB" - refused under MB; "BOOT FILES none" where there is no /boot/firmware (the Vagrant copy)
  bootloader stage|check
                 a Raspberry Pi's EEPROM: stage - its update put in place for the reboot to flash (rpi-eeprom-update -a);
                 check - "BOOTLOADER UP TO DATE", or not; "NO BOOTLOADER UPDATER" where there is none
  serving VIP [UNIT...]
                 this Pi holds the VIP and serves the units named - each one of keepalived's, installed, running, its
                 health URL answering (the units the Pi handing over had: one missing here is not served): "SERVING
                 <vip> <units>", or what is missing

The paths, the Consul address and a cap on every command's time (PI_PACKAGES_TIMEOUT, seconds) from the environment,
for the unit harness (tests/ansible/unit/pi-packages).
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

PATRONI_CONFIG = os.environ.get("PATRONI_CONFIG", "/etc/patroni/patroni.yml")
NOTIFY_LIB = os.environ.get("KEEPALIVED_NOTIFY_LIB", "/etc/keepalived/notify_lib.sh")
FSTAB = os.environ.get("FSTAB", "/etc/fstab")
CONSUL = os.environ.get("CONSUL_HTTP_ADDR", "http://127.0.0.1:8500")
CHECK_SERVICES = os.environ.get("KEEPALIVED_CHECK", "/etc/keepalived/check_services.sh")
FORGEJO_HEALTH = os.environ.get("FORGEJO_HEALTH", "http://127.0.0.1:3000/api/healthz")
MODULES = os.environ.get("MODULES_DIR", "/lib/modules")
RELEASE = os.environ.get("KERNEL_RELEASE") or os.uname().release
BOOT = os.environ.get("BOOT_FIRMWARE", "/boot/firmware")
EEPROM = os.environ.get("RPI_EEPROM_UPDATE", "/usr/bin/rpi-eeprom-update")
LISTS_PARENT = os.environ.get("PI_PACKAGES_LISTS_PARENT", "/var/tmp")
TIMEOUT_CAP = float(os.environ.get("PI_PACKAGES_TIMEOUT") or 0)

SUMMARY = re.compile(r"^(\d+) upgraded, (\d+) newly installed, (\d+) to remove and (\d+) not upgraded\.$", re.M)
# "Inst <pkg> [<installed>] (<candidate> <archive> [<arch>])" - no [<installed>] for a package new to the Pi
INST = re.compile(r"^Inst (\S+) (?:\[([^\]]+)\] )?\((\S+) ", re.M)
REMV = re.compile(r"^Remv (\S+)", re.M)


class NotRead(Exception):
    """An answer not read: the verdict is no, said as that."""


def run(cmd, timeout=120, check=True):
    """The command's output - its exit judged when check (a failure is an answer not read), else the whole result."""
    timeout = min(timeout, TIMEOUT_CAP) if TIMEOUT_CAP else timeout
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


def plan(args):
    if args not in ([], ["--fresh"]):
        raise NotRead(f"plan: {' '.join(args)} - [--fresh] only")
    audit = run(["dpkg", "--audit"], timeout=60).strip()
    if audit:
        print("REFUSED: dpkg's audit is not clean - " + " ".join(audit.split())[:300])
        return 1
    if args:
        lists = tempfile.mkdtemp(prefix="pi-packages-lists-", dir=LISTS_PARENT)
        try:
            os.mkdir(os.path.join(lists, "partial"))
            # its own lists, no binary caches written: the Pi's apt state as it was
            own = ["-o", f"Dir::State::Lists={lists}", "-o", "Dir::Cache::pkgcache=", "-o", "Dir::Cache::srcpkgcache="]
            run(["apt-get", "-q", *own, "update"], timeout=600)
            out = run(["apt-get", "-s", "-q", *own, "upgrade", "--with-new-pkgs"], timeout=300)
        finally:
            shutil.rmtree(lists, ignore_errors=True)
    else:
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
    if kept:
        print("KEPT BACK " + " ".join(kept_back(out)))
    print(f"PLAN {upgraded} upgraded, {new} new, {kept} kept back")
    return 0


def kept_back(out):
    """The packages apt names under "have been kept back:" (indented lines up to the next unindented one)."""
    names, inside = [], False
    for line in out.splitlines():
        if line.startswith("The following packages have been kept back:"):
            inside = True
        elif inside and line.startswith(" "):
            names += line.split()
        elif inside:
            break
    return names


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
    # an instance is listed by its template (getty@.service enabled, getty@tty1.service running)
    found = sorted(u for u in running if u in enabled or ("@" in u and u.split("@", 1)[0] + "@.service" in enabled))
    found = [u for u in found if u not in {unit for unit, _ in keepalived_services()}]
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
    skipped, not_yet = [], []
    for u, s in zip(units, states):
        if s == "active":
            continue
        if condition_failed(u):
            skipped.append(u)
        else:
            not_yet.append(f"{u} {s}")
    if not_yet:
        print("NOT YET " + ", ".join(not_yet))
        return 1
    print(f"BACK {len(units)}" + (f" ({', '.join(skipped)} skipped by its start condition)" if skipped else ""))
    return 0


def condition_failed(unit):
    """True when the unit's start conditions were checked at this boot and failed (systemd then leaves it inactive
    without an error: a first-boot unit) - a unit not tried yet has no condition timestamp."""
    props = dict(line.split("=", 1) for line in run(
        ["systemctl", "show", "-p", "ConditionResult", "-p", "ConditionTimestampMonotonic", unit], timeout=30).splitlines()
        if "=" in line)
    return props.get("ConditionResult") == "no" and props.get("ConditionTimestampMonotonic", "0") not in ("", "0")


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


def load_state(unit):
    return run(["systemctl", "show", "-p", "LoadState", "--value", unit], timeout=30).strip()


def vip_units(_args):
    found = [unit for unit, _ in keepalived_services() if load_state(unit) != "not-found"]
    for unit in found:
        print(unit)
    print(f"VIP UNITS {len(found)}")
    return 0


def forgejo_db():
    """None when Forgejo's healthz passes with its database ping, else what it said."""
    try:
        with urllib.request.urlopen(FORGEJO_HEALTH, timeout=10) as r:
            h = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return f"Forgejo's healthz answered {e.code}"
    except (urllib.error.URLError, OSError, ValueError) as e:
        return f"Forgejo's healthz not read ({e})"
    db = [c.get("status") for c in (h.get("checks") or {}).get("database:ping", [])]
    if h.get("status") != "pass" or db != ["pass"]:
        return f"Forgejo's healthz: {h.get('status')}, database {db or 'unchecked'}"
    return None


def standby(_args):
    bad = []
    state = run(["systemctl", "is-active", "keepalived"], timeout=30, check=False).stdout.strip()
    if state != "active":
        bad.append(f"keepalived {state or 'unread'}")
    if not os.path.exists(CHECK_SERVICES):
        bad.append(f"no {CHECK_SERVICES}")
    elif run([CHECK_SERVICES], timeout=60, check=False).returncode != 0:
        bad.append("keepalived's check_services.sh fails")
    db = forgejo_db()
    if db:
        bad.append(db)
    if bad:
        print("NOT STANDBY: " + ", ".join(bad))
        return 1
    print("STANDBY")
    return 0


RUNNING = ("active", "activating", "reloading", "deactivating", "refreshing")


def idle(units):
    if not units:
        print("IDLE (no keepalived service of its own)")
        return 0
    r = run(["systemctl", "is-active", *units], timeout=30, check=False)
    states = r.stdout.split()
    if len(states) != len(units):
        raise NotRead(f"systemctl is-active: {len(states)} states for {len(units)} units")
    running = [f"{u} {s}" for u, s in zip(units, states) if s in RUNNING]
    if running:
        print("RUNNING " + ", ".join(running))
        return 1
    print("IDLE " + " ".join(units))
    return 0


def kernel(_args):
    flavour = RELEASE.split("-", 1)[1] if "-" in RELEASE else ""
    try:
        same = [d for d in os.listdir(MODULES) if (d.split("-", 1)[1] if "-" in d else "") == flavour]
    except OSError as e:
        raise NotRead(f"{MODULES}: {e}") from None
    if RELEASE not in same:
        raise NotRead(f"{RELEASE} running, not in {MODULES}")
    newest = max(same, key=lambda d: [int(x) for x in re.findall(r"\d+", d.split("-", 1)[0])])
    if newest != RELEASE:
        print(f"NOT BOOTED {newest}: running {RELEASE}")
        return 1
    print(f"BOOTED {RELEASE}")
    return 0


def boot(args):
    if args not in ([],) and not (len(args) == 2 and args[0] == "--min-free" and args[1].isdigit()):
        raise NotRead(f"boot: {' '.join(args)} - [--min-free MB] only")
    if not os.path.isdir(BOOT):
        print("BOOT FILES none")
        return 0
    def digest(name):
        path = os.path.join(BOOT, name)
        if not os.path.exists(path):
            return "absent"
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    print(f"BOOT FILES config.txt={digest('config.txt')} cmdline.txt={digest('cmdline.txt')}")
    free = shutil.disk_usage(BOOT).free // 2**20
    if args and free < int(args[1]):
        print(f"REFUSED: {BOOT} has {free} MB free, under {args[1]} - a kernel and its initramfs need the room")
        return 1
    print(f"FREE {free} MB")
    return 0


def bootloader(args):
    if args not in (["stage"], ["check"]):
        raise NotRead("bootloader: stage or check")
    if not os.path.exists(EEPROM):
        print("NO BOOTLOADER UPDATER")
        return 0
    if args == ["stage"]:
        out = run([EEPROM, "-a"], timeout=300)
        print("STAGED: " + " ".join(out.split())[-300:])
        return 0
    r = run([EEPROM], timeout=120, check=False)
    line = next((x.strip() for x in r.stdout.splitlines() if x.strip().startswith("BOOTLOADER:")), "")
    if line == "BOOTLOADER: up to date":
        print("BOOTLOADER UP TO DATE")
        return 0
    print(f"BOOTLOADER NOT UP TO DATE: {line or 'no BOOTLOADER line'}")
    return 1


def serving(args):
    if not args:
        raise NotRead("serving: the VIP, then the units it must serve")
    vip, wanted = args[0], args[1:]
    if f" inet {vip}/" not in run(["ip", "-o", "-4", "addr", "show", "to", f"{vip}/32"]):
        print(f"NO VIP {vip} here")
        return 1
    urls = dict(keepalived_services())
    unknown = [u for u in wanted if u not in urls]
    if unknown:
        raise NotRead(f"serving: {' '.join(unknown)} not in keepalived's table")
    missing = []
    for unit in wanted:
        if load_state(unit) == "not-found":
            missing.append(f"{unit} not installed")
            continue
        state = run(["systemctl", "is-active", unit], timeout=30, check=False).stdout.strip()
        if state != "active":
            missing.append(f"{unit} {state or 'unread'}")
            continue
        try:
            with urllib.request.urlopen(urls[unit], timeout=5):
                pass
        except (urllib.error.URLError, OSError) as e:
            missing.append(f"{unit} not answering {urls[unit]} ({e})")
    if missing:
        print(f"NOT SERVING {vip}: " + ", ".join(missing))
        return 1
    print(f"SERVING {vip} {' '.join(wanted) or '(no keepalived service to serve)'}")
    return 0


COMMANDS = {"plan": plan, "services": services, "back": back, "gluster": gluster, "patroni": patroni,
            "consul": consul, "vip-units": vip_units, "serving": serving, "standby": standby, "idle": idle,
            "kernel": kernel, "boot": boot, "bootloader": bootloader}


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
