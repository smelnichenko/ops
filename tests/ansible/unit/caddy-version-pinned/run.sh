#!/bin/bash
# setup-caddy.yml runs the Caddy pinned, Caddy's own release (operator 2026-11-16: the official package - the xcaddy
# build existed for a Porkbun plugin nothing has used since 2026-06-21). Its version Renovate reads from Cloudsmith's own
# index. A restart pending when Caddy's files (Caddyfile, the wildcard pair, its unit) are not the ones it last loaded
# (a content stamp), the pin is not installed, or the process running is not the pinned /usr/bin/caddy (its running
# image read) - never a handler's note a cut-short run forgets. A Caddyfile the running Caddy refuses never written.
# One Pi at a time, the VIP's holder last (tasks/caddy-turn.yml): the package on that Pi alone - Cloudsmith's source
# there for the install alone, removed even when it fails - held, its config validated by that binary, restarted under
# the Pi restart lock (refused while this Pi serves and the other does not), serving again checked, its files recorded.
# The old xcaddy build removed once the pinned binary runs; the Verify play reads the running process's version. The
# playbook's own scripts run against stubs; its Jinja rendered.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml, jinja2' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_CVP'
import os, re, subprocess, sys, tempfile
import jinja2, yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
PB = "deploy/ansible/playbooks/"
text = open(PB + "setup-caddy.yml").read()
plays = yaml.safe_load(text)
setup = next(p for p in plays if p.get("name") == "Setup Caddy")
tasks = setup["tasks"]
by = {t.get("name", ""): (i, t) for i, t in enumerate(tasks)}
T = lambda n: by.get(n, (None, {}))[1]
I = lambda n: by.get(n, (None, None))[0]
turn = yaml.safe_load(open(PB + "tasks/caddy-turn.yml"))
TT = {t.get("name", ""): t for t in turn}
verify = {t.get("name", ""): t for p in plays if p.get("name") == "Verify Caddy" for t in p["tasks"]}
env = jinja2.Environment()
env.filters["extract"] = lambda k, d: d[k]
def render(expr, **ctx):
    out = env.from_string(expr).render(**ctx).strip()
    return {"True": True, "False": False}.get(out, out)
bare = lambda e: "{{" + (re.fullmatch(r"\s*\{\{(.*)\}\}\s*", e, re.S).group(1) if re.fullmatch(r"\s*\{\{(.*)\}\}\s*", e, re.S) else e) + "}}"

install_text = "\n".join(l for l in (open(PB + "tasks/caddy-turn.yml").read() + open(PB + "tasks/caddy-install.yml").read() + text)
                         .splitlines() if not l.lstrip().startswith("#"))
check("no xcaddy build, no Go, no Porkbun module, no restart handler or notify left",
      [w for w in ("xcaddy build", "go install", "caddy-dns/porkbun", "golang", "notify: Restart Caddy") if w in install_text]
      + [h.get("name") for h in setup.get("handlers", []) if h.get("name") == "Restart Caddy"], [])
import json
rules = [r for r in json.load(open("renovate/upgrade-cycle.json"))["packageRules"] if r.get("matchPackageNames") == ["caddy"]]
check("Renovate reads the version from Cloudsmith's own index (the deb datasource, the preset's rule: its arm64 index), the line "
      "just above the pin",
      (bool(re.search(r"# renovate: datasource=deb depName=caddy\n\s+caddy_version: \"\d", text)),
       [(r.get("matchDatasources"), r.get("registryUrls")) for r in rules]),
      (True, [(["deb"], ["https://dl.cloudsmith.io/public/caddy/stable/deb/debian?suite=any-version&components=main&binaryArch=arm64"])]))

