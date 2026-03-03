#!/usr/bin/env bash
# =============================================================================
# update-gitops-repo.sh
# Updates the Helm values file in the GitOps repository with a new image tag,
# then commits and pushes the change so ArgoCD can detect and sync it.
#
# Usage:
#   ./update-gitops-repo.sh
#
# Required environment variables:
#   GIT_TOKEN       - GitHub Personal Access Token (or SSH key path)
#   GITOPS_REPO_URL - HTTPS URL of the GitOps repository
#   APP_NAME        - Application name (e.g. "sample-app")
#   IMAGE_TAG       - New image tag to deploy (e.g. "a1b2c3d4")
#   ENVIRONMENT     - Target environment: "dev" or "prod" (default: "dev")
#   GIT_USER_NAME   - Git commit author name  (default: "Jenkins CI")
#   GIT_USER_EMAIL  - Git commit author email (default: "jenkins@example.com")
#
# Optional environment variables:
#   VALUES_FILE_PATH - Relative path inside repo to the values file
#                     (default: helm-charts/<APP_NAME>/values-<ENVIRONMENT>.yaml)
#   DRY_RUN         - Set to "true" to skip git push (default: false)
#
# Exit codes:
#   0  - Success
#   1  - Missing required variables
#   2  - Clone / git operation failure
#   3  - yq/sed update failure
# =============================================================================
set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Validate required variables ─────────────────────────────────────────────
REQUIRED_VARS=(GIT_TOKEN GITOPS_REPO_URL APP_NAME IMAGE_TAG)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    error "Required environment variable '$var' is not set."
    exit 1
  fi
done

ENVIRONMENT="${ENVIRONMENT:-dev}"
GIT_USER_NAME="${GIT_USER_NAME:-Jenkins CI}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-jenkins@example.com}"
DRY_RUN="${DRY_RUN:-false}"

VALUES_FILE_PATH="${VALUES_FILE_PATH:-helm-charts/${APP_NAME}/values-${ENVIRONMENT}.yaml}"

# ─── Workspace setup ─────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d -t gitops-update.XXXXXX)
trap 'rm -rf "${WORK_DIR}"' EXIT

info "Working directory: ${WORK_DIR}"

# ─── Clone GitOps repository ──────────────────────────────────────────────────
clone_repo() {
  info "Cloning GitOps repository..."

  # Inject token into URL for HTTPS auth
  # Format: https://<token>@github.com/org/repo.git
  AUTH_URL=$(echo "${GITOPS_REPO_URL}" | sed "s|https://|https://${GIT_TOKEN}@|")

  if git clone --depth 1 "${AUTH_URL}" "${WORK_DIR}/repo" 2>&1 | \
     sed 's/'"${GIT_TOKEN}"'/***TOKEN***/g'; then
    success "Repository cloned"
  else
    error "Failed to clone repository"
    exit 2
  fi
}

# ─── Configure git identity ───────────────────────────────────────────────────
configure_git() {
  cd "${WORK_DIR}/repo"
  git config user.name  "${GIT_USER_NAME}"
  git config user.email "${GIT_USER_EMAIL}"
  # Mask token in any push credential prompts
  git config credential.helper "!f() { echo username=oauth2; echo password=${GIT_TOKEN}; }; f"
}

# ─── Update image tag in values file ─────────────────────────────────────────
update_values_file() {
  local values_file="${WORK_DIR}/repo/${VALUES_FILE_PATH}"

  if [[ ! -f "${values_file}" ]]; then
    error "Values file not found: ${VALUES_FILE_PATH}"
    exit 3
  fi

  info "Updating image tag in: ${VALUES_FILE_PATH}"
  info "  Environment : ${ENVIRONMENT}"
  info "  Application : ${APP_NAME}"
  info "  New tag     : ${IMAGE_TAG}"

  # Extract current tag for logging
  CURRENT_TAG=$(grep -E '^\s+tag:' "${values_file}" | awk '{print $2}' | tr -d '"' || echo "unknown")
  info "  Current tag : ${CURRENT_TAG}"

  # Update using sed (yq is optional – prefer it if available)
  if command -v yq &>/dev/null; then
    yq e ".image.tag = \"${IMAGE_TAG}\"" -i "${values_file}"
  else
    # Portable sed approach (works on both GNU and BSD)
    sed -i.bak -E "s|(^[[:space:]]+tag:[[:space:]]*).+|\1\"${IMAGE_TAG}\"|" "${values_file}"
    rm -f "${values_file}.bak"
  fi

  # Verify change was applied
  NEW_TAG=$(grep -E '^\s+tag:' "${values_file}" | awk '{print $2}' | tr -d '"' || echo "unknown")
  if [[ "$NEW_TAG" == "$IMAGE_TAG" ]]; then
    success "Image tag updated: ${CURRENT_TAG} → ${IMAGE_TAG}"
  else
    error "Tag update verification failed. Expected '${IMAGE_TAG}', got '${NEW_TAG}'"
    exit 3
  fi
}

# ─── Add risk score annotation as YAML comment (optional enrichment) ──────────
annotate_risk_score() {
  local values_file="${WORK_DIR}/repo/${VALUES_FILE_PATH}"
  local risk_score="${RISK_SCORE:-unknown}"
  local risk_level="${RISK_LEVEL:-UNKNOWN}"
  local build_number="${BUILD_NUMBER:-0}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Prepend a header comment so the deploy record is self-documenting
  local header
  header="# ─── Automated update by Jenkins CI ───────────────────────────────────────
# Build     : ${build_number}
# Commit    : ${IMAGE_TAG}
# Deployed  : ${timestamp}
# Risk Score: ${risk_score}  [${risk_level}]
# ──────────────────────────────────────────────────────────────────────────"

  # Prepend header to file
  echo "${header}" | cat - "${values_file}" > /tmp/values_tmp && mv /tmp/values_tmp "${values_file}"
}

# ─── Commit and push ──────────────────────────────────────────────────────────
commit_and_push() {
  cd "${WORK_DIR}/repo"

  git add "${VALUES_FILE_PATH}"

  # Skip commit if nothing changed (idempotent)
  if git diff --staged --quiet; then
    warn "No changes detected — image tag may already be up to date."
    return
  fi

  COMMIT_MSG="chore(gitops): deploy ${APP_NAME}:${IMAGE_TAG} to ${ENVIRONMENT} [skip ci]

- Environment : ${ENVIRONMENT}
- Application : ${APP_NAME}
- Image tag   : ${IMAGE_TAG}
- Risk score  : ${RISK_SCORE:-N/A}
- Build #      : ${BUILD_NUMBER:-N/A}"

  git commit -m "${COMMIT_MSG}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "DRY_RUN=true — skipping git push"
    return
  fi

  info "Pushing to origin..."
  if git push origin HEAD; then
    success "Changes pushed to GitOps repository"
  else
    error "git push failed"
    exit 2
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  GitOps Repository Update — Intelligent CI/CD   "
  echo "══════════════════════════════════════════════════"

  clone_repo
  configure_git
  update_values_file
  annotate_risk_score
  commit_and_push

  echo ""
  success "GitOps update complete for ${APP_NAME}:${IMAGE_TAG} → ${ENVIRONMENT}"
  echo ""
}

main
