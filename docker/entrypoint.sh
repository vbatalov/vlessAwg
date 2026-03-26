#!/usr/bin/env bash
set -euo pipefail

AWG_CONFIG="${AWG_CONFIG:-/config/awg0.conf}"
AWG_INTERFACE="${AWG_INTERFACE:-awg0}"
AWG_ROUTE_TABLE="${AWG_ROUTE_TABLE:-100}"
ENABLE_IPV6_TABLE="${ENABLE_IPV6_TABLE:-1}"
AWG_WATCHDOG_ENABLED="${AWG_WATCHDOG_ENABLED:-1}"
AWG_WATCHDOG_INTERVAL="${AWG_WATCHDOG_INTERVAL:-15}"
AWG_WATCHDOG_STALE_SECONDS="${AWG_WATCHDOG_STALE_SECONDS:-75}"
AWG_WATCHDOG_FAIL_THRESHOLD="${AWG_WATCHDOG_FAIL_THRESHOLD:-3}"
AWG_MTU_OVERRIDE="${AWG_MTU_OVERRIDE:-}"
AWG_TCP_MSS="${AWG_TCP_MSS:-1240}"
AWG_PERSISTENT_KEEPALIVE="${AWG_PERSISTENT_KEEPALIVE:-25}"
AWG_BACKEND="${AWG_BACKEND:-auto}"
AWG_LISTEN_PORT="${AWG_LISTEN_PORT:-}"

AWG_SOURCE_IPV4=""
AWG_SOURCE_IPV6=""
ACTIVE_AWG_BACKEND="unknown"

fail() {
  echo "fatal: $*" >&2
  exit 1
}

trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

require_tools() {
  command -v awg >/dev/null || fail "awg not found"
  command -v awg-quick >/dev/null || fail "awg-quick not found"
  command -v xray >/dev/null || fail "xray not found"
  command -v ip >/dev/null || fail "ip command not found"
  command -v iptables >/dev/null || fail "iptables not found"

  if [[ "${AWG_BACKEND}" == "userspace" ]]; then
    command -v amneziawg-go >/dev/null || fail "amneziawg-go not found"
  fi
}

ensure_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "container must run as root"
}

ensure_awg_config() {
  [[ -f "${AWG_CONFIG}" ]] || fail "missing AmneziaWG config at ${AWG_CONFIG}"
  grep -Eq '^[[:space:]]*Address[[:space:]]*=' "${AWG_CONFIG}" || fail "AWG config must include Address"
}