# the reads at the top: the running image, the package installed
work = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
bin_ = os.path.join(work, "bin"); os.makedirs(bin_)
proc = os.path.join(work, "proc")
open(os.path.join(bin_, "systemctl"), "w").write('#!/bin/bash\ncat "' + work + '/pid"\n'); os.chmod(os.path.join(bin_, "systemctl"), 0o755)
def running(pid, version=None, deleted=False):
    open(os.path.join(work, "pid"), "w").write(str(pid) + "\n")
    if pid:
        d = os.path.join(proc, str(pid)); os.makedirs(d, exist_ok=True)
        target = os.path.join(work, "usr-bin-caddy" + (" (deleted)" if deleted else ""))
        open(target, "w").write("#!/bin/bash\n[ \"$1\" = version ] && echo '" + version + " h1:x='\n"); os.chmod(target, 0o755)
        link = os.path.join(d, "exe")
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(target, link)
    script = T("The Caddy running - its binary and the version it runs")["ansible.builtin.shell"].replace("/proc/", proc + "/")
    r = subprocess.run(["bash", "-c", script], env=dict(os.environ, PATH=bin_ + ":" + os.environ["PATH"]), capture_output=True, text=True)
    return r.returncode, r.stdout.strip().replace(work + "/usr-bin-caddy", "BIN")
check("the running read: its binary (a replaced one's ' (deleted)' cut), the version its image runs, its pid; none when stopped",
      [running(4242, "v2.10.0"), running(4243, "v2.10.0", deleted=True), running(0)],
      [(0, "BIN v2.10.0 4242"), (0, "BIN v2.10.0 4243"), (0, "none none")])
fx = T("The package absent, or installed at another version")["ansible.builtin.set_fact"]
st = lambda rc, out: (render(fx["_caddy_absent"], _caddy_installed={"rc": rc, "stdout": out}),
                      render(fx["_caddy_install"], caddy_version="2.10.2", _caddy_installed={"rc": rc, "stdout": out}))
check("the package: absent (none, or removed with its config kept - 'rc'), or installed at another version (a move in its turn)",
      [st(0, "ii |2.10.2"), st(0, "ii |2.10.0"), st(0, "rc |2.10.2"), st(1, "")], [(False, False), (False, True), (True, False), (True, False)])
early, early_val = T("Caddy installed where absent - before its unit names the binary"), T("The binary just installed takes the config as it stands")
check("absent: installed before its unit names /usr/bin/caddy (nothing running touched), the config validated by it at once",
      (early.get("ansible.builtin.include_tasks"), early.get("when"), early_val["ansible.builtin.command"].split()[:2], early_val.get("when"),
       I("Caddy installed where absent - before its unit names the binary") < I("Create Caddy systemd service")
       and I("The binary just installed takes the config as it stands") < I("Create Caddy systemd service")),
      ("tasks/caddy-install.yml", "_caddy_absent and not ansible_check_mode", ["/usr/bin/caddy", "validate"],
       "_caddy_absent and not ansible_check_mode", True))
gone = T("Caddy's apt repository never left behind")
check("Cloudsmith's source removed on every run (a run killed inside the install skips its always)",
      ((gone.get("ansible.builtin.file") or {}).get("path"), (gone.get("ansible.builtin.file") or {}).get("state"), gone.get("when")),
      ("/etc/apt/sources.list.d/caddy-stable.list", "absent", None))
reads = ["Read the *.pmon.dev wildcard cert from the cluster (cluster host)", "Read the *.pmon.dev wildcard key from the cluster (cluster host)",
         "Wait for + read the cert-reader token (cluster host)", "Read the cert-reader CA (cluster host)",
         "Read the cluster API endpoint for the Pi client (cluster host)"]
check("the cluster's reads run in a preview too (its token wait and the copies after it)", [T(n).get("check_mode") for n in reads], [False] * 5)
# a Caddyfile the Caddy running refuses never written
cf = T("Write Caddyfile")["ansible.builtin.copy"]
val = lambda out: " ".join(render(cf["validate"], _caddy_running={"stdout": out}).split())
check("the Caddyfile validated on write by the Caddy running (its own image); none running - nothing to break",
      (val("/usr/local/bin/caddy v2.10.0 4242"), val("none none"), sorted(T("Write Caddyfile").get("environment", {}))),
      ("/proc/4242/exe validate --adapter caddyfile --config %s", "true validate --adapter caddyfile --config %s",
       ["XDG_CONFIG_HOME", "XDG_DATA_HOME"]))
