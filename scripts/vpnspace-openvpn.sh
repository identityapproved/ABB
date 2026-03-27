#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS_NAME="${VPN_NAMESPACE:-vpnspace}"
VPN_USER="${VPN_USER:-${SUDO_USER:-${USER}}}"
VPN_USER_HOME="$(getent passwd "${VPN_USER}" | cut -d: -f6 || true)"
[[ -z "${VPN_USER_HOME}" ]] && VPN_USER_HOME="/home/${VPN_USER}"
CONFIG_DIR="${OPENVPN_CONFIG_DIR:-/opt/openvpn-configs}"
HOME_CONFIG_DIR="${OPENVPN_HOME_DIR:-${VPN_USER_HOME}/openvpn-configs}"
STATE_DIR="${OPENVPN_STATE_DIR:-/var/run/vpnspace-openvpn}"
PID_FILE="${STATE_DIR}/openvpn.pid"
CURRENT_FILE="${STATE_DIR}/current_config"
ACTIVE_CONFIG="${CONFIG_DIR}/active.ovpn"
LOG_FILE="${OPENVPN_LOG_FILE:-/var/log/vpnspace-openvpn.log}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

ensure_namespace() {
  if ! ip netns list | grep -q "^${NS_NAME}\b"; then
    echo "Namespace ${NS_NAME} not found. Run vpnspace.sh setup first." >&2
    exit 1
  fi
}

ensure_openvpn() {
  if ! command -v openvpn >/dev/null 2>&1; then
    echo "openvpn binary not found. Install openvpn before continuing." >&2
    exit 1
  fi
}

copy_with_delete() {
  local src="$1" dest="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${src}/" "${dest}/"
  else
    rm -rf "${dest:?}/"* "${dest:?}"/.[!.]* "${dest:?}"/..?* 2>/dev/null || true
    cp -a "${src}/." "${dest}/"
  fi
}

sync_home_configs() {
  if [[ -d "${HOME_CONFIG_DIR}" ]]; then
    install -d -m 0700 "${CONFIG_DIR}"
    copy_with_delete "${HOME_CONFIG_DIR}" "${CONFIG_DIR}"
    chmod -R go= "${CONFIG_DIR}"
  fi
}

list_configs() {
  find "${CONFIG_DIR}" -maxdepth 1 -type f -name '*.ovpn' ! -name 'active.ovpn' -printf '%f\n' | sort
}

pick_first_config() {
  list_configs | head -n1
}

current_config() {
  [[ -f "${CURRENT_FILE}" ]] && tr -d '\n' < "${CURRENT_FILE}"
}

pick_next_config() {
  local current="$1"
  mapfile -t configs < <(list_configs)
  local count="${#configs[@]}"
  [[ "${count}" -eq 0 ]] && return
  if [[ -z "${current}" ]]; then
    printf '%s\n' "${configs[0]}"
    return
  fi
  local i
  for ((i=0; i<count; i++)); do
    if [[ "${configs[i]}" == "${current}" ]]; then
      printf '%s\n' "${configs[(( (i+1) % count ))]}"
      return
    fi
  done
  printf '%s\n' "${configs[0]}"
}

set_active_config() {
  local cfg="$1"
  if [[ -z "${cfg}" || ! -f "${CONFIG_DIR}/${cfg}" ]]; then
    echo "Config ${cfg} not found under ${CONFIG_DIR}" >&2
    exit 1
  fi
  install -d -m 0700 "${CONFIG_DIR}"
  cp "${CONFIG_DIR}/${cfg}" "${ACTIVE_CONFIG}"
  chmod 0600 "${ACTIVE_CONFIG}"
  install -d -m 0755 "${STATE_DIR}"
  printf '%s\n' "${cfg}" > "${CURRENT_FILE}"
}

openvpn_running() {
  [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" >/dev/null 2>&1
}

start_openvpn() {
  ensure_namespace
  ensure_openvpn
  sync_home_configs
  local cfg="${1:-}"
  if [[ -z "${cfg}" ]]; then
    cfg="$(pick_first_config)"
  fi
  if [[ -z "${cfg}" ]]; then
    echo "No .ovpn files found in ${CONFIG_DIR}. Populate it (or ${HOME_CONFIG_DIR}) first." >&2
    exit 1
  fi
  if openvpn_running; then
    echo "OpenVPN already running (pid $(cat "${PID_FILE}")). Stop or rotate instead." >&2
    exit 1
  fi
  set_active_config "${cfg}"
  install -d -m 0755 "$(dirname "${PID_FILE}")"
  touch "${LOG_FILE}"
  chmod 0640 "${LOG_FILE}"

  ip netns exec "${NS_NAME}" openvpn \
    --config "${ACTIVE_CONFIG}" \
    --cd "${CONFIG_DIR}" \
    --writepid "${PID_FILE}" \
    --log-append "${LOG_FILE}" \
    --daemon \
    --persist-tun \
    --persist-key \
    --script-security 2

  echo "OpenVPN started inside namespace ${NS_NAME} using ${cfg}."
}

stop_openvpn() {
  if openvpn_running; then
    kill "$(cat "${PID_FILE}")"
    wait "$(cat "${PID_FILE}")" 2>/dev/null || true
    echo "OpenVPN stopped."
  else
    echo "OpenVPN not running."
  fi
  rm -f "${PID_FILE}"
}

status_openvpn() {
  if openvpn_running; then
    echo "OpenVPN running (pid $(cat "${PID_FILE}")), config: $(current_config)"
  else
    echo "OpenVPN is not running."
    return 1
  fi
}

rotate_openvpn() {
  ensure_namespace
  ensure_openvpn
  sync_home_configs
  if ! openvpn_running; then
    echo "OpenVPN is not running. Use start first." >&2
    exit 1
  fi
  local target="${1:-}"
  if [[ -z "${target}" ]]; then
    target="$(pick_next_config "$(current_config)")"
  fi
  if [[ -z "${target}" ]]; then
    echo "No other configs available to rotate to." >&2
    exit 1
  fi
  set_active_config "${target}"
  kill -HUP "$(cat "${PID_FILE}")"
  echo "OpenVPN rotation requested; now using ${target}."
}

print_configs() {
  list_configs
}

print_usage() {
  cat <<'EOF'
Usage: vpnspace-openvpn.sh <command> [args]

Commands:
  start [config.ovpn]   Start OpenVPN inside the vpnspace namespace.
  stop                  Stop the running OpenVPN instance.
  status                Show whether OpenVPN is running.
  rotate [config.ovpn]  Copy the given config (or next available) into active.ovpn and send SIGHUP.
  list                  List available .ovpn files under /opt/openvpn-configs.
  sync                  Manually sync ~/openvpn-configs into /opt/openvpn-configs.
EOF
}

main() {
  require_root "$@"
  local cmd="${1:-}"
  if [[ -z "${cmd}" ]]; then
    print_usage
    exit 1
  fi
  shift || true

  case "${cmd}" in
    start) start_openvpn "$@" ;;
    stop) stop_openvpn ;;
    status) status_openvpn ;;
    rotate) rotate_openvpn "$@" ;;
    list) list_configs ;;
    sync) sync_home_configs ;;
    *)
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
