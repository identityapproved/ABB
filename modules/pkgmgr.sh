# shellcheck shell=bash

SUPPORTED_HELPERS=(pacaur pikaur yay aura paru aurman)

declare -A HELPER_AUR_PACKAGES=(
  [pacaur]=pacaur
  [pikaur]=pikaur
  [yay]=yay
  [paru]=paru-bin
  [aura]=aura-bin
  [aurman]=aurman
)

declare -A HELPER_AUR_FALLBACKS=(
  [yay]=yay-git
)

normalize_pacman_testing_includes() {
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

helper_supported() {
  local helper="$1" candidate
  for candidate in "${SUPPORTED_HELPERS[@]}"; do
    if [[ "${candidate}" == "${helper}" ]]; then
      return 0
    fi
  done
  return 1
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

install_blackarch_repo() {
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

  selected_mirror="${BLACKARCH_MIRROR:-${saved_mirror:-${default_mirror}}}"
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

  if enable_multilib_repo; then
    result=0
  else
    result=$?
  fi
  if [[ ${result} -eq 0 ]]; then
    need_refresh=1
  elif [[ ${result} -eq 2 ]]; then
    log_warn "Proceeding without multilib automatically enabled."
  fi

  normalize_pacman_testing_includes

  if ((need_refresh)); then
    log_info "Refreshing package databases after BlackArch configuration."
    if ! pacman --noconfirm -Syyu; then
      log_warn "Pacman refresh failed after BlackArch setup; rerun 'pacman -Syyu' manually."
    fi
  fi

  return 0
}

prompt_for_package_manager() {
  if [[ -n "${PACKAGE_MANAGER}" ]]; then
    log_info "Using stored package manager: ${PACKAGE_MANAGER}"
    return
  fi

  local choice="" options="pacaur/pikaur/yay/aura/paru/aurman"
  while true; do
    read -rp "Select AUR helper to install (${options}, default yay): " choice </dev/tty || { log_error "Unable to read package manager selection."; exit 1; }
    choice="$(echo "${choice}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [[ -z "${choice}" ]] && choice="yay"
    if helper_supported "${choice}"; then
      PACKAGE_MANAGER="${choice}"
      break
    fi
    echo "Unsupported choice. Valid options: ${options}." >/dev/tty
  done
  log_info "Selected package manager: ${PACKAGE_MANAGER}"
}

install_aur_helper() {
  local helper="$1"
  local aur_pkg="${HELPER_AUR_PACKAGES[${helper}]:-}"
  local fallback_pkg="${HELPER_AUR_FALLBACKS[${helper}]:-}"
  local candidates=()
  local pkg repo_dir success=0

  if [[ -z "${helper}" || -z "${aur_pkg}" ]]; then
    log_error "Helper '${helper}' is not supported."
    exit 1
  fi

  candidates+=("${aur_pkg}")
  if [[ -n "${fallback_pkg}" ]]; then
    candidates+=("${fallback_pkg}")
  fi

  if command_exists "${helper}"; then
    log_info "${helper} already installed."
    append_installed_tool "${helper}"
    return
  fi

  if ! command_exists git; then
    log_error "git is required to build ${helper}. Install git and rerun 'abb-setup.sh package-manager'."
    exit 1
  fi

  pacman_install_packages base-devel

  local tmpdir clone_cmd build_cmd
  if ! tmpdir="$(mktemp -d)"; then
    log_error "Failed to create temporary directory for package manager build."
    exit 1
  fi
  chown -R "${NEW_USER}:${NEW_USER}" "${tmpdir}"
  for pkg in "${candidates[@]}"; do
    repo_dir="${tmpdir}/${pkg}"
    rm -rf "${repo_dir}"
    log_info "Preparing ${helper} using AUR package ${pkg}."
    clone_cmd=$(printf 'cd %q && /usr/bin/git clone --depth 1 %q %q' "${tmpdir}" "https://aur.archlinux.org/${pkg}.git" "${repo_dir}")
    if ! run_as_user "${clone_cmd}"; then
      log_warn "Cloning ${pkg} AUR repository failed."
      continue
    fi

    build_cmd=$(printf 'cd %q && /usr/bin/env PATH="/usr/bin:/bin:/usr/local/bin:$PATH" HOME="$HOME" makepkg -si --noconfirm --needed' "${repo_dir}")
    if run_as_user "${build_cmd}"; then
      log_info "Installed ${helper} via ${pkg}."
      append_installed_tool "${helper}"
      success=1
      break
    fi
    log_warn "Failed to build/install ${helper} from ${pkg}."
  done

  if ((success == 0)); then
    rm -rf "${tmpdir}"
    log_error "Unable to install ${helper}; all AUR package candidates failed."
    exit 1
  fi

  rm -rf "${tmpdir}"
}

aur_helper_install() {
  local package="$1" cmd=""
  if [[ -z "${package}" ]]; then
    return 1
  fi

  case "${PACKAGE_MANAGER}" in
    yay|paru|pikaur)
      cmd=$(printf '%s -S --noconfirm --needed %q' "${PACKAGE_MANAGER}" "${package}")
      ;;
    pacaur|aurman)
      cmd=$(printf '%s -S --noconfirm --noedit %q' "${PACKAGE_MANAGER}" "${package}")
      ;;
    aura)
      cmd=$(printf 'aura -A --noconfirm %q' "${package}")
      ;;
    *)
      log_error "Unsupported package manager '${PACKAGE_MANAGER}'."
      return 1
  esac

  if run_as_user "${cmd}"; then
    return 0
  fi
  log_warn "Failed to install ${package} via ${PACKAGE_MANAGER}."
  return 1
}

ensure_package_manager_ready() {
  if [[ -z "${PACKAGE_MANAGER}" ]]; then
    log_error "Package manager not configured yet. Run 'abb-setup.sh package-manager' first."
    exit 1
  fi
  if ! helper_supported "${PACKAGE_MANAGER}"; then
    log_error "Unsupported package manager '${PACKAGE_MANAGER}'."
    exit 1
  fi
  if ! command_exists "${PACKAGE_MANAGER}"; then
    log_error "Configured package manager '${PACKAGE_MANAGER}' not found. Run 'abb-setup.sh package-manager' first."
    exit 1
  fi
}

run_task_package_manager() {
  load_previous_answers
  if [[ -z "${NEW_USER}" ]]; then
    log_error "Run 'abb-setup.sh prompts' and 'abb-setup.sh accounts' before configuring the package manager."
    exit 1
  fi

  if [[ "${ENABLE_BLACKARCH_REPO}" == "yes" ]]; then
    install_blackarch_repo
    log_info "BlackArch repository prerequisites satisfied."
  else
    log_info "Skipping BlackArch repository configuration per operator preference."
  fi
  ensure_user_context
  log_info "Managed user context confirmed; proceeding to package manager selection."
  prompt_for_package_manager
  install_aur_helper "${PACKAGE_MANAGER}"
  record_prompt_answers
  log_info "Package manager '${PACKAGE_MANAGER}' ready."
}
