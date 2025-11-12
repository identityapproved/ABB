#!/usr/bin/env sh
set -eu

DEV="${dev:-tun0}"
TMP_FILE="$(mktemp "/tmp/resolvconf.${DEV}.XXXXXX")"

collect_options() {
  local idx=1 opt value
  > "${TMP_FILE}"
  while :; do
    eval "opt=\${foreign_option_${idx}:-}"
    [ -n "${opt:-}" ] || break
    case "${opt}" in
      "dhcp-option DNS"* )
        value="${opt#dhcp-option DNS }"
        printf 'nameserver %s\n' "${value}" >> "${TMP_FILE}"
        ;;
      "dhcp-option DOMAIN"* )
        value="${opt#dhcp-option DOMAIN }"
        printf 'domain %s\n' "${value}" >> "${TMP_FILE}"
        ;;
      "dhcp-option DOMAIN-SEARCH"* )
        value="${opt#dhcp-option DOMAIN-SEARCH }"
        printf 'search %s\n' "${value}" >> "${TMP_FILE}"
        ;;
    esac
    idx=$((idx + 1))
  done
}

if ! command -v resolvconf >/dev/null 2>&1; then
  exit 0
fi

case "${script_type:-}" in
  up)
    collect_options
    if [ -s "${TMP_FILE}" ]; then
      resolvconf -a "${DEV}" < "${TMP_FILE}" || true
    fi
    ;;
  down)
    resolvconf -d "${DEV}" || true
    ;;
esac

rm -f "${TMP_FILE}"
exit 0
