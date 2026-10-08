#!/bin/bash
# Tier 0 Bootstrap: Pre-GitOps components
#
# Deploys infrastructure that must exist before ArgoCD + Forgejo can operate.
# Uses external Helm chart repos (not Forgejo) and local values files.
#
# Prerequisites:
#   - kubeadm cluster running with Cilium CNI
#   - kubectl configured and working
#   - helm installed
#   - INFRA_DIR points to the infra repo (default: /home/sm/src/infra)
#
# Usage:
#   ./bootstrap.sh           # Full bootstrap
#   ./bootstrap.sh cert-manager  # Single component

set -uo pipefail

INFRA_DIR="${INFRA_DIR:-/home/sm/src/infra}"
VALUES_DIR="$INFRA_DIR/clusters/production"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[bootstrap]${NC} $*"; }
warn() { echo -e "${YELLOW}[bootstrap]${NC} $*"; }
err()  { echo -e "${RED}[bootstrap]${NC} $*" >&2; }

wait_for_pods() {
  local ns=$1
  local label=${2:-""}
  local timeout=${3:-120}
  log "Waiting for pods in $ns${label:+ ($label)}..."
  local selector=""
  [[ -n "$label" ]] && selector="-l $label"
  kubectl wait --for=condition=Ready pods $selector -n "$ns" --timeout="${timeout}s" 2>/dev/null || true
}

# --- cert-manager ---
install_cert_manager() {
  log "Installing cert-manager..."
  helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
  helm repo update jetstack
  helm upgrade --install cert-manager jetstack/cert-manager \
    -n cert-manager --create-namespace \
    --version v1.20.0 \
    -f "$VALUES_DIR/cert-manager/values.yaml" \
    --wait --timeout 120s
  log "cert-manager installed"
}

# --- porkbun-webhook ---
install_porkbun_webhook() {
  log "Installing porkbun-webhook..."
  helm repo add porkbun-webhook https://talinx.github.io/cert-manager-webhook-porkbun 2>/dev/null || true
  helm repo update porkbun-webhook
  helm upgrade --install porkbun-webhook porkbun-webhook/cert-manager-webhook-porkbun \
    -n cert-manager \
    --wait --timeout 60s
  log "porkbun-webhook installed"
}

# --- local-path-provisioner ---
install_local_path() {
  log "Installing local-path-provisioner..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  log "local-path-provisioner installed (set as default StorageClass)"
}

# --- external-secrets ---
install_external_secrets() {
  log "Installing external-secrets..."
  helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
  helm repo update external-secrets
  helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace \
    --version 2.2.0 \
    -f "$VALUES_DIR/external-secrets/values.yaml" \
    --set installCRDs=true \
    --wait --timeout 180s
  log "external-secrets installed"
}

# --- istio ---
install_istio() {
  log "Installing Istio..."

  # Gateway API CRDs (required for Istio Gateway resources)
  log "Installing Gateway API CRDs..."
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml 2>/dev/null || true

  helm repo add istio https://istio-release.storage.googleapis.com/charts 2>/dev/null || true
  helm repo update istio

  helm upgrade --install istio-base istio/base \
    -n istio-system --create-namespace \
    --version 1.25.2 \
    --wait --timeout 60s

  helm upgrade --install istiod istio/istiod \
    -n istio-system \
    --version 1.25.2 \
    -f "$VALUES_DIR/istio/istiod-values.yaml" \
    --wait --timeout 120s

  helm upgrade --install istio-cni istio/cni \
    -n istio-system \
    --version 1.25.2 \
    -f "$VALUES_DIR/istio/cni-values.yaml" \
    --wait --timeout 60s

  # Cilium + Istio coexistence:
  # - cni-exclusive=false: let Istio CNI chain after Cilium
  # - socketLB hostNamespaceOnly: prevent Cilium from DNATing service IPs
  #   in pod namespaces (Envoy needs to see the ClusterIP, not the pod IP)
  if cilium status >/dev/null 2>&1; then
    log "Configuring Cilium for Istio coexistence..."
    kubectl patch configmap cilium-config -n kube-system --type merge \
      -p '{"data":{"cni-exclusive":"false","bpf-lb-sock":"true","bpf-lb-sock-hostns-only":"true"}}' 2>/dev/null || true
    kubectl rollout restart daemonset/cilium -n kube-system
    kubectl rollout status daemonset/cilium -n kube-system --timeout=120s
  fi

  log "Istio installed"
}

