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
from plays import actions, files, load, plays, tasks  # noqa: E402
TOKEN_SENT = re.compile(r"X-Vault-Token|Bearer \{\{")
SECRET = re.compile(r"\{\{[^}]*\b\w*(password|passwd|secret|token|api_key|apikey)\w*\b[^}]*\}\}", re.I)
# where a secret is, or what a result says of it - not the secret
NOT_A_SECRET = re.compile(r"_(dir|file|path|name|ttl|policy|role|version)\b|\.(status|rc|changed|failed|skipped|id)\b", re.I)
# modules that log their arguments on their host ("Invoked with") or print them (set_fact's facts at -v), with the
# arguments each keeps out of its log itself (no_log in its own spec)
LOGGED = {"kubernetes.core.k8s": set(), "kubernetes.core.helm": set(), "ansible.builtin.uri": {"url_password", "password"},
          "community.hashi_vault.vault_kv2_write": {"data", "token"}, "ansible.builtin.set_fact": set(),
          "set_fact": set()}
# (file, task name): why what it templates is no secret
NOT_A_SECRET_TASK = {
    ("deploy/ansible/playbooks/setup-woodpecker.yml", "Find existing woodpecker-infra token"):
        "Forgejo's token list holds names and ids, never a token",
    ("deploy/ansible/playbooks/setup-nexus.yml", "Enable Docker Bearer Token Realm"): "a realm's name (DockerToken)",
}
INSECURE = re.compile(r"VAULT_SKIP_VERIFY|validate_certs: (?:(?:false|no)\b|'(?:false|no)'|\"(?:false|no)\")"
                      r"|curl\b[^\n]* (-k|--insecure)\b")
# a cat of an unseal file whose output is the task's (not one inside $(...) feeding a variable)
CAT_UNSEAL = re.compile(r"(^|[;&|\n])\s*cat\s+/etc/vault-unseal/")
# (file, register): why its result holds no secret
NOT_A_TOKEN = {
    ("deploy/ansible/playbooks/setup-argocd.yml", "existing_tokens"): "Forgejo lists a user's tokens by name only",
    ("deploy/ansible/playbooks/setup-woodpecker.yml", "existing_tokens"): "Forgejo lists a user's tokens by name only",
}


def problems(path, task):
    name = task.get("name", "?")
    if any(k in task for k in ("block", "rescue", "always")):  # a block's own keys: its environment
        own = {k: v for k, v in task.items() if k not in ("block", "rescue", "always")}
        return [f"{path}: block '{name}' does not verify a server's certificate"] \
            if INSECURE.search(yaml.safe_dump(own, width=10000)) else []
    text, out = yaml.safe_dump(task, width=10000), []
    if INSECURE.search(text):
        out.append(f"{path}: '{name}' does not verify Vault's (or another server's) certificate")
    if task.get("no_log") is True:
        return out
    for m, v in actions(task):
        if str(m).endswith(".slurp") or m == "slurp":
            if "/etc/vault-unseal/" in str((v or {}).get("src", "")):
                out.append(f"{path}: '{name}' reads {v['src']} into its result without no_log")
        elif CAT_UNSEAL.search(v if isinstance(v, str) else str((v or {}).get("cmd", "")) if isinstance(v, dict) else "") \
                and "register" in task:
            out.append(f"{path}: '{name}' registers what it reads in /etc/vault-unseal without no_log")
        if m in LOGGED and isinstance(v, dict) and (path, name) not in NOT_A_SECRET_TASK:
            for k, val in v.items():
                hits = [x.group(0) for x in SECRET.finditer(yaml.safe_dump(val, width=10000))
                        if not NOT_A_SECRET.search(x.group(0))] if k not in LOGGED[m] else []
                if hits:
                    out.append(f"{path}: '{name}' puts a secret in {m}'s {k} (logged or printed) without no_log")
                    break
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
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got if isinstance(got, list) else [got]))))


