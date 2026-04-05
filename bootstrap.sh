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
  log "local-path-provisioner installed"
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

  # Cilium CNI coexistence: disable exclusive mode so Istio CNI can chain
  if cilium status >/dev/null 2>&1; then
    log "Setting Cilium cni.exclusive=false for Istio CNI coexistence..."
    cilium config set cni-exclusive false 2>/dev/null || \
      kubectl patch configmap cilium-config -n kube-system --type merge -p '{"data":{"cni-exclusive":"false"}}' 2>/dev/null || true
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

  local VAULT_VIP="${VAULT_VIP:-192.168.11.5}"
  local VAULT_PI="${VAULT_PI:-192.168.11.4}"
  local VAULT_PASSWORD="${VAULT_ROOT_TOKEN:-}"

  # Fetch Vault CA cert from Pi
  if [[ -f /tmp/vault-ca.pem ]]; then
    log "Using cached Vault CA from /tmp/vault-ca.pem"
  else
    ssh "sm@${VAULT_PI}" "sudo cat /etc/vault.d/tls/ca-cert.pem" > /tmp/vault-ca.pem 2>/dev/null || {
      err "Cannot fetch Vault CA from Pi. Copy /etc/vault.d/tls/ca-cert.pem to /tmp/vault-ca.pem manually."
      return 1
    }
  fi

  local VAULT_CA_B64
  VAULT_CA_B64=$(base64 -w0 < /tmp/vault-ca.pem)

  # Create Vault CA secret in external-secrets namespace
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-pi-ca
  namespace: external-secrets
data:
  ca.crt: ${VAULT_CA_B64}
EOF

  # Create token reviewer ClusterRoleBinding
  kubectl apply -f - <<EOF
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

  # Create long-lived SA token for Vault token reviewer
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-token-reviewer
  namespace: external-secrets
  annotations:
    kubernetes.io/service-account.name: external-secrets
type: kubernetes.io/service-account-token
EOF

  sleep 3

  # Configure Vault kubernetes auth on Pi
  local K8S_CA
  K8S_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)
  local SA_TOKEN
  SA_TOKEN=$(kubectl get secret vault-token-reviewer -n external-secrets -o jsonpath='{.data.token}' | base64 -d)
  local K8S_HOST
  K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

  # Write K8s CA to temp file for Vault
  echo "$K8S_CA" > /tmp/k8s-ca.pem

  ssh "sm@${VAULT_PI}" "sudo bash -c '
    export VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=1
    export VAULT_TOKEN=\$(cat /etc/vault-unseal/root-token)
    vault write auth/kubernetes/config \
      kubernetes_host=\"${K8S_HOST}\" \
      kubernetes_ca_cert=@/dev/stdin \
      token_reviewer_jwt=\"${SA_TOKEN}\" \
      disable_local_ca_jwt=true << CERT
${K8S_CA}
CERT
    vault write auth/kubernetes/role/eso-role \
      bound_service_account_names=external-secrets \
      bound_service_account_namespaces=external-secrets \
      policies=eso-reader \
      ttl=1h
  '" 2>/dev/null || {
    warn "Could not configure Vault kubernetes auth via SSH. Configure manually."
    return 0
  }

  log "ESO → Pi Vault configured"
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
    vault-eso)          setup_vault_eso ;;
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
      log "  3. task deploy:forgejo     # Git forge"
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
