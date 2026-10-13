#!/usr/bin/env bash
# Upgrade Coder to the latest (or a specified) version by bumping the
# targetRevision in gitops/coder/coder-app.yaml and letting Argo CD sync it —
# the chart version lives in git now, not in .env or Terraform.
# Usage: upgrade_coder.sh [TARGET_VERSION]
#   TARGET_VERSION — optional, e.g. 2.34.6. Defaults to the latest GitHub release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_FILE="${ROOT_DIR}/gitops/coder/coder-app.yaml"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/cluster_context.sh
source "${SCRIPT_DIR}/../lib/cluster_context.sh"

CURRENT_VERSION=$(grep -A2 'repoURL: https://helm.coder.com/v2' "${APP_FILE}" | grep targetRevision | awk '{print $2}')

# ── Resolve target version ─────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
  TARGET_VERSION="${1#v}"
  info "Target version specified: ${TARGET_VERSION}"
else
  section "Fetching latest Coder release..."
  TARGET_VERSION=$(curl -sf https://api.github.com/repos/coder/coder/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")
  info "Latest release: v${TARGET_VERSION}"
fi

if [[ "${CURRENT_VERSION}" == "${TARGET_VERSION}" ]]; then
  info "Already on v${CURRENT_VERSION} — nothing to do"
  exit 0
fi

info "Upgrading Coder: v${CURRENT_VERSION} → v${TARGET_VERSION}"

# ── Bump the Application's targetRevision, commit, push ───────────────────────
section "Updating ${APP_FILE}..."
sed -i '' "s|targetRevision: ${CURRENT_VERSION}|targetRevision: ${TARGET_VERSION}|" "${APP_FILE}"

git -C "${ROOT_DIR}" add "${APP_FILE}"
git -C "${ROOT_DIR}" commit -m "Upgrade Coder to v${TARGET_VERSION}"
git -C "${ROOT_DIR}" push

# ── Wait for Argo CD to sync ────────────────────────────────────────────────────
section "Waiting for Argo CD to sync the new version..."
kubectl -n argocd annotate application coder argocd.argoproj.io/refresh=hard --overwrite >/dev/null

for _ in $(seq 1 30); do
  HEALTH=$(kubectl get application coder -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  SYNC=$(kubectl get application coder -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  [[ "${HEALTH}" == "Healthy" && "${SYNC}" == "Synced" ]] && break
  sleep 10
done

if [[ "${HEALTH}" != "Healthy" || "${SYNC}" != "Synced" ]]; then
  error "Argo CD did not reach Synced/Healthy — check: kubectl get application coder -n argocd"
  exit 1
fi

echo ""
info "Coder upgraded to v${TARGET_VERSION}"
info "The local coder CLI may now be a version behind — reinstall from the server if commands start failing:"
info "  curl -fsSL \${LOCAL_CODER_URL}/install.sh | sh"
