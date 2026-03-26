#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if docker compose ps --status running --services 2>/dev/null | grep -qx "xray"; then
  docker compose exec -T xray /usr/local/bin/vless-link
  exit 0
fi

docker compose run --rm --no-deps xray /usr/local/bin/vless-link
