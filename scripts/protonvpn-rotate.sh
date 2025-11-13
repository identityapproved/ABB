#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTONVPN_NS_SH="${PROTONVPN_NS_SH:-${SCRIPT_DIR}/vpnspace-protonvpn.sh}"
CONNECT_ARGS=("$@")

if [[ ${#CONNECT_ARGS[@]} -eq 0 ]]; then
  CONNECT_ARGS=(reconnect)
fi

if [[ ! -x "${PROTONVPN_NS_SH}" ]]; then
  echo "vpnspace-protonvpn.sh helper not found at ${PROTONVPN_NS_SH}" >&2
  exit 1
fi

exec "${PROTONVPN_NS_SH}" "${CONNECT_ARGS[@]}"
