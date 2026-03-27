#!/usr/bin/env bash
set -euo pipefail

PORT="${SSH_BYPASS_PORT:-22}"
MARK="${SSH_BYPASS_MARK:-22}"
TABLE="${SSH_BYPASS_TABLE:-128}"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

get_default_route() {
  local gw dev
  read -r _ _ gw _ dev _ <<<"$(ip route show default | head -n1)"
  [[ -n "$dev" ]] || {
    echo "No default route detected" >&2
    exit 1
  }
  echo "$gw" "$dev"
}

setup() {
  local gw dev
  read -r gw dev < <(get_default_route)
  echo "Detected default route: gw='${gw:-<none>}' dev='$dev'"

  echo "Setting up SSH bypass (port ${PORT}, mark ${MARK}, table ${TABLE})..."

  # Mark SSH traffic
  iptables -t mangle -C OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark "$MARK" 2>/dev/null ||
    iptables -t mangle -A OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark "$MARK"

  # Add IP rule
  ip rule show | grep -q "fwmark $MARK.*lookup $TABLE" || ip rule add fwmark "$MARK" table "$TABLE"

  # If the gateway is valid, use it; otherwise, just route through the device
  if ip route get "$gw" >/dev/null 2>&1; then
    ip route replace default via "$gw" dev "$dev" table "$TABLE"
  else
    echo "Gateway $gw not currently reachable; falling back to dev-only route."
    ip route replace default dev "$dev" table "$TABLE"
  fi

  echo "SSH bypass active."
}

teardown() {
  echo "Removing SSH bypass..."
  iptables -t mangle -D OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark "$MARK" 2>/dev/null || true
  ip rule del fwmark "$MARK" table "$TABLE" 2>/dev/null || true
  ip route flush table "$TABLE" 2>/dev/null || true
  echo "SSH bypass removed."
}

status() {
  echo "iptables:"
  iptables -t mangle -L OUTPUT -n | grep MARK || true
  echo
  echo "ip rule:"
  ip rule show | grep "$TABLE" || true
  echo
  echo "route table $TABLE:"
  ip route show table "$TABLE" || true
}

usage() { echo "Usage: $0 {setup|teardown|status}"; }

main() {
  require_root
  case "${1:-}" in
  setup) setup ;;
  teardown) teardown ;;
  status) status ;;
  *)
    usage
    exit 1
    ;;
  esac
}

main "$@"
