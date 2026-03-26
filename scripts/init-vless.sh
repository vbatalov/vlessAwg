#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
SERVER_HOST_ARG="${1:-}"
FORCE="${2:-}"

if [[ "${SERVER_HOST_ARG}" == "--force" ]]; then
  FORCE="--force"
  SERVER_HOST_ARG=""
fi

SERVER_HOST="${SERVER_HOST:-${SERVER_HOST_ARG}}"
if [[ -z "${SERVER_HOST}" && -f "${ENV_FILE}" ]]; then
  SERVER_HOST="$(awk -F= '/^SERVER_HOST=/{print $2; exit}' "${ENV_FILE}" | tr -d '"' | tr -d "'")"
fi
if [[ -z "${SERVER_HOST}" ]]; then
  echo "usage: ./scripts/init-vless.sh <server-ip> [--force]"
  echo "or set SERVER_HOST env"
  exit 1
fi

cd "${ROOT_DIR}"

echo "building image..."
if [[ "${FORCE}" == "--force" ]]; then
  SERVER_HOST="${SERVER_HOST}" docker compose build --no-cache gateway
else
  SERVER_HOST="${SERVER_HOST}" docker compose build gateway
fi
echo "starting container..."
docker compose up -d gateway
echo
echo "connection info:"
"${ROOT_DIR}/scripts/vless-link.sh"
