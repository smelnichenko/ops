#!/bin/bash
# setup-vault-pi.yml's CA signing the other Pi's CSR, its shell as the playbook holds it (the CA's root-only directory
# and Vault's TLS directory moved here, the CSR on stdin as the task gives it, the names its own task renders for pi2):
# a CSR asking for CA:TRUE and a name of its own gets a server certificate - CA:FALSE, serverAuth, exactly the
# playbook's names, the VIP's and loopback among them - which verifies against the CA; the CA's serial file lands
# beside its key, not in Vault's directory. Copied, the request's extensions made a CA certificate (the CA External
# Secrets trusts). Vault's own user owns only its data: nothing under /etc/vault.d is its to change. The CA is the
# playbook's own command's, and the chain verifies X.509-strict, as Python 3.13 verifies by default (the uri checks on
# the Pis): the playbook's CA without keyUsage failed every one of them (full run 2026-10-07 16:13).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "vault-csr: no python3 with ansible and yaml"; exit 2; }
# the playbook as Ansible loads it first: a quote in a free-form shell block's comment fails its argument splitting
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, deploy/ansible/playbooks/setup-vault-pi.yml > /dev/null 2>&1 \
  || { echo "FAIL deploy/ansible/playbooks/setup-vault-pi.yml does not load"; echo "vault-csr: 1 FAILED"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/ca" "$W/tls"
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes -keyout "$W/key.pem" -out "$W/hostile.csr" \
  -subj "/CN=pi2" -addext "basicConstraints=critical,CA:TRUE" -addext "subjectAltName=DNS:evil.example" 2> /dev/null
W=$W "$PY" - <<'PY'
import base64, os, shlex, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
plays = yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
tasks = [t for p in plays for t in p.get("tasks") or []]
task = next(t for t in tasks if str(t.get("name", "")).startswith("Sign the CSR with the CA on pi1"))
names = next(t for t in tasks if str(t.get("name", "")).startswith("The Pi's certificate names"))
ctx = {"vault_pi_dns": "vault-pi2.pmon.dev", "inventory_hostname": "pi2", "node_ip": "192.168.11.6",
       "keepalived_vip": "192.168.11.5"}
sans = [render(n, **ctx) for n in names["ansible.builtin.set_fact"]["_sans"]]
script = render(task["ansible.builtin.shell"], _sans=sans).replace(
    "/etc/vault.d/tls", os.path.join(W, "tls")).replace("/etc/vault-ca", os.path.join(W, "ca"))
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
# the CA as the playbook makes it, its paths moved here
make_ca = next(t for t in tasks if str(t.get("name", "")).startswith("Create the Vault CA on pi1"))
r = subprocess.run(shlex.split(render(make_ca["ansible.builtin.command"]).replace(
    "/etc/vault.d/tls", os.path.join(W, "tls")).replace("/etc/vault-ca", os.path.join(W, "ca"))),
    capture_output=True, text=True)
check("the CA made by the playbook's command", r.returncode == 0, r.stderr)
check("the CSR given on stdin, as the task gives it", task["args"].get("stdin", "").startswith("{{ _vault_csr.content"))
env_ok = {k: render(str(v), _sans=sans) for k, v in (task.get("environment") or {}).items()}
# stdin as the task renders it: the slurped CSR (base64) decoded
slurped = base64.b64encode(open(os.path.join(W, "hostile.csr"), "rb").read()).decode()
csr = render(task["args"]["stdin"], _vault_csr={"content": slurped})
r = subprocess.run(["bash", "-c", script], input=csr, capture_output=True, text=True, env=dict(os.environ, **env_ok))
check("a hostile CSR signed", r.returncode == 0, r.stderr)
open(os.path.join(W, "cert.pem"), "w").write(r.stdout)
text = subprocess.run(["openssl", "x509", "-in", os.path.join(W, "cert.pem"), "-noout", "-text"], capture_output=True,
                      text=True).stdout
check("not a CA (CA:FALSE)", "CA:FALSE" in text and "CA:TRUE" not in text, text[:400])
check("for serving TLS only", "TLS Web Server Authentication" in text, text)
got = sorted(x.strip().replace("IP Address:", "IP:") for x in
             text.split("X509v3 Subject Alternative Name:")[1].split("\n")[1].split(",")) \
    if "X509v3 Subject Alternative Name:" in text else []
check("exactly the playbook's names, not the request's", got == sorted(sans) and "evil.example" not in text, got)
check("the VIP's and loopback among them (External Secrets through the VIP, the unseal script on 127.0.0.1)",
      "IP:192.168.11.5" in sans and "IP:127.0.0.1" in sans, sans)
v = subprocess.run(["openssl", "verify", "-x509_strict", "-CAfile", os.path.join(W, "tls", "ca-cert.pem"),
                    os.path.join(W, "cert.pem")], capture_output=True, text=True)
check("verifies against the CA, X.509-strict (Python 3.13's default)", v.returncode == 0, v.stdout + v.stderr)
check("the CA's serial beside its key (root's), not in Vault's TLS directory",
      os.path.exists(os.path.join(W, "ca", "ca-cert.srl")) and not os.path.exists(os.path.join(W, "tls", "ca-cert.srl")))
# the names reach pi1's root shell from the other Pi's facts: one that is not a plain name or address (a quote, a
# command) is refused before the shell - and never templated into it
bad = sans[:2] + ["IP:1.2.3.4$(touch " + os.path.join(W, "pwned") + ")"]
script_bad = render(task["ansible.builtin.shell"], _sans=bad).replace(
    "/etc/vault.d/tls", os.path.join(W, "tls")).replace("/etc/vault-ca", os.path.join(W, "ca"))
env_bad = {k: render(str(v), _sans=bad) for k, v in (task.get("environment") or {}).items()}
r = subprocess.run(["bash", "-c", script_bad], input=csr, capture_output=True, text=True,
                   env=dict(os.environ, **env_bad))
check("a name that is not a name or an address: refused, nothing run", r.returncode != 0
      and not os.path.exists(os.path.join(W, "pwned")) and "not a name" in r.stdout + r.stderr, r.stdout + r.stderr)
# Vault's own user owns its data only: the config, the TLS directory and its files are root's (a compromised Vault
# swapped the CA its unseal script trusts, or its own config); the CA's directory is root-only
owned = []
def walk(ts):
    for t in ts or []:
        for k in ("block", "rescue", "always"):
            walk(t.get(k))
        f = t.get("ansible.builtin.file") or t.get("ansible.builtin.copy") or {}
        paths = [f.get("path") or f.get("dest")] + [i if isinstance(i, str) else i.get("path")
                                                     for i in (t.get("loop") or [])]
        if f.get("owner") == "vault" and any(str(x).startswith("/etc/vault.d") for x in paths if x):
            owned.append(t.get("name"))
for p in plays:
    walk(p.get("tasks"))
check("nothing under /etc/vault.d Vault's own", owned == [], owned)
ca_dir = next((t for t in tasks if (t.get("ansible.builtin.file") or {}).get("path") == "/etc/vault-ca"), {})
check("the CA's directory root-only", (ca_dir.get("ansible.builtin.file") or {}).get("mode") == "0700"
      and (ca_dir.get("ansible.builtin.file") or {}).get("owner") == "root", ca_dir)
print("vault-csr: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
