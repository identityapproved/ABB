#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENVPN_SH="${OPENVPN_HOST_SH:-${SCRIPT_DIR}/openvpn-connect.sh}"

if [[ ! -x "${OPENVPN_SH}" ]]; then
  echo "vpnspace-openvpn.sh not found at ${OPENVPN_SH}" >&2
  exit 1
fi

exec "${OPENVPN_SH}" rotate "$@"
