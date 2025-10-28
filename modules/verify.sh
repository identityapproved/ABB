# shellcheck shell=bash

final_verification() {
  log_info "Verification summary:"

  if command_exists pacman; then
    if ! pacman -Q tree tealdeer ripgrep fd zsh fzf bat htop iftop >/dev/null 2>&1; then
      log_warn "One or more core packages are missing. Review pacman output above."
    fi
  fi

  if command_exists yay; then
    run_as_user "yay --version" || log_warn "yay is installed but version check failed."
  else
    log_warn "yay not detected on PATH."
  fi

  run_as_user "command -v go >/dev/null 2>&1 && go version" || log_warn "Go runtime not found for ${NEW_USER}"
  run_as_user "pipx list" || log_warn "pipx list failed."

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
