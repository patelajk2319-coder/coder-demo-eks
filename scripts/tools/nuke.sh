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

: "${AWS_REGION:?AWS_REGION must be set in .env}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"

stop_coder_port_forward

# Destroy Coder first, while the cluster's AWS Load Balancer Controller is
# still alive: the Service's NLB, target group, and security groups are
# created by that controller, not Terraform. Destroying it later (once the
# controller itself is gone) orphans them and blocks VPC teardown on
# DependencyViolation.
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
    || warn "Destroying terraform/coder failed — the NLB and its security groups may not have been cleaned up; addons destroy below may fail on DependencyViolation as a result"
fi

# Destroy add-ons (ALB controller, Secrets Store CSI driver, RDS, Secrets
# Manager) next, while the cluster still exists — the kubernetes/helm
# providers here are configured against it.
if [[ -n "${EKS_CLUSTER_NAME:-}" ]] && [[ -f "${ADDONS_TF_DIR}/terraform.tfstate" ]]; then
  section "Destroying RDS, Secrets Manager, and cluster add-ons..."
  VPC_ID=$(terraform -chdir="${CORE_TF_DIR}" output -raw vpc_id 2>/dev/null || echo "")
  CLUSTER_SECURITY_GROUP_ID=$(terraform -chdir="${CORE_TF_DIR}" output -raw cluster_security_group_id 2>/dev/null || echo "")
  OIDC_PROVIDER_ARN=$(terraform -chdir="${CORE_TF_DIR}" output -raw oidc_provider_arn 2>/dev/null || echo "")
  OIDC_PROVIDER_URL=$(terraform -chdir="${CORE_TF_DIR}" output -raw oidc_provider_url 2>/dev/null || echo "")
  DATABASE_SUBNET_IDS=$(terraform -chdir="${CORE_TF_DIR}" output -json database_subnet_ids 2>/dev/null || echo "[]")
  terraform -chdir="${ADDONS_TF_DIR}" destroy -auto-approve \
    -var="region=${AWS_REGION}" \
    -var="kubeconfig_context=${EKS_CLUSTER_NAME}-admin" \
    -var="cluster_name=${EKS_CLUSTER_NAME}" \
    -var="vpc_id=${VPC_ID}" \
    -var="database_subnet_ids=${DATABASE_SUBNET_IDS}" \
    -var="cluster_security_group_id=${CLUSTER_SECURITY_GROUP_ID}" \
    -var="oidc_provider_arn=${OIDC_PROVIDER_ARN}" \
    -var="oidc_provider_url=${OIDC_PROVIDER_URL}" \
    -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
    || warn "Destroying terraform/addons failed — some resources may require manual cleanup in the AWS console"
fi

section "Destroying VPC and EKS cluster..."
terraform -chdir="${CORE_TF_DIR}" destroy -auto-approve \
  -var="region=${AWS_REGION}" \
  || warn "Terraform destroy failed — some resources may require manual cleanup in the AWS console"

# terraform/coder and terraform/addons state now refer to resources that no
# longer exist — clear them.
section "Clearing local terraform/coder and terraform/addons state..."
rm -f "${CODER_TF_DIR}"/terraform.tfstate "${CODER_TF_DIR}"/terraform.tfstate.backup
rm -f "${ADDONS_TF_DIR}"/terraform.tfstate "${ADDONS_TF_DIR}"/terraform.tfstate.backup

rm -f "${ROOT_DIR}/coder-init.json"
info "All AWS resources destroyed"
