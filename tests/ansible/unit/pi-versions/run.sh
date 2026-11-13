#!/bin/bash
# scripts/pi-versions.py: the Pis' versions as production runs them, written as extra vars only where the playbooks pin
# another - each of the six services the playbooks install at a version of their own (Forgejo, Patroni, Vault, Consul,
# Keycloak, versitygw), the pin read from where the playbooks hold it (vars file, play vars, a task file's default), so
# a bump there is followed; Forgejo's and Vault's checksum kept from the pins file when the version is unchanged
# (nothing fetched: every fetch here fails - a proxy that is not there); refused: two Pis at two versions, a service on
# neither, versitygw at a version its task file has no checksums for. The extra vars outrank the playbooks' own.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY_PI_VERSIONS'
import atexit, os, re, shutil, subprocess, sys, tempfile
import yaml
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


W = tempfile.mkdtemp()
atexit.register(shutil.rmtree, W, True)
pb = "deploy/ansible/playbooks"
# the playbooks' own pins, read here independently of the script
own = {
    "forgejo": str(yaml.safe_load(open("deploy/ansible/vars/forgejo.yml"))["forgejo_version"]),
    "patroni": str(yaml.safe_load(open("deploy/ansible/vars/patroni.yml"))["patroni_version"]),
    "vault": str(yaml.safe_load(open("deploy/ansible/vars/vault.yml"))["vault_version"]),
    "consul": str(yaml.safe_load(open(f"{pb}/setup-consul.yml"))[0]["vars"]["consul_version"]),
    "keycloak": str(yaml.safe_load(open(f"{pb}/setup-pi-services.yml"))[0]["vars"]["keycloak_version"]),
    "versitygw": re.search(r"vgw_version \| default\('([0-9.]+)'\)", open(f"{pb}/tasks/versitygw.yml").read())[1],
}
OFFLINE = {**os.environ, "https_proxy": "http://127.0.0.1:9", "http_proxy": "http://127.0.0.1:9",
           "HTTPS_PROXY": "http://127.0.0.1:9", "HTTP_PROXY": "http://127.0.0.1:9"}


def run(versions, old=None, pi2=None):
    """pi-versions.py on an inventory of both Pis (pi2's own versions where given): (rc, the pins file's vars, stderr)."""
    inv, pins = f"{W}/inventory.txt", f"{W}/pins.yml"
    with open(inv, "w") as f:
        f.write("image some/thing v1\n")
        for host, vs in (("pi1", versions), ("pi2", {**versions, **(pi2 or {})})):
            for name, v in vs.items():
                if v is not None:
                    f.write(f"pi {host} {name} {v}\n")
    if old is None:
        if os.path.exists(pins):
            os.remove(pins)
    else:
        open(pins, "w").write(yaml.safe_dump(old))
    r = subprocess.run(["scripts/pi-versions.py", inv, pins], capture_output=True, text=True, env=OFFLINE, timeout=120)
    body = yaml.safe_load(open(pins)) if r.returncode == 0 and os.path.exists(pins) else None
    return r.returncode, body, r.stderr.strip()


def bumped(v):
    """Another version than v: its last number plus one."""
    parts = v.split(".")
    return ".".join(parts[:-1] + [str(int(re.match(r"\d+", parts[-1])[0]) + 1)])


check("every service at the playbooks' own: nothing pinned", run(own)[:2], (0, {}))
for name, var in (("patroni", "patroni_version"), ("consul", "consul_version"), ("keycloak", "keycloak_version")):
    check(f"{name} at another version than the playbooks': pinned to production's, alone",
          run({**own, name: bumped(own[name])})[:2], (0, {var: bumped(own[name])}))
# Forgejo and Vault carry their checksum: kept from the file when the version is the same - nothing fetched
for name in ("forgejo", "vault"):
    v = bumped(own[name])
    old = {f"{name}_version": v, f"{name}_checksums": {"amd64": "ab" * 32}}
    check(f"{name} pinned, its checksum kept from the file (nothing fetched)",
          run({**own, name: v}, old=old)[:2], (0, old))
# the fetch itself, urlopen stubbed in the script's own process: the release's checksum parsed - Forgejo's .sha256
# (its first field), Vault's SHA256SUMS line of linux_amd64 (other systems' lines first); a failed fetch refuses and
# leaves the pins file as it was; a SHA256SUMS without linux_amd64 refuses
FETCHER = """
import io, runpy, sys, urllib.error, urllib.request
answers = {a.split(' ', 1)[0]: a.split(' ', 1)[1].replace('\\\\n', '\\n') for a in sys.argv[3:]}
asked = []
def urlopen(url, timeout=None):
    asked.append(url)
    if url not in answers:
        raise urllib.error.URLError('no network in a unit test')
    return io.BytesIO(answers[url].encode())
urllib.request.urlopen = urlopen
sys.argv = ['pi-versions.py', sys.argv[1], sys.argv[2]]
try:
    runpy.run_path('scripts/pi-versions.py', run_name='__main__')
finally:
    print('ASKED ' + ' '.join(asked), file=sys.stderr)
"""


