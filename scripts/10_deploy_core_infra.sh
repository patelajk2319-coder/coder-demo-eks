#!/usr/bin/env bash
# Deploy VPC, EKS cluster, and CloudWatch logs (terraform/core-infra), then RDS,
# Secrets Manager, and cluster add-ons (terraform/addons) once the cluster
# exists. Two separate Terraform states: core-infra only needs the aws/tls
# providers, so it never hits the "cluster doesn't exist yet" chicken-and-egg
# problem that a combined kubernetes/helm provider config would. Writes
# infrastructure outputs back to .env for subsequent steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CORE_TF_DIR="${ROOT_DIR}/terraform/core-infra"
ADDONS_TF_DIR="${ROOT_DIR}/terraform/addons"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found — copy .env.example and fill in values"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${AWS_REGION:?AWS_REGION must be set in .env}"
: "${TF_VAR_postgres_admin_password:?TF_VAR_postgres_admin_password must be set in .env}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"

section "Initialising Terraform (terraform/core-infra)..."
terraform -chdir="${CORE_TF_DIR}" init -upgrade

section "Deploying VPC and EKS cluster..."
terraform -chdir="${CORE_TF_DIR}" apply \
  -var="region=${AWS_REGION}" \
  -auto-approve

section "Extracting core-infra outputs..."
EKS_CLUSTER_NAME=$(terraform -chdir="${CORE_TF_DIR}" output -raw cluster_name)
VPC_ID=$(terraform -chdir="${CORE_TF_DIR}" output -raw vpc_id)
CLUSTER_SECURITY_GROUP_ID=$(terraform -chdir="${CORE_TF_DIR}" output -raw cluster_security_group_id)
OIDC_PROVIDER_ARN=$(terraform -chdir="${CORE_TF_DIR}" output -raw oidc_provider_arn)
OIDC_PROVIDER_URL=$(terraform -chdir="${CORE_TF_DIR}" output -raw oidc_provider_url)
DATABASE_SUBNET_IDS=$(terraform -chdir="${CORE_TF_DIR}" output -json database_subnet_ids | jq -c '.')

section "Writing kubeconfig..."
aws eks update-kubeconfig \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --alias "${EKS_CLUSTER_NAME}-admin"

info "EKS context '${EKS_CLUSTER_NAME}-admin' written to kubeconfig"

section "Verifying cluster connectivity..."
kubectl get nodes

section "Initialising Terraform (terraform/addons)..."
terraform -chdir="${ADDONS_TF_DIR}" init -upgrade

section "Deploying RDS, Secrets Manager, and cluster add-ons..."
terraform -chdir="${ADDONS_TF_DIR}" apply \
  -var="region=${AWS_REGION}" \
  -var="kubeconfig_context=${EKS_CLUSTER_NAME}-admin" \
  -var="cluster_name=${EKS_CLUSTER_NAME}" \
  -var="vpc_id=${VPC_ID}" \
  -var="database_subnet_ids=${DATABASE_SUBNET_IDS}" \
  -var="cluster_security_group_id=${CLUSTER_SECURITY_GROUP_ID}" \
  -var="oidc_provider_arn=${OIDC_PROVIDER_ARN}" \
  -var="oidc_provider_url=${OIDC_PROVIDER_URL}" \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  -auto-approve

section "Extracting addons outputs..."
RDS_ENDPOINT=$(terraform -chdir="${ADDONS_TF_DIR}" output -raw rds_endpoint)
RDS_DATABASE=$(terraform -chdir="${ADDONS_TF_DIR}" output -raw rds_database_name)
SECRETS_MANAGER_ARN=$(terraform -chdir="${ADDONS_TF_DIR}" output -raw anthropic_secret_arn)
CODER_IDENTITY_ROLE_ARN=$(terraform -chdir="${ADDONS_TF_DIR}" output -raw coder_identity_role_arn)

section "Updating .env with infrastructure outputs..."

update_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "${ROOT_DIR}/.env"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "${ROOT_DIR}/.env"
  else
    echo "${key}=${value}" >> "${ROOT_DIR}/.env"
  fi
}

update_env "EKS_CLUSTER_NAME"        "${EKS_CLUSTER_NAME}"
update_env "RDS_ENDPOINT"            "${RDS_ENDPOINT}"
update_env "RDS_DATABASE"            "${RDS_DATABASE}"
update_env "SECRETS_MANAGER_ARN"     "${SECRETS_MANAGER_ARN}"
update_env "CODER_IDENTITY_ROLE_ARN" "${CODER_IDENTITY_ROLE_ARN}"

echo ""
info "Core infrastructure is ready"
info "Run: task coder"
