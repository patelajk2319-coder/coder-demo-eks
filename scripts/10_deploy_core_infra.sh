#!/usr/bin/env bash
# Deploy VPC, EKS cluster, RDS PostgreSQL, Secrets Manager, CloudWatch logs,
# and cluster add-ons (AWS Load Balancer Controller, Secrets Store CSI Driver).
# Writes infrastructure outputs back to .env for subsequent steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/core-infra"

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

# ── Terraform init ─────────────────────────────────────────────────────────────
section "Initialising Terraform (terraform/core-infra)..."
terraform -chdir="${TF_DIR}" init -upgrade

# Two-pass apply: the kubernetes/helm providers read the cluster via a data
# source, which Terraform resolves before creating anything — fails on a
# fresh deploy unless the cluster exists first. module.vpc must be targeted
# alongside module.eks (eks only pulls in subnet IDs, not the NAT gateway/route
# tables — nodes with no internet route hang forever trying to bootstrap).
section "Bootstrapping VPC and EKS cluster (required before the kubernetes/helm providers can initialise)..."
terraform -chdir="${TF_DIR}" apply \
  -target=module.vpc \
  -target=module.eks \
  -var="region=${AWS_REGION}" \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  -auto-approve

section "Deploying VPC, RDS, Secrets Manager, and cluster add-ons..."
terraform -chdir="${TF_DIR}" apply \
  -var="region=${AWS_REGION}" \
  -var="anthropic_api_key=${ANTHROPIC_API_KEY}" \
  -auto-approve

# ── Extract outputs ────────────────────────────────────────────────────────────
section "Extracting Terraform outputs..."
EKS_CLUSTER_NAME=$(terraform -chdir="${TF_DIR}" output -raw cluster_name)
RDS_ENDPOINT=$(terraform -chdir="${TF_DIR}" output -raw rds_endpoint)
RDS_DATABASE=$(terraform -chdir="${TF_DIR}" output -raw rds_database_name)
SECRETS_MANAGER_ARN=$(terraform -chdir="${TF_DIR}" output -raw anthropic_secret_arn)
CODER_IDENTITY_ROLE_ARN=$(terraform -chdir="${TF_DIR}" output -raw coder_identity_role_arn)

# ── Write outputs back to .env ─────────────────────────────────────────────────
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

# ── Fetch EKS credentials ──────────────────────────────────────────────────────
section "Writing kubeconfig..."
aws eks update-kubeconfig \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --alias "${EKS_CLUSTER_NAME}-admin"

info "EKS context '${EKS_CLUSTER_NAME}-admin' written to kubeconfig"

# ── Verify connectivity ────────────────────────────────────────────────────────
section "Verifying cluster connectivity..."
kubectl get nodes

echo ""
info "Core infrastructure is ready"
info "Run: task coder"