# --- velero ---
install_velero() {
  log "Installing Velero..."

  # Create namespace and MinIO deployment first
  kubectl create namespace velero 2>/dev/null || true
  kubectl apply -f "$VALUES_DIR/cluster-config/velero-namespace.yaml" 2>/dev/null || true
  kubectl apply -f "$VALUES_DIR/cluster-config/velero-minio-deployment.yaml" 2>/dev/null || true

  helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts 2>/dev/null || true
  helm repo update vmware-tanzu
  helm upgrade --install velero vmware-tanzu/velero \
    -n velero \
    --version 12.0.0 \
    -f "$VALUES_DIR/velero/values.yaml" \
    --wait --timeout 120s
  log "Velero installed"
}

# --- vault-eso (connect ESO to Pi Vault) ---
setup_vault_eso() {
  log "Configuring ESO → Pi Vault connection..."

  local VAULT_PI="${VAULT_PI:-192.168.11.4}"
  # the cluster that Vault serves (K8S_EXPECTED: another pairing): a kube context left on another wrote that one into
  # production's Vault, and the applies below landed there
  local K8S_EXPECTED="${K8S_EXPECTED:-https://192.168.11.2:6443}"
  local K8S_CA K8S_HOST
  K8S_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}') \
    || { err "Cannot read the cluster's CA from the kubeconfig"; return 1; }
  K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}') \
    || { err "Cannot read the cluster's server from the kubeconfig"; return 1; }
  [[ $K8S_HOST =~ ^https://[A-Za-z0-9.:-]+$ ]] \
    || { err "The cluster's server is not a plain https URL: $K8S_HOST"; return 1; }
  [[ $K8S_HOST == "$K8S_EXPECTED" ]] || {
    err "REFUSED: the kube context's cluster is $K8S_HOST, not $K8S_EXPECTED - the one Vault on $VAULT_PI serves" \
      "(kubectl config use-context; K8S_EXPECTED names another pairing)"
    return 1
  }
  # base64 alone: it goes into the script run as root on the Pi (a line of its own would end that heredoc)
  [[ $K8S_CA =~ ^[A-Za-z0-9+/]+=*$ ]] || { err "The cluster's CA (certificate-authority-data) is not base64"; return 1; }
  # the ExternalSecret that proves External Secrets' login on the new config - one Ready now, picked before anything
  # is written. None Ready (a rebuilt cluster, DR step 5: Vault's config names the old cluster's CA): nothing logs in
  # to lose - switched all the same, proven by one of them, nothing put back
  local es was picked
  picked=$(eso_proof_target) || return 1
  read -r es was <<< "$picked"
  [[ -n $es ]] || log "no ExternalSecret on the store yet (a fresh cluster) - the login is proven when Argo makes them"
  [[ -z $es || $was == ready ]] || warn "no ExternalSecret on the store Ready now (a rebuilt cluster?) - switching" \
    "all the same, proven by $es"
  local work
  work=$(mktemp -d) || return 1
  # this run's own directory, removed however the step ends
  trap 'rm -rf "$work"; trap - RETURN' RETURN

  # Vault's CA read from the Pi now, never a copy kept in a world-writable directory: a planted one made the cluster
  # trust another Vault
  if ! ssh "sm@${VAULT_PI}" "sudo cat /etc/vault.d/tls/ca-cert.pem" > "$work/vault-ca.pem" \
      || [[ ! -s "$work/vault-ca.pem" ]]; then
    err "Cannot read Vault's CA from the Pi (/etc/vault.d/tls/ca-cert.pem)"
    return 1
  fi

  # each step checked and said: bootstrap.sh runs without set -e (`all` goes on past a failed component), and a
  # failed apply went by unnoticed - the Pi's Vault then configured for a cluster that does not trust it
  local VAULT_CA_B64
  VAULT_CA_B64=$(base64 -w0 < "$work/vault-ca.pem") || { err "Cannot encode Vault's CA"; return 1; }

  # Create Vault CA secret in external-secrets namespace
  if ! kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-pi-ca
  namespace: external-secrets
data:
  ca.crt: ${VAULT_CA_B64}
EOF
  then
    err "Cannot apply Secret external-secrets/vault-pi-ca (Vault's CA for ESO)"
    return 1
  fi

  # External Secrets' account may review tokens: Vault (no reviewer token of its own) reviews the short-lived token ESO
  # logs in with by that same token - a non-expiring token of this account, kept in Vault's config, was anyone's who
  # read it to use as External Secrets
  if ! kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-reviewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: external-secrets
    namespace: external-secrets
EOF
  then
    err "Cannot apply ClusterRoleBinding vault-token-reviewer (ESO's tokens reviewed by Vault)"
    return 1
  fi

  # Vault's Kubernetes auth on the Pi: the script on ssh's stdin, the root token read there (on no command line - any
  # local user reads those in /proc), Vault verified against its CA (its certificate names 127.0.0.1); no
  # token_reviewer_jwt - each client's own token reviews itself. The config before printed first - kept here, to put
  # back if External Secrets' login on the new one is not proven (a read failing otherwise than "none" writes
  # nothing); the role before the config, so a failure leaves the config as it was. A failure fails the step
  if ! ssh "sm@${VAULT_PI}" "sudo bash -s" > "$work/config-before.json" <<REMOTE; then
set -euo pipefail
umask 077
d=\$(mktemp -d)
trap 'rm -rf "\$d"' EXIT
base64 -d > "\$d/ca.pem" <<'B64'
${K8S_CA}
B64
export VAULT_ADDR=https://127.0.0.1:8200 VAULT_CACERT=/etc/vault.d/tls/ca-cert.pem
VAULT_TOKEN=\$(cat /etc/vault-unseal/root-token)
export VAULT_TOKEN
if ! before=\$(vault read -format=json auth/kubernetes/config 2> "\$d/err"); then
  grep -q 'No value found' "\$d/err" || { cat "\$d/err" >&2; exit 1; }
  before='{}'
fi
printf '%s\n' "\$before"
vault write auth/kubernetes/role/eso-role bound_service_account_names=external-secrets \\
  bound_service_account_namespaces=external-secrets policies=eso-reader ttl=1h > /dev/null
vault write auth/kubernetes/config kubernetes_host='${K8S_HOST}' kubernetes_ca_cert=@"\$d/ca.pem" \\
  disable_local_ca_jwt=true > /dev/null
REMOTE
    err "Configuring Vault's Kubernetes auth on the Pi failed (above)"
    # read before it failed: whether the write was made is not known here (the connection may have dropped after it)
    eso_say_before "$work/config-before.json" "$VAULT_PI"
    return 1
  fi
  if [[ -n $es ]]; then
    eso_switch_proven "$es" "$was" "$work/config-before.json" "$VAULT_PI" || return 1
  fi
  log "ESO → Pi Vault configured"
}

# The ExternalSecret proving External Secrets' login on Vault's new config, printed with whether it was Ready: one of
# the store Ready before the switch ("<ns/name> ready"), else the first ("<ns/name> none-ready"); nothing printed on a
# fresh cluster (no ExternalSecret, no old reviewer token). A read that fails is an error, never "none"
eso_proof_target() {
  local store=vault-backend  # infra's clusters/production/cluster-config/cluster-secret-store.yaml
  local list es token
  list=$(kubectl get externalsecret -A -o jsonpath="{range .items[?(@.spec.secretStoreRef.name==\"$store\")]}{.metadata.namespace}/{.metadata.name} {.status.conditions[?(@.type==\"Ready\")].status}{'\n'}{end}") \
    || { err "The ExternalSecrets of $store not listed - nothing switched"; return 1; }
  if [[ -z $list ]]; then
    token=$(kubectl -n external-secrets get secret vault-token-reviewer --ignore-not-found -o name) \
      || { err "The old reviewer token's Secret not read - nothing switched"; return 1; }
    if [[ -n $token ]]; then
      err "no ExternalSecret on $store to prove External Secrets' login with - nothing switched, the old reviewer" \
        "token kept"
      return 1
    fi
    return 0
  fi
  es=$(awk '$2 == "True" {print $1; exit}' <<< "$list")
  if [[ -n $es ]]; then
    printf '%s ready\n' "$es"
  else
    printf '%s none-ready\n' "$(awk 'NF {print $1; exit}' <<< "$list")"
  fi
}

# External Secrets' login on Vault's config as just written, proven before the old reviewer token goes: the
# ExternalSecret picked before the switch refreshed (External Secrets keeps no Vault token between syncs - each logs
# in), then production's old reviewer token deleted - a non-expiring token of External Secrets' own account (it reads
# and updates every Secret), kept in Vault's config until the write. Not proven: Vault's config as it was read before
# the write put back with that token, and the login on it proven again - unless none was Ready before (nothing logged
# in on the config before either: nothing to put back)
eso_switch_proven() {
  local es=$1 was=$2 before=$3 pi=$4 gone
  if eso_refreshed "$es"; then
    log "External Secrets logged in on the new config ($es refreshed)"
    gone=$(kubectl -n external-secrets delete secret vault-token-reviewer --ignore-not-found) \
      || { err "the old reviewer token (external-secrets/vault-token-reviewer) not deleted"; return 1; }
    [[ -z $gone ]] || log "the old reviewer token (external-secrets/vault-token-reviewer) deleted"
    return 0
  fi
  err "External Secrets' login on the new config NOT proven - nothing deleted; kubectl -n ${es%/*}" \
    "describe externalsecret ${es#*/}"
  if [[ $was != ready ]]; then
    err "nothing put back: no ExternalSecret logged in on the config before either"
    return 1
  fi
  eso_put_back "$before" "$pi" || { eso_say_before "$before" "$pi"; return 1; }
  if eso_refreshed "$es"; then
    log "External Secrets logs in on the config put back ($es refreshed)"
  else
    err "External Secrets' login NOT even on the config put back - kubectl -n ${es%/*} describe externalsecret ${es#*/}"
  fi
  return 1
}

# One refresh of the ExternalSecret asked for and waited for (ESO_PROOF_SECONDS): its syncedResourceVersion (the
# generation and a hash of its labels and annotations) changed from before the force-sync annotation and Ready - the
# reconcile that saw it began after the annotation, so after Vault's write; a sync already running when Vault was
# written refreshes with the version from before. ESO writes the version on a successful sync alone: one never synced
# (a rebuilt cluster, DR step 5) has none before - any version since is its first sync. Read with a separator (empty
# fields shifted a whitespace split); a read that fails is never "refreshed"
eso_refreshed() {
  local es=$1 line before now ready end
  local path='{.status.syncedResourceVersion}|{.status.conditions[?(@.type=="Ready")].status}'
  if ! line=$(kubectl -n "${es%/*}" get externalsecret "${es#*/}" -o jsonpath="$path"); then
    err "ExternalSecret $es's synced version not read - nothing proven"
    return 1
  fi
  IFS='|' read -r before _ <<< "$line"
  kubectl -n "${es%/*}" annotate externalsecret "${es#*/}" force-sync="$(date +%s)" --overwrite > /dev/null \
    || { err "Cannot ask ExternalSecret $es to refresh"; return 1; }
  end=$((SECONDS + ${ESO_PROOF_SECONDS:-90}))
  while :; do
    if line=$(kubectl -n "${es%/*}" get externalsecret "${es#*/}" -o jsonpath="$path"); then
      IFS='|' read -r now ready <<< "$line"
      [[ -n $now && $now != "$before" && $ready == True ]] && return 0
    fi
    if ((SECONDS >= end)); then
      err "ExternalSecret $es not refreshed since asked (Ready ${ready:-unread}, synced version ${now:-none})"
      return 1
    fi
    sleep 2
  done
}

# Vault's config as read before the write, said with how to put it back by hand - when this step could not, or does
# not know whether it wrote: its file is this run's, removed as the step ends. None of it secret: Vault reads back no
# reviewer token (token_reviewer_jwt_set alone)
eso_say_before() {
  local before=$1 pi=$2
  [[ -s $before ]] || return 0
  err "Vault's config before this run (auth/kubernetes/config on $pi) - to put back by hand: its data below," \
    "token_reviewer_jwt the token of external-secrets/vault-token-reviewer in place of token_reviewer_jwt_set, then" \
    "as root on $pi: vault write auth/kubernetes/config @<that JSON>"
  python3 -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1])).get("data") or {}, indent=1))' \
    "$before" >&2 || cat "$before" >&2
}

