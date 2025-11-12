#!/usr/bin/env bash
set -euo pipefail

VPN_CONTAINER="${VPN_CONTAINER:-vpn-gateway}"
ROTATE_MODE="${OPENVPN_ROTATE_MODE:-next}"
TARGET_CONFIG="${OPENVPN_TARGET_CONFIG:-}"

if [[ $# -gt 0 ]]; then
  case "$1" in
    next|--next)
      ROTATE_MODE="next"
      ;;
    random|--random)
      ROTATE_MODE="random"
      ;;
    *)
      ROTATE_MODE="explicit"
      TARGET_CONFIG="$1"
      ;;
  esac
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[openvpn-rotate] docker CLI not found." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "${VPN_CONTAINER}"; then
  echo "[openvpn-rotate] Container ${VPN_CONTAINER} is not running." >&2
  exit 1
fi

cmd=(docker exec "${VPN_CONTAINER}" openvpn-config-switch)

case "${ROTATE_MODE}" in
  next)
    ;;
  random)
    cmd+=("--random")
    ;;
  explicit)
    if [[ -z "${TARGET_CONFIG}" ]]; then
      echo "[openvpn-rotate] OPENVPN_TARGET_CONFIG must be set when ROTATE_MODE=explicit or when passing a custom config." >&2
      exit 1
    fi
    cmd+=("${TARGET_CONFIG}")
    ;;
  *)
    ;;
esac

echo "[openvpn-rotate] Executing ${cmd[*]} ..."
"${cmd[@]}"
