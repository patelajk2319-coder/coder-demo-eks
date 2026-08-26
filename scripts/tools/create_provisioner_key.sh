#!/usr/bin/env bash
# Mint a provisioner key for an external provisioner (e.g. a team-owned
# cluster) to register against this control plane. Minting is a control-plane
# governance action — the requesting team receives the key value out-of-band,
# they never get admin access to this Coder instance to create their own.
# Usage: create_provisioner_key.sh <name> <tag-key>=<tag-value>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found — copy .env.example and fill in values"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL must be set in .env}"
: "${CODER_ADMIN_PASSWORD:?CODER_ADMIN_PASSWORD must be set in .env}"

KEY_NAME="${1:?Usage: create_provisioner_key.sh <name> <tag-key>=<tag-value>}"
KEY_TAG="${2:?Usage: create_provisioner_key.sh <name> <tag-key>=<tag-value>}"

ensure_coder_port_forward
LOCAL_CODER_URL="http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"

TOKEN=$(curl -sf -X POST "${LOCAL_CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

CODER_URL="${LOCAL_CODER_URL}" coder login "${LOCAL_CODER_URL}" --token "${TOKEN}" &>/dev/null

section "Minting provisioner key '${KEY_NAME}' (tag: ${KEY_TAG})..."
CODER_URL="${LOCAL_CODER_URL}" coder provisioner keys create "${KEY_NAME}" \
  --org default \
  --tag "${KEY_TAG}"

echo ""
warn "The key above is shown once — copy it into the requesting team's .env"
warn "as CODER_PROVISIONER_KEY now. It cannot be retrieved again; delete and"
warn "recreate the key if it's lost."
