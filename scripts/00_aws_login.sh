#!/usr/bin/env bash
# Authenticate with AWS and print the active identity/region.
# Mirrors the AKS repo's `az login`: if AWS_PROFILE is SSO-backed, this opens a
# browser to establish/refresh the SSO session (aws sso login handles the AWS
# SDK's automatic credential refresh from there — no need to re-paste keys into
# .env). If AWS_PROFILE isn't SSO-backed, this just validates whatever
# credentials are already in the environment.

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

if [[ -n "${AWS_PROFILE:-}" ]] && aws configure get sso_session --profile "${AWS_PROFILE}" &>/dev/null; then
  section "Logging in to AWS SSO (profile: ${AWS_PROFILE})..."
  aws sso login --profile "${AWS_PROFILE}"
fi

section "Verifying AWS credentials (region: ${AWS_REGION})..."
if ! aws sts get-caller-identity --output table; then
  error "AWS credentials are invalid or expired."
  error "Refresh them (aws sso login, or however your session token is issued) and re-run 'task login'."
  exit 1
fi

echo ""
info "AWS credentials valid"
