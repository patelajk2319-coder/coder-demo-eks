#!/usr/bin/env bash
# Apply Coder platform-level config (license, provisioner keys) via the
# coderd Terraform provider. Requires task init to have run first (mints
# CODER_API_TOKEN, starts the port-forward this needs for the whole apply).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/coderd"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/lib/port_forward.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found"
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

: "${CODER_API_TOKEN:?CODER_API_TOKEN must be set in .env — run task init first}"

# CODER_ACCESS_URL is the internal NLB hostname — the coderd provider needs
# a URL reachable from this machine for the whole apply, not just a
# preflight check, so the port-forward must stay up throughout.
section "Ensuring port-forward to Coder..."
ensure_coder_port_forward
LOCAL_CODER_URL="http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"

section "Initialising Terraform (terraform/coderd)..."
terraform -chdir="${TF_DIR}" init -upgrade

section "Applying Coder platform config (license, provisioner keys)..."
terraform -chdir="${TF_DIR}" apply \
  -var="coder_url=${LOCAL_CODER_URL}" \
  -var="coder_api_token=${CODER_API_TOKEN}" \
  -auto-approve

echo ""
info "Coder platform config applied"
if terraform -chdir="${TF_DIR}" output -raw team_demo_provisioner_key &>/dev/null; then
  echo ""
  warn "team-demo provisioner key (copy into coder-team-cluster-demo/.env as CODER_PROVISIONER_KEY):"
  warn "  $(terraform -chdir="${TF_DIR}" output -raw team_demo_provisioner_key)"
fi
