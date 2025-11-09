#!/usr/bin/env bash
set -euo pipefail

WG_CONTAINER="${WG_CONTAINER:-wg-vpn}"
POOL_DIR="${POOL_DIR:-/opt/wg-configs/pool}"
ACTIVE_DIR="${ACTIVE_DIR:-/opt/wg-configs/active}"
LIST_FILE="${LIST_FILE:-$HOME/wireguard-profiles.txt}"

if [[ ! -f "${LIST_FILE}" ]]; then
  echo "WireGuard profile list not found at ${LIST_FILE}" >&2
  exit 1
fi

PROFILE="$(grep -v '^[[:space:]]*$' "${LIST_FILE}" | shuf -n1)"
CONF="${POOL_DIR}/${PROFILE}.conf"
ACTIVE_CONF="${ACTIVE_DIR}/wg0.conf"

if [[ ! -f "${CONF}" ]]; then
  echo "Missing WireGuard config: ${CONF}" >&2
  exit 1
fi

echo "[+] Switching docker WireGuard container (${WG_CONTAINER}) to profile: ${PROFILE}"
cp -f "${CONF}" "${ACTIVE_CONF}"
chmod 600 "${ACTIVE_CONF}"

docker exec "${WG_CONTAINER}" wg-quick down wg0 >/dev/null 2>&1 || true
sleep 1
docker exec "${WG_CONTAINER}" wg-quick up /config/wg0.conf

echo -n "[+] New exit IP: "
docker exec "${WG_CONTAINER}" sh -c 'curl https://am.i.mullvad.net/json | jq || curl -s ifconfig.me '
echo
