#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
TRUSTCHANNEL_CONFIG="${ROOT_DIR}/config/trustchannel-client.toml"

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
    software-properties-common

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

ensure_env_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
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

normalize_env_defaults() {
  local vless_packet_encoding trust_socks_port direct_port trust_port direct_name trust_name

  vless_packet_encoding="$(read_env_value "VLESS_PACKET_ENCODING")"
  trust_socks_port="$(read_env_value "TRUSTCHANNEL_UPSTREAM_SOCKS_PORT")"
  direct_port="$(read_env_value "VLESS_DIRECT_PORT")"
  trust_port="$(read_env_value "VLESS_TRUST_PORT")"
  direct_name="$(read_env_value "VLESS_DIRECT_NAME")"
  trust_name="$(read_env_value "VLESS_TRUST_NAME")"

  if [[ -z "${vless_packet_encoding}" ]]; then
    write_env_value "VLESS_PACKET_ENCODING" "xudp"
  fi

  if [[ -z "${trust_socks_port}" ]]; then
    write_env_value "TRUSTCHANNEL_UPSTREAM_SOCKS_PORT" "15080"
  fi

  if [[ -z "${direct_port}" ]]; then
    write_env_value "VLESS_DIRECT_PORT" "8443"
  fi

  if [[ -z "${trust_port}" ]]; then
    write_env_value "VLESS_TRUST_PORT" "443"
  fi

  if [[ -z "${direct_name}" ]]; then
    write_env_value "VLESS_DIRECT_NAME" "dockervpn-vless-vps"
  fi

  if [[ -z "${trust_name}" ]]; then
    write_env_value "VLESS_TRUST_NAME" "dockervpn-vless-trustchannel"
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

ensure_trustchannel_config() {
  [[ -f "${TRUSTCHANNEL_CONFIG}" ]] || fail "missing ${TRUSTCHANNEL_CONFIG}; copy config/trustchannel-client.toml.example and fill real credentials"
  chmod 600 "${TRUSTCHANNEL_CONFIG}"
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

wait_gateway_ready() {
  local i
  for i in $(seq 1 40); do
    if docker compose exec -T gateway test -f /opt/gateway.env >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "gateway did not become ready (/opt/gateway.env missing after start)"
}

print_debug() {
  local tc_port i out
  tc_port="$(read_env_value "TRUSTCHANNEL_UPSTREAM_SOCKS_PORT")"
  [[ -n "${tc_port}" ]] || tc_port="15080"

  wait_gateway_ready

  log "debug: docker status"
  docker compose ps

  log "debug: gateway summary"
  docker compose logs --tail=80 gateway || true

  log "debug: connection links"
  "${ROOT_DIR}/scripts/vless-link.sh" || true

  log "debug: egress checks"
  echo "host_ip=$(curl -4 -fsS --max-time 12 https://ifconfig.me/ip || echo FAIL)"
  echo "container_direct_ip=$(docker compose exec -T gateway curl -4 -fsS --max-time 12 https://ifconfig.me/ip || echo FAIL)"
  echo "container_trust_ip=$(docker compose exec -T gateway curl -4 -fsS --max-time 20 --socks5-hostname 127.0.0.1:${tc_port} https://ifconfig.me/ip || echo FAIL)"

  for i in $(seq 1 8); do
    out="$(docker compose exec -T gateway curl -4 -s --max-time 10 --socks5-hostname 127.0.0.1:${tc_port} -o /dev/null -w '%{http_code}' https://www.google.com/generate_204 || echo FAIL)"
    printf "trust_probe_%02d=%s\n" "${i}" "${out}"
    sleep 1
  done
}

main() {
  require_root
  require_ubuntu
  ensure_packages
  enable_docker
  ensure_env_file
  normalize_env_defaults
  ensure_trustchannel_config

  local server_host
  server_host="$(resolve_server_host)"
  write_env_value "SERVER_HOST" "${server_host}"

  log "using SERVER_HOST=${server_host}"
  build_and_start "${server_host}"
  print_debug

  log "install completed"
}

main "$@"
