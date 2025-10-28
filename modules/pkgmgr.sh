# shellcheck shell=bash

prompt_for_package_manager() {
  if [[ -n "${PACKAGE_MANAGER}" ]]; then
    log_info "Using stored package manager: ${PACKAGE_MANAGER}"
    return
  fi
  local choice=""
  while true; do
    read -rp "Select AUR helper to install (yay): " choice </dev/tty || { log_error "Unable to read package manager selection."; exit 1; }
    choice="$(echo "${choice}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "${choice}" in
      ""|yay)
        PACKAGE_MANAGER="yay"
        break
        ;;
      *)
        echo "Unsupported choice. Available option: yay." >/dev/tty
        ;;
    esac
  done
  log_info "Selected package manager: ${PACKAGE_MANAGER}"
}

install_yay_helper() {
  if command_exists yay; then
    log_info "yay already installed."
    append_installed_tool "yay"
    return
  fi
  if ! command_exists git; then
    log_error "git is required to install yay. Install git and rerun 'abb-setup.sh package-manager'."
    exit 1
  fi
  pacman_install_packages base-devel
  local tmpdir
  if ! tmpdir="$(mktemp -d)"; then
    log_error "Failed to create temporary directory for package manager build."
    exit 1
  fi
  chown -R "${NEW_USER}:${NEW_USER}" "${tmpdir}"
  if ! run_as_user "$(printf 'cd %q && /usr/bin/git clone https://aur.archlinux.org/yay.git' "${tmpdir}")"; then
    log_error "Cloning yay AUR repository failed."
    rm -rf "${tmpdir}"
    exit 1
  fi
  local build_cmd
  build_cmd=$(printf 'cd %q/yay && /usr/bin/env PATH="/usr/bin:/bin:/usr/local/bin:$PATH" HOME="$HOME" makepkg -si --noconfirm' "${tmpdir}")
  if run_as_user "${build_cmd}"; then
    log_info "Installed yay."
    append_installed_tool "yay"
  else
    log_error "Failed to build/install yay."
    rm -rf "${tmpdir}"
    exit 1
  fi
  rm -rf "${tmpdir}"
}

ensure_package_manager_ready() {
  case "${PACKAGE_MANAGER}" in
    yay)
      if ! command_exists yay; then
        log_error "Configured package manager 'yay' not found. Run 'abb-setup.sh package-manager' first."
        exit 1
      fi
      ;;
    "")
      log_error "Package manager not configured yet. Run 'abb-setup.sh package-manager' first."
      exit 1
      ;;
    *)
      log_error "Unsupported package manager '${PACKAGE_MANAGER}'."
      exit 1
      ;;
  esac
}

run_task_package_manager() {
  load_previous_answers
  if [[ -z "${NEW_USER}" ]]; then
    log_error "Run 'abb-setup.sh prompts' and 'abb-setup.sh accounts' before configuring the package manager."
    exit 1
  fi
  ensure_user_context
  prompt_for_package_manager
  case "${PACKAGE_MANAGER}" in
    yay)
      install_yay_helper
      ;;
    *)
      log_error "Unsupported package manager '${PACKAGE_MANAGER}'."
      exit 1
      ;;
  esac
  record_prompt_answers
  log_info "Package manager '${PACKAGE_MANAGER}' ready."
}