def fetch_run(versions, answers, old=None):
    inv, pins = f"{W}/inventory.txt", f"{W}/pins.yml"
    with open(inv, "w") as f:
        for host in ("pi1", "pi2"):
            for name, v in versions.items():
                f.write(f"pi {host} {name} {v}\n")
    if old is None:
        if os.path.exists(pins):
            os.remove(pins)
    else:
        open(pins, "w").write(old)
    r = subprocess.run([sys.executable, "-c", FETCHER, inv, pins, *[f"{u} {t}" for u, t in answers.items()]],
                       capture_output=True, text=True, timeout=120)
    asked = next((l[6:].split() for l in r.stderr.splitlines() if l.startswith("ASKED")), [])
    return r.returncode, (open(pins).read() if os.path.exists(pins) else None), asked, r.stdout + r.stderr


fv, vv = bumped(own["forgejo"]), bumped(own["vault"])
furl = f"https://codeberg.org/forgejo/forgejo/releases/download/v{fv}/forgejo-{fv}-linux-amd64.sha256"
vurl = f"https://releases.hashicorp.com/vault/{vv}/vault_{vv}_SHA256SUMS"
sums = (f"{'11' * 32}  vault_{vv}_darwin_amd64.zip\\n{'22' * 32}  vault_{vv}_linux_arm64.zip\\n"
        f"{'33' * 32}  vault_{vv}_linux_amd64.zip\\n")
rc, text, asked, out = fetch_run({**own, "forgejo": fv, "vault": vv},
                                 {furl: f"{'44' * 32}  forgejo-{fv}-linux-amd64", vurl: sums})
body = yaml.safe_load(text) if text else None
check("forgejo and vault at new versions, no checksum kept: each fetched from its release, its amd64 checksum parsed",
      (rc, sorted(asked), body), (0, sorted([furl, vurl]), {
          "forgejo_version": fv, "forgejo_checksums": {"amd64": "44" * 32},
          "vault_version": vv, "vault_checksums": {"amd64": "33" * 32}}))
check("  the run's line names each service, the pinned ones so", (" (pinned)" in out, f"forgejo {fv} (pinned)" in out,
      f"consul {own['consul']} (pinned)" in out), (True, True, False))
oldtext = yaml.safe_dump({"forgejo_version": "0.0.1", "forgejo_checksums": {"amd64": "cd" * 32}})
rc, text, asked, out = fetch_run({**own, "forgejo": fv}, {}, old=oldtext)
check("  forgejo at a version the file has no checksum for, its fetch failing: refused, the pins file as it was",
      (rc != 0, asked, text), (True, [furl], oldtext))
rc, text, asked, out = fetch_run({**own, "vault": vv}, {vurl: f"{'11' * 32}  vault_{vv}_darwin_amd64.zip\\n"})
check("  vault's SHA256SUMS without linux_amd64: refused, said", (rc != 0, "no linux_amd64 checksum" in out), (True, True))
rc, text, asked, out = fetch_run(own, {}, old="")
check("an empty pins file: read as none, nothing pinned", (rc, yaml.safe_load(text) if text else None), (0, {}))
rc, text, asked, out = fetch_run({**own, "forgejo": fv}, {furl: f"{'44' * 32}  x"}, old="")
check("  an empty pins file and a version to fetch: fetched, pinned", (rc, (yaml.safe_load(text) or {}).get(
      "forgejo_checksums") if text else None), (0, {"amd64": "44" * 32}))
rc, body, err = run({**own, "consul-template": "9.9.9"})
check("another service whose name starts with one of them (consul-template): not read as it", (rc, body), (0, {}))
check("versitygw at the default: nothing pinned; at a version the task file has checksums for: pinned",
      run({**own, "versitygw": "1.6.0"})[:2], (0, {} if own["versitygw"] == "1.6.0" else {"vgw_version": "1.6.0"}))
rc, body, err = run({**own, "versitygw": "9.9.9"})
check("versitygw at a version without checksums: refused, said", (rc != 0, "has none for it" in err), (True, True))
rc, body, err = run(own, pi2={"consul": bumped(own["consul"])})
check("the Pis at two versions of one service: refused, said", (rc != 0, "one version expected on both" in err),
      (True, True))
rc, body, err = run({**own, "keycloak": None})
check("a service on neither Pi: refused, said", (rc != 0, "keycloak" in err and "nowhere" in err), (True, True))
# the pins reach every playbook that installs these: setup-consul and the versitygw run too (go-task's PI_ARGS / the file)
tf = open("Taskfile.yml").read()
check("the copy's Pi stack passes the pins to setup-consul, and its versitygw run reads the file",
      (bool(re.search(r"playbooks/setup-consul\.yml \{\{\.PI_ARGS\}\}", tf)),
       "setup-pi-services.yml --tags versitygw -e @../../tests/ansible/copy/pi-versions.yml" in tf), (True, True))
print("pi-versions: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_PI_VERSIONS
