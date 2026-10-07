#!/bin/bash
# bootstrap.sh vault-eso against stubs - kubectl (the cluster: its CA, the reviewer token once its controller filled
# it), ssh (the Pi: `sudo cat` of Vault's CA, and the remote script run here with its root files moved) and vault
# (its arguments, its environment and the files it reads recorded): the cluster trusts the CA read from the Pi now
# (a "cached" one in world-writable /tmp was any local user's to plant); the reviewer token waited for, then reaching
# the Pi on ssh's stdin and Vault from a root-only file - on no command line (ssh's here, sudo's and vault's there:
# /proc); Vault verified against its CA, not skipped; a failure on the Pi fails the step (it warned and went on).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/infra/clusters/production" "$W/pi/etc/vault-unseal" "$W/pi/etc/vault.d/tls"
echo "THE-ROOT-TOKEN" > "$W/pi/etc/vault-unseal/root-token"
echo "THE PI'S VAULT CA" > "$W/pi/etc/vault.d/tls/ca-cert.pem"
JWT="eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJlc28ifQ.c2lnbmF0dXJl"
cat > "$W/bin/kubectl" <<STUB
#!/bin/bash
echo "kubectl \$*" >> "$W/kubectl-calls"
case "\$*" in
  "apply -f -") cat >> "$W/applied" ;;
  *certificate-authority-data*) printf '%s' "\$(printf 'THE CLUSTER CA' | base64 -w0)" ;;
  *cluster.server*) printf 'https://192.168.11.2:6443' ;;
  *"get secret vault-token-reviewer"*)
    n=\$(grep -c "get secret vault-token-reviewer" "$W/kubectl-calls")
    [ "\$n" -ge "\${TOKEN_FROM:-1}" ] && printf '%s' "\$(printf '%s' "$JWT" | base64 -w0)" ;;
esac
exit 0
STUB
# the Pi: its argv recorded; `sudo cat` answers its CA; `sudo bash -s` runs the script here, its root files moved
cat > "$W/bin/ssh" <<STUB
#!/bin/bash
echo "ssh \$*" >> "$W/ssh-argv"
case "\${@: -1}" in
  "sudo cat /etc/vault.d/tls/ca-cert.pem") cat "$W/pi/etc/vault.d/tls/ca-cert.pem" ;;
  "sudo bash -s") sed "s|/etc/vault|$W/pi/etc/vault|g" | bash -s ;;
  *) echo "unexpected: \$*" >&2; exit 9 ;;
esac
STUB
cat > "$W/bin/vault" <<STUB
#!/bin/bash
echo "vault \$*" >> "$W/vault-argv"
env | grep '^VAULT_' >> "$W/vault-env"
for a; do case "\$a" in *=@*) echo "\${a%%=@*} \$(cat "\${a#*=@}")" >> "$W/vault-files" ;; esac; done
[ -z "\${VAULT_FAIL:-}" ] || { echo "Error writing data: 403" >&2; exit 2; }
STUB
chmod +x "$W/bin"/*
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1))
}
run() {  # run <env...>: bootstrap.sh vault-eso, its exit in $rc
  rm -f "$W"/{kubectl-calls,applied,ssh-argv,vault-argv,vault-env,vault-files}
  out=$(env "$@" PATH="$W/bin:$PATH" INFRA_DIR="$W/infra" VAULT_PI=pi.test bash bootstrap.sh vault-eso 2>&1); rc=$?
}
# first, and without running it otherwise: a step that keeps anything in /tmp would write the real one here
check "nothing of it kept in /tmp (the CA a cache any local user plants)" \
  "$(sed -n '/^setup_vault_eso()/,/^}/p' bootstrap.sh | grep -c '/tmp')" 0
[ "$fails" = 0 ] || { echo "bootstrap-vault-eso: $fails FAILED (not run: it would write /tmp)"; exit 1; }
run TOKEN_FROM=3
check "the step passes" "$rc" 0
check "the cluster trusts the CA read from the Pi now" \
  "$(grep -c "ca.crt: $(base64 -w0 < "$W/pi/etc/vault.d/tls/ca-cert.pem")" "$W/applied")" 1
check "the reviewer token waited for (its controller fills it after the Secret)" \
  "$(grep -c 'get secret vault-token-reviewer' "$W/kubectl-calls")" 3
check "the token on no command line - ssh's here, vault's on the Pi" \
  "$(cat "$W/ssh-argv" "$W/vault-argv" | grep -c "$JWT")" 0
check "Vault reads it from a file, with the cluster's CA" \
  "$(grep -c "^token_reviewer_jwt $JWT$" "$W/vault-files") $(grep -c '^kubernetes_ca_cert THE CLUSTER CA$' "$W/vault-files")" \
  "1 1"
check "Vault verified against its CA, never skipped" \
  "$(grep -c '^VAULT_SKIP_VERIFY' "$W/vault-env") $(grep -c "^VAULT_CACERT=$W/pi/etc/vault.d/tls/ca-cert.pem$" "$W/vault-env")" \
  "0 2"
check "the role written" "$(grep -c 'auth/kubernetes/role/eso-role' "$W/vault-argv")" 1
run VAULT_FAIL=1
check "a failure on the Pi: the step fails, said so" "$rc $(grep -c 'failed' <<< "$out")" "1 1"
run TOKEN_FROM=999
check "no reviewer token at all: the step fails, nothing sent to the Pi" "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s')" "1 0"
echo "bootstrap-vault-eso: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
