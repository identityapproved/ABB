#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${OPENVPN_CONFIG_DIR:-/etc/openvpn/configs}"
ACTIVE_CONFIG="${OPENVPN_ACTIVE_CONFIG:-${CONFIG_DIR}/active.ovpn}"
STATE_DIR="${OPENVPN_STATE_DIR:-/var/run/openvpn}"
METADATA_FILE="${OPENVPN_CURRENT_FILE:-${STATE_DIR}/current_config}"
PID_FILE="${OPENVPN_PID_FILE:-${STATE_DIR}/openvpn.pid}"
LOCK_FILE="${OPENVPN_LOCK_FILE:-${STATE_DIR}/rotate.lock}"

log() {
  printf '[openvpn-rotate] %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: openvpn-config-switch [--next|--random|<config.ovpn>]
Rotate the running OpenVPN gateway to a different ProtonVPN configuration.
EOF
  exit 1
}

list_configs() {
  find "${CONFIG_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.ovpn' ! -name 'active.ovpn' -print | sed 's#.*/##' | sort
}

current_config() {
  if [[ -f "${METADATA_FILE}" ]]; then
    tr -d '\n' < "${METADATA_FILE}"
  fi
}

pick_next() {
  local current="$1"
  local -a configs=()
  while IFS= read -r line; do
    configs+=("${line}")
  done < <(list_configs)
  if ((${#configs[@]} == 0)); then
    log "No OpenVPN configs available to rotate."
    exit 1
  fi
  if [[ -z "${current}" ]]; then
    echo "${configs[0]}"
    return
  fi
  local i
  for ((i=0; i<${#configs[@]}; i++)); do
    if [[ "${configs[i]}" == "${current}" ]]; then
      echo "${configs[(( (i+1) % ${#configs[@]} ))]}"
      return
    fi
  done
  echo "${configs[0]}"
}

pick_random() {
  mapfile -t configs < <(list_configs)
  if ((${#configs[@]} == 0)); then
    log "No OpenVPN configs available to rotate."
    exit 1
  fi
  local idx=$(( RANDOM % ${#configs[@]} ))
  echo "${configs[idx]}"
}

reload_openvpn() {
  if [[ ! -f "${PID_FILE}" ]]; then
    log "PID file ${PID_FILE} not found; is OpenVPN running?"
    return
  fi
  local pid
  pid="$(tr -d '\n' < "${PID_FILE}")"
  if [[ -z "${pid}" ]]; then
    log "PID file empty; cannot signal OpenVPN."
    return
  fi
  kill -HUP "${pid}"
  log "Sent SIGHUP to OpenVPN (pid ${pid})."
}

switch_to() {
  local target="$1"
  if [[ ! -f "${CONFIG_DIR}/${target}" ]]; then
    log "Config ${target} not found under ${CONFIG_DIR}."
    exit 1
  fi
  install -m 0600 "${CONFIG_DIR}/${target}" "${ACTIVE_CONFIG}"
  printf '%s\n' "${target}" > "${METADATA_FILE}"
  log "Prepared ${target} as the active config."
  reload_openvpn
}

main() {
  local mode="next"
  local explicit=""
  if [[ $# -gt 0 ]]; then
    case "$1" in
      --next|next) mode="next" ;;
      --random|random) mode="random" ;;
      -*)
        usage
        ;;
      *)
        mode="explicit"
        explicit="$1"
        ;;
    esac
  fi

  exec 9>"${LOCK_FILE}"
  flock -x 9

  local target
  case "${mode}" in
    next)
      target="$(pick_next "$(current_config)")"
      ;;
    random)
      target="$(pick_random)"
      ;;
    explicit)
      target="${explicit}"
      ;;
  esac

  switch_to "${target}"
}

main "$@"
