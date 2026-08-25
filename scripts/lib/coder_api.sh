# shellcheck shell=bash
# Shared helper for scripts/logs/*.sh — authenticates to Coder and fetches a
# paginated API endpoint as JSON. Source colors.sh, cluster_context.sh, and
# port_forward.sh before this file.

# fetch_coder_json <endpoint> <output_file> <label>
fetch_coder_json() {
  local endpoint="$1" output_file="$2" label="$3"

  ensure_coder_port_forward
  local local_url="http://localhost:${CODER_PORT_FORWARD_LOCAL_PORT}"

  local token
  token=$(curl -sf -X POST "${local_url}/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

  section "Fetching ${label}..."
  curl -sf \
    -H "Coder-Session-Token: ${token}" \
    "${local_url}${endpoint}" \
    | jq '.' > "${output_file}"

  local count
  count=$(jq '.count' "${output_file}" 2>/dev/null || echo 0)
  info "Exported ${count} ${label} to ${output_file}"
}
