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
  local tmp_file=""
  if ! grep -Eq '^[[:space:]]*#?[[:space:]]*%wheel[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+ALL' /etc/sudoers; then
    log_warn "Wheel sudoers stanza not found in /etc/sudoers; skipping automatic edit."
    return
  fi
  if grep -Eq '^[[:space:]]*%wheel[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+ALL' /etc/sudoers; then
    log_info "Wheel sudoers entry already enabled."
    return
  fi
  tmp_file="$(mktemp)"
  cp /etc/sudoers "${tmp_file}"
  awk '
    BEGIN {done=0}
    {
      if (!done && $0 ~ /^[[:space:]]*#?[[:space:]]*%wheel[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+ALL/) {
        sub(/^([[:space:]]*)#\s*/, "\\1");
        done=1;
      }
      print
    }
  ' "${tmp_file}" > "${tmp_file}.new"
  if visudo -cf "${tmp_file}.new"; then
    cat "${tmp_file}.new" > /etc/sudoers
    chmod 0440 /etc/sudoers
    log_info "Enabled wheel sudoers entry."
  else
    log_error "visudo validation failed; preserving existing /etc/sudoers."
  fi
  rm -f "${tmp_file}" "${tmp_file}.new"
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
}

suggest_login_transfer() {
  cat <<EOF
Next steps:
  - Connect as ${NEW_USER} via SSH (e.g., ssh ${NEW_USER}@<host>).
  - Move or clone this ABB repository into /home/${NEW_USER}/ABB for day-to-day use.

After logging in as ${NEW_USER}, rerun 'sudo ./abb-setup.sh accounts' to retire the 'admin' account.
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
  suggest_login_transfer
  remove_admin_account
}
