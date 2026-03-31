#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${SERVER_HOST:?SERVER_HOST is required}"
VLESS_SNI="${VLESS_SNI:-www.cloudflare.com}"
VLESS_FP="${VLESS_FP:-chrome}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
VLESS_PACKET_ENCODING="${VLESS_PACKET_ENCODING:-xudp}"
VLESS_SHORT_ID="${VLESS_SHORT_ID:-}"

VLESS_DIRECT_PORT="${VLESS_DIRECT_PORT:-8443}"
VLESS_TRUST_PORT="${VLESS_TRUST_PORT:-443}"
VLESS_STATE_FILE="${VLESS_STATE_FILE:-/var/lib/dockervpn/vless-state.env}"

VLESS_DIRECT_NAME="${VLESS_DIRECT_NAME:-dockervpn-vless-vps}"
VLESS_TRUST_NAME="${VLESS_TRUST_NAME:-dockervpn-vless-trustchannel}"
VLESS_DIRECT_UUID="${VLESS_DIRECT_UUID:-}"
VLESS_TRUST_UUID="${VLESS_TRUST_UUID:-}"
TRUSTCHANNEL_UPSTREAM_SOCKS_PORT="${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT:-15080}"

VLESS_STATE_DIRECT_UUID=""
VLESS_STATE_TRUST_UUID=""
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

DIRECT_UUID="${VLESS_DIRECT_UUID:-${VLESS_STATE_DIRECT_UUID}}"
if [[ -z "${DIRECT_UUID}" ]]; then
  DIRECT_UUID="$(make_uuid)"
fi

TRUST_UUID="${VLESS_TRUST_UUID:-${VLESS_STATE_TRUST_UUID}}"
if [[ -z "${TRUST_UUID}" ]]; then
  TRUST_UUID="$(make_uuid)"
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
VLESS_STATE_DIRECT_UUID="${DIRECT_UUID}"
VLESS_STATE_TRUST_UUID="${TRUST_UUID}"
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
      "tag": "vless-direct",
      "listen": "0.0.0.0",
      "port": ${VLESS_DIRECT_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${DIRECT_UUID}",
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
    },
    {
      "tag": "vless-trust",
      "listen": "0.0.0.0",
      "port": ${VLESS_TRUST_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${TRUST_UUID}",
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
      "tag": "trustchannel",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": ${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT}
          }
        ]
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["vless-direct"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["vless-trust"],
        "outboundTag": "trustchannel"
      }
    ]
  }
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
VLESS_DIRECT_PORT="${VLESS_DIRECT_PORT}"
VLESS_TRUST_PORT="${VLESS_TRUST_PORT}"
VLESS_DIRECT_NAME="${VLESS_DIRECT_NAME}"
VLESS_TRUST_NAME="${VLESS_TRUST_NAME}"
VLESS_DIRECT_UUID="${DIRECT_UUID}"
VLESS_TRUST_UUID="${TRUST_UUID}"
TRUSTCHANNEL_UPSTREAM_SOCKS_PORT="${TRUSTCHANNEL_UPSTREAM_SOCKS_PORT}"
ENV
chmod 600 /opt/gateway.env
