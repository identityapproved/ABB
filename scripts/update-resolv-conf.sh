#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[openvpn-dns] %s\n' "$*" >&2
}

DEV="${dev:-tun0}"
TMP_FILE="$(mktemp "/tmp/resolvconf.${DEV}.XXXXXX")"
BACKUP_FILE="/etc/resolv.conf.openvpn-backup"

collect_options() {
  local idx=1 opt value var_name
  : > "${TMP_FILE}"
  while true; do
    var_name="foreign_option_${idx}"
    opt="${!var_name:-}"
    [[ -n "${opt}" ]] || break
    case "${opt}" in
      "dhcp-option DNS "*)
        value="${opt#dhcp-option DNS }"
        printf 'nameserver %s\n' "${value}" >> "${TMP_FILE}"
        ;;
      "dhcp-option DOMAIN "*)
        value="${opt#dhcp-option DOMAIN }"
        printf 'domain %s\n' "${value}" >> "${TMP_FILE}"
        ;;
      "dhcp-option DOMAIN-SEARCH "*)
        value="${opt#dhcp-option DOMAIN-SEARCH }"
        printf 'search %s\n' "${value}" >> "${TMP_FILE}"
        ;;
    esac
    ((idx++))
  done

  if ! grep -q '^nameserver' "${TMP_FILE}"; then
    log "No VPN DNS pushed; defaulting to 10.98.0.1"
    printf 'nameserver 10.98.0.1\n' >> "${TMP_FILE}"
  fi
}

apply_dns() {
  if [[ ! -f "${BACKUP_FILE}" ]]; then
    cp /etc/resolv.conf "${BACKUP_FILE}" 2>/dev/null || true
  fi
  log "Applying VPN-provided DNS to /etc/resolv.conf"
  cp "${TMP_FILE}" /etc/resolv.conf
}

restore_dns() {
  if [[ -f "${BACKUP_FILE}" ]]; then
    log "Restoring original DNS configuration"
    cp "${BACKUP_FILE}" /etc/resolv.conf
    rm -f "${BACKUP_FILE}"
  fi
}

case "${script_type:-}" in
  up)
    collect_options
    apply_dns
    ;;
  down)
    restore_dns
    ;;
esac

rm -f "${TMP_FILE}"