# Vault's config put back as it was read before the write, the old reviewer token (the kept Secret's) with it - both
# on ssh's stdin, on no command line
eso_put_back() {
  local before=$1 pi=$2 jwt payload
  if ! jwt=$(kubectl -n external-secrets get secret vault-token-reviewer -o jsonpath='{.data.token}' | base64 -d) \
      || [[ ! $jwt =~ ^[A-Za-z0-9._-]+$ ]]; then
    err "Vault's config NOT put back: no old reviewer token to put back (external-secrets/vault-token-reviewer)"
    return 1
  fi
  if ! payload=$(python3 -c 'import base64, json, sys
d = json.load(open(sys.argv[1])).get("data") or {}
if not d:
    sys.exit(1)
d.pop("token_reviewer_jwt_set", None)
d["token_reviewer_jwt"] = sys.stdin.read().strip()
print(base64.b64encode(json.dumps(d).encode()).decode())' "$before" <<< "$jwt"); then
    err "Vault's config NOT put back: none was read before the write"
    return 1
  fi
  if ! ssh "sm@${pi}" "sudo bash -s" <<REMOTE; then
set -euo pipefail
umask 077
d=\$(mktemp -d)
trap 'rm -rf "\$d"' EXIT
base64 -d > "\$d/config.json" <<'B64'
${payload}
B64
export VAULT_ADDR=https://127.0.0.1:8200 VAULT_CACERT=/etc/vault.d/tls/ca-cert.pem
VAULT_TOKEN=\$(cat /etc/vault-unseal/root-token)
export VAULT_TOKEN
vault write auth/kubernetes/config @"\$d/config.json" > /dev/null
REMOTE
    err "Vault's config NOT put back: the write on the Pi failed (above)"
    return 1
  fi
  log "Vault's config put back as it was before the write, its reviewer token with it"
}

# --- cluster-config (static resources) ---
install_cluster_config() {
  log "Applying cluster-config resources..."

  # Wait for ESO CRDs to be available
  log "Waiting for ExternalSecret CRD..."
  for i in $(seq 1 30); do
    kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1 && break
    sleep 5
  done

  # Wait for ClusterSecretStore CRD
  for i in $(seq 1 30); do
    kubectl get crd clustersecretstores.external-secrets.io >/dev/null 2>&1 && break
    sleep 5
  done

  # Apply all resources, retry failures
  local skipped=()
  for f in "$VALUES_DIR/cluster-config/"*.yaml; do
    kubectl apply -f "$f" --server-side 2>/dev/null || skipped+=("$f")
  done

  # Retry skipped resources (CRDs might have become ready)
  if [[ ${#skipped[@]} -gt 0 ]]; then
    sleep 10
    for f in "${skipped[@]}"; do
      kubectl apply -f "$f" --server-side 2>/dev/null || warn "Skipped: $(basename "$f")"
    done
  fi

  log "cluster-config applied"
}

# --- Main ---
main() {
  local component="${1:-all}"

  log "Tier 0 Bootstrap (component: $component)"
  log "INFRA_DIR: $INFRA_DIR"

  if [[ ! -d "$VALUES_DIR" ]]; then
    err "Values directory not found: $VALUES_DIR"
    err "Set INFRA_DIR to point to your infra repo clone"
    exit 1
  fi

  case "$component" in
    local-path)         install_local_path ;;
    cert-manager)       install_cert_manager ;;
    porkbun-webhook)    install_porkbun_webhook ;;
    external-secrets)   install_external_secrets ;;
    vault-eso)          setup_vault_eso || { err "vault-eso failed"; exit 1; } ;;
    istio)              install_istio ;;
    velero)             install_velero ;;
    cluster-config)     install_cluster_config ;;
    all)
      local failed=0
      install_local_path         || { err "local-path failed"; ((failed++)); }
      install_cert_manager       || { err "cert-manager failed"; ((failed++)); }
      install_porkbun_webhook    || { err "porkbun-webhook failed"; ((failed++)); }
      install_external_secrets   || { err "external-secrets failed"; ((failed++)); }
      setup_vault_eso            || { err "vault-eso failed"; ((failed++)); }
      install_istio              || { err "istio failed"; ((failed++)); }
      install_velero             || { err "velero failed"; ((failed++)); }
      install_cluster_config     || { err "cluster-config failed"; ((failed++)); }
      if [[ $failed -gt 0 ]]; then
        err "$failed component(s) failed — check output above"
        exit 1
      fi
      log "Tier 0 bootstrap complete!"
      log ""
      log "Next steps:"
      log "  1. task deploy:vault-pi    # If Vault Pi needs setup"
      log "  2. task deploy:vault       # Vault HA in cluster"
      log "  3. task deploy:pi-services     # Git forge"
      log "  4. task deploy:argocd      # GitOps controller"
      log "  5. ArgoCD syncs all Tier 1 apps automatically"
      ;;
    *)
      err "Unknown component: $component"
      err "Usage: $0 [cert-manager|porkbun-webhook|external-secrets|istio|velero|cluster-config|all]"
      exit 1
      ;;
  esac
}

main "$@"
