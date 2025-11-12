#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[protonvpn-gw] %s\n' "$*"
}

CLI_STATE_DIR="/root/.pvpn-cli"
CONNECT_ARGS="${PROTONVPN_CONNECT:---fastest}"
AUTO_CONNECT="${PROTONVPN_AUTO_CONNECT:-true}"

cli_initialized() {
  [[ -f "${CLI_STATE_DIR}/protonvpn_openvpn_configurations.json" ]]
}

attempt_connect() {
  if ! cli_initialized; then
    log "CLI not initialized yet. Exec into the container and run 'protonvpn init' interactively."
    return 1
  fi
  if protonvpn status | grep -q "Connected"; then
    return 0
  fi
  log "Attempting ProtonVPN connect ${CONNECT_ARGS}..."
  if protonvpn connect ${CONNECT_ARGS}; then
    log "Connected to ProtonVPN."
    return 0
  fi
  log "Connect command failed (likely awaiting interactive input)."
  return 1
}

main() {
  log "Starting ProtonVPN gateway container ($(date))."
  if [[ "${AUTO_CONNECT}" =~ ^(1|true|yes|on)$ ]]; then
    attempt_connect || true
  else
    log "AUTO_CONNECT disabled; waiting for manual protonvpn connect."
  fi

  while true; do
    sleep 300
    if [[ "${AUTO_CONNECT}" =~ ^(1|true|yes|on)$ ]]; then
      if ! protonvpn status | grep -q "Connected"; then
        log "Connection not active; retrying..."
        attempt_connect || true
      fi
    fi
  done
}

main "$@"
