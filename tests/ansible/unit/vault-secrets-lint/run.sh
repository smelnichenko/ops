#!/bin/bash
# Production's playbooks (deploy/ansible/playbooks, their task files too) talk to Vault verified and keep secrets out of
# the log: no `validate_certs: false` or VAULT_SKIP_VERIFY (the Pi Vault's certificate names 127.0.0.1 and its CA is on
# the Pi: /etc/vault.d/tls/ca-cert.pem); a task that reads /etc/vault-unseal/* into a result (slurp), sends a token
# (X-Vault-Token, an Authorization: Bearer header templated in) or registers one (a result named *token*) is no_log -
# -v printed the root token, and a module logs its arguments on its host ("Invoked with", headers not hidden) unless
# the task is no_log. Every task of every play section (tests/ansible/unit/plays.py's walk - pre_tasks and post_tasks
# went unseen). The Vagrant-only test playbooks are outside it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import files, load, plays, tasks  # noqa: E402
TOKEN_SENT = re.compile(r"X-Vault-Token|Bearer \{\{")
# (file, register): why its result holds no secret
NOT_A_TOKEN = {
    ("deploy/ansible/playbooks/setup-argocd.yml", "existing_tokens"): "Forgejo lists a user's tokens by name only",
    ("deploy/ansible/playbooks/setup-woodpecker.yml", "existing_tokens"): "Forgejo lists a user's tokens by name only",
}


def problems(path, task):
    if any(k in task for k in ("block", "rescue", "always")):
        return []
    name, text, out = task.get("name", "?"), yaml.safe_dump(task, width=10000), []
    if "validate_certs: false" in text or "VAULT_SKIP_VERIFY" in text:
        out.append(f"{path}: '{name}' does not verify Vault's (or another server's) certificate")
    if task.get("no_log") is True:
        return out
    slurp = task.get("ansible.builtin.slurp") or task.get("slurp") or {}
    if "/etc/vault-unseal/" in str(slurp.get("src", "")):
        out.append(f"{path}: '{name}' reads {slurp['src']} into its result without no_log")
    if TOKEN_SENT.search(text):
        out.append(f"{path}: '{name}' sends a token without no_log")
    reg = str(task.get("register", ""))
    if re.search("token", reg, re.I) and (path, reg) not in NOT_A_TOKEN:
        out.append(f"{path}: '{name}' registers {reg} without no_log")
    return out


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got))))


uri = lambda **k: {"name": "t", "ansible.builtin.uri": {"url": "x", **k}}
check("a Bearer token in a header: named", len(problems("f", uri(headers={"Authorization": "Bearer {{ t }}"}))), 1)
check("X-Vault-Token: named", len(problems("f", uri(headers={"X-Vault-Token": "{{ t }}"}))), 1)
check("a token registered: named", len(problems("f", {**uri(), "register": "kc_token"})), 1)
check("each no_log: none", problems("f", {**uri(headers={"Authorization": "Bearer {{ t }}"}), "register": "a_token",
                                         "no_log": True}), [])
check("a play's pre_tasks seen", [p for t in tasks([{"hosts": "all", "pre_tasks": [uri(validate_certs=False)]}])
                                  for p in problems("f", t)], ["f: 't' does not verify Vault's (or another server's) certificate"])
found, used = [], set()
paths = files("deploy/ansible/playbooks")
for f in paths:
    doc = load(f)
    for p in plays(doc):
        if "VAULT_SKIP_VERIFY" in yaml.safe_dump(p.get("vars") or {}, width=10000):
            found.append(f"{f}: play '{p.get('name')}' sets VAULT_SKIP_VERIFY in its vars")
    for t in tasks(doc):
        found += problems(f, t)
        if (f, str(t.get("register", ""))) in NOT_A_TOKEN:
            used.add((f, str(t.get("register"))))
check(f"{len(paths)} playbook and task files: Vault verified, tokens out of the log", found, [])
check("every exception still needed", sorted(set(NOT_A_TOKEN) - used), [])
print("vault-secrets-lint: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
