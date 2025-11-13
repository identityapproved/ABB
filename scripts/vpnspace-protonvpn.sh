#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPNSPACE_SH="${VPNSPACE_SH:-${SCRIPT_DIR}/vpnspace.sh}"
NS_NAME="${VPN_NAMESPACE:-vpnspace}"
VPN_USER="${VPN_USER:-${SUDO_USER:-${USER}}}"
VPN_USER_HOME="$(getent passwd "${VPN_USER}" | cut -d: -f6 || true)"
[[ -z "${VPN_USER_HOME}" ]] && VPN_USER_HOME="/home/${VPN_USER}"
PROTONVPN_BIN="${PROTONVPN_BIN:-${VPN_USER_HOME}/.local/bin/protonvpn}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

ensure_prereqs() {
  [[ -x "${VPNSPACE_SH}" ]] || { echo "vpnspace.sh not found at ${VPNSPACE_SH}" >&2; exit 1; }
  if ! ip netns list | grep -q "^${NS_NAME}\b"; then
    echo "Namespace ${NS_NAME} missing. Run vpnspace.sh setup first." >&2
    exit 1
  fi
  [[ -x "${PROTONVPN_BIN}" ]] || { echo "protonvpn-cli not found at ${PROTONVPN_BIN}" >&2; exit 1; }
}

ns_exec_user() {
  local user_home="${VPN_USER_HOME}"
  ip netns exec "${NS_NAME}" env -i HOME="${user_home}" SHELL=/bin/bash \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:${user_home}/.local/bin" \
    "$@"
}

connect_cmd() {
  local args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(connect --fastest)
  fi
  ns_exec_user "${PROTONVPN_BIN}" "${args[@]}"
}

disconnect_cmd() {
  ns_exec_user "${PROTONVPN_BIN}" disconnect || true
}

status_cmd() {
  ns_exec_user "${PROTONVPN_BIN}" status || true
}

print_usage() {
  cat <<'EOF'
Usage: vpnspace-protonvpn.sh <connect|disconnect|reconnect|status> [args]

Commands run protonvpn-cli inside the vpnspace namespace (defaults: namespace=vpnspace, user=$VPN_USER).
EOF
}

main() {
  require_root "$@"
  ensure_prereqs
  local cmd="${1:-}"
  if [[ -z "${cmd}" ]]; then
    print_usage
    exit 1
  fi
  shift || true
  case "${cmd}" in
    connect) connect_cmd "$@" ;;
    reconnect) connect_cmd reconnect ;;
    disconnect) disconnect_cmd ;;
    status) status_cmd ;;
    *)
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
