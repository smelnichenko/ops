#!/bin/bash
# setup-vault-pi.yml's first init, its shell and templates as the playbook holds them (the key directory moved to a
# temp one, vault a stub): the init's JSON lands on the Pi by the same command, root-only, whole (written aside, then
# moved) - an init that fails leaves no keys file; the unseal-keys and root-token files are made from that file.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "vault-init: no python3 with jinja2 and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/vault" <<'STUB'
#!/bin/sh
# operator init: the keys (VAULT_FAIL=1 cuts it short); secrets/auth list: MOUNTED's paths; enable: logged to CALLS,
# failing with ENABLE_FAIL=1 (a standby, a sealed Vault)
case "$1 $2" in
  "operator init")
    [ "${3:-}" = -status ] && exit "${STATUS_RC:-2}"  # 2: not initialised
    [ "${VAULT_FAIL:-}" = 1 ] && { printf '{"unseal_keys_b64": ["k1",'; echo "Error: connection reset" >&2; exit 2; }
    echo '{"unseal_keys_b64": ["k1", "k2", "k3"], "root_token": "hvs.root"}' ;;
  "secrets list" | "auth list")
    printf '{'; for m in ${MOUNTED:-}; do printf '"%s": {"type": "x"}, ' "$m"; done; printf '"cubbyhole/": {}}\n' ;;
  "secrets enable" | "auth enable")
    echo "$*" >> "$CALLS"; [ "${ENABLE_FAIL:-}" != 1 ] || { echo "Error: 503 standby" >&2; exit 2; } ;;
esac
STUB
chmod +x "$W/bin/vault"
W=$W "$PY" - <<'PY'
import base64, json, os, stat, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
tasks = {t.get("name"): t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
         for t in p.get("tasks") or [] for t in [t] + (t.get("block") or [])}
fails = 0
def check(name, ok):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}")
init = tasks["Initialise Vault - its keys written on the Pi as it returns them"]
script = jinja2.Environment().from_string(init["ansible.builtin.shell"]).render(
    vault_unseal_shares=3, vault_unseal_threshold=2).replace("/etc/vault-unseal", os.path.join(W, "vu"))
check("the init skipped once its keys file exists (creates)", init["args"]["creates"] == "/etc/vault-unseal/init.json")
env = dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"])
aside = lambda: [f for f in os.listdir(os.path.join(W, "vu")) if f.startswith("init.json.")]
r = subprocess.run(["bash", "-c", script], env=dict(env, VAULT_FAIL="1"), capture_output=True, text=True)
check("an init that fails, Vault not initialised: no keys file, nothing left aside (no shares exist)",
      r.returncode != 0 and not os.path.exists(os.path.join(W, "vu", "init.json")) and aside() == [])
r = subprocess.run(["bash", "-c", script], env=dict(env, VAULT_FAIL="1", STATUS_RC="0"), capture_output=True, text=True)
check("an init that fails with Vault initialised: its output kept aside for a look (shares may be in it)",
      r.returncode != 0 and "look by hand" in r.stdout + r.stderr and len(aside()) == 1)
for f in aside():
    os.remove(os.path.join(W, "vu", f))
r = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
path = os.path.join(W, "vu", "init.json")
check("the init's keys on the Pi, whole", r.returncode == 0 and json.load(open(path))["root_token"] == "hvs.root")
check("root-only: the file 0600, its directory 0700",
      stat.S_IMODE(os.stat(path).st_mode) == 0o600 and stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700)
slurped = {"content": base64.b64encode(open(path, "rb").read()).decode()}
keys = tasks["Persist unseal keys (first init only)"]["ansible.builtin.copy"]["content"]
token = tasks["Persist root token (first init only)"]["ansible.builtin.copy"]["content"]
env_j = jinja2.Environment()
env_j.filters["b64decode"] = lambda s: base64.b64decode(s).decode()
env_j.filters["from_json"] = json.loads
check("unseal-keys made from it", env_j.from_string(keys).render(_init_json=slurped).split() == ["k1", "k2", "k3"])
check("root-token made from it", env_j.from_string(token).render(_init_json=slurped) == "hvs.root")
# an ssh retry overlapping a first invocation still running: each writes its own file aside - the other's output (the
# only copy of the shares) never truncated
os.remove(path)
other = os.path.join(W, "vu", "init.json.part")
open(other, "w").write("THE OTHER RUN'S SHARES")
r = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
check("an overlapping init: the other's output untouched",
      os.path.exists(other) and open(other).read() == "THE OTHER RUN'S SHARES")
