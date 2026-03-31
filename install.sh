#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
AWG_CONFIG="${ROOT_DIR}/config/awg0.conf"

FORCE_REBUILD=0
SERVER_HOST_ARG=""

for arg in "$@"; do
  case "${arg}" in
    --force)
      FORCE_REBUILD=1
      ;;
    *)
      SERVER_HOST_ARG="${arg}"
      ;;
  esac
done

log() {
  printf "\n[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  echo "fatal: $*" >&2
  exit 1
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "run as root: sudo ./install.sh"
}

require_ubuntu() {
  [[ -f /etc/os-release ]] || fail "cannot detect OS"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || fail "unsupported OS: ${ID:-unknown} (expected ubuntu)"
}

ensure_packages() {
  log "installing system packages"
  apt-get update -y
  apt-get install -y \
    git \
    curl \
    ca-certificates \
    gnupg2 \
    software-properties-common \
    python3-launchpadlib \
    linux-headers-"$(uname -r)"

  if command -v docker >/dev/null 2>&1; then
    log "docker already installed, skipping engine install"
  else
    log "docker not found, installing engine"
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io; then
      apt-get install -y docker.io
    fi
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log "installing docker compose plugin"
    if ! apt-get install -y docker-compose-plugin; then
      apt-get install -y docker-compose-v2
    fi
  fi
}

enable_docker() {
  log "enabling docker service"
  systemctl enable --now docker
}

install_amneziawg_kernel_module() {
  if modinfo amneziawg >/dev/null 2>&1; then
    log "amneziawg module already installed"
  else
    log "installing amneziawg kernel module"
    add-apt-repository -y ppa:amnezia/ppa
    apt-get update -y
    apt-get install -y amneziawg
  fi

  echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
  modprobe amneziawg
}

configure_sysctl() {
  log "configuring sysctl for policy routing"
  cat > /etc/sysctl.d/99-dockervpn.conf <<'EOF'
net.ipv4.conf.all.src_valid_mark=1
EOF
  sysctl --system >/dev/null
}

ensure_env_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  fi
}

normalize_env_tuning() {
  local mtu mss keepalive wd_interval wd_stale wd_threshold wd_cooldown probe_enabled probe_url probe_timeout probe_threshold vless_packet_encoding

  mtu="$(read_env_value "AWG_MTU_OVERRIDE")"
  mss="$(read_env_value "AWG_TCP_MSS")"
  keepalive="$(read_env_value "AWG_PERSISTENT_KEEPALIVE")"
  wd_interval="$(read_env_value "AWG_WATCHDOG_INTERVAL")"
  wd_stale="$(read_env_value "AWG_WATCHDOG_STALE_SECONDS")"
  wd_threshold="$(read_env_value "AWG_WATCHDOG_FAIL_THRESHOLD")"
  wd_cooldown="$(read_env_value "AWG_WATCHDOG_RESTART_COOLDOWN")"
  probe_enabled="$(read_env_value "AWG_WATCHDOG_PROBE_ENABLED")"
  probe_url="$(read_env_value "AWG_WATCHDOG_PROBE_URL")"
  probe_timeout="$(read_env_value "AWG_WATCHDOG_PROBE_TIMEOUT")"
  probe_threshold="$(read_env_value "AWG_WATCHDOG_PROBE_FAIL_THRESHOLD")"
  vless_packet_encoding="$(read_env_value "VLESS_PACKET_ENCODING")"

  if [[ -z "${mtu}" || "${mtu}" == "1376" || "${mtu}" == "1200" ]]; then
    write_env_value "AWG_MTU_OVERRIDE" "1000"
  fi

  if [[ -z "${mss}" || "${mss}" == "1336" || "${mss}" == "1160" ]]; then
    write_env_value "AWG_TCP_MSS" "960"
  fi

  if [[ -z "${keepalive}" || "${keepalive}" == "25" || "${keepalive}" == "10" ]]; then
    write_env_value "AWG_PERSISTENT_KEEPALIVE" "5"
  fi

  if [[ -z "${wd_interval}" || "${wd_interval}" == "15" ]]; then
    write_env_value "AWG_WATCHDOG_INTERVAL" "5"
  fi

  if [[ -z "${wd_stale}" || "${wd_stale}" == "20" || "${wd_stale}" == "75" ]]; then
    write_env_value "AWG_WATCHDOG_STALE_SECONDS" "45"
  fi

  if [[ -z "${wd_threshold}" || "${wd_threshold}" == "1" || "${wd_threshold}" == "3" ]]; then
    write_env_value "AWG_WATCHDOG_FAIL_THRESHOLD" "2"
  fi

  if [[ -z "${wd_cooldown}" ]]; then
    write_env_value "AWG_WATCHDOG_RESTART_COOLDOWN" "25"
  fi

  if [[ -z "${probe_enabled}" || "${probe_enabled}" == "1" ]]; then
    write_env_value "AWG_WATCHDOG_PROBE_ENABLED" "0"
  fi

  if [[ -z "${probe_url}" ]]; then
    write_env_value "AWG_WATCHDOG_PROBE_URL" "http://1.1.1.1"
  fi

  if [[ -z "${probe_timeout}" ]]; then
    write_env_value "AWG_WATCHDOG_PROBE_TIMEOUT" "6"
  fi

  if [[ -z "${probe_threshold}" || "${probe_threshold}" == "1" ]]; then
    write_env_value "AWG_WATCHDOG_PROBE_FAIL_THRESHOLD" "6"
  fi

  if [[ -z "${vless_packet_encoding}" ]]; then
    write_env_value "VLESS_PACKET_ENCODING" "xudp"
  fi
}

