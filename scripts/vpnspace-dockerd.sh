#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPNSPACE_SH="${VPNSPACE_SH:-${SCRIPT_DIR}/vpnspace.sh}"

NS_NAME="${VPN_NAMESPACE:-vpnspace}"
DOCKERD_BIN="${DOCKERD_BIN:-/usr/bin/dockerd}"
SOCK_PATH="${VPN_DOCKER_SOCK:-/run/docker-vpnspace.sock}"
PID_FILE="${VPN_DOCKER_PIDFILE:-/run/docker-vpnspace.pid}"
DATA_ROOT="${VPN_DOCKER_DATA_ROOT:-/var/lib/docker-vpnspace}"
EXEC_ROOT="${VPN_DOCKER_EXEC_ROOT:-/var/run/docker-vpnspace}"
BIP="${VPN_DOCKER_BIP:-172.30.0.1/24}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

ensure_helpers() {
  [[ -x "${VPNSPACE_SH}" ]] || { echo "vpnspace.sh not found at ${VPNSPACE_SH}" >&2; exit 1; }
  command -v "${DOCKERD_BIN}" >/dev/null || { echo "dockerd not found at ${DOCKERD_BIN}" >&2; exit 1; }
}

ensure_namespace() {
  if ! ip netns list | grep -q "^${NS_NAME}\b"; then
    echo "Namespace ${NS_NAME} missing. Run vpnspace.sh setup first." >&2
    exit 1
  fi
}

start_dockerd() {
  ensure_namespace
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "dockerd already running inside ${NS_NAME} (pid $(cat "${PID_FILE}"))." >&2
    exit 0
  fi
  mkdir -p "$(dirname "${SOCK_PATH}")" "${DATA_ROOT}" "${EXEC_ROOT}"
  ip netns exec "${NS_NAME}" "${DOCKERD_BIN}" \
    --host="unix://${SOCK_PATH}" \
    --data-root="${DATA_ROOT}" \
    --exec-root="${EXEC_ROOT}" \
    --pidfile="${PID_FILE}" \
    --bip="${BIP}" \
    --iptables=false \
    --ip-masq=false &
  local pid=$!
  sleep 2
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "Failed to start dockerd inside ${NS_NAME}." >&2
    exit 1
  fi
  echo "${pid}" > "${PID_FILE}"
  echo "dockerd started in namespace ${NS_NAME} (socket ${SOCK_PATH})."
  echo "Export DOCKER_HOST=unix://${SOCK_PATH} to target this daemon."
}

stop_dockerd() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}")"
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}"
      wait "${pid}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
  fi
  rm -f "${SOCK_PATH}"
  echo "dockerd in ${NS_NAME} stopped."
}

status_dockerd() {
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "dockerd running (pid $(cat "${PID_FILE}")), socket ${SOCK_PATH}"
  else
    echo "dockerd is not running inside ${NS_NAME}"
    return 1
  fi
}

print_usage() {
  cat <<'EOF'
Usage: vpnspace-dockerd.sh <start|stop|status>

Starts a dedicated dockerd instance inside the vpnspace namespace.
Point DOCKER_HOST=unix:///run/docker-vpnspace.sock when running docker/compose
commands to ensure containers use the ProtonVPN namespace.
EOF
}

main() {
  require_root "$@"
  ensure_helpers
  local cmd="${1:-}"
  case "${cmd}" in
    start) start_dockerd ;;
    stop) stop_dockerd ;;
    status) status_dockerd ;;
    *) print_usage; exit 1 ;;
  esac
}

main "$@"
