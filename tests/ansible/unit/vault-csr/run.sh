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
# the unseal's own check (tasks/vault-unseal.yml) on that chain passes; on a chain whose CA has no keyUsage - one
# that openssl verify passes and Python 3.13 refuses - it fails: the check that guards every unseal checks as strictly
unseal = yaml.safe_load(open("deploy/ansible/playbooks/tasks/vault-unseal.yml"))
vcheck = next(t for t in unseal if str(t.get("name", "")).startswith("Vault's certificate verifies"))["ansible.builtin.shell"]
import shutil
shutil.copy(os.path.join(W, "cert.pem"), os.path.join(W, "tls", "vault-cert.pem"))
def unseal_check(tls):
    return subprocess.run(["bash", "-c", vcheck["cmd"].replace("/etc/vault.d/tls", tls)], capture_output=True,
                          text=True).returncode
check("the unseal's check: the playbook's chain passes", unseal_check(os.path.join(W, "tls")) == 0)
weak = os.path.join(W, "weak")
os.makedirs(weak)
q = lambda *a: subprocess.run(list(a), capture_output=True, text=True, cwd=weak)
q("openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-keyout", "ca.key",
  "-out", "ca-cert.pem", "-days", "2", "-subj", "/CN=weak", "-addext", "basicConstraints=critical,CA:TRUE")
q("openssl", "req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-keyout", "k.pem",
  "-out", "c.csr", "-subj", "/CN=vault")
open(os.path.join(weak, "ext"), "w").write("subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n")
q("openssl", "x509", "-req", "-in", "c.csr", "-CA", "ca-cert.pem", "-CAkey", "ca.key", "-CAcreateserial", "-days", "2",
  "-extfile", "ext", "-out", "vault-cert.pem")
plain = q("openssl", "verify", "-CAfile", "ca-cert.pem", "vault-cert.pem").returncode
weak_rc = unseal_check(weak)
check("the unseal's check: a CA without keyUsage (openssl's plain verify passes it) fails",
      (plain, weak_rc != 0) == (0, True), f"plain verify {plain}, the unseal's check {weak_rc}")
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
# what is checked is what is written: a list the check split otherwise (on blanks, globbing it) than the certificate's
# extension reads it - a tab between two names - refused; a newline (a second line in the extension file) refused
for label, odd in (("a tab between two names", "DNS:a.example\tDNS:b.example"),
                   ("a newline and a second name", "DNS:a.example\nDNS:b.example")):
    odd_sans = sans[:2] + [odd]
    script_odd = render(task["ansible.builtin.shell"], _sans=odd_sans).replace(
        "/etc/vault.d/tls", os.path.join(W, "tls")).replace("/etc/vault-ca", os.path.join(W, "ca"))
    env_odd = {k: render(str(v), _sans=odd_sans) for k, v in (task.get("environment") or {}).items()}
    r = subprocess.run(["bash", "-c", script_odd], input=csr, capture_output=True, text=True,
                       env=dict(os.environ, **env_odd))
    check(f"{label}: refused, nothing signed", r.returncode != 0 and "BEGIN CERTIFICATE" not in r.stdout
          and "REFUSED" in r.stdout + r.stderr, r.stdout[-200:] + r.stderr[-200:])
# the node's address from the inventory, not a fact the other Pi reports: pi1's CA signs what pi2's facts say
node_ip = next(p for p in plays if "node_ip" in (p.get("vars") or {}))["vars"]["node_ip"]
check("the node's address the inventory's (a forged default-IPv4 fact ignored)",
      render(node_ip, ansible_host="192.168.11.6", ansible_default_ipv4={"address": "6.6.6.6"}) == "192.168.11.6",
      node_ip)
# Vault's own user owns its data only: the config, the TLS directory and its files are root's (a compromised Vault
# swapped the CA its unseal script trusts, or its own config); the CA's directory is root-only
owned = []
def walk(ts):
    for t in ts or []:
        for k in ("block", "rescue", "always"):
            walk(t.get(k))
        f = t.get("ansible.builtin.file") or t.get("ansible.builtin.copy") or {}
        # each loop item rendered (its path and owner may be the item's: {{ item.owner }}), or the task alone; what
        # needs more than the item (a fact, an inventory variable) kept as written
        def soft(text, item):
            try:
                return str(render(str(text or ""), item=item))
            except Exception:
                return str(text or "")
        for item in (t.get("loop") if isinstance(t.get("loop"), list) else [None]):
            path = soft(f.get("path") or f.get("dest"), item)
            owner = soft(f.get("owner"), item)
            if owner == "vault" and path.startswith("/etc/vault.d"):
                owned.append(f"{t.get('name')}: {path}")
for p in plays:
    walk(p.get("tasks"))
