#!/bin/bash
# setup-caddy.yml's caddy-wildcard-sync.sh (the daily pull of the *.pmon.dev wildcard from the cluster) as the playbook
# writes it, rendered by Ansible's templar, against a curl stub: the cluster token reaches curl on a descriptor (-K),
# never on its command line - any local user reads those in /proc, and the token reads the wildcard's private key; the
# certificate and key installed, Caddy restarted, only when either changed; a failed pull changes nothing.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/etc/caddy/certs"
echo "THE-CLUSTER-TOKEN" > "$W/etc/caddy/cluster-token"
echo "CA" > "$W/etc/caddy/cluster-ca.crt"
# curl: its argv recorded, the config it reads from -K too; answers the Secret (CRT/KEY from the environment)
cat > "$W/bin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$W/curl-argv"
out=
while [ $# -gt 0 ]; do
  case "$1" in
    -K|--config) cat "$2" >> "$W/curl-config"; shift ;;
    -o) out=$2; shift ;;
  esac
  shift
done
[ -z "${CURL_FAILS:-}" ] || exit 22
grep -q 'Authorization: Bearer THE-CLUSTER-TOKEN' "$W/curl-config" 2> /dev/null || exit 22
printf '{"data": {"tls.crt": "%s", "tls.key": "%s"}}' "$(printf '%s' "${CRT:-crt1}" | base64 -w0)" \
  "$(printf '%s' "${KEY:-key1}" | base64 -w0)" > "$out"
STUB
for c in systemctl logger; do printf '#!/bin/bash\necho "%s $*" >> "$W/calls"\n' "$c" > "$W/bin/$c"; done
# install as the script calls it, owner and group dropped (no root here)
cat > "$W/bin/install" <<'STUB'
#!/bin/bash
args=(); while [ $# -gt 0 ]; do case "$1" in -o|-g) shift ;; *) args+=("$1") ;; esac; shift; done
exec /usr/bin/install "${args[@]}"
STUB
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
tasks = [t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-caddy.yml")) for t in p.get("tasks") or []]
task = next(t for t in tasks if (t.get("ansible.builtin.copy") or {}).get("dest") == "/usr/local/bin/caddy-wildcard-sync.sh")
script = render(task["ansible.builtin.copy"]["content"], _cluster_api={"stdout": "https://10.0.0.1:6443"})
script = script.replace("/etc/caddy", os.path.join(W, "etc/caddy"))
open(os.path.join(W, "sync.sh"), "w").write(script)
def run(**env):
    for f in ("curl-argv", "curl-config", "calls"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    r = subprocess.run(["bash", os.path.join(W, "sync.sh")], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], **env))
    read = lambda f: open(os.path.join(W, f)).read() if os.path.exists(os.path.join(W, f)) else ""  # noqa: E731
    return r, read("curl-argv"), read("calls")
crt, key = (os.path.join(W, "etc/caddy/certs", f) for f in ("wildcard.crt", "wildcard.key"))
def content(f):
    return open(f).read() if os.path.exists(f) else None
r, argv, calls = run()
check("the pull: the token on curl's descriptor, never its command line; the wildcard installed, Caddy restarted",
      (r.returncode, "THE-CLUSTER-TOKEN" in argv, content(crt), content(key), "systemctl restart caddy" in calls),
      (0, False, "crt1", "key1", True))
r, argv, calls = run()
check("the same again: nothing restarted", (r.returncode, "restart" in calls), (0, False))
r, argv, calls = run(KEY="key2")
check("the key alone changed (a re-key): installed, restarted", (r.returncode, content(key), "restart" in calls),
      (0, "key2", True))
r, argv, calls = run(CURL_FAILS="1", CRT="crt9")
check("the pull failing: the step fails, nothing changed", (r.returncode != 0, content(crt), "restart" in calls),
      (True, "crt1", False))
print("caddy-wildcard-sync: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
