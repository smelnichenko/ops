#!/bin/bash
# scripts/vagrant-gitops-mirror.py's two refusals that keep the copy off production: a --forgejo outside the Vagrant
# network refused before any API call; a production address the rewrite left (a gap in its map, simulated) stops the
# push. Each with its control: a Vagrant Forgejo goes on to the API, a full map leaves the Vagrant address.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
exec python3 - "$PWD" <<'PY_MIRROR_REFUSALS'
import importlib.machinery, importlib.util, os, subprocess, sys, tempfile
ops = sys.argv[1]
L = importlib.machinery.SourceFileLoader("mirror", os.path.join(ops, "scripts", "vagrant-gitops-mirror.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("mirror", L))
L.exec_module(m)
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
class Stop(Exception):
    pass
calls = []
def api(*a, **k):
    calls.append(a)
    raise Stop()
m.api = api
def main_with(forgejo):
    calls.clear()
    sys.argv = ["mirror", "--forgejo", forgejo]
    try:
        m.main()
        return "returned"
    except SystemExit as e:
        return "REFUSED" if "REFUSED" in str(e.code) else f"exit {e.code}"
    except Stop:
        return "api"
check("a production Forgejo (pi1 on the LAN): refused, no API call", (main_with("192.168.11.4:3000"), len(calls)),
      ("REFUSED", 0))
check("a name, not an address: refused, no API call", (main_with("git.pmon.dev:443"), len(calls)), ("REFUSED", 0))
check("control: the Vagrant Forgejo goes on to the API", (main_with("192.168.56.20:3000"), len(calls)), ("api", 1))
def rewrite(gap):
    t = tempfile.mkdtemp()
    g = lambda *a: subprocess.run(["git", "-C", t, *a], check=True, capture_output=True)
    g("init", "-q")
    open(os.path.join(t, "values.yaml"), "w").write("vault: https://192.168.11.9:8200\n")
    g("add", "values.yaml")
    saved = (m.ADDRESS_MAP, m.PROD_LAN_PREFIX)
    if gap:
        m.ADDRESS_MAP, m.PROD_LAN_PREFIX = [], ("192.168.11.", "192.168.11.")
    try:
        m.isolate_from_production(t)
        return "rewritten", open(os.path.join(t, "values.yaml")).read().strip()
    except SystemExit as e:
        return "stopped", "production addresses left" in str(e.code)
    finally:
        m.ADDRESS_MAP, m.PROD_LAN_PREFIX = saved
check("a production address the rewrite missed: stopped, said", rewrite(True), ("stopped", True))
check("control: the full map rewrites it", rewrite(False), ("rewritten", "vault: https://192.168.56.9:8200"))
print("mirror-refusals: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_MIRROR_REFUSALS
