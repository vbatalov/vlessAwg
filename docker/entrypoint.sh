#!/usr/bin/env bash
set -euo pipefail

AWG_CONFIG="${AWG_CONFIG:-/config/awg0.conf}"
AWG_INTERFACE="${AWG_INTERFACE:-awg0}"
AWG_ROUTE_TABLE="${AWG_ROUTE_TABLE:-100}"
AWG_ROUTE_MARK="${AWG_ROUTE_MARK:-100}"
VPN_UPSTREAM_SOCKS_PORT="${VPN_UPSTREAM_SOCKS_PORT:-15081}"
SOCKS_UPSTREAM_USER="${SOCKS_UPSTREAM_USER:-awgproxy}"
ENABLE_IPV6_TABLE="${ENABLE_IPV6_TABLE:-1}"

fail() {
  echo "fatal: $*" >&2
  exit 1
}

trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

require_tools() {
  command -v amneziawg-go >/dev/null || fail "amneziawg-go not found"
  command -v awg >/dev/null || fail "awg not found"
  command -v awg-quick >/dev/null || fail "awg-quick not found"
  command -v xray >/dev/null || fail "xray not found"
  command -v ip >/dev/null || fail "ip command not found"
  command -v iptables >/dev/null || fail "iptables not found"
  command -v danted >/dev/null || fail "danted not found"
}

ensure_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "container must run as root"
}

ensure_awg_config() {
  [[ -f "${AWG_CONFIG}" ]] || fail "missing AmneziaWG config at ${AWG_CONFIG}"
  grep -Eq '^[[:space:]]*Address[[:space:]]*=' "${AWG_CONFIG}" || fail "AWG config must include Address"
}

ensure_proxy_user() {
  if ! id -u "${SOCKS_UPSTREAM_USER}" >/dev/null 2>&1; then
    useradd --system --home /nonexistent --shell /usr/sbin/nologin "${SOCKS_UPSTREAM_USER}"
  fi
}

configure_dns() {
  local dns_line
  dns_line="$(
    awk -F= '
      /^[[:space:]]*DNS[[:space:]]*=/ {
        print $2
        exit
      }
    ' "${AWG_CONFIG}"
  )"

  if [[ -z "${dns_line//[[:space:]]/}" ]]; then
    return 0
  fi

  : > /etc/resolv.conf
  while IFS= read -r raw_dns; do
    dns="$(printf '%s' "${raw_dns}" | trim)"
    [[ -n "${dns}" ]] || continue
    echo "nameserver ${dns}" >> /etc/resolv.conf
  done < <(printf '%s\n' "${dns_line}" | tr ',' '\n')
}

sanitize_awg_config() {
  local sanitized="/run/${AWG_INTERFACE}.conf"
  awk '
    /^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*$/ { next }
    { print }
  ' "${AWG_CONFIG}" > "${sanitized}"
  chmod 600 "${sanitized}"
}

setup_awg_interface() {
  local sanitized="/run/${AWG_INTERFACE}.conf"
  local stripped="/run/${AWG_INTERFACE}.stripped.conf"

  if ip link show "${AWG_INTERFACE}" >/dev/null 2>&1; then
    ip link del "${AWG_INTERFACE}"
  fi

  LOG_LEVEL="${LOG_LEVEL:-info}" amneziawg-go "${AWG_INTERFACE}"
  awg-quick strip "${sanitized}" > "${stripped}"
  awg setconf "${AWG_INTERFACE}" "${stripped}"

  while IFS= read -r raw_address; do
    address="$(printf '%s' "${raw_address}" | trim)"
    [[ -n "${address}" ]] || continue
    ip address add "${address}" dev "${AWG_INTERFACE}"
  done < <(
    awk -F= '
      /^[[:space:]]*Address[[:space:]]*=/ {
        print $2
      }
    ' "${sanitized}" | tr ',' '\n'
  )

  mtu_value="$(awk -F= '
    /^[[:space:]]*MTU[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "${sanitized}")"

  ip link set dev "${AWG_INTERFACE}" up mtu "${mtu_value:-1420}"
}

setup_policy_routing() {
  local uid
  uid="$(id -u "${SOCKS_UPSTREAM_USER}")"

  if ! grep -Eq "^[[:space:]]*${AWG_ROUTE_TABLE}[[:space:]]+amnezia$" /etc/iproute2/rt_tables; then
    echo "${AWG_ROUTE_TABLE} amnezia" >> /etc/iproute2/rt_tables
  fi

  ip route replace default dev "${AWG_INTERFACE}" table "${AWG_ROUTE_TABLE}"
  ip rule del fwmark "${AWG_ROUTE_MARK}" table "${AWG_ROUTE_TABLE}" 2>/dev/null || true
  ip rule add fwmark "${AWG_ROUTE_MARK}" table "${AWG_ROUTE_TABLE}" priority 10000

  if [[ "${ENABLE_IPV6_TABLE}" == "1" ]] && ip -6 addr show dev "${AWG_INTERFACE}" | grep -q 'inet6 '; then
    ip -6 route replace default dev "${AWG_INTERFACE}" table "${AWG_ROUTE_TABLE}"
    ip -6 rule del fwmark "${AWG_ROUTE_MARK}" table "${AWG_ROUTE_TABLE}" 2>/dev/null || true
    ip -6 rule add fwmark "${AWG_ROUTE_MARK}" table "${AWG_ROUTE_TABLE}" priority 10000
  fi

  iptables -t mangle -D OUTPUT -m owner --uid-owner "${uid}" -j MARK --set-mark "${AWG_ROUTE_MARK}" 2>/dev/null || true
  iptables -t mangle -A OUTPUT -m owner --uid-owner "${uid}" -j MARK --set-mark "${AWG_ROUTE_MARK}"
}

render_danted_config() {
  cat > /etc/danted-vpn.conf <<CFG
logoutput: stderr
internal: 127.0.0.1 port = ${VPN_UPSTREAM_SOCKS_PORT}
external: ${AWG_INTERFACE}
socksmethod: none
user.privileged: root
user.notprivileged: ${SOCKS_UPSTREAM_USER}

client pass {
  from: 127.0.0.1/32 to: 0.0.0.0/0
  log: error connect disconnect
}

socks pass {
  from: 127.0.0.1/32 to: 0.0.0.0/0
  protocol: tcp udp
  log: error connect disconnect
}
CFG
}

start_danted() {
  danted -N 1 -f /etc/danted-vpn.conf &
}

show_summary() {
  echo "gateway started"
  echo "  awg config: ${AWG_CONFIG}"
  echo "  awg interface: ${AWG_INTERFACE}"
  echo "  vpn upstream socks: 127.0.0.1:${VPN_UPSTREAM_SOCKS_PORT}"
  echo "  route table/mark: ${AWG_ROUTE_TABLE}/${AWG_ROUTE_MARK}"
}

main() {
  ensure_root
  require_tools
  ensure_awg_config
  ensure_proxy_user
  configure_dns
  sanitize_awg_config
  setup_awg_interface
  setup_policy_routing
  render_danted_config
  start_danted
  /usr/local/bin/render-config.sh
  show_summary
  exec xray run -config /etc/xray/config.json
}

main "$@"
