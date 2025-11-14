#!/usr/bin/env bash
set -euo pipefail

PORT="${SSH_BYPASS_PORT:-22}"
MARK="${SSH_BYPASS_MARK:-22}"
TABLE="${SSH_BYPASS_TABLE:-128}"
RULE_FILE="${SSH_BYPASS_RULE_FILE:-/etc/iptables.rules}"
RC_LOCAL="${SSH_BYPASS_RC_LOCAL:-/etc/rc.local}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
}

default_route() {
  local line
  line="$(ip route show default | head -n1)"
  [[ -z "${line}" ]] && return 1
  local gw dev
  gw="$(awk '/default/ {for (i=1;i<=NF;i++) if ($i=="via") print $(i+1)}' <<<"${line}")"
  dev="$(awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' <<<"${line}")"
  [[ -z "${gw}" || -z "${dev}" ]] && return 1
  printf '%s %s\n' "${gw}" "${dev}"
}

ensure_iptables_rule() {
  if ! iptables -t mangle -C OUTPUT -p tcp --sport "${PORT}" -j MARK --set-mark "${MARK}" >/dev/null 2>&1; then
    iptables -t mangle -A OUTPUT -p tcp --sport "${PORT}" -j MARK --set-mark "${MARK}"
  fi
}

remove_iptables_rule() {
  iptables -t mangle -D OUTPUT -p tcp --sport "${PORT}" -j MARK --set-mark "${MARK}" 2>/dev/null || true
}

ensure_iprule() {
  if ! ip rule show | grep -q "fwmark ${MARK}.*lookup ${TABLE}"; then
    ip rule add fwmark "${MARK}" table "${TABLE}"
  fi
}

remove_iprule() {
  ip rule del fwmark "${MARK}" table "${TABLE}" 2>/dev/null || true
}

ensure_route_table() {
  local gw="$1" dev="$2"
  ip route replace default via "${gw}" dev "${dev}" table "${TABLE}"
}

flush_route_table() {
  ip route flush table "${TABLE}" 2>/dev/null || true
}

persist_iptables() {
  iptables-save > "${RULE_FILE}"
  if [[ ! -f "${RC_LOCAL}" ]]; then
    cat <<'EOF' > "${RC_LOCAL}"
#!/bin/sh
exit 0
EOF
  fi
  if ! grep -q "iptables-restore < ${RULE_FILE}" "${RC_LOCAL}"; then
    local tmp
    tmp="$(mktemp)"
    if grep -q '^exit 0' "${RC_LOCAL}"; then
      sed "/^exit 0/i iptables-restore < ${RULE_FILE}" "${RC_LOCAL}" > "${tmp}"
    else
      cat "${RC_LOCAL}" > "${tmp}"
      printf 'iptables-restore < %s\n' "${RULE_FILE}" >> "${tmp}"
      printf 'exit 0\n' >> "${tmp}"
    fi
    cat "${tmp}" > "${RC_LOCAL}"
    rm -f "${tmp}"
  fi
  chmod +x "${RC_LOCAL}"
}

setup() {
  local gw dev
  read -r gw dev < <(default_route) || {
    echo "Unable to detect default route. Aborting." >&2
    exit 1
  }
  ensure_iptables_rule
  ensure_iprule
  ensure_route_table "${gw}" "${dev}"
  persist_iptables
  echo "SSH bypass configured (port ${PORT}, mark ${MARK}, table ${TABLE})"
}

teardown() {
  remove_iptables_rule
  remove_iprule
  flush_route_table
  echo "SSH bypass removed."
}

status() {
  echo "iptables mangle OUTPUT rules:"
  iptables -t mangle -L OUTPUT -n --line-numbers | grep --color=never -E "MARK set ${MARK}" || true
  echo
  echo "ip rule:"
  ip rule show | grep --color=never "${TABLE}" || true
  echo
  echo "Routing table ${TABLE}:"
  ip route show table "${TABLE}" || true
}

usage() {
  cat <<EOF
Usage: ssh-bypass.sh <setup|teardown|status>

Environment overrides:
  SSH_BYPASS_PORT   (default 22)
  SSH_BYPASS_MARK   (default 22)
  SSH_BYPASS_TABLE  (default 128)
  SSH_BYPASS_RULE_FILE (default /etc/iptables.rules)
  SSH_BYPASS_RC_LOCAL (default /etc/rc.local)
EOF
}

main() {
  require_root
  local cmd="${1:-}"
  case "${cmd}" in
    setup) setup ;;
    teardown) teardown ;;
    status) status ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
