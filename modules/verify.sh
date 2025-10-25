# shellcheck shell=bash

final_verification() {
  log_info "Verification summary:"
  getenforce || true
  run_as_user "command -v go && go version" || log_warn "Go runtime not found for ${NEW_USER}"
  run_as_user "pipx list" || log_warn "pipx list failed."
  if [[ -f "${INSTALLED_TRACK_FILE}" ]]; then
    log_info "Installed tools recorded in ${INSTALLED_TRACK_FILE}"
  fi
  log_info "Provisioning log: ${LOG_FILE}"
}

run_task_verify() {
  ensure_user_context
  final_verification
}
