#!/usr/bin/env bash
# Start or stop the persistent Coder port-forward. Usage: port_forward.sh [stop]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/../lib/colors.sh"
# shellcheck source=scripts/lib/port_forward.sh
source "${SCRIPT_DIR}/../lib/port_forward.sh"

if [[ "${1:-}" == "stop" ]]; then
  stop_coder_port_forward
  info "Port-forward stopped"
else
  ensure_coder_port_forward
  info "Coder available at http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"
fi
