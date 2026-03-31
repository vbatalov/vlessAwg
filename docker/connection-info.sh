#!/usr/bin/env sh
set -eu

. /opt/gateway.env

printf 'VLESS VPS:\n'
printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp&flow=%s&packetEncoding=%s#%s\n\n' \
  "$VLESS_DIRECT_UUID" "$SERVER_HOST" "$VLESS_DIRECT_PORT" "$VLESS_SNI" "$VLESS_FP" "$VLESS_PUBLIC_KEY" "$VLESS_SHORT_ID" "$VLESS_FLOW" "${VLESS_PACKET_ENCODING:-xudp}" "$VLESS_DIRECT_NAME"

printf 'VLESS VPN:\n'
printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp&flow=%s&packetEncoding=%s#%s\n\n' \
  "$VLESS_VPN_UUID" "$SERVER_HOST" "$VLESS_VPN_PORT" "$VLESS_SNI" "$VLESS_FP" "$VLESS_PUBLIC_KEY" "$VLESS_SHORT_ID" "$VLESS_FLOW" "${VLESS_PACKET_ENCODING:-xudp}" "$VLESS_VPN_NAME"

printf 'SOCKS VPS: %s:%s\n' "$SERVER_HOST" "$SOCKS_DIRECT_PORT"
printf 'SOCKS VPN: %s:%s\n' "$SERVER_HOST" "$SOCKS_VPN_PORT"
