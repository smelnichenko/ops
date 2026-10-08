#!/bin/bash
# bootstrap.sh vault-eso against stubs - kubectl (the cluster: its CA), ssh (the Pi: `sudo cat` of Vault's CA, and the
# remote script run here with its root files moved) and vault (its arguments, its environment and the files it reads
# recorded): the cluster trusts the CA read from the Pi now (a "cached" one in world-writable /tmp was any local user's
# to plant); no reviewer token - Vault reviews External Secrets' short-lived token with that token itself (its account
# bound to system:auth-delegator), so no non-expiring token of that account is made, read or kept in Vault's config
# (one was: anyone reading it was External Secrets, every secret it may read); Vault verified against its CA, not
# skipped; a failure on the Pi fails the step (it warned and went on). Only on the cluster that Vault serves: a kube
# context on another refuses before any write. Then External Secrets' login on that config proven - one ExternalSecret,
# Ready before the switch (picked before any write), refreshed after it, Ready - before production's old reviewer token
# (a non-expiring token of External Secrets' own account, one that reads every Secret) is deleted. Not proven: Vault's
# config as it was put back - read before the write, its reviewer token from the kept Secret - and External Secrets'
# login on it proven again. None Ready before (a rebuilt cluster, DR step 5: Vault's config names the old cluster's CA,
# every ExternalSecret fails): nothing logs in to lose - switched all the same, proven by any ExternalSecret, nothing
# put back (the old config did not work either). Every read checked: a failed one is never "nothing there".
# tests/ansible/upgrade/isolate-cluster.yml writes the same configuration to the Vagrant Vault.
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
  "apply -f -") n=\$(( \$(cat "$W/applies" 2> /dev/null || echo 0) + 1 )); echo \$n > "$W/applies"
    if [ -n "\${APPLY_FAILS:-}" ] || [ "\${APPLY_FAILS_AT:-0}" = "\$n" ]; then
      echo "error: the server is currently unable to handle the request" >&2; exit 1
    fi
    { cat; echo ---; } >> "$W/applied" ;;
  "get externalsecret -A -o jsonpath="*) [ -z "\${ES_LIST_FAILS:-}" ] || { echo "error: etcdserver: request timed out" >&2; exit 1; }
    [ -n "\${ES_NONE:-}" ] || printf 'cert-manager/porkbun-secret-es %s\nargocd/x %s\n' "\${ES_FIRST:-True}" "\${ES_SECOND:-True}" ;;
  "-n "*" get externalsecret "*" -o jsonpath="*)
    n=\$(( \$(cat "$W/es-reads" 2> /dev/null || echo 0) + 1 )); echo \$n > "$W/es-reads"
    [ "\${ES_READ_FAILS_AT:-0}" != "\$n" ] || { echo "error: the server is currently unable to handle the request" >&2; exit 1; }
    # after the rollback (Vault's config written back), the login works again unless ROLLBACK_LOGIN=no
    # "<refresh time> <syncedResourceVersion> <Ready>": the version changes once a reconcile saw the force-sync annotation
    # (Inflight: one already running refreshes - a new time - with the version from before the annotation)
    if [ -e "$W/rolled-back" ] && [ -e "$W/annotated-again" ]; then
      [ "\${ROLLBACK_LOGIN:-yes}" = yes ] && echo "2026-10-08T03:00:00Z 1-ccc True" || echo "2026-10-08T01:00:00Z 1-aaa False"
    elif [ ! -e "$W/annotated" ] || [ "\${ES_READY:-True}" = Stale ]; then echo "2026-10-08T01:00:00Z 1-aaa True"
    elif [ "\${ES_READY:-True}" = True ]; then echo "2026-10-08T02:00:00Z 1-bbb True"
    elif [ "\${ES_READY:-True}" = Inflight ]; then echo "2026-10-08T02:00:00Z 1-aaa True"
    elif [ "\${ES_READY:-True}" = Moved ]; then echo "2026-10-08T02:00:00Z 1-bbb False"
    else echo "2026-10-08T01:00:00Z 1-aaa False"; fi ;;
  "-n "*" annotate externalsecret "*" force-sync="*" --overwrite")
    [ ! -e "$W/annotated" ] || touch "$W/annotated-again"; touch "$W/annotated"; echo "\$2/\$5" >> "$W/annotated-es" ;;
  "-n external-secrets get secret vault-token-reviewer --ignore-not-found -o name")
    [ -n "\${NO_TOKEN_SECRET:-}" ] || echo "secret/vault-token-reviewer" ;;
  "-n external-secrets delete secret vault-token-reviewer --ignore-not-found")
    [ -n "\${NO_TOKEN_SECRET:-}" ] || echo 'secret "vault-token-reviewer" deleted' ;;
  *certificate-authority-data*) if [ -n "\${CA_RAW:-}" ]; then printf '%s' "\$CA_RAW"
    else printf '%s' "\$(printf 'THE CLUSTER CA' | base64 -w0)"; fi ;;
  *cluster.server*) printf '%s' "\${SERVER:-https://192.168.11.2:6443}" ;;
  *"get secret vault-token-reviewer"*) [ -z "\${NO_TOKEN_SECRET:-}" ] || exit 1
    printf '%s' "\$(printf '%s' "$JWT" | base64 -w0)" ;;
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
for a; do case "\$a" in *=@*) echo "\${a%%=@*} \$(cat "\${a#*=@}")" >> "$W/vault-files" ;;
  @*) cat "\${a#@}" >> "$W/vault-json"; echo >> "$W/vault-json"; touch "$W/rolled-back" ;; esac; done