read_env_value() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key {print $2; exit}' "${ENV_FILE}" | tr -d '"' | tr -d "'"
}

write_env_value() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    echo "${key}=${value}" >> "${ENV_FILE}"
  fi
}

detect_public_ipv4() {
  local ip=""
  ip="$(curl -4 -fsS --max-time 10 https://ifconfig.me/ip || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"
  fi
  echo "${ip}"
}

resolve_server_host() {
  local current from_env detected
  current="${SERVER_HOST_ARG}"
  from_env="$(read_env_value "SERVER_HOST")"

  if [[ -z "${current}" || "${current}" == "1.1.1.1" ]]; then
    if [[ -n "${from_env}" && "${from_env}" != "1.1.1.1" ]]; then
      current="${from_env}"
    fi
  fi

  if [[ -z "${current}" || "${current}" == "1.1.1.1" ]]; then
    detected="$(detect_public_ipv4)"
    [[ -n "${detected}" ]] || fail "cannot detect public IPv4; pass it explicitly: ./install.sh <server-ip>"
    current="${detected}"
  fi

  echo "${current}"
}

ensure_awg_config() {
  [[ -f "${AWG_CONFIG}" ]] || fail "missing ${AWG_CONFIG}"
  chmod 600 "${AWG_CONFIG}"
}

build_and_start() {
  local server_host="$1"
  log "building docker image"
  if [[ "${FORCE_REBUILD}" -eq 1 ]]; then
    SERVER_HOST="${server_host}" docker compose build --no-cache gateway
  else
    SERVER_HOST="${server_host}" docker compose build gateway
  fi

  log "starting gateway container"
  docker compose up -d gateway
}

print_debug() {
  log "debug: docker status"
  docker compose ps

  log "debug: gateway summary"
  docker compose logs --tail=80 gateway || true

  log "debug: connection links"
  "${ROOT_DIR}/scripts/vless-link.sh" || true

  log "debug: egress checks"
  echo "host_ip=$(curl -4 -fsS --max-time 12 https://ifconfig.me/ip || echo FAIL)"
  echo "socks_vps=$(curl -4 -fsS --max-time 12 --socks5-hostname 127.0.0.1:1082 https://ifconfig.me/ip || echo FAIL)"
  echo "socks_vpn=$(curl -4 -fsS --max-time 20 --socks5-hostname 127.0.0.1:1081 https://ifconfig.me/ip || echo FAIL)"

  local i out
  for i in $(seq 1 12); do
    out="$(curl -4 -s --max-time 8 --socks5 127.0.0.1:1081 http://1.1.1.1 -o /dev/null -w "%{http_code}" || echo FAIL)"
    printf "vpn_probe_%02d=%s\n" "${i}" "${out}"
    sleep 1
  done
}

main() {
  require_root
  require_ubuntu
  ensure_packages
  enable_docker
  install_amneziawg_kernel_module
  configure_sysctl
  ensure_env_file
  normalize_env_tuning
  ensure_awg_config

  local server_host
  server_host="$(resolve_server_host)"
  write_env_value "SERVER_HOST" "${server_host}"
  write_env_value "AWG_BACKEND" "kernel"
  write_env_value "AWG_LISTEN_PORT" "20000"

  log "using SERVER_HOST=${server_host}"
  build_and_start "${server_host}"
  print_debug

  log "install completed"
}

main "$@"
