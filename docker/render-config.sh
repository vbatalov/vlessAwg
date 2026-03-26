#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${SERVER_HOST:?SERVER_HOST is required}"
VLESS_SNI="${VLESS_SNI:-www.cloudflare.com}"
VLESS_FP="${VLESS_FP:-chrome}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
VLESS_SHORT_ID="${VLESS_SHORT_ID:-}"

VLESS_DIRECT_PORT="${VLESS_DIRECT_PORT:-8443}"
VLESS_VPN_PORT="${VLESS_VPN_PORT:-443}"
SOCKS_DIRECT_PORT="${SOCKS_DIRECT_PORT:-1082}"
SOCKS_VPN_PORT="${SOCKS_VPN_PORT:-1081}"
VLESS_STATE_FILE="${VLESS_STATE_FILE:-/var/lib/dockervpn/vless-state.env}"

VLESS_DIRECT_NAME="${VLESS_DIRECT_NAME:-dockervpn-vless-vps}"
VLESS_VPN_NAME="${VLESS_VPN_NAME:-dockervpn-vless-vpn}"
VLESS_DIRECT_UUID="${VLESS_DIRECT_UUID:-}"
VLESS_VPN_UUID="${VLESS_VPN_UUID:-}"
AWG_SOURCE_IPV4="${AWG_SOURCE_IPV4:-}"
AWG_CONFIG="${AWG_CONFIG:-/config/awg0.conf}"

VLESS_STATE_DIRECT_UUID=""
VLESS_STATE_VPN_UUID=""
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

detect_awg_source_ipv4() {
  local ip
  ip="$(
    awk -F= '
      /^[[:space:]]*Address[[:space:]]*=/ {
        print $2
        exit
      }
    ' "${AWG_CONFIG}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/' | cut -d/ -f1
  )"

  [[ -n "${ip}" ]] || {
    echo "failed to detect AWG source IPv4" >&2
    exit 1
  }

  echo "${ip}"
}

if [[ -z "${AWG_SOURCE_IPV4}" ]]; then
  AWG_SOURCE_IPV4="$(detect_awg_source_ipv4)"
fi

DIRECT_UUID="${VLESS_DIRECT_UUID:-${VLESS_STATE_DIRECT_UUID}}"
if [[ -z "${DIRECT_UUID}" ]]; then
  DIRECT_UUID="$(make_uuid)"
fi

VPN_UUID="${VLESS_VPN_UUID:-${VLESS_STATE_VPN_UUID}}"
if [[ -z "${VPN_UUID}" ]]; then
  VPN_UUID="$(make_uuid)"
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
VLESS_STATE_VPN_UUID="${VPN_UUID}"
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
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "sendThrough": "${AWG_SOURCE_IPV4}"
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