os.path.exists(other) and os.remove(other)
os.path.exists(path) and os.remove(path)
r = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
# a run cut short between the init and its move (Vault initialised - the init is not run again): its output promoted,
# never left stranded aside; one that is not whole refuses
promote = tasks["A first init's output left aside promoted (a run cut short before its move)"]
pscript = promote["ansible.builtin.shell"].replace("/etc/vault-unseal", os.path.join(W, "vu"))
os.remove(path)
open(os.path.join(W, "vu", "init.json.ab12Cd"), "w").write('{"unseal_keys_b64": ["k1"], "root_token": "hvs.root"}')
r = subprocess.run(["bash", "-c", pscript], env=env, capture_output=True, text=True)
check("an init's output left aside: promoted", r.returncode == 0 and os.path.exists(path)
      and not os.path.exists(os.path.join(W, "vu", "init.json.ab12Cd")))
os.remove(path)
open(os.path.join(W, "vu", "init.json.ef34Gh"), "w").write('{"unseal_keys_b64": ["k1",')
r = subprocess.run(["bash", "-c", pscript], env=env, capture_output=True, text=True)
check("one cut short in its writing: refused, kept for a look", r.returncode != 0 and "not whole" in r.stdout + r.stderr
      and os.path.exists(os.path.join(W, "vu", "init.json.ef34Gh")))
os.remove(os.path.join(W, "vu", "init.json.ef34Gh"))
# the bootstrap's engines: enabled when missing, left when there, a failure a failure (it read "already-enabled", the
# keys file was removed and KV v2 never enabled)
open(os.path.join(W, "vu", "root-token"), "w").write("hvs.root")
calls = os.path.join(W, "calls")
for name, path_, enable in (("Enable KV v2", "secret/", "secrets enable -path=secret kv-v2"),
                            ("Enable Kubernetes auth", "kubernetes/", "auth enable kubernetes")):
    sh = tasks[name]["ansible.builtin.shell"].replace("/etc/vault-unseal", os.path.join(W, "vu"))
    for mounted, fail, want_rc, want_call in (("", "", 0, enable), (path_, "", 0, ""), ("", "1", 1, enable)):
        open(calls, "w").close()
        r = subprocess.run(["bash", "-c", sh], env=dict(env, MOUNTED=mounted, ENABLE_FAIL=fail, CALLS=calls),
                           capture_output=True, text=True)
        got = (min(r.returncode, 1), open(calls).read().strip())
        check(f"{name}: " + ("there already - left" if mounted else "failing - fails" if fail else "missing - enabled"),
              got == (want_rc, want_call))
# the bootstrap waits for this Vault to be the active one (an unsealed standby refuses writes), and the shares are on
# disk before the init's file - their only other copy - goes
block = next(t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
             for t in p.get("tasks") or [] if t.get("name", "").startswith("Bootstrap KV + ESO + k8s-auth"))["block"]
until = jinja2.Environment().compile_expression(block[0].get("until", "false"))
check("the bootstrap first waits for sys/health to say active (200) - not a standby (429), not sealed (503)",
      "sys/health" in str(block[0]) and [bool(until(**{block[0]["register"]: {"status": c}})) for c in (200, 429, 503)]
      == [True, False, False])
names = [t["name"] for t in block]
removal = names.index("The first init done - its keys file removed (the shares are in unseal-keys and root-token)")
check("the shares synced to disk before the keys file goes", "ansible.builtin.command" in block[removal - 1]
      and block[removal - 1]["ansible.builtin.command"].startswith("sync "))
print("vault-init: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
