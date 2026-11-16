#!/bin/bash
# setup-caddy.yml builds the Caddy pinned: the installed binary's version and its Porkbun module read, a build when either
# is not the pin (before, the module alone was read - caddy_version moved and nothing was built: wave-patches, 2026-11-16),
# built beside the running binary and checked (its version, its module) before one rename moves it over (written in
# place, a running binary refuses it), Caddy restarted after; the Verify play checks the pinned version running. The
# playbook's own scripts run against stubs (caddy, xcaddy - their paths a directory of their own); its Jinja rendered.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml, jinja2' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_CVP'
import os, subprocess, sys, tempfile
import jinja2, yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
plays = yaml.safe_load(open("deploy/ansible/playbooks/setup-caddy.yml"))
setup = next(p for p in plays if p.get("name") == "Setup Caddy")
by = {t.get("name", ""): t for t in setup["tasks"]}
verify = {t.get("name", ""): t for p in plays if p.get("name") == "Verify Caddy" for t in p["tasks"]}
env = jinja2.Environment()
read = by.get("The Caddy installed - its version, and whether it has the Porkbun module", {})
decide = by.get("Caddy to build - not the pinned version, or no Porkbun module", {})
build = by.get("Build Caddy with Porkbun DNS plugin", {})
xcaddy = by.get("Install xcaddy", {})
check("the steps there: the installed read, the decision, xcaddy, the build", all((read, decide, xcaddy, build)), True)
if not all((read, decide, xcaddy, build)):
    print(f"caddy-version-pinned: {fails} FAILED"); sys.exit(1)

work = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
bin_ = os.path.join(work, "bin")
os.makedirs(bin_)
def fake_caddy(path, version, porkbun=True):
    open(path, "w").write("#!/bin/bash\ncase \"$1\" in version) echo '" + version + " h1:x=' ;; list-modules) echo http.handlers.file_server"
                          + ("; echo dns.providers.porkbun" if porkbun else "") + " ;; esac\n")
    os.chmod(path, 0o755)
def run(script, **ctx):
    text = env.from_string(script).render(caddy_version="2.10.2", **ctx).replace("/usr/local/bin/", bin_ + "/")
    r = subprocess.run(["bash", "-c", text], capture_output=True, text=True, timeout=30, env=dict(os.environ, GOPATH=work))
    return r.returncode, r.stdout.strip()
caddy = os.path.join(bin_, "caddy")
def installed(version=None, porkbun=True):
    if os.path.exists(caddy):
        os.remove(caddy)
    if version:
        fake_caddy(caddy, version, porkbun)
    return run(read["ansible.builtin.shell"])
check("the installed read: its version and its module - none when no binary",
      [installed("v2.10.0"), installed("v2.10.2", porkbun=False), installed()], [(0, "v2.10.0 1"), (0, "v2.10.2 0"), (0, "none 0")])
check("  read in a preview too (check_mode false)", read.get("check_mode"), False)
dec = decide["ansible.builtin.set_fact"]["caddy_build"]
check("built when not the pinned version or no Porkbun module (pinned 2.10.2)",
      [env.from_string(dec).render(caddy_version="2.10.2", caddy_check={"stdout": o}).strip()
       for o in ("v2.10.0 1", "v2.10.2 1", "v2.10.2 0", "none 0", "v2.10.2 1\n")], ["True", "False", "True", "True", "False"])
check("  the pin a fact for the Verify play", decide["ansible.builtin.set_fact"].get("caddy_pinned"), "{{ caddy_version }}")
check("xcaddy installed when a build is needed, once", (xcaddy.get("when"), (xcaddy.get("args") or {}).get("creates")),
      ("caddy_build", "/usr/local/bin/xcaddy"))
# xcaddy's stub writes the binary its run is told to (--output), at the version and with the module the case says
def builds(version, porkbun=True):
    fake_caddy(caddy, "v2.10.0")
    open(os.path.join(bin_, "xcaddy"), "w").write(
        "#!/bin/bash\nout=; while [ $# -gt 0 ]; do [ \"$1\" = --output ] && out=$2; shift; done\n"
        "cat > \"$out\" <<'C'\n#!/bin/bash\ncase \"$1\" in version) echo '" + version + " h1:x=' ;; list-modules) echo x"
        + ("; echo dns.providers.porkbun" if porkbun else "") + " ;; esac\nC\nchmod +x \"$out\"\n")
    os.chmod(os.path.join(bin_, "xcaddy"), 0o755)
    rc, _ = run(build["ansible.builtin.shell"])
    return rc, subprocess.run([caddy, "version"], capture_output=True, text=True).stdout.split()[0], os.path.exists(caddy + ".new")
check("the build: beside the running binary, checked, moved over it - the pinned version installed",
      builds("v2.10.2"), (0, "v2.10.2", False))
check("  a build of another version: refused, the running binary untouched", builds("v2.10.1")[:2], (1, "v2.10.0"))
check("  a build without the Porkbun module: refused, the running binary untouched", builds("v2.10.2", porkbun=False)[:2], (1, "v2.10.0"))
check("  run when a build is needed, Caddy restarted after it", (build.get("when"), build.get("notify")), ("caddy_build", "Restart Caddy"))
pinned = verify.get("This Pi's Caddy the pinned version", {})
check("the Verify play: the pinned version running (the play's fact), never judged in a preview",
      (pinned.get("failed_when"), pinned.get("when")),
      ("caddy_running_version.stdout != 'v' ~ (caddy_pinned | default('not set by the play above'))", "not ansible_check_mode"))
print("caddy-version-pinned: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_CVP
