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

refresh_pacman_mirrors() {
  log_info "Installing reflector to refresh Arch mirror list."
  pacman_install_packages reflector
  if command_exists reflector; then
    if reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; then
      log_info "Mirror list updated using reflector."
    else
      log_warn "Reflector failed to refresh mirrors."
    fi
  else
    log_warn "Reflector binary unavailable after install attempt."
  fi

  if ! pacman --noconfirm -Syyu; then
    log_warn "Pacman refresh after mirror update failed; rerun 'pacman -Syyu' manually."
  fi
}

run_task_package_manager() {
  load_previous_answers
  if [[ -z "${NEW_USER}" ]]; then
    log_error "Run 'abb-setup.sh prompts' and 'abb-setup.sh accounts' before configuring the package manager."
    exit 1
  fi

  refresh_pacman_mirrors
  blackarch_ensure_ready
  ensure_user_context
  log_info "Managed user context confirmed; proceeding to package manager selection."
  prompt_for_package_manager
  install_aur_helper "${PACKAGE_MANAGER}"
  record_prompt_answers
  log_info "Package manager '${PACKAGE_MANAGER}' ready."
}
