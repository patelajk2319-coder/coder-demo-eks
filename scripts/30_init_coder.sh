#!/usr/bin/env bash
# Initialise Coder: create admin user, write credentials to coder-init.json,
# mint a long-lived API token for the coderd Terraform provider (task coder-config).

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
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

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

# License upload and provisioner-key minting are now managed declaratively by
# `task coder-config` (terraform/coderd, coderd_license/coderd_provisioner_key)
# — not this script. See below for the one-time API token that step needs.

# ── Mint a long-lived API token for Terraform (the coderd provider) ───────────
# A dedicated token, not this script's own interactive session token above:
# keeps Terraform's auth independent of CODER_SESSION_DURATION and password
# logins. Shown once — if CODER_API_TOKEN in .env stops working (revoked,
# expired), clear it and re-run this script to mint a fresh one.
if [[ -z "${CODER_API_TOKEN:-}" ]]; then
  section "Minting a long-lived API token for Terraform (coderd provider)..."
  CODER_URL="${LOCAL_CODER_URL}" coder login "${LOCAL_CODER_URL}" --token "${TOKEN}" &>/dev/null

  API_TOKEN=$(CODER_URL="${LOCAL_CODER_URL}" coder tokens create \
    --name terraform-coderd \
    --lifetime 876h)

  if [[ -z "${API_TOKEN}" ]]; then
    error "Failed to mint a Terraform API token"
    exit 1
  fi

  echo ""
  warn "CODER_API_TOKEN (shown once — add it to .env now):"
  warn "  ${API_TOKEN}"
  warn "Needed by: task coder-config (this repo) and coder-template-api-python's .env"
else
  info "CODER_API_TOKEN already set in .env — skipping mint"
fi

echo ""
info "Coder initialised"
info "Coder URL (VPC-internal): ${CODER_ACCESS_URL}"
info "Local access:             ${LOCAL_CODER_URL}"
info "Admin user:               ${CODER_ADMIN_EMAIL}"
info "Port-forward left running — stop with: task port-forward-stop"
info "Next: add CODER_API_TOKEN to .env (if just minted), then run: task coder-config"
