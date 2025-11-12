#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[openvpn-gw] %s\n' "$*"
}

CONFIG_SRC="${OPENVPN_SRC_DIR:-/opt/openvpn-configs}"
CONFIG_DIR="${OPENVPN_CONFIG_DIR:-/etc/openvpn/configs}"
ACTIVE_CONFIG="${OPENVPN_ACTIVE_CONFIG:-${CONFIG_DIR}/active.ovpn}"
STATE_DIR="${OPENVPN_STATE_DIR:-/var/run/openvpn}"
PID_FILE="${OPENVPN_PID_FILE:-${STATE_DIR}/openvpn.pid}"
CURRENT_FILE="${OPENVPN_CURRENT_FILE:-${STATE_DIR}/current_config}"
AUTH_FILE_ENV="${OPENVPN_AUTH_FILE:-}"

ensure_timezone() {
  if [[ -n "${TZ:-}" && -f "/usr/share/zoneinfo/${TZ}" ]]; then
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
  fi
}

copy_configs() {
  if [[ ! -d "${CONFIG_SRC}" ]]; then
    log "Source directory ${CONFIG_SRC} not mounted. Provide ProtonVPN OpenVPN configs under /opt/openvpn-configs."
    exit 1
  fi
  install -d -m 0700 "${CONFIG_DIR}"
  local copied=0
  while IFS= read -r cfg; do
    [[ -f "${cfg}" ]] || continue
    local base="${cfg##*/}"
    install -m 0600 "${cfg}" "${CONFIG_DIR}/${base}"
    copied=1
  done < <(find "${CONFIG_SRC}" -mindepth 1 -maxdepth 1 -type f -name '*.ovpn' -print)
  if ((copied == 0)); then
    log "No .ovpn files found in ${CONFIG_SRC}. Add ProtonVPN configs there before starting the container."
    exit 1
  fi
}

select_initial_config() {
  local preferred="${OPENVPN_CONFIG:-}"
  if [[ -n "${preferred}" && -f "${CONFIG_DIR}/${preferred}" ]]; then
    echo "${preferred}"
    return
  fi
  local first
  first="$(find "${CONFIG_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.ovpn' ! -name 'active.ovpn' -print | sed 's#.*/##' | sort | head -n1)"
  if [[ -z "${first}" ]]; then
    log "No OpenVPN configuration files available under ${CONFIG_DIR}."
    exit 1
  fi
  if [[ -n "${preferred}" ]]; then
    log "Preferred config ${preferred} not found. Falling back to ${first}."
  fi
  echo "${first}"
}

activate_config() {
  local cfg_name="$1"
  cp "${CONFIG_DIR}/${cfg_name}" "${ACTIVE_CONFIG}"
  chmod 0600 "${ACTIVE_CONFIG}"
  printf '%s\n' "${cfg_name}" > "${CURRENT_FILE}"
}

main() {
  ensure_timezone
  mkdir -p "${STATE_DIR}"
  copy_configs
  local initial
  initial="$(select_initial_config)"
  activate_config "${initial}"
  log "Launching OpenVPN with ${initial}."

  local extra=()
  if [[ -n "${OPENVPN_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2086
    eval "set -- ${OPENVPN_EXTRA_ARGS}"
    extra=("$@")
  fi

  local auth_args=()
  local auth_file="${AUTH_FILE_ENV}"
  if [[ -z "${auth_file}" ]]; then
    auth_file="${CONFIG_DIR}/credentials.txt"
  fi
  if [[ -f "${auth_file}" ]]; then
    chmod 0600 "${auth_file}" || true
    auth_args=(--auth-user-pass "${auth_file}")
  fi

  exec openvpn \
    --config "${ACTIVE_CONFIG}" \
    --cd "${CONFIG_DIR}" \
    --writepid "${PID_FILE}" \
    --script-security 2 \
    --auth-nocache \
    --persist-key \
    --persist-tun \
    --verb "${OPENVPN_LOG_VERBOSITY:-3}" \
    "${auth_args[@]}" \
    "${extra[@]}"
}

main "$@"
