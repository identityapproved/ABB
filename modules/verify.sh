# shellcheck shell=bash

final_verification() {
  log_info "Verification summary:"

  if command_exists pacman; then
    if ! pacman -Q tree tealdeer ripgrep fd zsh fzf bat htop iftop wireguard-tools openresolv >/dev/null 2>&1; then
      log_warn "One or more core packages are missing. Review pacman output above."
    fi
  fi

  if [[ -n "${PACKAGE_MANAGER}" ]] && command_exists "${PACKAGE_MANAGER}"; then
    if ! run_as_user "${PACKAGE_MANAGER} --version" >/dev/null 2>&1; then
      run_as_user "${PACKAGE_MANAGER} -V" >/dev/null 2>&1 || log_warn "${PACKAGE_MANAGER} version check failed."
    fi
  else
    log_warn "Configured package manager '${PACKAGE_MANAGER:-unset}' not detected on PATH."
  fi

  if run_as_user "command -v pdtm" >/dev/null 2>&1; then
    run_as_user "pdtm --version" >/dev/null 2>&1 || log_warn "pdtm version check failed."
  else
    log_warn "pdtm not detected for ${NEW_USER}."
  fi

  command_exists masscan >/dev/null 2>&1 || log_warn "masscan not detected. Re-run 'abb-setup.sh tools' to install it via pacman."
  if run_as_user "command -v feroxbuster" >/dev/null 2>&1; then
    run_as_user "feroxbuster --version" >/dev/null 2>&1 || true
  else
    log_warn "feroxbuster not detected. Re-run 'abb-setup.sh tools' and select the preferred installation method."
  fi

  if [[ "${TRUFFLEHOG_INSTALL}" == "yes" ]]; then
    if ! command_exists trufflehog; then
      log_warn "trufflehog CLI not detected despite installation request."
    fi
  fi

  if run_as_user "command -v mull >/dev/null 2>&1"; then
    run_as_user "mull --help" >/dev/null 2>&1 || log_warn "Mullvad CLI (mull) responds unexpectedly."
  else
    log_warn "Mullvad CLI wrapper 'mull' not detected. Re-run 'abb-setup.sh utilities' after reviewing the WireGuard setup logs."
  fi

  if [[ "${CONTAINER_ENGINE}" == "docker" ]]; then
    command_exists amass >/dev/null 2>&1 || log_warn "Amass wrapper not detected. Re-run 'abb-setup.sh docker-tools' to install the Docker helper."
    command_exists feroxbuster-docker >/dev/null 2>&1 || log_warn "feroxbuster Docker wrapper not detected. Re-run 'abb-setup.sh docker-tools'."
    command_exists trufflehog-docker >/dev/null 2>&1 || log_warn "trufflehog Docker wrapper not detected. Re-run 'abb-setup.sh docker-tools'."
  fi

  case "${NODE_MANAGER}" in
    fnm)
      run_as_user "command -v fnm" >/dev/null 2>&1 || log_warn "fnm not detected despite selection."
      ;;
    nvm)
      run_as_user "[[ -s ~/.nvm/nvm.sh ]]" >/dev/null 2>&1 || log_warn "nvm directory not found for ${NEW_USER}."
      ;;
  esac

  run_as_user "command -v go >/dev/null 2>&1 && go version" || log_warn "Go runtime not found for ${NEW_USER}"
  run_as_user "pipx list" || log_warn "pipx list failed."

  local pd_missing=()
  for tool in ${PDTM_TOOLS[*]}; do
    if ! run_as_user "[[ -x \$HOME/.local/bin/${tool} ]]" >/dev/null 2>&1; then
      pd_missing+=("${tool}")
    fi
  done
  if ((${#pd_missing[@]})); then
    log_warn "ProjectDiscovery binaries missing from ~/.local/bin: ${pd_missing[*]}"
  fi

  if [[ -f "${INSTALLED_TRACK_FILE}" ]]; then
    log_info "Installed tools recorded in ${INSTALLED_TRACK_FILE}"
  fi
  log_info "Provisioning log: ${LOG_FILE}"
}

run_task_verify() {
  ensure_user_context
  ensure_package_manager_ready
  final_verification
}
