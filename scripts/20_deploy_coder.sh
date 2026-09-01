#!/usr/bin/env bash
# Deploy Coder to EKS via Terraform (Helm release).
# Requires core infrastructure to be running (task infra).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/coder"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"

# ── Load environment ───────────────────────────────────────────────────────────
if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found — run task infra first"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME missing — run task infra first}"
: "${TF_VAR_postgres_admin_password:?TF_VAR_postgres_admin_password must be set in .env}"
: "${CODER_VERSION:?CODER_VERSION must be set in .env}"
: "${GITHUB_OAUTH_CLIENT_ID:?GITHUB_OAUTH_CLIENT_ID must be set in .env}"

# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/lib/cluster_context.sh"

# Always start with an inert placeholder — a stale .env value would make Coder
# try to resolve an unreachable host at startup. Real URL is applied below once
# the NLB hostname is known.
ACCESS_URL="http://placeholder"

# ── Terraform init ─────────────────────────────────────────────────────────────
section "Initialising Terraform (terraform/coder)..."
terraform -chdir="${TF_DIR}" init -upgrade

# ── Terraform apply ────────────────────────────────────────────────────────────
section "Deploying Coder to EKS..."
terraform -chdir="${TF_DIR}" apply \
  -var="coder_access_url=${ACCESS_URL}" \
  -var="coder_version=${CODER_VERSION}" \
  -var="github_oauth_client_id=${GITHUB_OAUTH_CLIENT_ID}" \
  -auto-approve

# ── Wait for Coder rollout ─────────────────────────────────────────────────────
section "Waiting for Coder deployment to be ready..."
kubectl rollout status deployment/coder -n coder --timeout=5m

# ── Resolve Coder URL — internal NLB (VPC-private) ─────────────────────────────
section "Retrieving Coder service endpoint..."

# Internal-only NLB (via the AWS Load Balancer Controller) — gets a
# VPC-private hostname, reachable only from inside the VPC. Access from
# outside (browser, CLI) requires 'task port-forward'.
LB_HOSTNAME=""
for _ in $(seq 1 30); do
  LB_HOSTNAME=$(kubectl get svc coder -n coder -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${LB_HOSTNAME}" ]] && break
  sleep 10
done

if [[ -z "${LB_HOSTNAME}" ]]; then
  warn "NLB hostname not yet assigned — check: kubectl get svc coder -n coder"
  warn "Re-run 'task coder' once the NLB is provisioned"
  exit 1
fi

CODER_URL="http://${LB_HOSTNAME}"
info "Internal NLB hostname: ${LB_HOSTNAME}"
info "Coder URL (VPC-internal): ${CODER_URL}"

if grep -q "^CODER_ACCESS_URL=" "${ROOT_DIR}/.env"; then
  sed -i '' "s|^CODER_ACCESS_URL=.*|CODER_ACCESS_URL=${CODER_URL}|" "${ROOT_DIR}/.env"
else
  echo "CODER_ACCESS_URL=${CODER_URL}" >> "${ROOT_DIR}/.env"
fi

section "Re-applying Coder with correct access URL..."
terraform -chdir="${TF_DIR}" apply \
  -var="coder_access_url=${CODER_URL}" \
  -var="coder_version=${CODER_VERSION}" \
  -var="github_oauth_client_id=${GITHUB_OAUTH_CLIENT_ID}" \
  -auto-approve

echo ""
info "Coder is running on EKS"
info "Coder URL (VPC-internal): ${CODER_URL}"
info "Run: task init"
info "For browser/CLI access from outside the VPC, run: task port-forward"
