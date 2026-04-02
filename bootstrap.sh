#!/bin/bash
# Tier 0 Bootstrap: Pre-GitOps components
#
# Deploys infrastructure that must exist before ArgoCD + Forgejo can operate.
# Uses external Helm chart repos (not Forgejo) and local values files.
#
# Prerequisites:
#   - kubeadm cluster running with Calico CNI
#   - kubectl configured and working
#   - helm installed
#   - INFRA_DIR points to the infra repo (default: /home/sm/src/infra)
#
# Usage:
#   ./bootstrap.sh           # Full bootstrap
#   ./bootstrap.sh cert-manager  # Single component

set -euo pipefail

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

# --- external-secrets ---
install_external_secrets() {
  log "Installing external-secrets..."
  helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
  helm repo update external-secrets
  helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace \
    --version 2.2.0 \
    -f "$VALUES_DIR/external-secrets/values.yaml" \
    --wait --timeout 120s
  log "external-secrets installed"
}

# --- istio ---
install_istio() {
  log "Installing Istio..."
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

# --- cluster-config (static resources) ---
install_cluster_config() {
  log "Applying cluster-config resources..."
  for f in "$VALUES_DIR/cluster-config/"*.yaml; do
    kubectl apply -f "$f" --server-side 2>/dev/null || warn "Skipped: $(basename "$f")"
  done
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
    cert-manager)       install_cert_manager ;;
    porkbun-webhook)    install_porkbun_webhook ;;
    external-secrets)   install_external_secrets ;;
    istio)              install_istio ;;
    velero)             install_velero ;;
    cluster-config)     install_cluster_config ;;
    all)
      install_cert_manager
      install_porkbun_webhook
      install_external_secrets
      install_istio
      install_velero
      install_cluster_config
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
