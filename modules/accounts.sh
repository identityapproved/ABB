# shellcheck shell=bash

set_user_password() {
  local pass1="" pass2=""
  while true; do
    read -rsp "Set password for ${NEW_USER} (leave blank to skip): " pass1 </dev/tty || { log_error "Unable to read password."; return; }
    echo >/dev/tty
    if [[ -z "${pass1}" ]]; then
      log_warn "Skipped password configuration for ${NEW_USER}. Use 'passwd ${NEW_USER}' later if needed."
      return
    fi
    read -rsp "Confirm password: " pass2 </dev/tty || { log_error "Unable to confirm password."; return; }
    echo >/dev/tty
    if [[ "${pass1}" != "${pass2}" ]]; then
      echo "Passwords do not match. Try again." >/dev/tty
      continue
    fi
    if echo "${NEW_USER}:${pass1}" | chpasswd; then
      log_info "Password configured for ${NEW_USER}."
    else
      log_warn "Failed to set password for ${NEW_USER}."
    fi
    return
  done
}

create_managed_user() {
  if id -u "${NEW_USER}" >/dev/null 2>&1; then
    log_info "User ${NEW_USER} already exists."
    return
  fi
  log_info "Creating user ${NEW_USER}."
  if ! useradd -m -s /bin/bash "${NEW_USER}"; then
    log_error "Failed to create user ${NEW_USER}."
    exit 1
  fi
  set_user_password
}

ensure_wheel_group() {
  if ! id -nG "${NEW_USER}" | grep -qw wheel; then
    usermod -aG wheel "${NEW_USER}"
    log_info "Added ${NEW_USER} to wheel group."
  fi
}

enable_wheel_sudoers() {
  if grep -Eq '^[[:space:]]*%wheel[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+ALL' /etc/sudoers; then
    log_info "Wheel sudoers entry already enabled in /etc/sudoers."
    return
  fi
  local tmp_file
  tmp_file="$(mktemp)"
  cp /etc/sudoers "${tmp_file}"
  if ! LC_ALL=C sed -i 's/^[[:space:]]*#\s*\(%wheel ALL=(ALL:ALL) ALL\)/\1/' "${tmp_file}"; then
    log_error "Failed to update wheel entry in temporary sudoers copy."
    rm -f "${tmp_file}"
    return
  fi
  LC_ALL=C sed -i 's/^[[:space:]]*\\1%wheel/%wheel/' "${tmp_file}"
  if visudo -cf "${tmp_file}"; then
    cat "${tmp_file}" > /etc/sudoers
    chmod 0440 /etc/sudoers
    log_info "Enabled wheel sudoers entry in /etc/sudoers."
  else
    log_error "visudo validation failed; wheel entry not enabled."
  fi
  rm -f "${tmp_file}"
}

copy_authorized_keys_from_admin() {
  local admin_home="" target_home=""
  if [[ "${NEW_USER}" == "admin" ]]; then
    return
  fi
  if ! id -u admin >/dev/null 2>&1; then
    log_warn "admin account not present; skipping authorized_keys copy."
    return
  fi
  admin_home="$(getent passwd admin | cut -d: -f6)"
  target_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${admin_home}" || -z "${target_home}" ]]; then
    log_warn "Unable to determine home directories for key migration."
    return
  fi
  if [[ ! -f "${admin_home}/.ssh/authorized_keys" ]]; then
    log_warn "No authorized_keys found for admin; skipping key copy."
    return
  fi
  install -d -m 0700 "${target_home}/.ssh"
  if [[ -f "${target_home}/.ssh/authorized_keys" ]]; then
    log_info "authorized_keys already exists for ${NEW_USER}; leaving as-is."
  else
    cp "${admin_home}/.ssh/authorized_keys" "${target_home}/.ssh/authorized_keys"
    log_info "Copied admin authorized_keys to ${NEW_USER}."
  fi
  chown -R "${NEW_USER}:${NEW_USER}" "${target_home}/.ssh"
  chmod 0700 "${target_home}/.ssh"
  chmod 0600 "${target_home}/.ssh/authorized_keys"
}