en = T("Enable Caddy").get("ansible.builtin.systemd_service") or {}
check("Caddy enabled here, started by its turn (a fresh Pi: the package installed there first)", (en.get("enabled"), en.get("state")), (True, None))

ORDER = ["Caddy's files against the ones it last loaded", "Its restart pending - other files, the pin not installed, or not the pinned /usr/bin/caddy running",
         "Any Pi pending", "The Pi holding the VIP - its Caddy the last", "Both Pis in the play before any turn - the holder's needs the other serving",
         "The Pi without the VIP first", "Both Pis still in the play before the holder's turn", "The VIP's holder last",
         "Nothing pending - its files recorded current", "The Caddy running now - the pinned /usr/bin/caddy", "The xcaddy-built Caddy and xcaddy removed"]
idx = [I(n) for n in ORDER]
check("the turns all there in their order, after every file Caddy runs is written", None not in idx and idx == sorted(idx)
      and idx[0] > max(I("Write Caddyfile"), I("Create Caddy systemd service"), I("Install wildcard key on the Pi")), True)
if None in idx:
    print(f"caddy-version-pinned: {fails} FAILED"); sys.exit(1)
stamp = T(ORDER[0])
check("the stamp over the files Caddy runs: its Caddyfile, the wildcard pair, its unit",
      (stamp.get("ansible.builtin.include_tasks"), stamp["vars"]["loaded_service"], sorted(stamp["vars"]["loaded_files"])),
      ("tasks/restart-pending.yml", "caddy", sorted(["/etc/caddy/Caddyfile", "/etc/caddy/certs/wildcard.crt", "/etc/caddy/certs/wildcard.key",
                                                     "/etc/systemd/system/caddy.service"])))
pend = T(ORDER[1])["ansible.builtin.set_fact"]["_caddy_pending"]
P = lambda install, stamp_, out: render(pend, caddy_version="2.10.2", _caddy_install=install, _caddy_running={"stdout": out},
                                        **({"_restart_pending": {"stdout_lines": [stamp_, "h"]}} if stamp_ else {}))
check("pending: the pin to install, other files than loaded, not the pinned /usr/bin/caddy running - or no stamp read (a preview)",
      [P(False, "current", "/usr/bin/caddy v2.10.2 1"), P(True, "current", "/usr/bin/caddy v2.10.2 1"), P(False, "pending", "/usr/bin/caddy v2.10.2 1"),
       P(False, "current", "/usr/local/bin/caddy v2.10.2 1"), P(False, "current", "/usr/bin/caddy v2.10.0 1"), P(False, "current", "none none"),
       P(False, None, "/usr/bin/caddy v2.10.2 1")], [False, True, True, True, True, True, True])
anyp = T(ORDER[2])["ansible.builtin.set_fact"]["_caddy_any_pending"].strip()
hv = lambda a, b: {"pi1": ({"_caddy_pending": a} if a is not None else {}), "pi2": ({"_caddy_pending": b} if b is not None else {})}
check("any pending: either Pi's in the play", [render(anyp, ansible_play_hosts=[h for h, v in (("pi1", x), ("pi2", y)) if v is not None], hostvars=hv(x, y))
      for x, y in ((False, False), (True, False), (False, True), (False, None))], [False, True, True, False])
w = lambda n, me, anyp_=True, holder="pi2": render(bare(str(T(n).get("when", "True"))), _caddy_any_pending=anyp_, inventory_hostname=me, pi_vip_holder=holder)
check("the turns: the Pi without the VIP first, then the holder - each the turn's own tasks (tasks/caddy-turn.yml)",
      ([w(ORDER[5], m) for m in ("pi1", "pi2")], [w(ORDER[7], m) for m in ("pi1", "pi2")], T(ORDER[5]).get("ansible.builtin.include_tasks"),
       T(ORDER[7]).get("ansible.builtin.include_tasks")), ([True, False], [False, True], "tasks/caddy-turn.yml", "tasks/caddy-turn.yml"))
