#!/usr/bin/env bash
set -euo pipefail

GLUETUN_CONTAINER="${GLUETUN_CONTAINER:-vpn-gateway}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[gluetun-rotate] docker CLI not found. Install Docker first." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "${GLUETUN_CONTAINER}"; then
  echo "[gluetun-rotate] Container ${GLUETUN_CONTAINER} is not running. Start it before rotating." >&2
  exit 1
fi

echo "[gluetun-rotate] Restarting ${GLUETUN_CONTAINER} to request a new ProtonVPN exit IP."
docker restart "${GLUETUN_CONTAINER}" >/dev/null
