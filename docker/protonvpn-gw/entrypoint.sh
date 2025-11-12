#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[protonvpn-gw] %s\n' "$*"
}

require_env() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    log "Environment variable ${var} is required."
    exit 1
  fi
}

ensure_cli_initialized() {
  if [[ ! -f /root/.pvpn-cli/protonvpn_openvpn_configurations.json ]]; then
    log "Initializing protonvpn-cli for the first time..."
    protonvpn init --protocol wireguard --username "${PROTONVPN_USERNAME}" --password "${PROTONVPN_PASSWORD}" || true
  fi
}

connect_vpn() {
  if protonvpn status | grep -q "Connected"; then
    log "Already connected."
    return
  fi
  log "Connecting to ProtonVPN (${PROTONVPN_CONNECT:-"--fastest"})..."
  protonvpn connect "${PROTONVPN_CONNECT:---fastest}"
}

main() {
  log "Starting ProtonVPN gateway container ($(date))."
  require_env PROTONVPN_USERNAME
  require_env PROTONVPN_PASSWORD
  ensure_cli_initialized
  connect_vpn

  log "Entering health loop."
  while true; do
    sleep 300
    if ! protonvpn status | grep -q "Connected"; then
      log "Connection dropped; reconnecting..."
      protonvpn connect "${PROTONVPN_CONNECT:---fastest}"
    fi
  done
}

main "$@"
