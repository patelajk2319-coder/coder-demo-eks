#!/usr/bin/env bash
# Deploy VPC, EKS cluster, CloudWatch logs, RDS, and Secrets Manager
# (terraform/core-infra — pure AWS, no kubernetes/helm needed), then the AWS
# Load Balancer Controller and Secrets Store CSI driver (terraform/addons —
# needs the cluster to exist first) once the cluster is ready. Two separate
# Terraform states so core-infra never hits the "cluster doesn't exist yet"
# chicken-and-egg problem a combined kubernetes/helm provider config would.
# terraform/addons reads core-infra's outputs directly via
# terraform_remote_state, so this script only needs to extract the handful
# of values other scripts use directly. Writes those back to .env.

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

: "${TF_VAR_postgres_admin_password:?TF_VAR_postgres_admin_password must be set in .env}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"

section "Initialising Terraform (terraform/core-infra)..."
terraform -chdir="${CORE_TF_DIR}" init -upgrade

section "Deploying VPC, EKS, RDS, and Secrets Manager..."
terraform -chdir="${CORE_TF_DIR}" apply \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  -auto-approve

EKS_CLUSTER_NAME=$(terraform -chdir="${CORE_TF_DIR}" output -raw cluster_name)
RDS_ENDPOINT=$(terraform -chdir="${CORE_TF_DIR}" output -raw rds_endpoint)
RDS_DATABASE=$(terraform -chdir="${CORE_TF_DIR}" output -raw rds_database_name)

# Set the Kubernetes cluster context so we can run kubectl commands and apply Helm charts.
section "Writing kubeconfig..."
aws eks update-kubeconfig \
  --name "${EKS_CLUSTER_NAME}" \
  --alias "${EKS_CLUSTER_NAME}-admin"

info "EKS context '${EKS_CLUSTER_NAME}-admin' written to kubeconfig"

section "Verifying cluster connectivity..."
if ! kubectl wait --for=condition=Ready node --all --timeout=120s; then
  error "Nodes did not reach Ready — check 'kubectl get nodes' before retrying"
  exit 1
fi
kubectl get nodes

section "Initialising Terraform (terraform/addons)..."
terraform -chdir="${ADDONS_TF_DIR}" init -upgrade

section "Deploying cluster add-ons (AWS Load Balancer Controller, Secrets Store CSI driver)..."
terraform -chdir="${ADDONS_TF_DIR}" apply -auto-approve

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
