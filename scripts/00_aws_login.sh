#!/usr/bin/env bash
# Validate AWS credentials and print the active identity/region.
# Unlike Azure, there's no interactive browser login step here — credentials
# come from ~/.aws/config and ~/.aws/credentials (or whatever AWS_PROFILE points
# at). This just confirms they're valid before we deploy anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"

# shellcheck source=/dev/null
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

: "${AWS_REGION:?AWS_REGION must be set in .env}"

section "Verifying AWS credentials (region: ${AWS_REGION})..."
if ! aws sts get-caller-identity --output table; then
  error "AWS credentials are invalid or expired."
  error "Refresh them (aws sso login, or however your session token is issued) and re-run 'task login'."
  exit 1
fi

echo ""
info "AWS credentials valid"
