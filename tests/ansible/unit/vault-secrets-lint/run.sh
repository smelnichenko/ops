#!/bin/bash
# Production's playbooks (deploy/ansible/playbooks, their task files too) talk to Vault verified and keep its secrets
# out of the log: no `validate_certs: false` or VAULT_SKIP_VERIFY (the Pi Vault's certificate names 127.0.0.1 and its
# CA is on the Pi: /etc/vault.d/tls/ca-cert.pem); a task that reads /etc/vault-unseal/* into a result (slurp) or sends
# X-Vault-Token is no_log (-v printed the root token). The Vagrant-only test playbooks are outside it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import glob, sys
import yaml
found = []
def walk(tasks, path):
    for t in tasks or []:
        if not isinstance(t, dict):
            continue
        for k in ("block", "rescue", "always"):
            walk(t.get(k), path)
        if any(k in t for k in ("block", "rescue", "always")):
            continue
        name, text = t.get("name", "?"), yaml.safe_dump(t, width=10000)
        if "validate_certs: false" in text or "VAULT_SKIP_VERIFY" in text:
            found.append(f"{path}: '{name}' does not verify Vault's (or another server's) certificate")
        slurp = t.get("ansible.builtin.slurp") or t.get("slurp") or {}
        if "/etc/vault-unseal/" in str(slurp.get("src", "")) and t.get("no_log") is not True:
            found.append(f"{path}: '{name}' reads {slurp['src']} into its result without no_log")
        if "X-Vault-Token" in text and t.get("no_log") is not True:
            found.append(f"{path}: '{name}' sends X-Vault-Token without no_log")
files = sorted(glob.glob("deploy/ansible/playbooks/**/*.yml", recursive=True))
for f in files:
    for doc in yaml.safe_load(open(f)) or []:
        if isinstance(doc, dict) and "tasks" in doc:
            if "VAULT_SKIP_VERIFY" in yaml.safe_dump(doc.get("vars") or {}, width=10000):
                found.append(f"{f}: play '{doc.get('name')}' sets VAULT_SKIP_VERIFY in its vars")
            walk(doc["tasks"], f)
            walk(doc.get("handlers"), f)
        elif isinstance(doc, dict):  # a task file
            walk([doc], f)
print("\n".join(found) or f"{len(files)} playbook and task files: Vault verified, its secrets out of the log")
print("vault-secrets-lint: " + ("ALL-PASS" if not found else f"{len(found)} FAILED"))
sys.exit(1 if found else 0)
PY
