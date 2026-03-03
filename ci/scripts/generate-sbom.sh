#!/usr/bin/env bash
# =============================================================================
# generate-sbom.sh
# Generates a Software Bill of Materials (SBOM) for a container image using
# Syft (SPDX JSON format) and optionally attests it with Cosign.
#
# Usage:
#   ./generate-sbom.sh <IMAGE> [OUTPUT_FILE] [--attest]
#
# Environment variables:
#   COSIGN_KEY_REF  - Cosign key reference (e.g. k8s://jenkins/cosign-keys)
#                    Required only when --attest is passed.
#   SYFT_VERSION    - Syft version to install (default: latest stable)
#
# Exit codes:
#   0  - Success
#   1  - Missing arguments or tool installation failure
#   2  - SBOM generation failure
#   3  - Cosign attestation failure
# =============================================================================
set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 <IMAGE> [OUTPUT_FILE] [--attest]"
  echo ""
  echo "Arguments:"
  echo "  IMAGE        Full image reference (registry/repo:tag)"
  echo "  OUTPUT_FILE  Path for SBOM JSON output (default: sbom-<tag>.spdx.json)"
  echo "  --attest     Attach SBOM as a Cosign attestation to the image"
  echo ""
  echo "Environment:"
  echo "  COSIGN_KEY_REF   Cosign key reference (required with --attest)"
  echo "  SYFT_VERSION     Syft version to pin (default: latest)"
  exit 1
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  usage
fi

IMAGE="$1"
ATTEST=false
OUTPUT_FILE=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --attest) ATTEST=true ;;
    --*)      error "Unknown flag: $1"; usage ;;
    *)        OUTPUT_FILE="$1" ;;
  esac
  shift
done

# Derive default output filename from image tag
if [[ -z "$OUTPUT_FILE" ]]; then
  TAG="${IMAGE##*:}"
  OUTPUT_FILE="sbom-${TAG}.spdx.json"
fi

COSIGN_KEY_REF="${COSIGN_KEY_REF:-}"

# ─── Install Syft if not present ──────────────────────────────────────────────
install_syft() {
  if command -v syft &>/dev/null; then
    SYFT_INSTALLED_VER=$(syft version | grep -oP 'Version:\s+\K[\d.]+' || echo "unknown")
    info "Syft already installed (${SYFT_INSTALLED_VER})"
    return
  fi

  info "Installing Syft..."
  SYFT_VERSION="${SYFT_VERSION:-}"
  if [[ -n "$SYFT_VERSION" ]]; then
    INSTALL_ARGS=(-b /usr/local/bin "v${SYFT_VERSION}")
  else
    INSTALL_ARGS=(-b /usr/local/bin)
  fi

  if curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
       | sh -s -- "${INSTALL_ARGS[@]}"; then
    success "Syft installed successfully"
  else
    error "Failed to install Syft"
    exit 1
  fi
}

# ─── Install Cosign if not present ────────────────────────────────────────────
install_cosign() {
  if command -v cosign &>/dev/null; then
    info "Cosign already installed"
    return
  fi

  info "Installing Cosign v2..."
  COSIGN_VERSION="2.2.0"
  COSIGN_URL="https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64"

  curl -sSfL "${COSIGN_URL}" -o /tmp/cosign
  chmod +x /tmp/cosign
  mv /tmp/cosign /usr/local/bin/cosign
  success "Cosign installed"
}

# ─── Generate SBOM ────────────────────────────────────────────────────────────
generate_sbom() {
  info "Generating SBOM for image: ${IMAGE}"
  info "Output file: ${OUTPUT_FILE}"

  if syft "${IMAGE}" -o spdx-json > "${OUTPUT_FILE}"; then
    local pkg_count
    pkg_count=$(python3 -c "
import json, sys
with open('${OUTPUT_FILE}') as f:
    data = json.load(f)
pkgs = data.get('packages', [])
print(len(pkgs))
" 2>/dev/null || echo "N/A")
    success "SBOM generated — ${pkg_count} packages catalogued"
  else
    error "SBOM generation failed for image: ${IMAGE}"
    exit 2
  fi
}

# ─── Print SBOM summary ───────────────────────────────────────────────────────
print_summary() {
  info "SBOM Summary:"
  python3 - <<'PYEOF'
import json, sys, os

sbom_file = os.environ.get("SBOM_FILE", "")
if not sbom_file or not os.path.exists(sbom_file):
    print("  (summary unavailable)")
    sys.exit(0)

with open(sbom_file) as f:
    data = json.load(f)

packages = data.get("packages", [])
# Count by SPDX license
by_license = {}
for pkg in packages:
    lic = pkg.get("licenseConcluded", "NOASSERTION")
    by_license[lic] = by_license.get(lic, 0) + 1

print(f"  Total packages : {len(packages)}")
print(f"  Unique licenses: {len(by_license)}")
top = sorted(by_license.items(), key=lambda x: x[1], reverse=True)[:5]
for lic, count in top:
    print(f"    {count:>4}  {lic}")
PYEOF
}
export SBOM_FILE="${OUTPUT_FILE}"

# ─── Cosign attestation ───────────────────────────────────────────────────────
attest_sbom() {
  if [[ -z "$COSIGN_KEY_REF" ]]; then
    error "COSIGN_KEY_REF is required for attestation"
    exit 3
  fi

  info "Attesting SBOM to image with Cosign..."
  if cosign attest \
       --key "${COSIGN_KEY_REF}" \
       --type spdxjson \
       --predicate "${OUTPUT_FILE}" \
       "${IMAGE}"; then
    success "SBOM attestation attached to ${IMAGE}"
  else
    error "Cosign attestation failed"
    exit 3
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "════════════════════════════════════════════"
  echo "   SBOM Generator — Intelligent CI/CD       "
  echo "════════════════════════════════════════════"

  install_syft
  generate_sbom
  print_summary

  if [[ "$ATTEST" == "true" ]]; then
    install_cosign
    attest_sbom
  fi

  echo ""
  success "SBOM written to: ${OUTPUT_FILE}"
  echo ""
}

main
