#!/usr/bin/env bash
# Display Coder access URL, admin credentials, and live cluster state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"

# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"

INIT_FILE="${ROOT_DIR}/coder-init.json"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Coder on EKS — Connection Info${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ -f "${INIT_FILE}" ]]; then
  ACCESS_URL=$(jq -r '.access_url'   "${INIT_FILE}")
  ADMIN_USER=$(jq -r '.admin_user'   "${INIT_FILE}")
  ADMIN_EMAIL=$(jq -r '.admin_email' "${INIT_FILE}")
  echo "  URL (VPC-internal): ${ACCESS_URL}"
  echo "  User:                ${ADMIN_USER}"
  echo "  Email:               ${ADMIN_EMAIL}"
  echo "  Password:            (see .env → CODER_ADMIN_PASSWORD)"
  echo ""
  info "For browser/CLI access from outside the VPC, run: task port-forward"
else
  warn "coder-init.json not found — run: task init"
fi

echo ""
section "EKS Cluster: ${EKS_CLUSTER_NAME:-unknown}"
echo "  Region: ${AWS_REGION:-unknown}"
echo "  RDS:    ${RDS_ENDPOINT:-unknown}"

echo ""
section "Pods (coder namespace)"
kubectl get pods -n coder 2>/dev/null || warn "coder namespace not found"

echo ""
section "Coder service"
kubectl get svc coder -n coder 2>/dev/null || warn "coder service not found"

echo ""
info "Export logs: task audit-logs | task ai-logs | task connection-logs"
echo ""
