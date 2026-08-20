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

# Destroy Coder first, while the cluster's AWS Load Balancer Controller is
# still alive: the Service's NLB, target group, and security groups are
# created by that controller, not Terraform. Destroying core-infra first
# orphans them (controller gone) and blocks VPC teardown on DependencyViolation.
if [[ -n "${EKS_CLUSTER_NAME:-}" ]] && [[ -f "${CODER_TF_DIR}/terraform.tfstate" ]]; then
  section "Destroying Coder (lets the AWS Load Balancer Controller clean up the NLB first)..."
  POSTGRES_CONN_URL="postgresql://${POSTGRES_ADMIN_USER:-pgadmin}:${TF_VAR_postgres_admin_password:-}@${RDS_ENDPOINT:-}/${RDS_DATABASE:-}?sslmode=require"
  terraform -chdir="${CODER_TF_DIR}" destroy -auto-approve \
    -var="kubeconfig_context=${EKS_CLUSTER_NAME}-admin" \
    -var="region=${AWS_REGION}" \
    -var="coder_access_url=${CODER_ACCESS_URL:-http://placeholder}" \
    -var="coder_version=${CODER_VERSION:-2.33.6}" \
    -var="postgres_connection_url=${POSTGRES_CONN_URL}" \
    -var="anthropic_secret_arn=${SECRETS_MANAGER_ARN:-}" \
    -var="coder_identity_role_arn=${CODER_IDENTITY_ROLE_ARN:-}" \
    || warn "Destroying terraform/coder failed — the NLB and its security groups may not have been cleaned up; core-infra destroy below may fail on DependencyViolation as a result"
fi

# anthropic_api_key has no default — must be passed or destroy prompts
# interactively. Deleting the EKS cluster takes the rest of the platform
# down with it, no separate cleanup needed.
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
