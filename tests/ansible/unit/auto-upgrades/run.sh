#!/bin/bash
# tasks/auto-upgrades.yml (setup-host-hardening.yml), its conditions evaluated by Ansible itself (a condition that is no
# boolean fails here as it does on the host): apt reads the package's files as they ship (its 20auto-upgrades enabled
# or disabled) and ours after them - nftables blacklisted, the reboot on (off on the copy) at 07:30, a failed lists
# update a failure (apt-get update itself exits non-zero on an unreachable mirror with ours, zero without); the play's
# apt check passes on that and fails on each part missing; the package's logind drop-in masked before the package is
# installed, and the play's logind check failing on the unmasked merge; the metrics script's file for each state of the
# stamps and the reboot flag - the set-up's time before a first success, nothing left behind when it cannot write; the
# units, the metrics check on node_exporter's own number format.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
command -v apt-config > /dev/null || { echo "FAIL apt-config not found - apt's configuration is read with apt itself here"; exit 1; }
PYTHONDONTWRITEBYTECODE=1 exec "$PY" - <<'PY_AUTOUPGRADES'
import os, stat, subprocess, tempfile, yaml
from ansible.template import Templar, trust_as_template
from ansible.parsing.dataloader import DataLoader
fails = 0
def check(name, got, want):
    global fails
    print(("PASS " if got == want else "FAIL ") + name)
    if got != want:
        print(f"    got:  {got!r}\n    want: {want!r}")
        fails += 1

play = yaml.safe_load(open("deploy/ansible/playbooks/setup-host-hardening.yml"))[0]
V = dict(play["vars"])
tasks = yaml.safe_load(open("deploy/ansible/playbooks/tasks/auto-upgrades.yml"))
T = {t["name"]: t for t in tasks}
order = [t["name"] for t in tasks]
def templar(**extra):
    return Templar(loader=DataLoader(), variables={**V, **extra})
def tpl(s, **extra):  # a value, templated as Ansible does
    return templar(**extra).template(trust_as_template(s))
def cond(s, **extra):  # a condition, as Ansible evaluates it: a non-boolean result raises
    return templar(**extra).evaluate_conditional(trust_as_template(s))
def asserts(task, **extra):  # every `that` of an assert task, its task vars templated first
    ctx = dict(extra)
    for k, x in (task.get("vars") or {}).items():
        ctx[k] = tpl(x, **ctx)
    return all(cond(c, **ctx) for c in task["ansible.builtin.assert"]["that"])

names = [t.get("name") for t in play["tasks"]]
imp = [t for t in play["tasks"] if t.get("ansible.builtin.import_tasks") == "tasks/auto-upgrades.yml"]
check("imported by setup-host-hardening.yml, once, after the textfile directory its metrics go to",
      (len(imp), len(imp) == 1 and names.index(imp[0]["name"])
       > names.index("The node_exporter textfile directory - root's, each job's file its own")), (1, True))
inv = lambda name: yaml.safe_load(open(f"deploy/ansible/inventory/{name}.yml"))["all"]["vars"]
check("the reboot on ten (the play's default, no production override), off on the copy; at 07:30 (operator, 2026-11-22)",
      (V["auto_upgrades_reboot"], "auto_upgrades_reboot" in inv("production"), inv("vagrant").get("auto_upgrades_reboot"),
       V["auto_upgrades_reboot_time"]), (True, False, False, "07:30"))

# ── logind: the package's drop-in masked before the package lands ──
MASK = "Mask unattended-upgrades' logind drop-in - the kubelet's 180 s shutdown delay stays in effect"
mask = T[MASK]["ansible.builtin.file"]
check("the package's logind drop-in replaced in /etc by a link to /dev/null (systemd's mask), before the install",
      (mask["dest"], mask["src"], mask["state"], mask.get("force"), order.index(MASK) < order.index("Install unattended-upgrades")),
      ("/etc/systemd/logind.conf.d/unattended-upgrades-logind-maxdelay.conf", "/dev/null", "link", True, True))
# systemd-analyze cat-config systemd/logind.conf on trixie (read 2026-11-22): the package's /usr/lib drop-in sorts after
# the kubelet's 99-kubelet.conf and its 30 s wins; masked, the file is listed with nothing under it
MERGED = ("# /etc/systemd/logind.conf\n[Login]\n#InhibitDelayMaxSec=5\n"
          "# /etc/systemd/logind.conf.d/99-kubelet.conf\n# Kubelet logind override\n[Login]\nInhibitDelayMaxSec=180\n")
