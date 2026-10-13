#!/usr/bin/env bash
# Start or stop the persistent Argo CD port-forward. Usage: argocd_port_forward.sh [stop]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found — copy .env.example and fill in values"
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"
# shellcheck source=scripts/lib/argocd_port_forward.sh
source "${SCRIPT_DIR}/../lib/argocd_port_forward.sh"

if [[ "${1:-}" == "stop" ]]; then
  stop_argocd_port_forward
  info "Port-forward stopped"
else
  ensure_argocd_port_forward
  info "Argo CD available at http://localhost:${ARGOCD_PORT_FORWARD_LOCAL_PORT}"
  info "Initial admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
fi
