#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPNSPACE_SH="${VPNSPACE_SH:-${SCRIPT_DIR}/vpnspace.sh}"
CONNECT_ARGS=("${@:-reconnect}")

if [[ ! -x "${VPNSPACE_SH}" ]]; then
  echo "vpnspace.sh helper not found at ${VPNSPACE_SH}" >&2
  exit 1
fi

exec "${VPNSPACE_SH}" connect "${CONNECT_ARGS[@]}"