if [ "\$*" = "read -format=json auth/kubernetes/config" ]; then
  case "\${OLD_CONFIG:-there}" in
    there) echo '{"data": {"kubernetes_host": "https://192.168.11.2:6443", "kubernetes_ca_cert": "OLD CA",'
      echo '  "disable_local_ca_jwt": false, "issuer": "", "pem_keys": [], "token_reviewer_jwt_set": true}}' ;;
    none) echo "No value found at auth/kubernetes/config" >&2; exit 2 ;;
    error) echo "Error reading auth/kubernetes/config: 403 permission denied" >&2; exit 2 ;;
  esac
  exit 0
fi
[ -z "\${VAULT_FAIL:-}" ] || { echo "Error writing data: 403" >&2; exit 2; }
STUB
chmod +x "$W/bin"/*
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1))
}
run() {  # run <env...>: bootstrap.sh vault-eso, its exit in $rc; its temp files under $W/tmp
  rm -rf "$W"/{kubectl-calls,applied,applies,annotated,annotated-again,annotated-es,es-reads,rolled-back,ssh-argv} \
    "$W"/{vault-argv,vault-env,vault-files,vault-json,tmp} "$W"/pwned-*
  mkdir "$W/tmp"
  out=$(env "$@" PATH="$W/bin:$PATH" INFRA_DIR="$W/infra" VAULT_PI=pi.test TMPDIR="$W/tmp" ESO_PROOF_SECONDS=1 ESO_SETTLE_SECONDS=0 \
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
  "$(grep -c 'kubernetes.io/service-account-token' "$W/applied") $(grep 'get secret' "$W/kubectl-calls" | grep -vc ' -o name$')" \
  "0 0"
check "its account may review tokens (system:auth-delegator) - Vault reviews its token with that token" \
  "$(sed -n '/kind: ClusterRoleBinding/,/^---$/p' "$W/applied" | tr -d ' ' | grep -cE '^name:(system:auth-delegator|external-secrets)$|^namespace:external-secrets$')" 3
check "Vault's config: no reviewer token, the client's own used (disable_local_ca_jwt), the cluster's CA from a file" \
  "$(grep -c token_reviewer_jwt "$W/vault-argv" "$W/vault-files" | awk -F: '{s += $2} END {print s}') \
$(grep -c 'auth/kubernetes/config .*disable_local_ca_jwt=true' "$W/vault-argv") \
$(grep -c '^kubernetes_ca_cert THE CLUSTER CA$' "$W/vault-files")" "0 1 1"
check "Vault verified against its CA by every call, never skipped" \
  "$(grep -c '^VAULT_SKIP_VERIFY' "$W/vault-env") $(grep -c "^VAULT_CACERT=$W/pi/etc/vault.d/tls/ca-cert.pem$" "$W/vault-env")" \
  "0 $(wc -l < "$W/vault-argv")"
check "the role written" "$(grep -c 'auth/kubernetes/role/eso-role' "$W/vault-argv")" 1
check "its work directory gone when it ends" "$(ls -A "$W/tmp" | wc -l)" 0
# the switch: External Secrets' login on the new config proven, then the old reviewer token deleted - in that order
order() { grep -nE 'annotate externalsecret|delete secret vault-token-reviewer' "$W/kubectl-calls" | cut -d' ' -f2-4 | tr '\n' ','; }
check "after Vault's write: one ExternalSecret refreshed now (force-sync), then the old reviewer token deleted, said" \
  "$(order) $(grep -c 'old reviewer token .*deleted' <<< "$out")" \
  "-n cert-manager annotate,-n external-secrets delete, 1"
check "the new config written after the old one read (to put back)" \
  "$(grep -nE '^vault (read -format=json|write) auth/kubernetes/config' "$W/vault-argv" | cut -d' ' -f2 | tr '\n' ,)" "read,write,"
run ES_READY=False
check "External Secrets not logging in on the new config: the step fails, said so, the old token kept" \
  "$rc $(grep -c 'delete secret' "$W/kubectl-calls") $(grep -c 'NOT proven' <<< "$out")" "1 0 1"
check "... Vault's config put back as it was read - its reviewer token (the kept Secret's) with it - the login on it proven again" "$(python3 -c '
import json, sys
d = json.loads(open(sys.argv[1]).read())
print(d.get("kubernetes_ca_cert"), d.get("token_reviewer_jwt") == sys.argv[2], "token_reviewer_jwt_set" in d,
      d.get("disable_local_ca_jwt"))' "$W/vault-json" "$JWT" 2> /dev/null) $(grep -c 'put back as it was' <<< "$out") \
$(grep -c 'logs in on the config put back' <<< "$out")" "OLD CA True False False 1 1"
check "... the reviewer token on no command line (the Pi's script on ssh's stdin)" \
  "$(grep -c "$JWT" "$W/ssh-argv" "$W/vault-argv" | awk -F: '{s += $2} END {print s}')" 0
run ES_READY=False ROLLBACK_LOGIN=no
check "... the login failing on the config put back too: the step fails, said so" \
  "$rc $(grep -c 'NOT even on the config put back' <<< "$out")" "1 1"
run ES_READY=False NO_TOKEN_SECRET=1 ES_NONE=
check "... no reviewer token to put back: nothing written back, said, the step fails" \
  "$rc $(test -e "$W/vault-json" && echo written || echo none) $(grep -c 'NOT put back' <<< "$out")" "1 none 1"
run ES_READY=False OLD_CONFIG=none
check "... no config there before (a fresh Vault): nothing to put back, said, the step fails" \
  "$rc $(test -e "$W/vault-json" && echo written || echo none) $(grep -c 'NOT put back' <<< "$out")" "1 none 1"
run OLD_CONFIG=error
check "the config before not read (an error, not 'none'): the step fails before any write" \
  "$rc $(cat "$W/vault-argv" 2> /dev/null | grep -c '^vault write')" "1 0"
# the ExternalSecret proving it: one Ready before the switch, picked before any write
run ES_FIRST=False
check "the first ExternalSecret not Ready before the switch: the next Ready one proves it" \
  "$rc $(cat "$W/annotated-es" 2> /dev/null)" "0 argocd/x"
# none Ready before the switch - a rebuilt cluster (DR step 5): switched all the same, proven by an ExternalSecret
run ES_FIRST=False ES_SECOND=False NO_TOKEN_SECRET=1
check "none Ready before the switch (a rebuilt cluster): switched, proven by one of them refreshed and Ready; passes" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(grep -c '^vault write auth/kubernetes/config' "$W/vault-argv") \
$(cat "$W/annotated-es" 2> /dev/null | head -1)" "0 1 1 cert-manager/porkbun-secret-es"
run ES_FIRST=False ES_SECOND=False ES_READY=False
check "none Ready before, not proven after: the step fails, said - nothing put back (the old config did not work either)" \
  "$rc $(test -e "$W/vault-json" && echo put-back || echo none) $(grep -c 'NOT proven' <<< "$out")" "1 none 1"
run ES_LIST_FAILS=1
check "the ExternalSecrets not listed (an error, not 'none'): the step fails before any write, the token kept" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(grep -c 'delete secret' "$W/kubectl-calls")" "1 0 0"
run ES_LIST_FAILS=1 NO_TOKEN_SECRET=1
check "... and no old token either: still an error, never a fresh cluster - nothing written" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(grep -c 'fresh cluster' <<< "$out")" "1 0 0"
run ES_READ_FAILS_AT=1
check "its refresh time before not read: the step fails, never 'refreshed' - the old token kept" \
  "$rc $(grep -c 'delete secret' "$W/kubectl-calls")" "1 0"
run ES_READY=Stale
check "not refreshed (Ready from before, its refresh time unchanged): the step fails, the old token kept" \
  "$rc $(grep -c 'delete secret' "$W/kubectl-calls")" "1 0"
run ES_READY=Moved
check "refreshed but not Ready: the step fails, the old token kept" "$rc $(grep -c 'delete secret' "$W/kubectl-calls")" "1 0"
run ES_READY=Inflight
check "a sync already running at the write refreshing (a new time, the version before the annotation): no proof, fails" "$rc $(grep -c 'delete secret' "$W/kubectl-calls")" "1 0"
run ES_NONE=1 NO_TOKEN_SECRET=1
check "no ExternalSecret yet (a fresh cluster), no old token: passes, said" \
  "$rc $(grep -c 'delete secret' "$W/kubectl-calls") $(grep -c 'no ExternalSecret' <<< "$out")" "0 0 1"
run ES_NONE=1
check "no ExternalSecret to prove the login with, the old token there: fails, the token kept" \
  "$rc $(grep -c 'delete secret' "$W/kubectl-calls")" "1 0"
# only on the cluster Vault serves: a kube context left on another wrote that one into production's Vault
run SERVER=https://10.9.9.9:6443
check "a kube context on another cluster: refused before any write - nothing applied, nothing sent to the Pi" \
  "$rc $(cat "$W/applies" 2> /dev/null || echo 0) $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(grep -c 'REFUSED' <<< "$out")" \
  "1 0 0 1"
run SERVER=https://10.9.9.9:6443 K8S_EXPECTED=https://10.9.9.9:6443
check "another pairing named (K8S_EXPECTED): passes" "$rc" 0
run APPLY_FAILS_AT=2
check "only the ClusterRoleBinding's apply failing: the step fails, said so, nothing sent to the Pi" \
  "$rc $(grep -c "ClusterRoleBinding" <<< "$out") $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s')" "1 1 0"
# what goes into the script run as root on the Pi, checked first: the cluster CA as base64 alone (a line of its own
# ended the script's heredoc, the rest ran as root), the server a plain https URL
run CA_RAW=$'QUJD\nB64\n'"touch $W/pwned-by-ca"$'\n'
check "a cluster CA that is not base64: the step fails, nothing sent to the Pi, nothing run" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(ls "$W"/pwned-* 2> /dev/null | wc -l)" "1 0 0"
# a step that fails says so and goes no further: bootstrap.sh runs without set -e, and a failed apply went by
# unnoticed - the step went on
run APPLY_FAILS=1
check "the cluster's apply failing: the step fails, said so, nothing sent to the Pi" \
  "$rc $(grep -c "vault-pi-ca\|vault-eso failed" <<< "$out") $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s')" "1 2 0"
run SERVER="https://192.168.11.2:6443' ; touch $W/pwned-by-server ; '"
check "a server that is not a plain https URL: the step fails, nothing sent to the Pi, nothing run" \
  "$rc $(cat "$W/ssh-argv" 2> /dev/null | grep -c 'bash -s') $(ls "$W"/pwned-* 2> /dev/null | wc -l)" "1 0 0"
run VAULT_FAIL=1
check "a failure on the Pi: the step fails, said so" "$rc $(grep -c "Kubernetes auth on the Pi failed" <<< "$out")" "1 1"
# the Vagrant Vault configured as ten's: the same keys in the same write, the same account bound, no token Secret
keys() { grep -oE '(kubernetes_host|kubernetes_ca_cert|token_reviewer_jwt|disable_local_ca_jwt|issuer|pem_keys)=' | sort -u | tr -d '\n'; }
iso=tests/ansible/upgrade/isolate-cluster.yml
check "isolate-cluster.yml writes Vault's Kubernetes auth with bootstrap.sh's keys" \
  "$(sed -n '/vault write auth\/kubernetes\/config/,/> \/dev\/null/p' "$iso" | keys)" \
  "$(sed -n '/^vault write auth\/kubernetes\/config/,/> \/dev\/null/p' bootstrap.sh | keys)"
check "isolate-cluster.yml: no non-expiring token Secret, none read; External Secrets' account bound to system:auth-delegator" \
  "$(grep -c 'service-account-token\|get secret vault-token-reviewer' "$iso") $(python3 -c '
import sys, yaml
crbs = [t["kubernetes.core.k8s"]["definition"] for p in yaml.safe_load(open(sys.argv[1])) for t in p.get("tasks") or []
        if (t.get("kubernetes.core.k8s") or {}).get("definition", {}).get("kind") == "ClusterRoleBinding"]
print(sorted((c["roleRef"]["name"], s["kind"], s.get("namespace"), s["name"]) for c in crbs for s in c["subjects"]))' "$iso")" \
  "0 [('system:auth-delegator', 'ServiceAccount', 'external-secrets', 'external-secrets')]"
check "isolate-cluster.yml: the Vagrant Vault verified against its CA, as ten's; the cluster CA in no fixed /tmp file" \
  "$(grep -c 'VAULT_SKIP_VERIFY' "$iso") $(grep -c 'VAULT_CACERT=/etc/vault.d/tls/ca-cert.pem' "$iso") \
$(sed -n '/Configure Kubernetes auth in the Vagrant Vault/,$p' "$iso" | grep -c '/tmp/')" "0 1 0"
# the task that runs it on production: said so, asked first (it switches every ExternalSecret's login)
check "deploy:vault-eso: says PRODUCTION, asks first, runs this step" "$(python3 -c '
import yaml
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]["deploy:vault-eso"]
print(str(t.get("desc", "")).startswith("PRODUCTION"), "PRODUCTION" in str(t.get("prompt", "")),
      [str(c) for c in t.get("cmds", [])] == ["./bootstrap.sh vault-eso"])')" "True True True"
echo "bootstrap-vault-eso: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