sync_repo_to_user_home() {
  local user_home dest
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_warn "Unable to determine home directory for ${NEW_USER}; skipping ABB repo clone."
    return
  fi
  dest="${user_home}/ABB"
  if [[ -d "${dest}" ]]; then
    log_info "ABB repository already present at ${dest}."
    return
  fi
  if ! command_exists git; then
    log_warn "git not available; copy the ABB repository to ${dest} manually."
    return
  fi
  log_info "Cloning ABB repository into ${dest}."
  if git clone --recursive "${REPO_ROOT}" "${dest}" >/dev/null 2>&1; then
    chown -R "${NEW_USER}:${NEW_USER}" "${dest}" || log_warn "Failed to adjust ownership for ${dest}."
    log_info "ABB repository copied to ${dest}."
  else
    log_warn "Cloning ABB into ${dest} failed; copy it manually."
  fi
}

ensure_primary_user() {
  if [[ -z "${NEW_USER}" ]]; then
    log_error "Managed username is empty. Re-run prompts first."
    exit 1
  fi
  if [[ "${NEW_USER}" == "root" ]]; then
    log_error "Refusing to manage the root account. Choose a different username."
    exit 1
  fi
  if [[ "${NEW_USER}" == "admin" ]]; then
    log_error "Select a non-admin username via 'abb-setup.sh prompts' before continuing."
    exit 1
  fi

  create_managed_user
  ensure_wheel_group
  enable_wheel_sudoers
  copy_authorized_keys_from_admin
  sync_repo_to_user_home
}

verify_managed_user_ready() {
  if [[ -z "${NEW_USER}" ]]; then
    log_error "Managed username is empty. Run 'abb-setup.sh prompts' first."
    exit 1
  fi
  if ! id -u "${NEW_USER}" >/dev/null 2>&1; then
    log_error "User ${NEW_USER} is not present. Run 'abb-setup.sh accounts' to create it."
    exit 1
  fi
}

suggest_login_transfer() {
  cat <<EOF
Next steps:
  - Reconnect as ${NEW_USER} via SSH (for example: ssh ${NEW_USER}@<host>).
  - After reconnecting, run 'sudo ./abb-setup.sh accounts' to continue with provisioning.
EOF
}

should_offer_admin_cleanup() {
  if [[ "${NEW_USER}" == "admin" ]]; then
    return 1
  fi
  if ! id -u admin >/dev/null 2>&1; then
    return 1
  fi
  local invoking="${SUDO_USER:-}"
  if [[ -z "${invoking}" ]]; then
    return 1
  fi
  if [[ "${invoking}" != "${NEW_USER}" ]]; then
    log_info "Admin account still present. Log in as ${NEW_USER} and rerun 'abb-setup.sh accounts' to remove it."
    return 1
  fi
  return 0
}

remove_admin_account() {
  if ! should_offer_admin_cleanup; then
    return
  fi
  local confirm=""
  read -rp "Remove the legacy 'admin' account now? (yes/no): " confirm </dev/tty || { log_warn "Skipping admin removal."; return; }
  case "${confirm,,}" in
    yes|y)
      if command_exists deluser; then
        deluser --remove-home admin >/dev/null 2>&1 || log_warn "deluser failed; attempting userdel -r admin."
      fi
      if userdel -r admin >/dev/null 2>&1; then
        log_info "Removed admin account and home directory."
      else
        log_warn "Failed to remove admin with userdel. Manual cleanup may be required."
      fi
      ;;
    no|n)
      log_info "Admin account retained."
      ;;
    *)
      log_info "Unrecognised response. Admin account retained."
      ;;
  esac
}

run_task_accounts() {
  load_previous_answers
  if [[ -z "${NEW_USER}" ]]; then
    prompt_for_user
    record_prompt_answers
  fi
  ensure_primary_user
  init_installed_tracker
  remove_admin_account
  record_prompt_answers
  if [[ "${SUDO_USER:-}" != "${NEW_USER}" ]]; then
    suggest_login_transfer
    log_info "Exiting so you can reconnect as ${NEW_USER}."
    exit 0
  fi
  if id -u admin >/dev/null 2>&1; then
    log_info "The 'admin' account is still present. Rerun this task after logging in as ${NEW_USER} to remove it."
  fi
  log_info "Managed account ${NEW_USER} is ready."
}
