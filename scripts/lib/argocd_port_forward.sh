#!/usr/bin/env bash
# Persistent kubectl port-forward to Argo CD's server (internal-only, same as
# Coder's). Source, then call ensure_argocd_port_forward / stop_argocd_port_forward.

ARGOCD_PORT_FORWARD_LOCAL_PORT="${ARGOCD_PORT_FORWARD_LOCAL_PORT:-8443}"
ARGOCD_PORT_FORWARD_PID_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.argocd-port-forward.pid"

_argocd_port_forward_running() {
  [[ -f "${ARGOCD_PORT_FORWARD_PID_FILE}" ]] && kill -0 "$(cat "${ARGOCD_PORT_FORWARD_PID_FILE}")" 2>/dev/null
}

ensure_argocd_port_forward() {
  if _argocd_port_forward_running; then
    info "Port-forward already running (PID $(cat "${ARGOCD_PORT_FORWARD_PID_FILE}"))"
    return 0
  fi

  kubectl port-forward -n argocd svc/argocd-server "${ARGOCD_PORT_FORWARD_LOCAL_PORT}:80" \
    >/dev/null 2>&1 &
  disown
  echo "$!" > "${ARGOCD_PORT_FORWARD_PID_FILE}"

  for _ in $(seq 1 30); do
    curl -sf "http://localhost:${ARGOCD_PORT_FORWARD_LOCAL_PORT}/healthz" &>/dev/null && return 0
    _argocd_port_forward_running || break
    sleep 1
  done

  error "kubectl port-forward to svc/argocd-server did not become ready"
  stop_argocd_port_forward
  return 1
}

stop_argocd_port_forward() {
  if _argocd_port_forward_running; then
    kill "$(cat "${ARGOCD_PORT_FORWARD_PID_FILE}")" 2>/dev/null
  fi
  rm -f "${ARGOCD_PORT_FORWARD_PID_FILE}"
}