UNMASKED = MERGED + "# /usr/lib/systemd/logind.conf.d/unattended-upgrades-logind-maxdelay.conf\n[Login]\n# delay\nInhibitDelayMaxSec=30\n"
MASKED = MERGED + "# /etc/systemd/logind.conf.d/unattended-upgrades-logind-maxdelay.conf\n"
lg = T["Check the kubelet's shutdown delay is the one in effect, not the package's 30 s"]
logind = lambda out: asserts(lg, _auto_upgrades_logind={"stdout_lines": out.splitlines()})
check("the play's logind check passes on the masked merge, fails on the package's 30 s last",
      (logind(MASKED), logind(UNMASKED)), (True, False))
check("  and fails when no InhibitDelayMaxSec is read at all", logind("# /etc/systemd/logind.conf\n[Login]\n"), False)

# ── apt: the package's files as they ship, ours after them ──
conf_task = T["Nftables never upgraded unattended, the reboot at its time, a failed lists update a failure"]["ansible.builtin.copy"]
ours_name = os.path.basename(conf_task["dest"])
check("ours read after the package's 20auto-upgrades and 50unattended-upgrades",
      sorted([ours_name, "20auto-upgrades", "50unattended-upgrades"])[-1], ours_name)
check("  root's, 0644", (conf_task["owner"], conf_task["group"], conf_task["mode"]), ("root", "root", "0644"))
PKG50 = """// the package's 50unattended-upgrades (2.12), its settings
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian";
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Package-Blacklist {
};
"""
PKG20 = {"enabled": 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n',
         "disabled": 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n'}
def apt_env(d, parts):
    os.makedirs(d + "/parts", exist_ok=True)
    for n, c in parts.items():
        with open(f"{d}/parts/{n}", "w") as f:
            f.write(c)
    with open(d + "/main.conf", "w") as f:
        f.write(f'Dir::Etc::Parts "{d}/parts/";\nDir::Etc::Main "/dev/null";\n')
    return {**os.environ, "APT_CONFIG": d + "/main.conf"}
def apt_dump(parts):
    with tempfile.TemporaryDirectory() as d:
        r = subprocess.run(["apt-config", "dump", "Unattended-Upgrade", "APT::Periodic", "APT::Update::Error-Mode"],
                           capture_output=True, text=True, env=apt_env(d, parts))
        return r.returncode, r.stdout.splitlines()
ac = T["Check apt reads nftables blacklisted, the reboot at its time, the daily units on"]
play_apt = lambda lines, **extra: asserts(ac, _auto_upgrades_config={"stdout_lines": lines, "stdout": "\n".join(lines)},
                                          **extra)
pick = lambda lines, *prefixes: [l for l in lines if l.startswith(prefixes)]
for reboot in (True, False):
    ours = tpl(conf_task["content"], auto_upgrades_reboot=reboot)
    onoff = "on" if reboot else "off"
    for state, pkg20 in PKG20.items():
        rc, lines = apt_dump({"20auto-upgrades": pkg20, "50unattended-upgrades": PKG50, ours_name: ours})
        check(f"reboot {onoff}, the package's 20auto-upgrades {state}: apt reads nftables blacklisted, the daily units "
              "on, a failed lists update an error",
              (rc, pick(lines, "Unattended-Upgrade::Package-Blacklist::", "APT::Periodic::", "APT::Update::Error-Mode")),
              (0, ['Unattended-Upgrade::Package-Blacklist:: "^nftables$";', 'APT::Periodic::Update-Package-Lists "1";',
                   'APT::Periodic::Unattended-Upgrade "1";', 'APT::Update::Error-Mode "any";']))
        check(f"  the reboot {onoff}, a logged-in session not holding it back, at 07:30",
              pick(lines, "Unattended-Upgrade::Automatic-Reboot"),
              [f'Unattended-Upgrade::Automatic-Reboot "{str(reboot).lower()}";',
               'Unattended-Upgrade::Automatic-Reboot-WithUsers "true";', 'Unattended-Upgrade::Automatic-Reboot-Time "07:30";'])
        check("  the package's own origins untouched (the release and its security archive)",
              len(pick(lines, "Unattended-Upgrade::Origins-Pattern::")), 3)
        check("  the play's apt check passes on it", play_apt(lines, auto_upgrades_reboot=reboot), True)
rc, good = apt_dump({"20auto-upgrades": PKG20["disabled"], "50unattended-upgrades": PKG50, ours_name: tpl(conf_task["content"])})
for what, drop in (("nftables not blacklisted", "^nftables$"), ("another reboot time", "Automatic-Reboot-Time"),
                   ("the reboot off", 'Automatic-Reboot "'), ("a failed lists update ignored", "Error-Mode"),
                   ("the lists not updated daily", "Update-Package-Lists"), ("no daily upgrade", "Periodic::Unattended-Upgrade"),
                   ("a session holding the reboot", "WithUsers")):
    check(f"  fails with {what}", play_apt([l for l in good if drop not in l]), False)
copy_dump = apt_dump({"20auto-upgrades": PKG20["enabled"], "50unattended-upgrades": PKG50,
                      ours_name: tpl(conf_task["content"], auto_upgrades_reboot=False)})[1]
check("  fails on the copy's file (reboot off) where ten's is wanted", play_apt(copy_dump), False)
# what Error-Mode is there for: apt-get update itself, on a source that does not resolve
def update_rc(parts):
    with tempfile.TemporaryDirectory() as d:
        for sub in ("lists/partial", "cache/archives/partial", "sources.d"):
            os.makedirs(f"{d}/{sub}")
        with open(d + "/sources.list", "w") as f:
            f.write("deb http://unresolvable.invalid/debian trixie main\n")
        return subprocess.run(["apt-get", "-qq", "-o", f"Dir::Etc::SourceList={d}/sources.list", "-o",
                               f"Dir::Etc::SourceParts={d}/sources.d", "-o", f"Dir::State::Lists={d}/lists", "-o",
                               f"Dir::Cache={d}/cache", "-o", "Debug::NoLocking=1", "update"],
                              capture_output=True, env=apt_env(d, parts)).returncode
check("apt-get update on an unreachable mirror: non-zero with ours (its stamp untouched), zero without",
      (update_rc({ours_name: tpl(conf_task["content"])}) != 0, update_rc({})), (True, 0))

# ── the metrics script ──
script = T["Write the script that reports apt's daily units to Prometheus"]["ansible.builtin.copy"]
check("the script root's, 0755", (script["owner"], script["mode"]), ("root", "0755"))
src = tpl(script["content"])
SETUP = 1763600000
def run_metrics(stamps, reboot, writable=True, setup=True):
    with tempfile.TemporaryDirectory() as d:
        for sub in ("periodic", "textfile"):
            os.makedirs(f"{d}/{sub}")
        s = src
        for a, b in (("periodic=/var/lib/apt/periodic", f"periodic={d}/periodic"),
                     ("setup=/etc/apt/apt.conf.d/52schnappy-auto-upgrades", f"setup={d}/setup"),
                     ("reboot_required=/run/reboot-required", f"reboot_required={d}/reboot-required"),
                     (f"out={V['node_exporter_textfile_dir']}/apt_upgrades.prom", f"out={d}/textfile/apt_upgrades.prom")):
            assert s.count(a) == 1, a
            s = s.replace(a, b)
        for path, t in {**{f"periodic/{n}": t for n, t in stamps.items()}, **({"setup": SETUP} if setup else {})}.items():
            open(f"{d}/{path}", "w").close()
            os.utime(f"{d}/{path}", (t, t))
        if reboot:
            open(d + "/reboot-required", "w").close()
        if not writable:
            os.chmod(d + "/textfile", 0o555)
        r = subprocess.run(["bash", "-c", s], capture_output=True, text=True)
        os.chmod(d + "/textfile", 0o755)
        files = sorted(os.listdir(d + "/textfile"))
        body = open(d + "/textfile/apt_upgrades.prom").read() if "apt_upgrades.prom" in files else None
        mode = stat.S_IMODE(os.stat(d + "/textfile/apt_upgrades.prom").st_mode) if body is not None else None
        return r.returncode, files, mode, body
samples = lambda body: [l for l in body.splitlines() if not l.startswith("#")]
rc, files, mode, body = run_metrics({}, False)
check("no success yet: the set-up's time for both (the alert counts its 26 h from set-up), no reboot owed",
      (rc, files, mode, samples(body)), (0, ["apt_upgrades.prom"], 0o644,
       [f"apt_update_last_success_timestamp_seconds {SETUP}", f"apt_unattended_upgrade_last_success_timestamp_seconds {SETUP}",
        "node_reboot_required 0"]))
rc, files, mode, body = run_metrics({"update-stamp": 1763700000, "upgrade-stamp": 1763701800}, True)
check("both stamps, a reboot owed: their times and the flag 1 - one file, no temporary left",
      (rc, files, samples(body)), (0, ["apt_upgrades.prom"],
       ["apt_update_last_success_timestamp_seconds 1763700000",
        "apt_unattended_upgrade_last_success_timestamp_seconds 1763701800", "node_reboot_required 1"]))
check("  every sample with its HELP and TYPE (gauge)",
      all(f"# HELP {s.split()[0]} " in body and f"# TYPE {s.split()[0]} gauge" in body for s in samples(body)), True)
rc, files, mode, body = run_metrics({"unattended-upgrades-stamp": 1763701800}, False)
check("unattended-upgrades' own stamp (written by a failed run too) is no success",
      samples(body)[1], f"apt_unattended_upgrade_last_success_timestamp_seconds {SETUP}")
rc, files, mode, body = run_metrics({}, False, writable=False)
check("a directory it cannot write: it fails, and leaves nothing behind", (rc != 0, files), (True, []))
rc, files, mode, body = run_metrics({}, False, setup=False)
check("a failure after its temporary file is made (no stamp, no set-up file): it fails, its temporary removed",
      (rc != 0, files), (True, []))
# each value alone unreadable (its stamp missing, no set-up file): a value lost in an argument would be written empty
for missing, present in (("update-stamp", "upgrade-stamp"), ("upgrade-stamp", "update-stamp")):
    rc, files, mode, body = run_metrics({present: 1763700000}, False, setup=False)
    check(f"  {missing} alone unreadable: it fails too, no file with an empty value", (rc != 0, files), (True, []))
units = T["Write the units that run it (a 5-minute timer, the first run a minute after boot)"]
svc, tmr = [tpl(i["content"]) for i in units["loop"]]
check("the service runs the script once, writing only to the textfile directory",
      ("ExecStart=" + script["dest"] in svc, f"ReadWritePaths={V['node_exporter_textfile_dir']}" in svc,
       "ProtectSystem=strict" in svc, "Type=oneshot" in svc), (True,) * 4)
check("its timer: a minute after boot, then every 5 minutes, enabled at boot",
      ("OnBootSec=1min" in tmr, "OnUnitActiveSec=5min" in tmr, "WantedBy=timers.target" in tmr), (True,) * 3)
en = T["Enable + start the metrics timer"]
check("the timer enabled and started after a daemon-reload - not in check mode (its unit is not written then)",
      ({k: en["ansible.builtin.systemd"][k] for k in ("name", "enabled", "state", "daemon_reload")},
       cond(en["when"], ansible_check_mode=False), cond(en["when"], ansible_check_mode=True)),
      ({"name": "apt-upgrades-metrics.timer", "enabled": True, "state": "started", "daemon_reload": True}, True, False))
now = T["Report apt's daily units to Prometheus now"]
check("the service run once before node_exporter is read",
      (now["ansible.builtin.systemd"]["name"], now["ansible.builtin.systemd"]["state"],
       order.index("Report apt's daily units to Prometheus now")
       < order.index("Check node_exporter serves them - the lists, the upgrade and the reboot owed")),
      ("apt-upgrades-metrics.service", "started", True))
met = T["Check node_exporter serves them - the lists, the upgrade and the reboot owed"]
served = ("# HELP apt_update_last_success_timestamp_seconds x\napt_update_last_success_timestamp_seconds 1.7637e+09\n"
          "apt_unattended_upgrade_last_success_timestamp_seconds 1.7637018e+09\nnode_reboot_required 0\n")
ok = lambda content, status=200: cond(met["until"], _auto_upgrades_metrics={"status": status, "content": content})
check("the metrics check passes on node_exporter's number format with all three served (a boolean, as Ansible needs)",
      ok(served), True)
check("  fails with the upgrade's missing, with no reboot flag, on a 500",
      [ok(served.replace("apt_unattended_upgrade_last_success", "x")), ok(served.replace("node_reboot_required 0", "")),
       ok(served, 500)], [False, False, False])
check("  retried (node_exporter reads the file on its next scrape)", met["retries"] >= 2, True)
print("auto-upgrades: " + ("ALL-PASS" if fails == 0 else f"{fails} FAILED"))
raise SystemExit(1 if fails else 0)
PY_AUTOUPGRADES
