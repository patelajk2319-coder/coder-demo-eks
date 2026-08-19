#!/usr/bin/env bash
# Destroy all AWS infrastructure, including EKS — leaves a clean environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/core-infra"
CODER_TF_DIR="${ROOT_DIR}/terraform/coder"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${AWS_REGION:?AWS_REGION must be set in .env}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"

stop_coder_port_forward

# anthropic_api_key has no default — must be passed or destroy prompts
# interactively. Deleting the EKS cluster takes Coder down with it, no separate
# cleanup needed.
section "Destroying AWS core infrastructure..."
terraform -chdir="${TF_DIR}" destroy -auto-approve \
  -var="region=${AWS_REGION}" \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  || warn "Terraform destroy failed — some resources may require manual cleanup in the AWS console"

# terraform/coder state now refers to resources that no longer exist — clear it.
section "Clearing local terraform/coder state..."
rm -f "${CODER_TF_DIR}"/terraform.tfstate "${CODER_TF_DIR}"/terraform.tfstate.backup

rm -f "${ROOT_DIR}/coder-init.json"
info "All AWS resources destroyed"
