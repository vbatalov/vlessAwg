#!/usr/bin/env bash
set -euo pipefail

TRUSTCHANNEL_CONFIG="${TRUSTCHANNEL_CONFIG:-/config/trustchannel-client.toml}"
TRUSTCHANNEL_UPSTREAM_SOCKS_PORT="${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT:-15080}"
TRUSTCHANNEL_RUNTIME_CONFIG="/run/trustchannel-client.toml"

fail() {
  echo "fatal: $*" >&2
  exit 1
}

require_tools() {
  command -v trusttunnel_client >/dev/null || fail "trusttunnel_client not found"
  command -v xray >/dev/null || fail "xray not found"
}

ensure_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "container must run as root"
}

ensure_trustchannel_config() {
  [[ -f "${TRUSTCHANNEL_CONFIG}" ]] || fail "missing TrustChannel config at ${TRUSTCHANNEL_CONFIG}"
  [[ -s "${TRUSTCHANNEL_CONFIG}" ]] || fail "TrustChannel config is empty: ${TRUSTCHANNEL_CONFIG}"
}

render_trustchannel_config() {
  if grep -Eq '^[[:space:]]*\[endpoint\][[:space:]]*$' "${TRUSTCHANNEL_CONFIG}"; then
    awk '
      /^\[listener\]/ { exit }
      { print }
    ' "${TRUSTCHANNEL_CONFIG}" > "${TRUSTCHANNEL_RUNTIME_CONFIG}"
  else
    cat > "${TRUSTCHANNEL_RUNTIME_CONFIG}" <<'BASE'
loglevel = "info"
vpn_mode = "general"
killswitch_enabled = true
killswitch_allow_ports = []
post_quantum_group_enabled = true
exclusions = []
dns_upstreams = []

[endpoint]
BASE
    sed 's/^[[:space:]]*client_random_prefix[[:space:]]*=/client_random =/' "${TRUSTCHANNEL_CONFIG}" >> "${TRUSTCHANNEL_RUNTIME_CONFIG}"
  fi

  cat >> "${TRUSTCHANNEL_RUNTIME_CONFIG}" <<CONFIG
[listener]
[listener.socks]
address = "127.0.0.1:${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT}"
username = ""
password = ""
CONFIG

  chmod 600 "${TRUSTCHANNEL_RUNTIME_CONFIG}"
}

wait_for_trustchannel() {
  local i
  for i in $(seq 1 40); do
    if (: > "/dev/tcp/127.0.0.1/${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT}") >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "TrustChannel socks listener did not start on 127.0.0.1:${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT}"
}

start_trustchannel() {
  trusttunnel_client -c "${TRUSTCHANNEL_RUNTIME_CONFIG}" &
  wait_for_trustchannel
}

show_summary() {
  echo "gateway started"
  echo "  trustchannel config: ${TRUSTCHANNEL_CONFIG}"
  echo "  trustchannel runtime config: ${TRUSTCHANNEL_RUNTIME_CONFIG}"
  echo "  trustchannel upstream socks: 127.0.0.1:${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT}"
}

main() {
  ensure_root
  require_tools
  ensure_trustchannel_config
  render_trustchannel_config
  start_trustchannel
  /usr/local/bin/render-config.sh
  show_summary
  exec xray run -config /etc/xray/config.json
}

main "$@"
