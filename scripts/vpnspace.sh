#!/usr/bin/env bash
set -euo pipefail

NS_NAME="${VPN_NAMESPACE:-vpnspace}"
HOST_VETH="${VPN_HOST_VETH:-vpn-veth0}"
NS_VETH="${VPN_NS_VETH:-vpn-veth1}"
SUBNET="${VPN_SUBNET:-10.200.0.0/24}"
HOST_IP="${VPN_HOST_IP:-10.200.0.1/24}"
NS_IP="${VPN_NS_IP:-10.200.0.2/24}"
VPN_USER="${VPN_USER:-${SUDO_USER:-${USER}}}"
PROTONVPN_BIN="${PROTONVPN_BIN:-/home/${VPN_USER}/.local/bin/protonvpn}"
UPSTREAM_IF="${VPN_UPSTREAM_IF:-$(ip route show default | awk 'NR==1 {print $5}' 2>/dev/null || echo eth0)}"
MASQ_RULE="-s ${SUBNET} -o ${UPSTREAM_IF} -j MASQUERADE"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

log() {
  printf '[vpnspace] %s\n' "$*"
}

ensure_prereqs() {
  command -v ip >/dev/null || { echo "iproute2 is required." >&2; exit 1; }
  command -v iptables >/dev/null || { echo "iptables is required." >&2; exit 1; }
}

create_namespace() {
  if ip netns list | grep -q "^${NS_NAME}\b"; then
    log "Namespace ${NS_NAME} already exists."
    return
  fi
  ip netns add "${NS_NAME}"
  ip link add "${HOST_VETH}" type veth peer name "${NS_VETH}"
  ip link set "${NS_VETH}" netns "${NS_NAME}"
  ip addr add "${HOST_IP}" dev "${HOST_VETH}"
  ip link set "${HOST_VETH}" up
  ip netns exec "${NS_NAME}" ip addr add "${NS_IP}" dev "${NS_VETH}"
  ip netns exec "${NS_NAME}" ip link set "${NS_VETH}" up
  ip netns exec "${NS_NAME}" ip link set lo up
  local host_ip ns_ip
  host_ip="${HOST_IP%%/*}"
  ns_ip="${NS_IP%%/*}"
  ip netns exec "${NS_NAME}" ip route add default via "${host_ip}"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  if ! iptables -t nat -C POSTROUTING ${MASQ_RULE} >/dev/null 2>&1; then
    iptables -t nat -A POSTROUTING ${MASQ_RULE}
  fi
  log "Namespace ${NS_NAME} created (gateway ${host_ip}, namespace IP ${ns_ip})."
}

delete_namespace() {
  if ip netns list | grep -q "^${NS_NAME}\b"; then
    ip netns delete "${NS_NAME}"
    log "Namespace ${NS_NAME} deleted."
  fi
  ip link show "${HOST_VETH}" >/dev/null 2>&1 && ip link delete "${HOST_VETH}"
  if iptables -t nat -C POSTROUTING ${MASQ_RULE} >/dev/null 2>&1; then
    iptables -t nat -D POSTROUTING ${MASQ_RULE}
  fi
}

ns_exec() {
  ip netns exec "${NS_NAME}" "$@"
}

ensure_namespace_exists() {
  if ! ip netns list | grep -q "^${NS_NAME}\b"; then
    echo "Namespace ${NS_NAME} is missing. Run '$0 setup' first." >&2
    exit 1
  fi
}

connect_vpn() {
  ensure_namespace_exists
  if [[ ! -x "${PROTONVPN_BIN}" ]]; then
    echo "Cannot find protonvpn-cli at ${PROTONVPN_BIN}. Adjust PROTONVPN_BIN or VPN_USER." >&2
    exit 1
  fi
  local args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(connect --fastest)
  fi
  ns_exec runuser -u "${VPN_USER}" -- "${PROTONVPN_BIN}" "${args[@]}"
}

disconnect_vpn() {
  ensure_namespace_exists
  ns_exec runuser -u "${VPN_USER}" -- "${PROTONVPN_BIN}" disconnect || true
}

status_vpn() {
  ensure_namespace_exists
  ns_exec runuser -u "${VPN_USER}" -- "${PROTONVPN_BIN}" status || true
}

ns_shell() {
  ensure_namespace_exists
  local shell_cmd="${SHELL:-/bin/bash}"
  ns_exec sudo -u "${VPN_USER}" -E "${shell_cmd}"
}

ns_exec_user() {
  ensure_namespace_exists
  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 exec <command...>" >&2
    exit 1
  fi
  ns_exec sudo -u "${VPN_USER}" -E "$@"
}

print_usage() {
  cat <<'EOF'
Usage: vpnspace.sh <command> [args]

Commands:
  setup                 Create the vpnspace namespace and veth pair.
  teardown              Remove the namespace, veth pair, and NAT rule.
  connect [args]        Run protonvpn-cli inside the namespace (default: connect --fastest).
  disconnect            Disconnect protonvpn inside the namespace.
  reconnect             Wrapper for protonvpn-cli reconnect.
  status                Show protonvpn status inside the namespace.
  shell                 Open an interactive shell inside vpnspace as VPN_USER.
  exec <cmd...>         Run an arbitrary command inside vpnspace as VPN_USER.
  ip <args>             Execute 'ip' inside the namespace (root).
EOF
}

main() {
  local cmd="${1:-}"
  if [[ -z "${cmd}" ]]; then
    print_usage
    exit 1
  fi
  shift || true

  case "${cmd}" in
    setup)
      require_root "$cmd" "$@"
      ensure_prereqs
      create_namespace
      ;;
    teardown)
      require_root "$cmd" "$@"
      delete_namespace
      ;;
    connect)
      require_root "$cmd" "$@"
      connect_vpn "$@"
      ;;
    disconnect)
      require_root "$cmd" "$@"
      disconnect_vpn
      ;;
    reconnect)
      require_root "$cmd" "$@"
      connect_vpn reconnect
      ;;
    status)
      require_root "$cmd" "$@"
      status_vpn
      ;;
    shell)
      require_root "$cmd" "$@"
      ns_shell
      ;;
    exec)
      require_root "$cmd" "$@"
      ns_exec_user "$@"
      ;;
    ip)
      require_root "$cmd" "$@"
      ensure_namespace_exists
      ns_exec ip "$@"
      ;;
    *)
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