check("  both Pis in the play before any turn and before the holder's", [("difference(ansible_play_hosts)" in str(T(n)["ansible.builtin.assert"]["that"]),
      T(n).get("when")) for n in (ORDER[4], ORDER[6])], [(True, "_caddy_any_pending")] * 2)
strict = jinja2.Environment(undefined=jinja2.StrictUndefined)
def skipped(n):
    try:
        return strict.from_string(bare(str(T(n).get("when", "True")))).render(_caddy_any_pending=False, inventory_hostname="pi1").strip() == "False"
    except jinja2.UndefinedError as e:
        return f"undefined: {e}"
check("nothing pending: the holder's read, the asserts and both turns skipped - the holder never read",
      {n: skipped(n) for n in ORDER[3:8]}, {n: True for n in ORDER[3:8]})

# the turn
inst_tasks = yaml.safe_load(open(PB + "tasks/caddy-install.yml"))
IT = {t.get("name", ""): t for t in inst_tasks}
blk = IT.get("Caddy installed at the pin - its source there for the install alone", {})
bn = {t.get("name", ""): t for t in blk.get("block", [])}
key, repo, pkg = bn.get("Caddy's apt key", {}), bn.get("Caddy's apt repository, for this install", {}), bn.get("Caddy, the version pinned", {})
a = pkg.get("ansible.builtin.apt") or {}
check("the install (tasks/caddy-install.yml): gpg, the pinned key, the source, the package at the pin either direction, its own "
      "restart held back, then held",
      ((bn.get("The gpg tool, for the key's check", {}).get("ansible.builtin.apt") or {}).get("name"),
       key.get("ansible.builtin.include_tasks"), key.get("vars", {}).get("apt_key_fingerprint"),
       f"signed-by={key.get('vars', {}).get('apt_key_dest')}]" in (repo.get("ansible.builtin.copy") or {}).get("content", ""),
       a.get("name"), a.get("allow_downgrade"), a.get("allow_change_held_packages"), a.get("policy_rc_d"),
       (IT.get("Caddy held at the pin", {}).get("ansible.builtin.dpkg_selections") or {}).get("selection")),
      ("gpg", "apt-key-pinned.yml", "65760C51EDEA2017CEA2CA15155B6D79CA56EA34", True, "caddy={{ caddy_version }}", True, True, 101, "hold"))
check("  Cloudsmith's source removed again, the install failing or not (always)",
      [(t.get("ansible.builtin.file") or {}).get("path") for t in blk.get("always", []) if (t.get("ansible.builtin.file") or {}).get("state") == "absent"],
      ["/etc/apt/sources.list.d/caddy-stable.list"])
mv = TT.get("Caddy moved to the pin here", {})
check("the turn moves an installed package to the pin on its Pi alone (never in a preview)",
      (mv.get("ansible.builtin.include_tasks"), mv.get("when")), ("caddy-install.yml", "_caddy_install and not ansible_check_mode"))
names = [t.get("name", "") for t in turn]
H, V, R = ("Caddy moved to the pin here", "The config as the binary installed reads it - before this Pi restarts",
           "Caddy restarted here under the Pi restart lock - the other Pi serving, this one serving again after")
check("  moved, validated by the binary installed, restarted, its files recorded - in that order",
      names.index(H) < names.index(V) < names.index(R) < names.index("The files it runs recorded")
      and (TT[V]["ansible.builtin.command"].split()[:2], TT[V].get("when")) == (["/usr/bin/caddy", "validate"], "_caddy_pending and not ansible_check_mode"),
      True)
rec = TT["The files it runs recorded"]
check("  recorded where restarted or found current (the stamp's hash), never in a preview",
      (rec.get("ansible.builtin.include_tasks"), rec["vars"]["loaded_hash"], rec.get("when")),
      ("restart-recorded.yml", "{{ _restart_pending.stdout_lines[1] }}",
       "not ansible_check_mode and (_caddy_pending or _restart_pending.stdout_lines[0] == 'current')"))
