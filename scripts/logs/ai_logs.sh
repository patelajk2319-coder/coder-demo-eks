#!/usr/bin/env bash
# Export Coder AI Bridge interception logs to data/ai-logs.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_FILE="${ROOT_DIR}/data/ai-logs.json"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"

# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL must be set in .env}"
: "${CODER_ADMIN_PASSWORD:?CODER_ADMIN_PASSWORD must be set in .env}"

mkdir -p "${ROOT_DIR}/data"

# Coder's LoadBalancer is internal-only — reach it via port-forward.
ensure_coder_port_forward
LOCAL_CODER_URL="http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"

TOKEN=$(curl -sf -X POST "${LOCAL_CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

section "Fetching AI Bridge interception log..."
curl -sf \
  -H "Coder-Session-Token: ${TOKEN}" \
  "${LOCAL_CODER_URL}/api/v2/aibridge/interceptions?limit=100&offset=0" \
  | jq '.' > "${OUTPUT_FILE}"

COUNT=$(jq '.count' "${OUTPUT_FILE}" 2>/dev/null || echo 0)
info "Exported ${COUNT} AI Bridge interceptions to ${OUTPUT_FILE}"
