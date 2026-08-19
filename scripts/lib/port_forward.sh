#!/usr/bin/env bash
# Persistent kubectl port-forward to Coder (its LoadBalancer is internal-only).
# Source, then call ensure_coder_port_forward / stop_coder_port_forward.
# Tracked via a PID file so it survives the script that started it.

CODER_PORT_FORWARD_LOCAL_PORT="${CODER_PORT_FORWARD_LOCAL_PORT:-8080}"
CODER_PORT_FORWARD_PID_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.coder-port-forward.pid"

_coder_port_forward_running() {
  [[ -f "${CODER_PORT_FORWARD_PID_FILE}" ]] && kill -0 "$(cat "${CODER_PORT_FORWARD_PID_FILE}")" 2>/dev/null
}

# Starts the port-forward if not already running, and leaves it running for
# subsequent commands (task port-forward-stop, or another 'task init' run).
ensure_coder_port_forward() {
  if _coder_port_forward_running; then
    info "Port-forward already running (PID $(cat "${CODER_PORT_FORWARD_PID_FILE}"))"
    return 0
  fi

  kubectl port-forward -n coder svc/coder "${CODER_PORT_FORWARD_LOCAL_PORT}:80" \
    >/dev/null 2>&1 &
  disown
  echo "$!" > "${CODER_PORT_FORWARD_PID_FILE}"

  for _ in $(seq 1 30); do
    curl -sf "http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}/healthz" &>/dev/null && return 0
    _coder_port_forward_running || break
    sleep 1
  done

  error "kubectl port-forward to svc/coder did not become ready"
  stop_coder_port_forward
  return 1
}

stop_coder_port_forward() {
  if _coder_port_forward_running; then
    kill "$(cat "${CODER_PORT_FORWARD_PID_FILE}")" 2>/dev/null
  fi
  rm -f "${CODER_PORT_FORWARD_PID_FILE}"
}
