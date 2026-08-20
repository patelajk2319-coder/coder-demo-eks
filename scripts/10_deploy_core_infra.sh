#!/usr/bin/env bash
# Deploy VPC, EKS cluster, and CloudWatch logs (terraform/core-infra), then RDS,
# Secrets Manager, and cluster add-ons (terraform/cluster-services) once the cluster
# exists. Two separate Terraform states: core-infra only needs the aws/tls
# providers, so it never hits the "cluster doesn't exist yet" chicken-and-egg
# problem that a combined kubernetes/helm provider config would. terraform/cluster-services
# reads core-infra's outputs directly via terraform_remote_state, so this
# script only needs to extract the handful of values other scripts use
# directly. Writes those back to .env for subsequent steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CORE_TF_DIR="${ROOT_DIR}/terraform/core-infra"
CLUSTER_SERVICES_TF_DIR="${ROOT_DIR}/terraform/cluster-services"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found — copy .env.example and fill in values"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${TF_VAR_postgres_admin_password:?TF_VAR_postgres_admin_password must be set in .env}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"

section "Initialising Terraform (terraform/core-infra)..."
terraform -chdir="${CORE_TF_DIR}" init -upgrade

section "Deploying VPC and EKS cluster..."
terraform -chdir="${CORE_TF_DIR}" apply -auto-approve

EKS_CLUSTER_NAME=$(terraform -chdir="${CORE_TF_DIR}" output -raw cluster_name)

section "Writing kubeconfig..."
aws eks update-kubeconfig \
  --name "${EKS_CLUSTER_NAME}" \
  --alias "${EKS_CLUSTER_NAME}-admin"

info "EKS context '${EKS_CLUSTER_NAME}-admin' written to kubeconfig"

section "Verifying cluster connectivity..."
kubectl get nodes

section "Initialising Terraform (terraform/cluster-services)..."
terraform -chdir="${CLUSTER_SERVICES_TF_DIR}" init -upgrade

section "Deploying RDS, Secrets Manager, and cluster add-ons..."
terraform -chdir="${CLUSTER_SERVICES_TF_DIR}" apply \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  -auto-approve

RDS_ENDPOINT=$(terraform -chdir="${CLUSTER_SERVICES_TF_DIR}" output -raw rds_endpoint)
RDS_DATABASE=$(terraform -chdir="${CLUSTER_SERVICES_TF_DIR}" output -raw rds_database_name)

section "Updating .env with infrastructure outputs..."

update_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "${ROOT_DIR}/.env"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "${ROOT_DIR}/.env"
  else
    echo "${key}=${value}" >> "${ROOT_DIR}/.env"
  fi
}

update_env "EKS_CLUSTER_NAME" "${EKS_CLUSTER_NAME}"
update_env "RDS_ENDPOINT"     "${RDS_ENDPOINT}"
update_env "RDS_DATABASE"     "${RDS_DATABASE}"

echo ""
info "Core infrastructure is ready"
info "Run: task coder"
