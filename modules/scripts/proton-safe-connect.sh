#!/usr/bin/env bash
# proton-safe-connect
# Preserves the SSH route before invoking protonvpn-cli so your session survives the tunnel cutover.

set -euo pipefail

command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: proton-safe-connect [--client-ip <ip>] [-- <protonvpn-cli args>]

Examples:
  sudo proton-safe-connect                           # auto-detect SSH client and run "protonvpn-cli connect --fastest"
  sudo proton-safe-connect --client-ip 203.0.113.5   # force a specific client IP
  sudo proton-safe-connect -- --protocol udp --fastest
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This helper must run as root (use sudo)." >&2
    exit 1
  fi
}

detect_client_ip() {
  local provided="$1"
  local detected="${provided}"
  if [[ -z "${detected}" && -n "${SSH_CLIENT:-}" ]]; then
    detected="${SSH_CLIENT%% *}"
  fi
  if [[ -z "${detected}" && -t 0 ]]; then
    read -rp "Enter the IP of your SSH client to keep routed: " detected </dev/tty || true
  fi
  if [[ -z "${detected}" ]]; then
    echo "Unable to determine SSH client IP. Pass --client-ip <ip> explicitly." >&2
    exit 1
  fi
  echo "${detected}"
}

parse_args() {
  CLIENT_IP=""
  PROTON_ARGS=()
  while (($#)); do
    case "$1" in
      --client-ip=*)
        CLIENT_IP="${1#*=}"
        ;;
      --client-ip)
        shift
        CLIENT_IP="${1:-}"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        PROTON_ARGS=("$@")
        break
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift || true
  done
  if ((${#PROTON_ARGS[@]} == 0)); then
    PROTON_ARGS=(connect --fastest)
  fi
}

ensure_protonvpn_cli() {
  if ! command_exists protonvpn-cli >/dev/null 2>&1; then
    echo "protonvpn-cli not found. Run 'abb-setup.sh vpn' with ProtonVPN selected first." >&2
    exit 1
  fi
}

install_static_route() {
  local client_ip="$1"
  local default_route gateway iface
  default_route="$(ip route show default 0.0.0.0/0 | head -n1)"
  gateway="$(awk '{print $3}' <<<"${default_route}")"
  iface="$(awk '{print $5}' <<<"${default_route}")"
  if [[ -z "${gateway}" || -z "${iface}" ]]; then
    echo "Unable to identify default gateway/interface. Current routes:" >&2
    ip route show
    exit 1
  fi
  echo "[proton-safe-connect] Ensuring ${client_ip}/32 routes via ${gateway} (${iface})."
  ip route replace "${client_ip}/32" via "${gateway}" dev "${iface}"
}

connect_protonvpn() {
  local args=("$@")
  echo "[proton-safe-connect] Running protonvpn-cli ${args[*]}"
  protonvpn-cli "${args[@]}"
}

main() {
  need_root
  ensure_protonvpn_cli
  parse_args "$@"
  local client_ip
  client_ip=$(detect_client_ip "${CLIENT_IP}")
  install_static_route "${client_ip}"
  connect_protonvpn "${PROTON_ARGS[@]}"
  echo "[proton-safe-connect] ProtonVPN connected. SSH route to ${client_ip} remains in place:"
  ip route show "${client_ip}/32"
}

main "$@"
