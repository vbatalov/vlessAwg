#!/usr/bin/env sh
set -eu

SERVER_HOST="${SERVER_HOST:?SERVER_HOST is required}"
VLESS_PORT="${VLESS_PORT:-443}"
VLESS_SNI="${VLESS_SNI:-www.cloudflare.com}"
VLESS_FP="${VLESS_FP:-chrome}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
VLESS_NAME="${VLESS_NAME:-dockervpn-vless}"
VLESS_UUID="${VLESS_UUID:-}"
VLESS_SHORT_ID="${VLESS_SHORT_ID:-}"

UUID="${VLESS_UUID}"
if [ -z "${UUID}" ]; then
  UUID="$(xray uuid)"
fi

SHORT_ID="${VLESS_SHORT_ID}"
if [ -z "${SHORT_ID}" ]; then
  SHORT_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
fi

KEYS="$(xray x25519)"
PRIVATE_KEY="$(printf '%s\n' "${KEYS}" | awk -F': *' '/^PrivateKey:/{print $2}')"
PUBLIC_KEY="$(printf '%s\n' "${KEYS}" | awk -F': *' '/PublicKey/{print $2; exit}')"

if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ]; then
  echo "failed to parse x25519 output"
  printf '%s\n' "${KEYS}"
  exit 1
fi

mkdir -p /etc/xray /opt
cat > /etc/xray/config.json <<JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
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
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
JSON

cat > /opt/vless.env <<ENV
SERVER_HOST="${SERVER_HOST}"
VLESS_PORT="${VLESS_PORT}"
VLESS_UUID="${UUID}"
VLESS_SNI="${VLESS_SNI}"
VLESS_FP="${VLESS_FP}"
VLESS_FLOW="${VLESS_FLOW}"
VLESS_PUBLIC_KEY="${PUBLIC_KEY}"
VLESS_SHORT_ID="${SHORT_ID}"
VLESS_NAME="${VLESS_NAME}"
ENV

cat > /usr/local/bin/vless-link <<'EOF'
#!/usr/bin/env sh
set -eu
. /opt/vless.env
echo "vless://${VLESS_UUID}@${SERVER_HOST}:${VLESS_PORT}?encryption=none&security=reality&sni=${VLESS_SNI}&fp=${VLESS_FP}&pbk=${VLESS_PUBLIC_KEY}&sid=${VLESS_SHORT_ID}&type=tcp&flow=${VLESS_FLOW}#${VLESS_NAME}"
EOF
chmod +x /usr/local/bin/vless-link
