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
  if grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    log_info "multilib repository already enabled."
    return 1
  fi

  sed -i 's/^#\s*\[multilib\]/[multilib]/' /etc/pacman.conf
  sed -i 's/^#\s*Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/' /etc/pacman.conf

  if grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    log_info "Enabled multilib repository in /etc/pacman.conf."
    return 0
  fi

  log_warn "Unable to enable multilib repository automatically. Review /etc/pacman.conf."
  return 2
}

install_blackarch_repo() {
  local need_refresh=0
  local conf_file="/etc/pacman.d/blackarch.conf"
  local key_tmp=""
  local key_ids=""
  local result

  if [[ ! -f "${conf_file}" ]] || ! grep -Eq 'https://blackarch\.org/repo/included/\$arch' "${conf_file}"; then
    cat <<'EOF' > "${conf_file}"
[blackarch]
Server = https://blackarch.org/repo/included/$arch
Include = /etc/pacman.d/mirrorlist
EOF
    chmod 0644 "${conf_file}"
    log_info "Configured BlackArch repository definition in ${conf_file}."
    need_refresh=1
  else
    log_info "BlackArch repository definition already present at ${conf_file}."
  fi

  if ! pacman-key --list-keys 0E5E3303 >/dev/null 2>&1; then
    pacman_install_packages curl gnupg
    key_tmp="$(mktemp /tmp/blackarch-key.XXXXXX.asc)"
    if [[ -z "${key_tmp}" ]]; then
      log_error "Failed to create temporary file for BlackArch key."
      exit 1
    fi
    if ! curl -fsSLo "${key_tmp}" "https://blackarch.org/keyring/blackarch.asc"; then
      log_error "Failed to download BlackArch key."
      rm -f "${key_tmp}"
      exit 1
    fi
    if ! pacman-key --add "${key_tmp}"; then
      log_error "Failed to import BlackArch key into pacman keyring."
      rm -f "${key_tmp}"
      exit 1
    fi
    key_ids="$(gpg --with-colons --import-options show-only --import "${key_tmp}" 2>/dev/null | awk -F: '/^pub/ {print $5}')"
    rm -f "${key_tmp}"
    if [[ -z "${key_ids}" ]]; then
      key_ids="0E5E3303"
    fi
    for key_id in ${key_ids}; do
      if pacman-key --lsign-key "${key_id}"; then
        log_info "Locally signed BlackArch key ${key_id}."
      else
        log_warn "Failed to locally sign BlackArch key ${key_id}."
      fi
    done
    need_refresh=1
  else
    log_info "BlackArch pacman key already present."
  fi

  if ! grep -Eq '^\s*Include\s*=\s*/etc/pacman\.d/blackarch\.conf' /etc/pacman.conf; then
    printf '\n# Include BlackArch repository configuration\nInclude = /etc/pacman.d/blackarch.conf\n' >> /etc/pacman.conf
    log_info "Linked ${conf_file} from /etc/pacman.conf."
    need_refresh=1
  else
    log_info "/etc/pacman.conf already references ${conf_file}."
  fi

  enable_multilib_repo
  result=$?
  if [[ ${result} -eq 0 ]]; then
    need_refresh=1
  elif [[ ${result} -eq 2 ]]; then
    log_warn "Proceeding without multilib automatically enabled."
  fi

  if ((need_refresh)); then
    log_info "Refreshing package databases after BlackArch configuration."
    if ! pacman --noconfirm -Syyu; then
      log_warn "Pacman refresh failed after BlackArch setup; rerun 'pacman -Syyu' manually."
    fi
  fi
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

  install_blackarch_repo
  ensure_user_context
  prompt_for_package_manager
  install_aur_helper "${PACKAGE_MANAGER}"
  record_prompt_answers
  log_info "Package manager '${PACKAGE_MANAGER}' ready."
}
