#!/bin/bash
# bootstrap.sh vault-eso against stubs - kubectl (the cluster: its CA), ssh (the Pi: `sudo cat` of Vault's CA, and the
# remote script run here with its root files moved) and vault (its arguments, its environment and the files it reads
# recorded): the cluster trusts the CA read from the Pi now (a "cached" one in world-writable /tmp was any local user's
# to plant); no reviewer token - Vault reviews External Secrets' short-lived token with that token itself (its account
# bound to system:auth-delegator), so no non-expiring token of that account is made, read or kept in Vault's config
# (one was: anyone reading it was External Secrets, every secret it may read); Vault verified against its CA, not
# skipped; a failure on the Pi fails the step (it warned and went on). tests/ansible/upgrade/isolate-cluster.yml writes
# the same configuration to the Vagrant Vault.
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
  "apply -f -") { cat; echo ---; } >> "$W/applied" ;;
  *certificate-authority-data*) if [ -n "\${CA_RAW:-}" ]; then printf '%s' "\$CA_RAW"
    else printf '%s' "\$(printf 'THE CLUSTER CA' | base64 -w0)"; fi ;;
  *cluster.server*) printf '%s' "\${SERVER:-https://192.168.11.2:6443}" ;;
  *"get secret vault-token-reviewer"*) printf '%s' "\$(printf '%s' "$JWT" | base64 -w0)" ;;
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
run() {  # run <env...>: bootstrap.sh vault-eso, its exit in $rc; its temp files under $W/tmp
  rm -rf "$W"/{kubectl-calls,applied,ssh-argv,vault-argv,vault-env,vault-files,tmp} "$W"/pwned-*; mkdir "$W/tmp"
  out=$(env "$@" PATH="$W/bin:$PATH" INFRA_DIR="$W/infra" VAULT_PI=pi.test TMPDIR="$W/tmp" \
    bash bootstrap.sh vault-eso 2>&1); rc=$?
}
# first, and without running it otherwise: a step that keeps anything in /tmp would write the real one here
check "nothing of it kept in /tmp (the CA a cache any local user plants)" \
  "$(sed -n '/^setup_vault_eso()/,/^}/p' bootstrap.sh | grep -c '/tmp')" 0
[ "$fails" = 0 ] || { echo "bootstrap-vault-eso: $fails FAILED (not run: it would write /tmp)"; exit 1; }
run
check "the step passes" "$rc" 0
check "the cluster trusts the CA read from the Pi now" \
  "$(grep -c "ca.crt: $(base64 -w0 < "$W/pi/etc/vault.d/tls/ca-cert.pem")" "$W/applied")" 1
check "no non-expiring token of External Secrets' account made, none read" \
  "$(grep -c 'kubernetes.io/service-account-token' "$W/applied") $(grep -c 'get secret' "$W/kubectl-calls")" "0 0"
check "its account may review tokens (system:auth-delegator) - Vault reviews its token with that token" \
  "$(sed -n '/kind: ClusterRoleBinding/,/^---$/p' "$W/applied" | tr -d ' ' | grep -cE '^name:(system:auth-delegator|external-secrets)$|^namespace:external-secrets$')" 3
check "Vault's config: no reviewer token, the client's own used (disable_local_ca_jwt), the cluster's CA from a file" \
  "$(grep -c token_reviewer_jwt "$W/vault-argv" "$W/vault-files" | awk -F: '{s += $2} END {print s}') \
$(grep -c 'auth/kubernetes/config .*disable_local_ca_jwt=true' "$W/vault-argv") \
$(grep -c '^kubernetes_ca_cert THE CLUSTER CA$' "$W/vault-files")" "0 1 1"
check "Vault verified against its CA, never skipped" \
  "$(grep -c '^VAULT_SKIP_VERIFY' "$W/vault-env") $(grep -c "^VAULT_CACERT=$W/pi/etc/vault.d/tls/ca-cert.pem$" "$W/vault-env")" \
  "0 2"
check "the role written" "$(grep -c 'auth/kubernetes/role/eso-role' "$W/vault-argv")" 1
check "its work directory gone when it ends" "$(ls -A "$W/tmp" | wc -l)" 0
# what goes into the script run as root on the Pi, checked first: the cluster CA as base64 alone (a line of its own
# ended the script's heredoc, the rest ran as root), the server a plain https URL
run CA_RAW=$'QUJD\nB64\n'"touch $W/pwned-by-ca"$'\n'
check "a cluster CA that is not base64: the step fails, nothing sent to the Pi, nothing run" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(ls "$W"/pwned-* 2> /dev/null | wc -l)" "1 0 0"
run SERVER="https://192.168.11.2:6443' ; touch $W/pwned-by-server ; '"
check "a server that is not a plain https URL: the step fails, nothing sent to the Pi, nothing run" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(ls "$W"/pwned-* 2> /dev/null | wc -l)" "1 0 0"
run VAULT_FAIL=1
check "a failure on the Pi: the step fails, said so" "$rc $(grep -c 'failed' <<< "$out")" "1 1"
# the Vagrant Vault configured as ten's: the same keys in the same write, the same account bound, no token Secret
keys() { grep -oE '(kubernetes_host|kubernetes_ca_cert|token_reviewer_jwt|disable_local_ca_jwt|issuer|pem_keys)=' | sort -u | tr -d '\n'; }
iso=tests/ansible/upgrade/isolate-cluster.yml
check "isolate-cluster.yml writes Vault's Kubernetes auth with bootstrap.sh's keys" \
  "$(sed -n '/vault write auth\/kubernetes\/config/,/> \/dev\/null/p' "$iso" | keys)" \
  "$(sed -n '/^vault write auth\/kubernetes\/config/,/> \/dev\/null/p' bootstrap.sh | keys)"
check "isolate-cluster.yml: no non-expiring token Secret, none read; the account bound to system:auth-delegator" \
  "$(grep -c 'service-account-token\|get secret vault-token-reviewer' "$iso") $(grep -c 'name: system:auth-delegator' "$iso")" "0 1"
check "isolate-cluster.yml: the Vagrant Vault verified against its CA, as ten's; the cluster CA in no fixed /tmp file" \
  "$(grep -c 'VAULT_SKIP_VERIFY' "$iso") $(grep -c 'VAULT_CACERT=/etc/vault.d/tls/ca-cert.pem' "$iso") \
$(sed -n '/Configure Kubernetes auth in the Vagrant Vault/,$p' "$iso" | grep -c '/tmp/')" "0 1 0"
echo "bootstrap-vault-eso: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