check("nothing under /etc/vault.d Vault's own", owned == [], owned)
ca_dir = next((t for t in tasks if (t.get("ansible.builtin.file") or {}).get("path") == "/etc/vault-ca"), {})
check("the CA's directory root-only", (ca_dir.get("ansible.builtin.file") or {}).get("mode") == "0700"
      and (ca_dir.get("ansible.builtin.file") or {}).get("owner") == "root", ca_dir)
# the CA's files on pi1 (the CA's Pi): its directory, the move of production's key and serial out of Vault's TLS
# directory, and the key root's alone - each delegated to pi1, once: a run limited to pi2 signed with a key no task
# had moved. Moved, production's key kept Vault's user as its owner (vault:vault 0400 there, checked 2026-10-08)
on_pi1 = lambda t: t.get("delegate_to") == "pi1" and t.get("run_once") is True
move = next((t for t in tasks if "/etc/vault-ca/" in str(t.get("ansible.builtin.shell", ""))
             and "mv -n" in str(t.get("ansible.builtin.shell", ""))), None)
key = next((t for t in tasks if (t.get("ansible.builtin.file") or {}).get("path") == "/etc/vault-ca/ca-key.pem"), None)
check("the CA's directory, the move and the key's owner each on pi1, once",
      all(x is not None and on_pi1(x) for x in (ca_dir, move, key)), [ca_dir.get("name"), (move or {}).get("name"),
                                                                       (key or {}).get("name")])
kf = (key or {}).get("ansible.builtin.file") or {}
check("the CA's key root's alone, read-only", (kf.get("owner"), kf.get("group"), kf.get("mode")) == ("root", "root", "0400"),
      kf)
check("its owner set after the CA is made (a first install's key exists only then)", key is not None
      and tasks.index(key) > tasks.index(make_ca), "")
if move:
    old, new = os.path.join(W, "old-tls"), os.path.join(W, "new-ca")
    os.makedirs(old); os.makedirs(new)
    for f, body in (("ca-key.pem", "KEY"), ("ca-cert.srl", "0A")):
        open(os.path.join(old, f), "w").write(body)
    sh = move["ansible.builtin.shell"]
    sh = (sh if isinstance(sh, str) else sh["cmd"]).replace("/etc/vault.d/tls", old).replace("/etc/vault-ca", new)
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True)
    check("production's key and serial moved beside each other, out of Vault's directory", r.returncode == 0
          and sorted(os.listdir(new)) == ["ca-cert.srl", "ca-key.pem"] and os.listdir(old) == [], r.stderr)
    # a key in both places: the same - the copy Vault can read removed; another - refused, both kept (which one signed
    # the CA is the operator's to say)
    open(os.path.join(old, "ca-key.pem"), "w").write("KEY")
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True)
    got = (r.returncode, os.path.exists(os.path.join(old, "ca-key.pem")), open(os.path.join(new, "ca-key.pem")).read())
    check("the same key in Vault's directory too: that copy removed, the root-only one kept", got == (0, False, "KEY"),
          (got, r.stdout, r.stderr))
    open(os.path.join(old, "ca-key.pem"), "w").write("OTHER")
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True)
    got = (r.returncode != 0, "REFUSED" in r.stdout + r.stderr, open(os.path.join(old, "ca-key.pem")).read(),
           open(os.path.join(new, "ca-key.pem")).read())
    check("another key in Vault's directory: refused, both kept, the root-only one never overwritten",
          got == (True, True, "OTHER", "KEY"), (got, r.stdout, r.stderr))
    os.remove(os.path.join(old, "ca-key.pem"))
# a CA key on another Pi, where Vault can read it: refused
other = next((t for t in tasks if "ca-key.pem" in str(t.get("ansible.builtin.shell", "")) and "pi1" in str(t.get("when", ""))),
             None)
check("a CA key in another Pi's Vault directory: a task refuses it", other is not None, "")
if other:
    tls = os.path.join(W, "pi2-tls"); os.makedirs(tls)
    sh2 = other["ansible.builtin.shell"]
    sh2 = (sh2 if isinstance(sh2, str) else sh2["cmd"]).replace("/etc/vault.d/tls", tls)
    r = subprocess.run(["bash", "-c", sh2], capture_output=True, text=True)
    check("none there: passes", r.returncode == 0, r.stderr)
    open(os.path.join(tls, "ca-key.pem"), "w").write("KEY")
    r = subprocess.run(["bash", "-c", sh2], capture_output=True, text=True)
    got = (r.returncode != 0, "REFUSED" in r.stdout + r.stderr, os.path.exists(os.path.join(tls, "ca-key.pem")))
    check("one there: refused, left as it is", got == (True, True, True), got)
print("vault-csr: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
