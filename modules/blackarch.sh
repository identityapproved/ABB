# shellcheck shell=bash

BLACKARCH_TASK_COMPLETED="${BLACKARCH_TASK_COMPLETED:-0}"

blackarch_normalize_testing_includes() {
  local conf="/etc/pacman.conf"
  local tmp changed=0
  tmp="$(mktemp)"
  local awk_status=0
  if awk '
    BEGIN { commented_section = 0; changed = 0 }
    {
      line = $0
      if ($0 ~ /^[[:space:]]*#[[:space:]]*\[[^]]+\]/) {
        commented_section = 1
      } else if ($0 ~ /^[[:space:]]*\[[^]]+\]/) {
        commented_section = 0
      }
      if (commented_section && $0 ~ /^[[:space:]]*Include = \/etc\/pacman\.d\/mirrorlist/) {
        sub(/Include =/, "#Include =")
        changed = 1
      }
      print
    }
    END { if (changed) exit 2 }
  ' "${conf}" > "${tmp}"; then
    awk_status=0
  else
    awk_status=$?
  fi
  case ${awk_status} in
    0)
      rm -f "${tmp}"
      ;;
    2)
      if ! cmp -s "${conf}" "${tmp}"; then
        cat "${tmp}" > "${conf}"
        log_info "Commented inactive testing mirror Includes in /etc/pacman.conf."
      fi
      rm -f "${tmp}"
      ;;
    *)
      rm -f "${tmp}"
      log_warn "Unable to normalise testing repository Includes in /etc/pacman.conf."
      ;;
  esac
  return 0
}

blackarch_enable_multilib_repo() {
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
    return 1
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
      return 0
    fi
  fi

  log_warn "Unable to enable multilib repository automatically. Review /etc/pacman.conf."
  return 2
}

blackarch_configure_repo() {
  local need_refresh=0
  local conf_file="/etc/pacman.d/blackarch.conf"
  local default_mirror="https://www.blackarch.org/blackarch"
  local saved_mirror="${BLACKARCH_MIRROR_SELECTED:-}"
  local selected_mirror existing_server

  if [[ -z "${saved_mirror}" && -f "${conf_file}" ]]; then
    existing_server="$(awk -F'= ' '/^[[:space:]]*Server[[:space:]]*=/ {print $2; exit}' "${conf_file}" | tr -d '[:space:]')"
    if [[ -n "${existing_server}" ]]; then
      saved_mirror="${existing_server%/\$repo/os/\$arch}"
    fi
  fi

  selected_mirror="${saved_mirror:-${default_mirror}}"
  selected_mirror="${selected_mirror%/}"
  if [[ -z "${selected_mirror}" ]]; then
    selected_mirror="${default_mirror}"
  fi
  local server_line="Server = ${selected_mirror}/\$repo/os/\$arch"
  local result

  if [[ "${selected_mirror}" != "${default_mirror}" ]]; then
    log_info "Using custom BlackArch mirror: ${selected_mirror}"
  fi

  local conf_needs_update=0
  if [[ ! -f "${conf_file}" ]]; then
    conf_needs_update=1
  elif ! grep -Fxq "${server_line}" "${conf_file}"; then
    conf_needs_update=1
  elif grep -Fxq 'Include = /etc/pacman.d/mirrorlist' "${conf_file}"; then
    conf_needs_update=1
  fi

  if ((conf_needs_update)); then
    {
      printf '[blackarch]\n'
      printf '%s\n' "${server_line}"
    } > "${conf_file}"
    BLACKARCH_MIRROR_SELECTED="${selected_mirror}"
    chmod 0644 "${conf_file}"
    log_info "Configured BlackArch repository definition in ${conf_file}."
    need_refresh=1
  else
    log_info "BlackArch repository definition already present at ${conf_file}."
    if [[ -z "${BLACKARCH_MIRROR_SELECTED}" ]]; then
      BLACKARCH_MIRROR_SELECTED="${selected_mirror}"
    fi
  fi

  if ! grep -Eq '^\s*Include\s*=\s*/etc/pacman\.d/blackarch\.conf' /etc/pacman.conf; then
    printf '\n# Include BlackArch repository configuration\nInclude = /etc/pacman.d/blackarch.conf\n' >> /etc/pacman.conf
    log_info "Linked ${conf_file} from /etc/pacman.conf."
    need_refresh=1
  else
    log_info "/etc/pacman.conf already references ${conf_file}."
  fi

  local need_keyring=0
  local siglevel_added=0
  if ! pacman -Qi blackarch-keyring >/dev/null 2>&1; then
    need_keyring=1
  fi

  if ((need_keyring)); then
    if ! grep -Eq '^\s*SigLevel\s*=\s*Never\s*$' "${conf_file}"; then
      sed -i '1a SigLevel = Never' "${conf_file}"
      siglevel_added=1
      log_warn "Temporarily disabling signature checks for BlackArch to install blackarch-keyring."
    else
      log_warn "Using existing SigLevel = Never override to install blackarch-keyring."
    fi

    if pacman --noconfirm -Sy blackarch-keyring; then
      log_info "Installed blackarch-keyring package."
      need_refresh=1
    else
      if ((siglevel_added)); then
        sed -i '/^\s*SigLevel\s*=\s*Never\s*$/d' "${conf_file}"
        log_info "Restored BlackArch signature settings after failed keyring installation."
      fi
      log_error "Failed to install blackarch-keyring. Verify network connectivity and rerun."
      exit 1
    fi

    sed -i '/^\s*SigLevel\s*=\s*Never\s*$/d' "${conf_file}"
    log_info "Re-enabled signature verification for the BlackArch repository."
  else
    log_info "BlackArch keyring already trusted."
  fi

  if blackarch_enable_multilib_repo; then
    result=0
  else
    result=$?
  fi
  if [[ ${result} -eq 0 ]]; then
    need_refresh=1
  elif [[ ${result} -eq 2 ]]; then
    log_warn "Proceeding without multilib automatically enabled."
  fi

  blackarch_normalize_testing_includes

  if ((need_refresh)); then
    log_info "Refreshing package databases after BlackArch configuration."
    if ! pacman --noconfirm -Syyu; then
      log_warn "Pacman refresh failed after BlackArch setup; rerun 'pacman -Syyu' manually."
    fi
  fi
}

run_task_blackarch() {
  load_previous_answers
  if [[ -z "${ENABLE_BLACKARCH_REPO}" ]]; then
    prompt_for_blackarch_repo
  fi

  if [[ "${ENABLE_BLACKARCH_REPO}" != "yes" ]]; then
    log_info "Skipping BlackArch repository configuration per operator preference."
    BLACKARCH_TASK_COMPLETED=1
    record_prompt_answers
    return 0
  fi

  blackarch_configure_repo
  BLACKARCH_TASK_COMPLETED=1
  record_prompt_answers
  log_info "BlackArch repository prerequisites satisfied."
}

blackarch_ensure_ready() {
  if [[ "${BLACKARCH_TASK_COMPLETED}" -eq 1 ]]; then
    return 0
  fi
  load_previous_answers
  if [[ -z "${ENABLE_BLACKARCH_REPO}" ]]; then
    prompt_for_blackarch_repo
    record_prompt_answers
  fi
  if [[ "${ENABLE_BLACKARCH_REPO}" != "yes" ]]; then
    log_info "Skipping BlackArch repository configuration per operator preference."
    BLACKARCH_TASK_COMPLETED=1
    return 0
  fi
  run_task_blackarch
}
