#!/usr/bin/env sh
set -eu

. /opt/gateway.env

printf 'VLESS VPS:\n'
printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp&flow=%s&packetEncoding=%s#%s\n\n' \
  "$VLESS_DIRECT_UUID" "$SERVER_HOST" "$VLESS_DIRECT_PORT" "$VLESS_SNI" "$VLESS_FP" "$VLESS_PUBLIC_KEY" "$VLESS_SHORT_ID" "$VLESS_FLOW" "${VLESS_PACKET_ENCODING:-xudp}" "$VLESS_DIRECT_NAME"

printf 'VLESS TrustChannel:\n'
printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp&flow=%s&packetEncoding=%s#%s\n\n' \
  "$VLESS_TRUST_UUID" "$SERVER_HOST" "$VLESS_TRUST_PORT" "$VLESS_SNI" "$VLESS_FP" "$VLESS_PUBLIC_KEY" "$VLESS_SHORT_ID" "$VLESS_FLOW" "${VLESS_PACKET_ENCODING:-xudp}" "$VLESS_TRUST_NAME"
