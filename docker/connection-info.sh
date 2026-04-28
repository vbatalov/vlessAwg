#!/usr/bin/env sh
set -eu

. /opt/gateway.env

printf 'VLESS:\n'
printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp&flow=%s&packetEncoding=%s#%s\n' \
  "$VLESS_UUID" "$SERVER_HOST" "$VLESS_PORT" "$VLESS_SNI" "$VLESS_FP" "$VLESS_PUBLIC_KEY" "$VLESS_SHORT_ID" "$VLESS_FLOW" "${VLESS_PACKET_ENCODING:-xudp}" "$VLESS_NAME"
