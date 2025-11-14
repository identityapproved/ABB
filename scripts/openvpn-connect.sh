#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_USER="${VPN_USER:-${SUDO_USER:-${USER}}}"
VPN_USER_HOME="$(getent passwd "${VPN_USER}" | cut -d: -f6 || true)"
[[ -z "${VPN_USER_HOME}" ]] && VPN_USER_HOME="/home/${VPN_USER}"

CONFIG_DIR="${OPENVPN_CONFIG_DIR:-/opt/openvpn-configs}"
HOME_CONFIG_DIR="${OPENVPN_HOME_DIR:-${VPN_USER_HOME}/openvpn-configs}"
STATE_DIR="${OPENVPN_STATE_DIR:-/var/run/openvpn-host}"
PID_FILE="${STATE_DIR}/openvpn.pid"
CURRENT_FILE="${STATE_DIR}/current_config"
ROUTE_FILE="${STATE_DIR}/route.env"
ACTIVE_CONFIG="${CONFIG_DIR}/active.ovpn"
LOG_FILE="${OPENVPN_LOG_FILE:-/var/log/openvpn-host.log}"
DEFAULT_BYPASS_MARK="${SSH_BYPASS_MARK:-22}"
DEFAULT_BYPASS_TABLE="${SSH_BYPASS_TABLE:-100}"
DEFAULT_SSH_PORT="${SSH_BYPASS_PORT:-22}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E "$0" "$@"
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
  [[ -d "${CONFIG_DIR}" ]] || return
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

default_route_info() {
  local line
  line="$(ip route show default | head -n1)"
  [[ -z "${line}" ]] && return 1
  local gw dev
  gw="$(awk '/default/ {for (i=1;i<=NF;i++) if ($i=="via") print $(i+1)}' <<<"${line}")"
  dev="$(awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' <<<"${line}")"
  if [[ -z "${gw}" || -z "${dev}" ]]; then
    return 1
  fi
  printf '%s %s\n' "${gw}" "${dev}"
}

first_remote_host() {
  awk '/^[[:space:]]*remote[[:space:]]+/ {print $2; exit}' "${ACTIVE_CONFIG}" 2>/dev/null
}

resolve_host_ip() {
  local host="$1"
  if [[ -z "${host}" ]]; then
    return
  fi
  if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "${host}"
    return
  fi
  getent ahostsv4 "${host}" | awk '{print $1; exit}'
}

ensure_host_route() {
  local dest="$1" gw="$2" dev="$3"
  [[ -z "${dest}" || -z "${gw}" || -z "${dev}" ]] && return
  ip route replace "${dest}/32" via "${gw}" dev "${dev}" >/dev/null 2>&1 || \
    ip route add "${dest}/32" via "${gw}" dev "${dev}" >/dev/null 2>&1 || true
}

record_routes() {
  local gw="$1" dev="$2" remote_ip="$3" ssh_ip="$4" ssh_port="$5" ssh_bypass="$6"
  install -d -m 0755 "${STATE_DIR}"
  {
    printf 'DEFAULT_GW=%q\n' "${gw}"
    printf 'DEFAULT_DEV=%q\n' "${dev}"
    printf 'REMOTE_IP=%q\n' "${remote_ip}"
    printf 'SSH_IP=%q\n' "${ssh_ip}"
    printf 'SSH_PORT=%q\n' "${ssh_port}"
    printf 'SSH_BYPASS=%q\n' "${ssh_bypass}"
    printf 'BYPASS_MARK_VALUE=%q\n' "${DEFAULT_BYPASS_MARK}"
    printf 'BYPASS_TABLE_ID=%q\n' "${DEFAULT_BYPASS_TABLE}"
  } > "${ROUTE_FILE}"
  chmod 0600 "${ROUTE_FILE}"
}

restore_routes() {
  [[ -f "${ROUTE_FILE}" ]] || return
  # shellcheck disable=SC1090
  source "${ROUTE_FILE}"
  if [[ -n "${REMOTE_IP:-}" && -n "${DEFAULT_GW:-}" && -n "${DEFAULT_DEV:-}" ]]; then
    ip route del "${REMOTE_IP}/32" >/dev/null 2>&1 || true
  fi
  if [[ -n "${SSH_IP:-}" && -n "${DEFAULT_GW:-}" && -n "${DEFAULT_DEV:-}" ]]; then
    ip route del "${SSH_IP}/32" >/dev/null 2>&1 || true
  fi
  if [[ -n "${DEFAULT_GW:-}" && -n "${DEFAULT_DEV:-}" ]]; then
    ip route replace default via "${DEFAULT_GW}" dev "${DEFAULT_DEV}" >/dev/null 2>&1 || true
  fi
  if [[ "${SSH_BYPASS:-false}" == "true" ]]; then
    local mark="${BYPASS_MARK_VALUE:-${DEFAULT_BYPASS_MARK}}"
    local table="${BYPASS_TABLE_ID:-${DEFAULT_BYPASS_TABLE}}"
    remove_ssh_bypass "${SSH_PORT:-}" "${mark}" "${table}"
  fi
  rm -f "${ROUTE_FILE}"
}

credentials_file() {
  local candidate
  for candidate in credentials.txt credentials.text; do
    if [[ -f "${CONFIG_DIR}/${candidate}" ]]; then
      printf '%s\n' "${CONFIG_DIR}/${candidate}"
      return
    fi
  done
}

