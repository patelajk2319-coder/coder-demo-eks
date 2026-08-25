#!/usr/bin/env bash
# Export Coder AI Bridge interception logs to data/ai-logs.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"
# shellcheck source=scripts/lib/coder_api.sh
source "${SCRIPT_DIR}/../lib/coder_api.sh"

# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL must be set in .env}"
: "${CODER_ADMIN_PASSWORD:?CODER_ADMIN_PASSWORD must be set in .env}"

mkdir -p "${ROOT_DIR}/data"

fetch_coder_json "/api/v2/aibridge/interceptions?limit=100&offset=0" \
  "${ROOT_DIR}/data/ai-logs.json" "AI Bridge interceptions"
