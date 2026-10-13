#!/usr/bin/env bash
# Deploy Coder's namespace/identity/config prerequisites via Terraform, then
# wait for Argo CD's "coder" Application (the actual Helm release) to sync.
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
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME missing — run task infra first}"
: "${GITHUB_OAUTH_CLIENT_ID:?GITHUB_OAUTH_CLIENT_ID must be set in .env}"

# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/lib/cluster_context.sh"

# ── Terraform init ─────────────────────────────────────────────────────────────
section "Initialising Terraform (terraform/coder)..."
terraform -chdir="${TF_DIR}" init -upgrade

# ── Terraform apply ────────────────────────────────────────────────────────────
section "Deploying Coder's namespace, identity, and config..."
terraform -chdir="${TF_DIR}" apply \
  -var="github_oauth_client_id=${GITHUB_OAUTH_CLIENT_ID}" \
  -auto-approve

# ── Wait for Argo CD to sync the Helm release ──────────────────────────────────
section "Waiting for Argo CD's 'coder' Application to become Healthy..."
for _ in $(seq 1 30); do
  HEALTH=$(kubectl get application coder -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  [[ "${HEALTH}" == "Healthy" ]] && break
  sleep 10
done

if [[ "${HEALTH}" != "Healthy" ]]; then
  error "Argo CD's 'coder' Application did not become Healthy — check: kubectl get application coder -n argocd"
  exit 1
fi

CODER_URL="http://coder.coder-demo.internal"

if grep -q "^CODER_ACCESS_URL=" "${ROOT_DIR}/.env"; then
  sed -i '' "s|^CODER_ACCESS_URL=.*|CODER_ACCESS_URL=${CODER_URL}|" "${ROOT_DIR}/.env"
else
  echo "CODER_ACCESS_URL=${CODER_URL}" >> "${ROOT_DIR}/.env"
fi

echo ""
info "Coder is running on EKS"
info "Coder URL (VPC-internal): ${CODER_URL}"
info "Run: task init"
info "For browser/CLI access from outside the VPC, run: task port-forward"
