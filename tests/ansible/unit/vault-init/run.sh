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
[ "${VAULT_FAIL:-}" = 1 ] && { printf '{"unseal_keys_b64": ["k1",'; echo "Error: connection reset" >&2; exit 2; }
echo '{"unseal_keys_b64": ["k1", "k2", "k3"], "root_token": "hvs.root"}'
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
r = subprocess.run(["bash", "-c", script], env=dict(env, VAULT_FAIL="1"), capture_output=True, text=True)
check("an init that fails: no keys file (only the part written aside)",
      r.returncode != 0 and not os.path.exists(os.path.join(W, "vu", "init.json")))
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
print("vault-init: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
