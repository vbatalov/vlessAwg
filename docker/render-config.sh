#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${SERVER_HOST:?SERVER_HOST is required}"
VLESS_SNI="${VLESS_SNI:-www.cloudflare.com}"
VLESS_FP="${VLESS_FP:-chrome}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
VLESS_PACKET_ENCODING="${VLESS_PACKET_ENCODING:-xudp}"
VLESS_SHORT_ID="${VLESS_SHORT_ID:-}"

VLESS_PORT="${VLESS_PORT:-8443}"
VLESS_STATE_FILE="${VLESS_STATE_FILE:-/var/lib/dockervpn/vless-state.env}"

VLESS_NAME="${VLESS_NAME:-dockervpn-vless}"
VLESS_UUID="${VLESS_UUID:-}"

VLESS_STATE_UUID=""
VLESS_STATE_SHORT_ID=""
VLESS_STATE_PRIVATE_KEY=""
VLESS_STATE_PUBLIC_KEY=""

if [[ -f "${VLESS_STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  . "${VLESS_STATE_FILE}"
fi

make_uuid() {
  xray uuid
}

make_short_id() {
  od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
}

UUID="${VLESS_UUID:-${VLESS_STATE_UUID}}"
if [[ -z "${UUID}" ]]; then
  UUID="$(make_uuid)"
fi

SHORT_ID="${VLESS_SHORT_ID:-${VLESS_STATE_SHORT_ID}}"
if [[ -z "${SHORT_ID}" ]]; then
  SHORT_ID="$(make_short_id)"
fi

PRIVATE_KEY="${VLESS_STATE_PRIVATE_KEY}"
PUBLIC_KEY="${VLESS_STATE_PUBLIC_KEY}"
if [[ -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" ]]; then
  KEYS="$(xray x25519)"
  PRIVATE_KEY="$(printf '%s\n' "${KEYS}" | awk -F': *' '/^PrivateKey:/{print $2}')"
  PUBLIC_KEY="$(printf '%s\n' "${KEYS}" | awk -F': *' '/^PublicKey:/{print $2; exit} /^Password \(PublicKey\):/{print $2; exit}')"
fi

if [[ -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" ]]; then
  echo "failed to parse x25519 output" >&2
  if [[ -n "${KEYS:-}" ]]; then
    printf '%s\n' "${KEYS}" >&2
  fi
  exit 1
fi

mkdir -p "$(dirname "${VLESS_STATE_FILE}")"
cat > "${VLESS_STATE_FILE}" <<STATE
VLESS_STATE_UUID="${UUID}"
VLESS_STATE_SHORT_ID="${SHORT_ID}"
VLESS_STATE_PRIVATE_KEY="${PRIVATE_KEY}"
VLESS_STATE_PUBLIC_KEY="${PUBLIC_KEY}"
STATE
chmod 600 "${VLESS_STATE_FILE}"

cat > /etc/xray/config.json <<JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless",
      "listen": "0.0.0.0",
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "${VLESS_FLOW}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${VLESS_SNI}:443",
          "xver": 0,
          "serverNames": [
            "${VLESS_SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
JSON

cat > /opt/gateway.env <<ENV
SERVER_HOST="${SERVER_HOST}"
VLESS_SNI="${VLESS_SNI}"
VLESS_FP="${VLESS_FP}"
VLESS_FLOW="${VLESS_FLOW}"
VLESS_PACKET_ENCODING="${VLESS_PACKET_ENCODING}"
VLESS_PUBLIC_KEY="${PUBLIC_KEY}"
VLESS_SHORT_ID="${SHORT_ID}"
VLESS_PORT="${VLESS_PORT}"
VLESS_NAME="${VLESS_NAME}"
VLESS_UUID="${UUID}"
ENV
chmod 600 /opt/gateway.env
