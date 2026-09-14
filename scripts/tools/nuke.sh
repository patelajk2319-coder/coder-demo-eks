#!/usr/bin/env bash
# Destroy all AWS infrastructure, including EKS — leaves a clean environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CORE_TF_DIR="${ROOT_DIR}/terraform/core-infra"
ADDONS_TF_DIR="${ROOT_DIR}/terraform/addons"
CODER_TF_DIR="${ROOT_DIR}/terraform/coder"
CODERD_TF_DIR="${ROOT_DIR}/terraform/coderd"

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

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"
: "${GITHUB_OAUTH_CLIENT_SECRET:?GITHUB_OAUTH_CLIENT_SECRET must be set in .env}"

# Destroy platform config (license, provisioner keys) first, while the
# coderd API this state's provider talks to is still alive — the Helm
# release (and coderd itself) gets destroyed a few steps below.
if [[ -f "${CODERD_TF_DIR}/terraform.tfstate" ]]; then
  : "${CODER_API_TOKEN:?CODER_API_TOKEN must be set in .env to destroy terraform/coderd}"
  section "Destroying Coder platform config (license, provisioner keys)..."
  ensure_coder_port_forward
  terraform -chdir="${CODERD_TF_DIR}" destroy -auto-approve \
    -var="coder_url=http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}" \
    -var="coder_api_token=${CODER_API_TOKEN}" \
    || warn "Destroying terraform/coderd failed — license/provisioner-key resources may need manual cleanup via the dashboard before the cluster underneath them is gone"
fi

stop_coder_port_forward

# Destroy Coder first, while the cluster's AWS Load Balancer Controller is
# still alive: the Service's NLB, target group, and security groups are
# created by that controller, not Terraform. Destroying it later (once the
# controller itself is gone) orphans them and blocks VPC teardown on
# DependencyViolation.
if [[ -f "${CODER_TF_DIR}/terraform.tfstate" ]]; then
  section "Destroying Coder (lets the AWS Load Balancer Controller clean up the NLB first)..."
  terraform -chdir="${CODER_TF_DIR}" destroy -auto-approve \
    -var="coder_access_url=${CODER_ACCESS_URL:-http://placeholder}" \
    -var="github_oauth_client_id=${GITHUB_OAUTH_CLIENT_ID:-placeholder}" \
    || warn "Destroying terraform/coder failed — the NLB and its security groups may not have been cleaned up; addons destroy below may fail on DependencyViolation as a result"
fi

# Destroy add-ons (ALB controller, Secrets Store CSI driver) next, while the
# cluster still exists — the kubernetes/helm providers here are configured
# against it.
if [[ -f "${ADDONS_TF_DIR}/terraform.tfstate" ]]; then
  section "Destroying cluster add-ons..."
  terraform -chdir="${ADDONS_TF_DIR}" destroy -auto-approve \
    || warn "Destroying terraform/addons failed — some resources may require manual cleanup in the AWS console"
fi

section "Destroying VPC, EKS, RDS, and Secrets Manager..."
terraform -chdir="${CORE_TF_DIR}" destroy -auto-approve \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  -var="github_oauth_client_secret=${GITHUB_OAUTH_CLIENT_SECRET}" \
  || warn "Terraform destroy failed — some resources may require manual cleanup in the AWS console"

# terraform/coder, terraform/coderd, and terraform/addons state now refer to
# resources that no longer exist — clear them.
section "Clearing local terraform/coder, terraform/coderd, and terraform/addons state..."
rm -f "${CODER_TF_DIR}"/terraform.tfstate "${CODER_TF_DIR}"/terraform.tfstate.backup
rm -f "${CODERD_TF_DIR}"/terraform.tfstate "${CODERD_TF_DIR}"/terraform.tfstate.backup
rm -f "${ADDONS_TF_DIR}"/terraform.tfstate "${ADDONS_TF_DIR}"/terraform.tfstate.backup

rm -f "${ROOT_DIR}/coder-init.json"
info "All AWS resources destroyed"
