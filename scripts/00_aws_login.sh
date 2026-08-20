#!/usr/bin/env bash
# Authenticate with AWS. Mirrors the AKS repo's `az login`: if AWS_PROFILE is
# SSO-backed, opens a browser to refresh the session (no need to re-paste keys
# into .env). Otherwise just validates whatever credentials are present.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"

# shellcheck source=/dev/null
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

if [[ -n "${AWS_PROFILE:-}" ]] && aws configure get sso_session --profile "${AWS_PROFILE}" &>/dev/null; then
  section "Logging in to AWS SSO (profile: ${AWS_PROFILE})..."
  aws sso login --profile "${AWS_PROFILE}"
fi

section "Verifying AWS credentials..."
if ! aws sts get-caller-identity --output table; then
  error "AWS credentials are invalid or expired."
  error "Refresh them (aws sso login, or however your session token is issued) and re-run 'task login'."
  exit 1
fi

echo ""
info "AWS credentials valid"
