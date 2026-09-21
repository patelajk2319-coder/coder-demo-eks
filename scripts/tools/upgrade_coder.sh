#!/usr/bin/env bash
# Upgrade Coder to the latest (or a specified) version via Terraform.
# Usage: upgrade_coder.sh [TARGET_VERSION]
#   TARGET_VERSION — optional, e.g. 2.34.6. Defaults to the latest GitHub release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/coder"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found"
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

: "${CODER_VERSION:?CODER_VERSION must be set in .env}"
: "${CODER_ACCESS_URL:?CODER_ACCESS_URL must be set in .env — run task coder first}"
: "${TF_VAR_postgres_admin_password:?TF_VAR_postgres_admin_password must be set in .env}"
: "${GITHUB_OAUTH_CLIENT_ID:?GITHUB_OAUTH_CLIENT_ID must be set in .env}"

CURRENT_VERSION="${CODER_VERSION}"

# ── Resolve target version ─────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
  TARGET_VERSION="${1#v}"
  info "Target version specified: ${TARGET_VERSION}"
else
  section "Fetching latest Coder release..."
  TARGET_VERSION=$(curl -sf https://api.github.com/repos/coder/coder/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")
  info "Latest release: v${TARGET_VERSION}"
fi

if [[ "${CURRENT_VERSION}" == "${TARGET_VERSION}" ]]; then
  info "Already on v${CURRENT_VERSION} — nothing to do"
  exit 0
fi

info "Upgrading Coder: v${CURRENT_VERSION} → v${TARGET_VERSION}"

# ── Terraform apply ────────────────────────────────────────────────────────────
section "Applying Terraform (terraform/coder)..."
terraform -chdir="${TF_DIR}" init -upgrade
terraform -chdir="${TF_DIR}" apply \
  -var="coder_access_url=${CODER_ACCESS_URL}" \
  -var="coder_version=${TARGET_VERSION}" \
  -var="github_oauth_client_id=${GITHUB_OAUTH_CLIENT_ID}" \
  -auto-approve

# ── Wait for rollout ───────────────────────────────────────────────────────────
section "Waiting for rollout..."
kubectl rollout status deployment/coder -n coder --timeout=5m

# ── Update .env ────────────────────────────────────────────────────────────────
sed -i '' "s|^CODER_VERSION=.*|CODER_VERSION=${TARGET_VERSION}|" "${ROOT_DIR}/.env"
info ".env updated: CODER_VERSION=${TARGET_VERSION}"

echo ""
info "Coder upgraded to v${TARGET_VERSION}"
info "The local coder CLI may now be a version behind — reinstall from the server if commands start failing:"
info "  curl -fsSL \${LOCAL_CODER_URL}/install.sh | sh"
