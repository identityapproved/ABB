#!/usr/bin/env bash
set -euo pipefail

WG_CONTAINER="${WG_CONTAINER:-wg-vpn}"
POOL_DIR="${POOL_DIR:-/opt/wg-configs/pool}"
ACTIVE_DIR="${ACTIVE_DIR:-/opt/wg-configs/active}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "rotate-wg.sh must be run with sudo/root to update /opt/wg-configs." >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-${USER}}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6 2>/dev/null)"
LIST_FILE="${LIST_FILE:-${TARGET_HOME}/wireguard-profiles.txt}"

if [[ -z "${TARGET_HOME}" || ! -f "${LIST_FILE}" ]]; then
  echo "WireGuard profile list not found for user ${TARGET_USER}." >&2
  echo "Expected location: ${LIST_FILE}" >&2
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
install -m 600 "${CONF}" "${ACTIVE_CONF}"

docker exec "${WG_CONTAINER}" wg-quick down wg0 >/dev/null 2>&1 || true
sleep 1
docker exec "${WG_CONTAINER}" wg-quick up /config/wg0.conf

echo -n "[+] New exit IP: "
docker exec "${WG_CONTAINER}" sh -c 'curl https://am.i.mullvad.net/json | jq || curl -s ifconfig.me '
echo
