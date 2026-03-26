#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if docker compose ps --status running --services 2>/dev/null | grep -qx "gateway"; then
  docker compose exec -T gateway /usr/local/bin/connection-info.sh
  exit 0
fi

echo "gateway container is not running"
echo "start it first: ./scripts/init-vless.sh"
exit 1