detect_ssh_ip() {
  local ip
  ip="${SSH_CLIENT:-}"
  ip="${ip%% *}"
  if [[ -n "${ip}" ]]; then
    printf '%s\n' "${ip}"
    return
  fi
  if command -v ss >/dev/null 2>&1; then
    local peer
    peer="$(ss -tnp 2>/dev/null | awk '/ESTAB/ && /sshd/ {print $5; exit}')"
    if [[ -n "${peer}" ]]; then
      ip="${peer%:*}"
      printf '%s\n' "${ip}"
      return
    fi
  fi
}

detect_ssh_port() {
  local conn="${SSH_CONNECTION:-}"
  if [[ -n "${conn}" ]]; then
    local _c1 _c2 _c3 port
    read -r _c1 _c2 _c3 port <<<"${conn}"
    if [[ -n "${port}" ]]; then
      printf '%s\n' "${port}"
      return
    fi
  fi
  if command -v ss >/dev/null 2>&1; then
    local local_addr
    local_addr="$(ss -tnp 2>/dev/null | awk '/ESTAB/ && /sshd/ {print $4; exit}')"
    if [[ -n "${local_addr}" ]]; then
      printf '%s\n' "${local_addr##*:}"
      return
    fi
  fi
  printf '%s\n' "${DEFAULT_SSH_PORT}"
}

ensure_ssh_bypass() {
  local gw="$1" dev="$2" port="$3"
  [[ -z "${port}" ]] && return 1
  if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables not available; cannot preserve SSH route." >&2
    return 1
  fi
  if ! iptables -t mangle -C OUTPUT -p tcp --sport "${port}" -j MARK --set-mark "${DEFAULT_BYPASS_MARK}" >/dev/null 2>&1; then
    iptables -t mangle -A OUTPUT -p tcp --sport "${port}" -j MARK --set-mark "${DEFAULT_BYPASS_MARK}"
  fi
  if ! ip rule show | grep -q "fwmark ${DEFAULT_BYPASS_MARK}.*lookup ${DEFAULT_BYPASS_TABLE}"; then
    ip rule add fwmark "${DEFAULT_BYPASS_MARK}" table "${DEFAULT_BYPASS_TABLE}"
  fi
  ip route replace default via "${gw}" dev "${dev}" table "${DEFAULT_BYPASS_TABLE}"
  return 0
}

remove_ssh_bypass() {
  local port="$1" mark="$2" table="$3"
  [[ -z "${port}" ]] && return
  if command -v iptables >/dev/null 2>&1; then
    iptables -t mangle -D OUTPUT -p tcp --sport "${port}" -j MARK --set-mark "${mark}" 2>/dev/null || true
  fi
  ip rule del fwmark "${mark}" table "${table}" 2>/dev/null || true
  ip route flush table "${table}" 2>/dev/null || true
}

start_openvpn() {
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

  local gw dev remote_host remote_ip ssh_ip ssh_port ssh_bypass cred_file
  read -r gw dev < <(default_route_info) || {
    echo "Unable to detect default route. Aborting to avoid losing connectivity." >&2
    exit 1
  }
  remote_host="$(first_remote_host)"
  remote_ip="$(resolve_host_ip "${remote_host}")"
  ssh_ip="$(detect_ssh_ip || true)"
  ssh_port="$(detect_ssh_port || true)"
  ensure_host_route "${remote_ip}" "${gw}" "${dev}"
  if [[ -n "${ssh_ip}" ]]; then
    ensure_host_route "${ssh_ip}" "${gw}" "${dev}"
  fi
  ssh_bypass="false"
  if [[ -n "${ssh_port}" ]]; then
    if ensure_ssh_bypass "${gw}" "${dev}" "${ssh_port}"; then
      ssh_bypass="true"
    fi
  fi
  record_routes "${gw}" "${dev}" "${remote_ip}" "${ssh_ip}" "${ssh_port}" "${ssh_bypass}"

  cred_file="$(credentials_file || true)"
  if [[ -n "${cred_file}" ]]; then
    chmod 0600 "${cred_file}"
  fi

  install -d -m 0755 "$(dirname "${PID_FILE}")"
  touch "${LOG_FILE}"
  chmod 0640 "${LOG_FILE}"

  local args=(
    --config "${ACTIVE_CONFIG}"
    --cd "${CONFIG_DIR}"
    --writepid "${PID_FILE}"
    --log-append "${LOG_FILE}"
    --daemon
    --persist-tun
    --persist-key
    --script-security 2
    --up /etc/openvpn/update-resolv-conf
    --down /etc/openvpn/update-resolv-conf
  )
  if [[ -n "${cred_file}" ]]; then
    args+=(--auth-user-pass "${cred_file}")
  fi

  openvpn "${args[@]}"
  echo "OpenVPN started on host using ${cfg}."
}

stop_openvpn() {
  if openvpn_running; then
    kill "$(cat "${PID_FILE}")"
    wait "$(cat "${PID_FILE}")" 2>/dev/null || true
    echo "OpenVPN stopped."
  else
    echo "OpenVPN is not running."
  fi
  rm -f "${PID_FILE}"
  restore_routes
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

print_usage() {
  cat <<'EOF'
Usage: openvpn-connect.sh <command> [args]

Commands:
  start [config.ovpn]   Start OpenVPN on the host using the specified config.
  stop                  Stop the running OpenVPN instance and restore routes/DNS.
  status                Report whether OpenVPN is running.
  rotate [config.ovpn]  Switch to the next (or specified) config without dropping the tunnel.
  list                  Show available .ovpn files under /opt/openvpn-configs.
  sync                  Copy ~/openvpn-configs into /opt/openvpn-configs.
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
