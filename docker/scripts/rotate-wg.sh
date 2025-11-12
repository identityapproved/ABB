#!/usr/bin/env bash
set -euo pipefail

WG_CONTAINER="${WG_CONTAINER:-vpn-gateway}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[host-rotate] docker CLI not found. Install Docker and rerun." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "${WG_CONTAINER}"; then
  echo "[host-rotate] Container ${WG_CONTAINER} is not running. Start it before rotating." >&2
  exit 1
fi

echo "[host-rotate] Triggering Mullvad rotation inside ${WG_CONTAINER}."
docker exec "${WG_CONTAINER}" container-rotate-wg.sh
