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

fix_default_route() {
  local timeout=20
  while ! ip link show tun0 >/dev/null 2>&1; do
    ((timeout--)) || { log "tun0 not found before timeout; skipping route fix."; return 1; }
    sleep 1
  done

  if ip route show default 2>/dev/null | grep -q 'dev tun0'; then
    log "Default route already uses tun0."
    return 0
  fi

  log "Adjusting default route to use tun0."
  ip route del default || true
  ip route add default dev tun0
}

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

  if [[ -f "${CONFIG_SRC}/credentials.txt" ]]; then
    install -m 0600 "${CONFIG_SRC}/credentials.txt" "${CONFIG_DIR}/credentials.txt"
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
  if [[ ! -f "${auth_file}" && -n "${OPENVPN_AUTH_USER:-}" && -n "${OPENVPN_AUTH_PASS:-}" ]]; then
    auth_file="${CONFIG_DIR}/credentials.auto"
    {
      printf '%s\n' "${OPENVPN_AUTH_USER}"
      printf '%s\n' "${OPENVPN_AUTH_PASS}"
    } > "${auth_file}"
    chmod 0600 "${auth_file}"
  fi
  if [[ -f "${auth_file}" ]]; then
    chmod 0600 "${auth_file}" || true
    auth_args=(--auth-user-pass "${auth_file}")
  else
    log "No credentials file detected. Add credentials.txt under ${CONFIG_SRC} or set OPENVPN_AUTH_USER/OPENVPN_AUTH_PASS."
    exit 1
  fi

  openvpn \
    --config "${ACTIVE_CONFIG}" \
    --cd "${CONFIG_DIR}" \
    --writepid "${PID_FILE}" \
    --script-security 2 \
    --auth-nocache \
    --persist-key \
    --persist-tun \
    --verb "${OPENVPN_LOG_VERBOSITY:-3}" \
    "${auth_args[@]}" \
    "${extra[@]}" &
  local vpn_pid=$!

  fix_default_route

  wait "${vpn_pid}"
}

main "$@"
