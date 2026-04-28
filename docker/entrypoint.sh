#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "fatal: $*" >&2
  exit 1
}

require_tools() {
  command -v xray >/dev/null || fail "xray not found"
}

ensure_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "container must run as root"
}

show_summary() {
  echo "gateway started"
  echo "  mode: VLESS only"
}

main() {
  ensure_root
  require_tools
  /usr/local/bin/render-config.sh
  show_summary
  exec xray run -config /etc/xray/config.json
}

main "$@"
