#!/usr/bin/env bash
# Destroy all AWS infrastructure, including EKS — leaves a clean environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CORE_TF_DIR="${ROOT_DIR}/terraform/core-infra"
ADDONS_TF_DIR="${ROOT_DIR}/terraform/addons"
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

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"

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
  || warn "Terraform destroy failed — some resources may require manual cleanup in the AWS console"

# terraform/coder and terraform/addons state now refer to resources that no
# longer exist — clear them.
section "Clearing local terraform/coder and terraform/addons state..."
rm -f "${CODER_TF_DIR}"/terraform.tfstate "${CODER_TF_DIR}"/terraform.tfstate.backup
rm -f "${ADDONS_TF_DIR}"/terraform.tfstate "${ADDONS_TF_DIR}"/terraform.tfstate.backup

rm -f "${ROOT_DIR}/coder-init.json"
info "All AWS resources destroyed"
