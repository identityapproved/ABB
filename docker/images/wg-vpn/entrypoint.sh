#!/usr/bin/env bash
set -euo pipefail

ROTATE_SECONDS="${WG_ROTATE_SECONDS:-900}"
CONTAINER_NAME="${HOSTNAME:-wg-vpn}"

echo "[entrypoint] Mullvad WireGuard container starting (rotate every ${ROTATE_SECONDS}s)."
echo "[entrypoint] Generate configs with: docker exec -it ${CONTAINER_NAME} bootstrap-mullvad"

while true; do
  if /usr/local/bin/container-rotate-wg.sh; then
    sleep "${ROTATE_SECONDS}"
  else
    echo "[entrypoint] rotation helper reported no profiles. Retrying in 30s..."
    sleep 30
  fi
done