uri = lambda **k: {"name": "t", "ansible.builtin.uri": {"url": "x", **k}}
check("a Bearer token in a header: named", len(problems("f", uri(headers={"Authorization": "Bearer {{ t }}"}))), 1)
check("X-Vault-Token: named", len(problems("f", uri(headers={"X-Vault-Token": "{{ t }}"}))), 1)
check("a token registered: named", len(problems("f", {**uri(), "register": "kc_token"})), 1)
check("each no_log: none", problems("f", {**uri(headers={"Authorization": "Bearer {{ t }}"}), "register": "a_token",
                                         "no_log": True}), [])
check("a play's pre_tasks seen", [p for t in tasks([{"hosts": "all", "pre_tasks": [uri(validate_certs=False)]}])
                                  for p in problems("f", t)], ["f: 't' does not verify Vault's (or another server's) certificate"])
check("a block's environment skipping verify: named",
      len(problems("f", {"name": "b", "environment": {"VAULT_SKIP_VERIFY": "1"}, "block": []})), 1)
check("curl -k: named", len(problems("f", {"name": "c", "ansible.builtin.shell": "curl -k https://x"})), 1)
check("validate_certs as the string false: named", len(problems("f", uri(validate_certs="false"))), 1)
check("ansible.legacy.slurp of the unseal keys: named",
      len(problems("f", {"name": "s", "ansible.legacy.slurp": {"src": "/etc/vault-unseal/unseal-keys"}})), 1)
check("the root token read by a registered shell: named",
      len(problems("f", {"name": "r", "ansible.builtin.shell": "cat /etc/vault-unseal/root-token", "register": "r"})), 1)
check("an unseal file read into a variable, its output not the file: not named",
      problems("f", {"name": "v", "ansible.builtin.shell": "t=$(cat /etc/vault-unseal/root-token)\nVAULT_TOKEN=$t vault status",
                     "register": "v"}), [])
check("a secret in helm's values: named",
      len(problems("f", {"name": "h", "kubernetes.core.helm": {"values": {"x": "{{ oidc_client_secret }}"}}})), 1)
check("a secret in a k8s definition: named",
      len(problems("f", {"name": "k", "kubernetes.core.k8s": {"definition": {"data": {"x": "{{ a_password }}"}}}})), 1)
check("a password set as a fact: named", len(problems("f", {"name": "f", "ansible.builtin.set_fact": {
    "p": "{{ lookup('password', '/dev/null') }}"}})), 1)
check("uri's url_password (no_log in its own spec), a chart's version: not named",
      problems("f", uri(url_password="{{ admin_password }}")) + problems("f", {"name": "v", "kubernetes.core.helm": {
          "chart_version": "{{ external_secrets_chart_version }}"}}), [])
found, used = [], set()
paths = files("deploy/ansible/playbooks")
for f in paths:
    doc = load(f)
    for p in plays(doc):
        if "VAULT_SKIP_VERIFY" in yaml.safe_dump(p.get("vars") or {}, width=10000):
            found.append(f"{f}: play '{p.get('name')}' sets VAULT_SKIP_VERIFY in its vars")
    for p in plays(doc):
        if INSECURE.search(yaml.safe_dump(p.get("environment") or {}, width=10000)):
            found.append(f"{f}: play '{p.get('name')}' does not verify a server's certificate in its environment")
    for t in tasks(doc):
        found += problems(f, t)
        if (f, str(t.get("register", ""))) in NOT_A_TOKEN:
            used.add((f, str(t.get("register"))))
        if (f, t.get("name")) in NOT_A_SECRET_TASK:
            used.add((f, t.get("name")))
check(f"{len(paths)} playbook and task files: Vault verified, tokens out of the log", found, [])
check("every exception still needed", sorted((set(NOT_A_TOKEN) | set(NOT_A_SECRET_TASK)) - used), [])
print("vault-secrets-lint: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
