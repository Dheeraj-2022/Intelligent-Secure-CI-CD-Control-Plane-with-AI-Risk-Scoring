#!/usr/bin/env bash
# =============================================================================
# cosign-key-pair.sh
# Generates a Cosign key pair and stores the private key as a Kubernetes
# Secret so Jenkins pipeline agents can sign container images.
#
# Usage:
#   ./cosign-key-pair.sh [--namespace <ns>] [--secret-name <name>] [--rotate]
#
# Environment variables:
#   COSIGN_PASSWORD   - Password to encrypt the private key (required)
#   K8S_NAMESPACE     - Kubernetes namespace for the secret (default: jenkins)
#   SECRET_NAME       - Kubernetes Secret name (default: cosign-keys)
#
# Prerequisites:
#   - cosign >= 2.0 installed and in PATH
#   - kubectl configured with cluster admin permissions
# =============================================================================
set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Defaults ─────────────────────────────────────────────────────────────────
K8S_NAMESPACE="${K8S_NAMESPACE:-jenkins}"
SECRET_NAME="${SECRET_NAME:-cosign-keys}"
ROTATE=false
KEY_DIR=$(mktemp -d -t cosign-keys.XXXXXX)
trap 'rm -rf "${KEY_DIR}"' EXIT

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)    K8S_NAMESPACE="$2"; shift 2 ;;
    --secret-name)  SECRET_NAME="$2";   shift 2 ;;
    --rotate)       ROTATE=true;         shift   ;;
    *)              error "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Validate prerequisites ───────────────────────────────────────────────────
check_prerequisites() {
  for cmd in cosign kubectl; do
    if ! command -v "${cmd}" &>/dev/null; then
      error "Required tool not found: ${cmd}"
      exit 1
    fi
  done

  if [[ -z "${COSIGN_PASSWORD:-}" ]]; then
    error "COSIGN_PASSWORD environment variable must be set."
    exit 1
  fi
}

# ─── Check for existing secret ────────────────────────────────────────────────
check_existing_secret() {
  if kubectl get secret "${SECRET_NAME}" -n "${K8S_NAMESPACE}" &>/dev/null; then
    if [[ "${ROTATE}" == "true" ]]; then
      warn "Rotating existing Cosign key pair in secret '${SECRET_NAME}'..."
      # Backup existing keys as a dated secret
      local backup_name="${SECRET_NAME}-backup-$(date +%Y%m%d%H%M%S)"
      kubectl get secret "${SECRET_NAME}" -n "${K8S_NAMESPACE}" -o yaml | \
        sed "s/name: ${SECRET_NAME}/name: ${backup_name}/" | \
        kubectl apply -f - 2>/dev/null || true
      info "Backed up existing keys to secret '${backup_name}'"
      kubectl delete secret "${SECRET_NAME}" -n "${K8S_NAMESPACE}" || true
    else
      warn "Secret '${SECRET_NAME}' already exists in namespace '${K8S_NAMESPACE}'."
      warn "Use --rotate to replace it. Exiting."
      exit 0
    fi
  fi
}

# ─── Generate key pair ────────────────────────────────────────────────────────
generate_key_pair() {
  info "Generating Cosign key pair..."

  cd "${KEY_DIR}"
  COSIGN_PASSWORD="${COSIGN_PASSWORD}" cosign generate-key-pair

  if [[ ! -f "${KEY_DIR}/cosign.key" || ! -f "${KEY_DIR}/cosign.pub" ]]; then
    error "Key generation failed — expected cosign.key and cosign.pub"
    exit 1
  fi

  success "Key pair generated"
  info "  Private key : ${KEY_DIR}/cosign.key (encrypted with COSIGN_PASSWORD)"
  info "  Public key  : ${KEY_DIR}/cosign.pub"
}

# ─── Store keys in Kubernetes secret ─────────────────────────────────────────
store_in_k8s() {
  info "Ensuring namespace '${K8S_NAMESPACE}' exists..."
  kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  info "Creating Kubernetes Secret '${SECRET_NAME}' in namespace '${K8S_NAMESPACE}'..."
  kubectl create secret generic "${SECRET_NAME}" \
    --namespace "${K8S_NAMESPACE}" \
    --from-file=cosign.key="${KEY_DIR}/cosign.key" \
    --from-file=cosign.pub="${KEY_DIR}/cosign.pub" \
    --from-literal=cosign.password="${COSIGN_PASSWORD}"

  # Label the secret for easy identification and rotation tracking
  kubectl label secret "${SECRET_NAME}" -n "${K8S_NAMESPACE}" \
    app.kubernetes.io/managed-by=cosign-key-pair.sh \
    security/key-type=image-signing \
    security/rotation-date="$(date +%Y-%m-%d)" \
    --overwrite

  success "Secret '${SECRET_NAME}' created in namespace '${K8S_NAMESPACE}'"
}

# ─── Export public key to file (for verification in other clusters) ────────────
export_public_key() {
  local pub_key_file="./cosign.pub"
  cp "${KEY_DIR}/cosign.pub" "${pub_key_file}"
  success "Public key exported to: ${pub_key_file}"
  info "Distribute cosign.pub to any cluster that needs to verify image signatures."
}

# ─── Print verification instructions ─────────────────────────────────────────
print_usage_info() {
  echo ""
  echo "══════════════════════════════════════════════════════════════"
  echo "  Cosign Key Pair Setup Complete"
  echo "══════════════════════════════════════════════════════════════"
  echo ""
  echo "  Sign an image:"
  echo "    cosign sign --key k8s://${K8S_NAMESPACE}/${SECRET_NAME} \\"
  echo "      <registry>/<image>:<tag>"
  echo ""
  echo "  Verify an image:"
  echo "    cosign verify --key cosign.pub \\"
  echo "      <registry>/<image>:<tag>"
  echo ""
  echo "  In Jenkinsfile (shared library):"
  echo "    sh 'cosign sign --key k8s://${K8S_NAMESPACE}/${SECRET_NAME} \${IMAGE}'"
  echo ""
  echo "  Rotate keys (run this script with --rotate):"
  echo "    COSIGN_PASSWORD=<new_pass> ./cosign-key-pair.sh --rotate"
  echo ""
  echo "  Key Kubernetes Secret reference:"
  echo "    Namespace  : ${K8S_NAMESPACE}"
  echo "    Secret name: ${SECRET_NAME}"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "════════════════════════════════════════════════"
  echo "   Cosign Key Pair Generator — CI/CD Security   "
  echo "════════════════════════════════════════════════"

  check_prerequisites
  check_existing_secret
  generate_key_pair
  store_in_k8s
  export_public_key
  print_usage_info
}

main
