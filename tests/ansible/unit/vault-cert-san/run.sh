#!/bin/bash
# tasks/vault-unseal.yml's check that Vault's certificate names 127.0.0.1 (the unseal script reaches Vault there, the
# certificate checked), as the task holds it, openssl a stub answering the certificate's subjectAltName: 127.0.0.1 at
# the end of the list or before another name passes; 127.0.0.10 or 127.0.0.100 alone does not (an unanchored grep
# passed them - every unseal then failed at the address, both Pis sealed after a power cut).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/openssl" <<'STUB'
#!/bin/bash
case "$1" in
  verify) exit 0 ;;
  x509) printf 'X509v3 Subject Alternative Name: \n    %s\n' "$SAN" ;;
esac
STUB
chmod +x "$W/bin/openssl"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYSAN'
import os, subprocess, sys
import yaml
W = os.environ["W"]
task = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/tasks/vault-unseal.yml"))
            if "names 127.0.0.1" in t.get("name", ""))
cmd = task["ansible.builtin.shell"]["cmd"]
fails = 0
for san, want in (("DNS:vault.pmon.dev, IP Address:192.168.11.5, IP Address:127.0.0.1", 0),
                  ("IP Address:127.0.0.1, DNS:vault.pmon.dev", 0),
                  ("DNS:vault.pmon.dev, IP Address:127.0.0.10", 1),
                  ("IP Address:127.0.0.100, IP Address:192.168.11.5", 1)):
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], SAN=san))
    ok = min(r.returncode, 1) == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {san}: {'passes' if want == 0 else 'fails'}" + ("" if ok else f" (rc {r.returncode})"))
print("vault-cert-san: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYSAN
