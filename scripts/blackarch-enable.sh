#!/usr/bin/env bash
set -euo pipefail

log_info() { printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"; }
log_warn() { printf '[%s] WARN: %s\n' "$(date --iso-8601=seconds)" "$*" >&2; }
log_error() { printf '[%s] ERROR: %s\n' "$(date --iso-8601=seconds)" "$*" >&2; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Run this script as root (sudo ./scripts/blackarch-enable.sh)."
    exit 1
  fi
}

normalize_testing_includes() {
  local conf="/etc/pacman.conf" tmp status=0
  tmp="$(mktemp)"
  if awk '
    BEGIN { commented = 0; changed = 0 }
    {
      line = $0
      if ($0 ~ /^[[:space:]]*#[[:space:]]*\[[^]]+\]/) {
        commented = 1
      } else if ($0 ~ /^[[:space:]]*\[[^]]+\]/) {
        commented = 0
      }
      if (commented && $0 ~ /^[[:space:]]*Include = \/etc\/pacman\.d\/mirrorlist/) {
        sub(/Include =/, "#Include =")
        changed = 1
      }
      print
    }
    END { if (changed) exit 2 }
  ' "${conf}" > "${tmp}"; then
    status=0
  else
    status=$?
  fi

  case "${status}" in
    0)
      rm -f "${tmp}"
      ;;
    2)
      if ! cmp -s "${conf}" "${tmp}"; then
        cat "${tmp}" > "${conf}"
        log_info "Commented testing repository mirror Includes in /etc/pacman.conf."
      fi
      rm -f "${tmp}"
      ;;
    *)
      rm -f "${tmp}"
      log_warn "Unable to normalise testing repository Includes."
      ;;
  esac
}

enable_multilib_repo() {
  local conf="/etc/pacman.conf"
  if awk '
      BEGIN { found = 0 }
      /^\[multilib\]/ {
        if (getline > 0 && $0 ~ /^[[:space:]]*Include = \/etc\/pacman\.d\/mirrorlist/) {
          found = 1
        }
      }
      END { exit(found ? 0 : 1) }
    ' "${conf}" >/dev/null 2>&1; then
    log_info "multilib repository already enabled."
    return
  fi

  if perl -0pi -e 's/^\s*#\s*\[multilib\]\s*\n\s*#\s*Include = \/etc\/pacman\.d\/mirrorlist/[multilib]\nInclude = \/etc\/pacman\.d\/mirrorlist/m' "${conf}"; then
    if awk '
        BEGIN { found = 0 }
        /^\[multilib\]/ {
          if (getline > 0 && $0 ~ /^[[:space:]]*Include = \/etc\/pacman\.d\/mirrorlist/) {
            found = 1
          }
        }
        END { exit(found ? 0 : 1) }
      ' "${conf}" >/dev/null 2>&1; then
      log_info "Enabled multilib repository in /etc/pacman.conf."
    else
      log_warn "Unable to verify multilib inclusion."
    fi
  else
    log_warn "Failed to edit /etc/pacman.conf for multilib."
  fi
}

configure_blackarch_repo() {
  local conf_file="/etc/pacman.d/blackarch.conf"
  local default_mirror="https://www.blackarch.org/blackarch"
  local server_line="Server = ${default_mirror}/\$repo/os/\$arch"
  local need_refresh=0 siglevel_added=0

  if [[ ! -f "${conf_file}" || ! grep -Fxq "${server_line}" "${conf_file}" ]]; then
    {
      printf '[blackarch]\n'
      printf '%s\n' "${server_line}"
    } > "${conf_file}"
    chmod 0644 "${conf_file}"
    log_info "Wrote BlackArch repository definition to ${conf_file}."
    need_refresh=1
  else
    log_info "BlackArch definition already present at ${conf_file}."
  fi

  if ! grep -Eq '^\s*Include\s*=\s*/etc/pacman\.d/blackarch\.conf' /etc/pacman.conf; then
    printf '\n# Include BlackArch repository configuration\nInclude = /etc/pacman.d/blackarch.conf\n' >> /etc/pacman.conf
    log_info "Referenced ${conf_file} from /etc/pacman.conf."
    need_refresh=1
  else
    log_info "/etc/pacman.conf already includes ${conf_file}."
  fi

  if ! pacman -Qi blackarch-keyring >/dev/null 2>&1; then
    sed -i '1a SigLevel = Never' "${conf_file}"
    siglevel_added=1
    log_warn "Temporarily disabling signature checks to install blackarch-keyring."
    if pacman --noconfirm -Sy blackarch-keyring; then
      log_info "Installed blackarch-keyring."
      need_refresh=1
    else
      log_error "blackarch-keyring installation failed."
      sed -i '/^\s*SigLevel\s*=\s*Never\s*$/d' "${conf_file}" || true
      exit 1
    fi
  else
    log_info "blackarch-keyring already installed."
  fi

  if ((siglevel_added)); then
    sed -i '/^\s*SigLevel\s*=\s*Never\s*$/d' "${conf_file}" || true
    log_info "Restored signature verification for BlackArch."
  fi

  enable_multilib_repo
  normalize_testing_includes

  if ((need_refresh)); then
    log_info "Refreshing pacman databases."
    if ! pacman --noconfirm -Syyu; then
      log_warn "Pacman refresh failed; rerun 'pacman -Syyu' manually."
    fi
  fi
}

main() {
  require_root
  log_info "Enabling the BlackArch repository (optional helper)."
  configure_blackarch_repo
  log_info "BlackArch repository configured. Install packages with 'pacman -S <pkg>' or disable the Include line if no longer needed."
}

main "$@"
