#!/usr/bin/env bash
# Initialise Coder: create admin user, write credentials to coder-init.json, apply license.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/lib/cluster_context.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/lib/port_forward.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  error ".env not found"
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "${ROOT_DIR}/.env"; set +a

: "${CODER_ACCESS_URL:?CODER_ACCESS_URL must be set in .env — run task coder first}"
: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL must be set in .env}"
: "${CODER_ADMIN_PASSWORD:?CODER_ADMIN_PASSWORD must be set in .env}"

if ! command -v coder &>/dev/null; then
  section "Installing Coder CLI..."
  brew install coder/coder/coder
fi

# CODER_ACCESS_URL is the internal NLB hostname — unreachable from outside the
# VPC, so API calls go through a port-forward instead. Left running after this
# script exits (task port-forward-stop to tear it down).
section "Starting port-forward to Coder..."
ensure_coder_port_forward
LOCAL_CODER_URL="http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"
info "Coder reachable via ${LOCAL_CODER_URL}"

# ── Create admin user (first-time only) ───────────────────────────────────────
section "Creating Coder admin user..."

# A 404 means no first user yet; 200 means one already exists.
FIRST_USER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${LOCAL_CODER_URL}/api/v2/users/first")

if [[ "${FIRST_USER_STATUS}" == "404" ]]; then
  CODER_URL="${LOCAL_CODER_URL}" coder login \
    --first-user-email    "${CODER_ADMIN_EMAIL}" \
    --first-user-password "${CODER_ADMIN_PASSWORD}" \
    --first-user-username "coderadmin" \
    --first-user-trial=false
  info "Admin user created"
else
  info "Admin user already exists — continuing"
fi

# ── Obtain session token ───────────────────────────────────────────────────────
section "Obtaining session token..."

TOKEN=$(curl -sf -X POST "${LOCAL_CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

if [[ -z "${TOKEN}" ]]; then
  error "Failed to obtain session token — check admin credentials in .env"
  exit 1
fi

cat > "${ROOT_DIR}/coder-init.json" <<EOF
{
  "access_url": "${CODER_ACCESS_URL}",
  "admin_email": "${CODER_ADMIN_EMAIL}",
  "session_token": "${TOKEN}"
}
EOF
chmod 600 "${ROOT_DIR}/coder-init.json"
info "Credentials written to coder-init.json"

# ── Apply license ──────────────────────────────────────────────────────────────
LICENSE_FILE="${ROOT_DIR}/licence.lic"
if [[ -f "${LICENSE_FILE}" ]]; then
  section "Checking for an existing license..."
  EXISTING=$(curl -sf "${LOCAL_CODER_URL}/api/v2/licenses" \
    -H "Coder-Session-Token: ${TOKEN}" | jq 'length')
  if [[ "${EXISTING}" -gt 0 ]]; then
    info "License already active — skipping upload"
  else
    section "Uploading license..."
    curl -sf -X POST "${LOCAL_CODER_URL}/api/v2/licenses" \
      -H "Coder-Session-Token: ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"license\":\"$(cat "${LICENSE_FILE}")\"}" >/dev/null
    info "License applied"
  fi
fi

echo ""
info "Coder initialised"
info "Coder URL (VPC-internal): ${CODER_ACCESS_URL}"
info "Local access:             ${LOCAL_CODER_URL}"
info "Admin user:               ${CODER_ADMIN_EMAIL}"
info "Port-forward left running — stop with: task port-forward-stop"
