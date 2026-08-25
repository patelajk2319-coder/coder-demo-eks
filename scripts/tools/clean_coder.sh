#!/usr/bin/env bash
# Reset Coder to a clean state, leaving EKS and RDS intact: destroys the Helm
# release and terraform/coder state, drops and recreates the database, clears
# the access URL from .env. Doesn't touch workspace namespaces (coder-ws-*) —
# run your workspaces repo's clean task first if you have one.
# After this: task coder && task init

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/coder"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found — nothing to clean"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME must be set in .env — run task infra first}"
: "${RDS_ENDPOINT:?RDS_ENDPOINT must be set in .env — run task infra first}"
: "${RDS_ADMIN_USERNAME:?RDS_ADMIN_USERNAME must be set in .env — run task infra first}"
: "${TF_VAR_postgres_admin_password:?TF_VAR_postgres_admin_password must be set in .env}"

# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"

stop_coder_port_forward

# ── Remove Helm release ────────────────────────────────────────────────────────
section "Removing Coder Helm release..."
if helm status coder -n coder &>/dev/null; then
  helm uninstall coder -n coder
  info "Helm release removed"
else
  info "No Helm release found — skipping"
fi

# ── Delete namespace ───────────────────────────────────────────────────────────
section "Deleting coder namespace..."
kubectl delete namespace coder --ignore-not-found=true
info "Namespace removed"

# ── Clear Terraform coder state ────────────────────────────────────────────────
section "Clearing terraform/coder state..."
terraform -chdir="${TF_DIR}" state rm kubernetes_annotations.coder_sa 2>/dev/null || true
terraform -chdir="${TF_DIR}" state rm kubernetes_manifest.secret_provider_class 2>/dev/null || true
terraform -chdir="${TF_DIR}" state rm helm_release.coder 2>/dev/null || true
terraform -chdir="${TF_DIR}" state rm kubernetes_namespace.coder 2>/dev/null || true
info "Terraform state cleared"

# ── Reset the Coder database ───────────────────────────────────────────────────
section "Resetting Coder database..."
DB_NAME="${RDS_DATABASE:-coder}"
PG_HOST="${RDS_ENDPOINT}"

# kubectl exec into a temporary psql pod so we can reach the private RDS instance
kubectl run pg-reset \
  --image=postgres:16 \
  --restart=Never \
  --namespace=default \
  --env="PGPASSWORD=${TF_VAR_postgres_admin_password}" \
  --command -- sleep 120 &>/dev/null

kubectl wait pod/pg-reset --for=condition=Ready --timeout=60s --namespace=default &>/dev/null

kubectl exec pg-reset --namespace=default -- \
  psql -h "${PG_HOST}" -U "${RDS_ADMIN_USERNAME}" -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();" &>/dev/null

kubectl exec pg-reset --namespace=default -- \
  psql -h "${PG_HOST}" -U "${RDS_ADMIN_USERNAME}" -d postgres \
  -c "DROP DATABASE IF EXISTS ${DB_NAME};"

kubectl exec pg-reset --namespace=default -- \
  psql -h "${PG_HOST}" -U "${RDS_ADMIN_USERNAME}" -d postgres \
  -c "CREATE DATABASE ${DB_NAME} WITH ENCODING='UTF8' LC_COLLATE='en_US.utf8' LC_CTYPE='en_US.utf8' TEMPLATE=template0;"


kubectl delete pod pg-reset --namespace=default &>/dev/null
info "Database '${DB_NAME}' reset"

# ── Clear access URL and init credentials ───────────────────────────────────────
section "Clearing access URL from .env..."
sed -i '' "s|^CODER_ACCESS_URL=.*|CODER_ACCESS_URL=|" "${ROOT_DIR}/.env"
rm -f "${ROOT_DIR}/coder-init.json"
info "Access URL cleared, coder-init.json removed"

echo ""
info "Coder has been reset — EKS and RDS are still running"
info "Re-deploy with: task coder && task init"
