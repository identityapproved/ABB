#!/usr/bin/env bash
set -euo pipefail

# Defaults
PORT="${SSH_BYPASS_PORT:-22}"
MARK="${SSH_BYPASS_MARK:-22}"
TABLE="${SSH_BYPASS_TABLE:-128}"
RULE_FILE="${SSH_BYPASS_RULE_FILE:-/etc/iptables.rules}"
RC_LOCAL="${SSH_BYPASS_RC_LOCAL:-/etc/rc.local}"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

get_default_gateway() {
  local gw dev
  read -r _ _ gw _ dev _ <<<"$(ip route show default | head -n1)"
  if [[ -z "$gw" || -z "$dev" ]]; then
    echo "Error: Could not detect default gateway." >&2
    exit 1
  fi
  echo "$gw $dev"
}

setup() {
  local gw dev
  read -r gw dev < <(get_default_gateway)

  echo "Default gateway: $gw on $dev"

  echo "Configuring SSH bypass on port ${PORT} (mark ${MARK}, table ${TABLE})..."

  # Mark outbound SSH traffic
  if ! iptables -t mangle -C OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark "$MARK" 2>/dev/null; then
    iptables -t mangle -A OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark "$MARK"
  fi

  # Create routing rule
  if ! ip rule show | grep -q "fwmark $MARK.*lookup $TABLE"; then
    ip rule add fwmark "$MARK" table "$TABLE"
  fi

  # Create routing table with the *real* gateway
  ip route replace default via "$gw" dev "$dev" table "$TABLE"

  # Save and make persistent
  iptables-save >"$RULE_FILE"
  if [[ ! -f "$RC_LOCAL" ]]; then
    cat >"$RC_LOCAL" <<'EOF'
#!/bin/sh
exit 0
EOF
  fi
  if ! grep -q "iptables-restore < $RULE_FILE" "$RC_LOCAL"; then
    sed -i "/^exit 0/i iptables-restore < $RULE_FILE" "$RC_LOCAL"
  fi
  if ! grep -q "ip rule add fwmark $MARK table $TABLE" "$RC_LOCAL"; then
    sed -i "/^exit 0/i ip rule add fwmark $MARK table $TABLE" "$RC_LOCAL"
  fi
  if ! grep -q "ip route replace default via $gw dev $dev table $TABLE" "$RC_LOCAL"; then
    sed -i "/^exit 0/i ip route replace default via $gw dev $dev table $TABLE" "$RC_LOCAL"
  fi
  chmod +x "$RC_LOCAL"

  echo "SSH bypass configured and persisted."
}

teardown() {
  echo "Removing SSH bypass..."
  iptables -t mangle -D OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark "$MARK" 2>/dev/null || true
  ip rule del fwmark "$MARK" table "$TABLE" 2>/dev/null || true
  ip route flush table "$TABLE" 2>/dev/null || true
  echo "SSH bypass removed."
}

status() {
  echo "=== iptables mangle OUTPUT rules ==="
  iptables -t mangle -L OUTPUT -n --line-numbers | grep --color=never MARK || true
  echo
  echo "=== ip rules ==="
  ip rule show | grep --color=never "$TABLE" || true
  echo
  echo "=== routing table $TABLE ==="
  ip route show table "$TABLE" || true
}

usage() {
  echo "Usage: $0 {setup|teardown|status}"
}

main() {
  require_root
  local cmd="${1:-}"
  case "$cmd" in
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
