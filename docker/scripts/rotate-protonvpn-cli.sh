#!/usr/bin/env bash
set -euo pipefail

VPN_CONTAINER="${VPN_CONTAINER:-vpn-gateway}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[protonvpn-cli-rotate] docker CLI not found." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "${VPN_CONTAINER}"; then
  echo "[protonvpn-cli-rotate] Container ${VPN_CONTAINER} is not running." >&2
  exit 1
fi

echo "[protonvpn-cli-rotate] Reconnecting ${VPN_CONTAINER}..."
docker exec "${VPN_CONTAINER}" protonvpn reconnect
