#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${WG_CONFIG_DIR:-/var/lib/mullvad/profiles}"
INTERFACE="${WG_INTERFACE:-wg0}"
ACTIVE_CONF="/etc/wireguard/${INTERFACE}.conf"

shopt -s nullglob
mapfile -t profiles < <(find "${CONFIG_DIR}" -maxdepth 1 -type f -name '*.conf' -print)
shopt -u nullglob

if ((${#profiles[@]} == 0)); then
  echo "[rotate] No Mullvad configs found in ${CONFIG_DIR}. Run 'docker exec -it ${HOSTNAME:-vpn-gateway} bootstrap-mullvad' first." >&2
  exit 1
fi

profile="${profiles[RANDOM % ${#profiles[@]}]}"
install -D -m 0600 "${profile}" "${ACTIVE_CONF}"
echo "[rotate] Selected $(basename "${profile}") for interface ${INTERFACE}."

if wg show "${INTERFACE}" >/dev/null 2>&1; then
  wg-quick down "${INTERFACE}" >/dev/null 2>&1 || true
fi

if output="$(wg-quick up "${INTERFACE}" 2>&1)"; then
  curl -fsS https://am.i.mullvad.net/json | jq '.ip, .mullvad_exit_ip_hostname' || true
  exit 0
fi

echo "[rotate] Failed to bring up ${INTERFACE} with profile $(basename "${profile}"). wg-quick output:"
printf '%s\n' "${output}"
exit 2
