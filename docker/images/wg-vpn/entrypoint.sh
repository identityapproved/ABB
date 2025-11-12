#!/usr/bin/env bash
set -euo pipefail

ROTATE_SECONDS="${WG_ROTATE_SECONDS:-900}"
CONTAINER_NAME="${HOSTNAME:-vpn-gateway}"

echo "[entrypoint] Mullvad WireGuard container starting (rotate every ${ROTATE_SECONDS}s)."
echo "[entrypoint] Generate configs with: docker exec -it ${CONTAINER_NAME} bootstrap-mullvad"

# Ensure resolvconf target exists; link /etc/resolv.conf to runtime-managed file
if [[ -f /run/resolvconf/resolv.conf ]]; then
  ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf
fi

while true; do
  if /usr/local/bin/container-rotate-wg.sh; then
    sleep "${ROTATE_SECONDS}"
  else
    status=$?
    case "${status}" in
      1)
        echo "[entrypoint] Mullvad profiles missing; run 'docker exec -it ${CONTAINER_NAME} bootstrap-mullvad'. Retrying in 30s..."
        ;;
      2)
        echo "[entrypoint] wg-quick failed to apply the selected profile (exit ${status}). Retrying in 30s..."
        ;;
      *)
        echo "[entrypoint] rotation helper exited with status ${status}. Retrying in 30s..."
        ;;
    esac
    sleep 30
  fi
done
