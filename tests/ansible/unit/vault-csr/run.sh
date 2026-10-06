#!/bin/bash
# setup-vault-pi.yml's CA signing the other Pi's CSR, its shell as the playbook holds it (the CA's directory moved here,
# the CSR on stdin as the task gives it): a CSR asking for CA:TRUE and a name of its own gets a server certificate -
# CA:FALSE, serverAuth, exactly the playbook's names - which verifies against the CA. Copied, the request's extensions
# made a CA certificate (the CA External Secrets trusts).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "vault-csr: no python3 with jinja2 and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-384 -days 1 -nodes -keyout "$W/ca-key.pem" \
  -out "$W/ca-cert.pem" -subj "/CN=Test CA" 2> /dev/null
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes -keyout "$W/key.pem" -out "$W/hostile.csr" \
  -subj "/CN=pi2" -addext "basicConstraints=critical,CA:TRUE" -addext "subjectAltName=DNS:evil.example" 2> /dev/null
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
task = next(t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml")) for t in p.get("tasks") or []
            if str(t.get("name", "")).startswith("Sign the CSR with the CA on pi1"))
sans = ["DNS:vault-pi2.pmon.dev", "DNS:pi2.schnappy.io", "IP:192.168.11.6", "IP:192.168.11.5", "IP:127.0.0.1"]
script = jinja2.Environment().from_string(task["ansible.builtin.shell"]).render(_sans=sans).replace(
    "/etc/vault.d/tls", W)
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
check("the CSR given on stdin, as the task gives it", task["args"].get("stdin", "").startswith("{{ _vault_csr.content"))
r = subprocess.run(["bash", "-c", script], input=open(os.path.join(W, "hostile.csr")).read(), capture_output=True,
                   text=True)
check("a hostile CSR signed", r.returncode == 0, r.stderr)
open(os.path.join(W, "cert.pem"), "w").write(r.stdout)
text = subprocess.run(["openssl", "x509", "-in", os.path.join(W, "cert.pem"), "-noout", "-text"], capture_output=True,
                      text=True).stdout
check("not a CA (CA:FALSE)", "CA:FALSE" in text and "CA:TRUE" not in text, text[:400])
check("for serving TLS only", "TLS Web Server Authentication" in text, text)
check("exactly the playbook's names, not the request's", "evil.example" not in text and "vault-pi2.pmon.dev" in text
      and "IP Address:127.0.0.1" in text, text)
v = subprocess.run(["openssl", "verify", "-CAfile", os.path.join(W, "ca-cert.pem"), os.path.join(W, "cert.pem")],
                   capture_output=True, text=True)
check("verifies against the CA", v.returncode == 0, v.stdout + v.stderr)
print("vault-csr: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
