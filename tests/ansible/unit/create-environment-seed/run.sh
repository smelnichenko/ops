#!/bin/bash
# create-environment.yml's "Seed Vault secrets" as the playbook holds it (its script and stdin rendered by Ansible's
# templar, vault a stub that records each path and its body, jq the real one behind a wrapper that records its
# arguments): every value stored at its path, the optional ones skipped when .env has none, and no value on any
# command line - they were jq's --arg values and the task's environment (sudo's command line on pi1).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "create-environment-seed: no python3 with ansible and yaml"; exit 2; }
command -v jq > /dev/null || { echo "create-environment-seed: no jq"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/vault" <<'STUB'
#!/bin/bash
echo "vault $*" >> "$W/argv"
echo "$3 $(tr -d '\n')" >> "$W/stored"  # the body on one line, however jq printed it
STUB
cat > "$W/bin/jq" <<STUB
#!/bin/bash
echo "jq \$*" >> "\$W/argv"
exec $(command -v jq) "\$@"
STUB
chmod +x "$W/bin/"*
W=$W "$PY" - <<'PY'
import json, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/create-environment.yml"))[0]
task = next(t for t in play["tasks"] if str(t.get("name", "")).startswith("Seed Vault secrets"))
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
check("the task's output hidden (its stdin holds the values)", task.get("no_log"), True)
VALUES = {"gen_db_password": "db-p'w\"1", "gen_valkey_password": "vk-pw-2", "gen_minio_password": "mn-pw-3",
          "gen_kafka_cluster_id": "kafka-id-4"}
ENV = {"ANTHROPIC_API_KEY": "ai-key-5", "MAIL_PASSWORD": "", "RESEND_WEBHOOK_SECRET": "sig-6", "RESEND_API_KEY": "rs-7"}
os.environ.update(ENV)
shell = task["ansible.builtin.shell"]
script = render(shell["cmd"], env_ns="schnappy-x", vault_cli_env=":", **VALUES)
stdin = render(shell["stdin"], **VALUES)
for f in ("argv", "stored"):
    open(os.path.join(W, f), "w").close()
r = subprocess.run(["bash", "-c", script], input=str(stdin), capture_output=True, text=True,
                   env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"]))
check("the seed ran", (r.returncode, r.stderr.strip()), (0, ""))
stored = {l.split(" ", 1)[0]: json.loads(l.split(" ", 1)[1]) for l in open(os.path.join(W, "stored")).read().splitlines()}
check("every value at its path, the optional ones present stored, the empty one skipped", stored, {
    "secret/schnappy-x/postgres": {"database": "monitor", "username": "monitor", "password": VALUES["gen_db_password"]},
    "secret/schnappy-x/valkey": {"password": "vk-pw-2"}, "secret/schnappy-x/s3gw": {"access_key": "admin",
                                                                                    "secret_key": "mn-pw-3"},
    "secret/schnappy-x/kafka": {"cluster_id": "kafka-id-4"}, "secret/schnappy-x/ai": {"api_key": "ai-key-5"},
    "secret/schnappy-x/webhook": {"signing_secret": "sig-6", "api_key": "rs-7"}})
check("the mail secret skipped, said so", "SKIPPED secret/schnappy-x/mail" in r.stdout, True)
argv = open(os.path.join(W, "argv")).read()
leaked = [v for v in list(VALUES.values()) + [v for v in ENV.values() if v] if v in argv]
check("no value on any command line (vault's, jq's)", leaked, [])
check("no value in the task's environment", [k for k, v in (task.get("environment") or {}).items()
                                              if any(s in str(v) for s in ("password", "secret", "key"))], [])
print("create-environment-seed: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