# the restart script under stubs: curl answers per address, systemctl notes its restart
rs = TT[R]["ansible.builtin.shell"]
check("  the restart inside pi-restart-locked caddy (Consul's lock: one restart at a time across both Pis)",
      rs.startswith("/usr/local/bin/pi-restart-locked caddy <<'RESTART'"), True)
inner = env.from_string(rs.split("<<'RESTART'\n", 1)[1].rsplit("RESTART", 1)[0]).render(peer_ip="10.0.0.2", inventory_hostname="pi1")
inner = inner.replace("seq 30", "seq 3").replace("sleep 2", "sleep 0")
check("  the restart's wait ends at its minute (a deadline on /proc/uptime, not just its tries), its probe verifying the wildcard",
      ("/proc/uptime) + 60 ))" in inner, " -sk " in rs or "--insecure" in rs), (True, False))
open(os.path.join(bin_, "curl"), "w").write('#!/bin/bash\nfor a; do case "$a" in git.pmon.dev:443:*) ip=${a##*:} ;; esac; done\n'
                                             'f="' + work + '/up-$ip"; [ -e "' + work + '/restarted" ] && [ -e "$f.after" ] && f="$f.after"\n'
                                             'cat "$f" 2>/dev/null || echo 000\n')
open(os.path.join(bin_, "systemctl"), "w").write('#!/bin/bash\necho "$*" >> "' + work + '/systemctl.log"; touch "' + work + '/restarted"\n')
for f in ("curl", "systemctl"):
    os.chmod(os.path.join(bin_, f), 0o755)
def restart(local, peer, local_after):
    for f in os.listdir(work):
        if f.startswith("up-") or f in ("restarted", "systemctl.log"):
            os.remove(os.path.join(work, f))
    for ip, code in (("127.0.0.1", local), ("10.0.0.2", peer)):
        open(os.path.join(work, "up-" + ip), "w").write(code)
    open(os.path.join(work, "up-127.0.0.1.after"), "w").write(local_after)
    r = subprocess.run(["bash", "-c", inner], env=dict(os.environ, PATH=bin_ + ":" + os.environ["PATH"]), capture_output=True, text=True, timeout=30)
    log = open(os.path.join(work, "systemctl.log")).read().strip() if os.path.exists(os.path.join(work, "systemctl.log")) else ""
    return r.returncode, log, "REFUSED" in r.stderr
check("  the restart (Caddy itself: any HTTP answer, a 502 too - Forgejo down must not block it): refused while this Pi answers "
      "and the other does not (nothing restarted); the other answering, a 502 - restarted, answering again; a fresh Pi started; "
      "never answering again - fails",
      [restart("200", "000", "200"), restart("502", "502", "502"), restart("000", "000", "200"), restart("200", "200", "000")],
      [(1, "", True), (0, "restart caddy", False), (0, "restart caddy", False), (1, "restart caddy", False)])
now, rm = T(ORDER[9]), T(ORDER[10])
check("the old xcaddy build removed only after the pinned /usr/bin/caddy is read running",
      ("/usr/bin/caddy v" in now.get("failed_when", ""), rm.get("loop")), (True, ["/usr/local/bin/caddy", "/usr/local/bin/xcaddy"]))
pinned = verify.get("This Pi's Caddy the pinned version", {})
check("the Verify play: the running process's own image (/proc/<pid>/exe) at the pin, never judged in a preview",
      ('"/proc/$pid/exe" version' in (pinned.get("ansible.builtin.shell") or ""), pinned.get("failed_when"), pinned.get("when")),
      (True, "caddy_running_version.stdout != 'v' ~ (caddy_pinned | default('not set by the play above'))", "not ansible_check_mode"))
# a preview skips the uri module: its result has no status, so whatever reads forgejo_https runs in a run alone (every
# preview failed on the print, 2026-11-16)
readers = sorted(n for n, t in verify.items() if "forgejo_https" in json.dumps(t))
check("the Verify play: the Forgejo probe and whatever reads it skipped in a preview",
      (readers, sorted({str(verify[n].get("when")) for n in readers})),
      (["Print results", "Test HTTPS Forgejo"], ["not ansible_check_mode"]))
print("caddy-version-pinned: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_CVP
