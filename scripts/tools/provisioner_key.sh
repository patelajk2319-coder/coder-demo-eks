#!/usr/bin/env bash
# Mint (or re-fetch, if already current) team-demo's provisioner key alone —
# not the license — and print it. Needs CODER_API_TOKEN already minted; run
# task init first if it's missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/coderd"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found"
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

: "${CODER_API_TOKEN:?CODER_API_TOKEN must be set in .env — run task init first}"

section "Ensuring port-forward to Coder..."
ensure_coder_port_forward
LOCAL_CODER_URL="http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"

section "Initialising Terraform (terraform/coderd)..."
terraform -chdir="${TF_DIR}" init -upgrade

# -target is deliberate: this resource has no dependency on coderd_license,
# so this never touches it. Terraform will print its standard -target
# caution below — expected, not an error.
section "Applying the team-demo provisioner key..."
terraform -chdir="${TF_DIR}" apply \
  -target=coderd_provisioner_key.team_demo \
  -var="coder_url=${LOCAL_CODER_URL}" \
  -var="coder_api_token=${CODER_API_TOKEN}" \
  -auto-approve

echo ""
info "team-demo provisioner key:"
terraform -chdir="${TF_DIR}" output -raw team_demo_provisioner_key
echo ""