configure_dns() {
  local dns_line dns raw_dns
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

extract_awg_source_ips() {
  local sanitized address
  sanitized="/run/${AWG_INTERFACE}.conf"
  AWG_SOURCE_IPV4=""
  AWG_SOURCE_IPV6=""

  while IFS= read -r address; do
    address="$(printf '%s' "${address}" | trim)"
    [[ -n "${address}" ]] || continue
    address="${address%%/*}"

    if [[ -z "${AWG_SOURCE_IPV4}" && "${address}" == *.* ]]; then
      AWG_SOURCE_IPV4="${address}"
      continue
    fi

    if [[ -z "${AWG_SOURCE_IPV6}" && "${address}" == *:* ]]; then
      AWG_SOURCE_IPV6="${address}"
    fi
  done < <(
    awk -F= '
      /^[[:space:]]*Address[[:space:]]*=/ {
        print $2
      }
    ' "${sanitized}" | tr ',' '\n'
  )

  [[ -n "${AWG_SOURCE_IPV4}" ]] || fail "failed to detect AWG source IPv4 from Address"
}

create_awg_interface() {
  local kernel_err="/run/awg-kernel.err"

  ACTIVE_AWG_BACKEND="unknown"

  if [[ "${AWG_BACKEND}" == "auto" || "${AWG_BACKEND}" == "kernel" ]]; then
    if ip link add "${AWG_INTERFACE}" type amneziawg 2>"${kernel_err}"; then
      ACTIVE_AWG_BACKEND="kernel"
      return 0
    fi

    if [[ "${AWG_BACKEND}" == "kernel" ]]; then
      fail "kernel backend requested but unavailable: $(cat "${kernel_err}")"
    fi
  fi

  command -v amneziawg-go >/dev/null || fail "amneziawg-go not found for userspace backend"
  LOG_LEVEL="${LOG_LEVEL:-info}" amneziawg-go "${AWG_INTERFACE}"
  ACTIVE_AWG_BACKEND="userspace"
}

setup_awg_interface() {
  local sanitized="/run/${AWG_INTERFACE}.conf"
  local stripped="/run/${AWG_INTERFACE}.stripped.conf"
  local raw_address address mtu_value target_mtu

  if ip link show "${AWG_INTERFACE}" >/dev/null 2>&1; then
    ip link del "${AWG_INTERFACE}"
  fi

  create_awg_interface
  awg-quick strip "${sanitized}" > "${stripped}"
  awg setconf "${AWG_INTERFACE}" "${stripped}"
  if [[ -n "${AWG_LISTEN_PORT}" && "${AWG_LISTEN_PORT}" != "0" ]]; then
    awg set "${AWG_INTERFACE}" listen-port "${AWG_LISTEN_PORT}"
  fi


  if [[ -n "${AWG_PERSISTENT_KEEPALIVE}" && "${AWG_PERSISTENT_KEEPALIVE}" != "0" ]]; then
    while IFS= read -r peer; do
      [[ -n "${peer}" ]] || continue
      awg set "${AWG_INTERFACE}" peer "${peer}" persistent-keepalive "${AWG_PERSISTENT_KEEPALIVE}"
    done < <(awg show "${AWG_INTERFACE}" peers || true)
  fi

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

  target_mtu="${AWG_MTU_OVERRIDE:-${mtu_value:-1420}}"
  ip link set dev "${AWG_INTERFACE}" up mtu "${target_mtu}"

  extract_awg_source_ips
}

setup_policy_routing() {
  if ! grep -Eq "^[[:space:]]*${AWG_ROUTE_TABLE}[[:space:]]+amnezia$" /etc/iproute2/rt_tables; then
    echo "${AWG_ROUTE_TABLE} amnezia" >> /etc/iproute2/rt_tables
  fi

  ip route replace default dev "${AWG_INTERFACE}" table "${AWG_ROUTE_TABLE}"
  ip rule del from "${AWG_SOURCE_IPV4}/32" table "${AWG_ROUTE_TABLE}" 2>/dev/null || true
  ip rule add from "${AWG_SOURCE_IPV4}/32" table "${AWG_ROUTE_TABLE}" priority 10000

  if [[ "${ENABLE_IPV6_TABLE}" == "1" && -n "${AWG_SOURCE_IPV6}" ]]; then
    ip -6 route replace default dev "${AWG_INTERFACE}" table "${AWG_ROUTE_TABLE}"
    ip -6 rule del from "${AWG_SOURCE_IPV6}/128" table "${AWG_ROUTE_TABLE}" 2>/dev/null || true
    ip -6 rule add from "${AWG_SOURCE_IPV6}/128" table "${AWG_ROUTE_TABLE}" priority 10000
  fi

  iptables -t mangle -D OUTPUT -o "${AWG_INTERFACE}" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "${AWG_TCP_MSS}" 2>/dev/null || true
  iptables -t mangle -A OUTPUT -o "${AWG_INTERFACE}" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "${AWG_TCP_MSS}"
}

latest_handshake_age_seconds() {
  local latest now
  latest="$(awg show "${AWG_INTERFACE}" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')"

  if [[ -z "${latest}" || "${latest}" == "0" ]]; then
    echo "999999"
    return 0
  fi

  now="$(date +%s)"
  echo "$((now - latest))"
}

restart_awg_stack() {
  echo "watchdog: restarting ${AWG_INTERFACE}"
  sanitize_awg_config
  setup_awg_interface
  setup_policy_routing
}

start_awg_watchdog() {
  if [[ "${AWG_WATCHDOG_ENABLED}" != "1" ]]; then
    return 0
  fi

  (
    set +e
    local fail_count age
    fail_count=0

    while true; do
      sleep "${AWG_WATCHDOG_INTERVAL}"
      age="$(latest_handshake_age_seconds)"

      if [[ "${age}" -ge "${AWG_WATCHDOG_STALE_SECONDS}" ]]; then
        fail_count=$((fail_count + 1))
        echo "watchdog: stale handshake ${age}s (${fail_count}/${AWG_WATCHDOG_FAIL_THRESHOLD})"
      else
        fail_count=0
      fi

      if [[ "${fail_count}" -ge "${AWG_WATCHDOG_FAIL_THRESHOLD}" ]]; then
        restart_awg_stack
        fail_count=0
      fi
    done
  ) &
}

show_summary() {
  echo "gateway started"
  echo "  awg config: ${AWG_CONFIG}"
  echo "  awg interface: ${AWG_INTERFACE}"
  echo "  awg backend: ${ACTIVE_AWG_BACKEND}"
  echo "  awg listen port: ${AWG_LISTEN_PORT:-auto}"
  echo "  awg source ipv4: ${AWG_SOURCE_IPV4}"
  echo "  awg source ipv6: ${AWG_SOURCE_IPV6:-none}"
  echo "  route table: ${AWG_ROUTE_TABLE}"
  echo "  awg mtu override: ${AWG_MTU_OVERRIDE:-auto}"
  echo "  awg tcp mss: ${AWG_TCP_MSS}"
  echo "  awg keepalive: ${AWG_PERSISTENT_KEEPALIVE}"
  echo "  watchdog: enabled=${AWG_WATCHDOG_ENABLED} interval=${AWG_WATCHDOG_INTERVAL}s stale=${AWG_WATCHDOG_STALE_SECONDS}s threshold=${AWG_WATCHDOG_FAIL_THRESHOLD}"
}

main() {
  ensure_root
  require_tools
  ensure_awg_config
  configure_dns
  sanitize_awg_config
  setup_awg_interface
  setup_policy_routing
  export AWG_SOURCE_IPV4 AWG_SOURCE_IPV6
  /usr/local/bin/render-config.sh
  start_awg_watchdog
  show_summary
  exec xray run -config /etc/xray/config.json
}

main "$@"
