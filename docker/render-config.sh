#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${SERVER_HOST:?SERVER_HOST is required}"
VLESS_SNI="${VLESS_SNI:-www.cloudflare.com}"
VLESS_FP="${VLESS_FP:-chrome}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
VLESS_SHORT_ID="${VLESS_SHORT_ID:-}"

VLESS_DIRECT_PORT="${VLESS_DIRECT_PORT:-443}"
VLESS_VPN_PORT="${VLESS_VPN_PORT:-8443}"
SOCKS_DIRECT_PORT="${SOCKS_DIRECT_PORT:-1082}"
SOCKS_VPN_PORT="${SOCKS_VPN_PORT:-1081}"
VPN_UPSTREAM_SOCKS_PORT="${VPN_UPSTREAM_SOCKS_PORT:-15081}"

VLESS_DIRECT_NAME="${VLESS_DIRECT_NAME:-dockervpn-vless-vps}"
VLESS_VPN_NAME="${VLESS_VPN_NAME:-dockervpn-vless-vpn}"
VLESS_DIRECT_UUID="${VLESS_DIRECT_UUID:-}"
VLESS_VPN_UUID="${VLESS_VPN_UUID:-}"

make_uuid() {
  xray uuid
}

make_short_id() {
  od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
}

DIRECT_UUID="${VLESS_DIRECT_UUID}"
if [[ -z "${DIRECT_UUID}" ]]; then
  DIRECT_UUID="$(make_uuid)"
fi

VPN_UUID="${VLESS_VPN_UUID}"
if [[ -z "${VPN_UUID}" ]]; then
  VPN_UUID="$(make_uuid)"
fi

SHORT_ID="${VLESS_SHORT_ID}"
if [[ -z "${SHORT_ID}" ]]; then
  SHORT_ID="$(make_short_id)"
fi

KEYS="$(xray x25519)"
PRIVATE_KEY="$(printf '%s\n' "${KEYS}" | awk -F': *' '/^PrivateKey:/{print $2}')"
PUBLIC_KEY="$(printf '%s\n' "${KEYS}" | awk -F': *' '/^PublicKey:/{print $2; exit}')"

if [[ -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" ]]; then
  echo "failed to parse x25519 output" >&2
  printf '%s\n' "${KEYS}" >&2
  exit 1
fi

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
      "tag": "vless-vpn",
      "listen": "0.0.0.0",
      "port": ${VLESS_VPN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${VPN_UUID}",
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
      "tag": "socks-direct",
      "listen": "0.0.0.0",
      "port": ${SOCKS_DIRECT_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "0.0.0.0"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "socks-vpn",
      "listen": "0.0.0.0",
      "port": ${SOCKS_VPN_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "0.0.0.0"
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
      "tag": "vpn",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": ${VPN_UPSTREAM_SOCKS_PORT}
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
        "inboundTag": ["vless-direct", "socks-direct"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["vless-vpn", "socks-vpn"],
        "outboundTag": "vpn"
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
VLESS_PUBLIC_KEY="${PUBLIC_KEY}"
VLESS_SHORT_ID="${SHORT_ID}"
VLESS_DIRECT_PORT="${VLESS_DIRECT_PORT}"
VLESS_VPN_PORT="${VLESS_VPN_PORT}"
SOCKS_DIRECT_PORT="${SOCKS_DIRECT_PORT}"
SOCKS_VPN_PORT="${SOCKS_VPN_PORT}"
VLESS_DIRECT_UUID="${DIRECT_UUID}"
VLESS_VPN_UUID="${VPN_UUID}"
VLESS_DIRECT_NAME="${VLESS_DIRECT_NAME}"
VLESS_VPN_NAME="${VLESS_VPN_NAME}"
ENV
