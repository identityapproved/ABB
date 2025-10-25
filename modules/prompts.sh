# shellcheck shell=bash

prompt_for_user() {
  if [[ -n "${NEW_USER}" ]]; then
    log_info "Using existing user selection: ${NEW_USER}"
    return
  fi
  local input=""
  while true; do
    read -rp "Enter name for the new non-root user: " input </dev/tty || { log_error "Unable to read username."; exit 1; }
    input="$(echo "${input}" | tr -d '[:space:]')"
    if [[ -z "${input}" ]]; then
      echo "Username cannot be blank." >/dev/tty
      continue
    fi
    if [[ "${input}" == "root" ]]; then
      echo "Do not use root for the managed account." >/dev/tty
      continue
    fi
    NEW_USER="${input}"
    break
  done
  log_info "Selected user: ${NEW_USER}"
}

prompt_for_editor_choice() {
  local choice=""
  if [[ -n "${EDITOR_CHOICE}" ]]; then
    log_info "Editor preference: ${EDITOR_CHOICE}"
    return
  fi
  while true; do
    read -rp "Configure which editor (vim/neovim/both): " choice </dev/tty || { log_error "Unable to read editor choice."; exit 1; }
    case "${choice,,}" in
      vim)
        EDITOR_CHOICE="vim"
        break
        ;;
      neovim|nvim)
        EDITOR_CHOICE="neovim"
        break
        ;;
      both)
        EDITOR_CHOICE="both"
        break
        ;;
      *)
        echo "Please answer vim, neovim, or both." >/dev/tty
        ;;
    esac
  done
  log_info "Editor selection: ${EDITOR_CHOICE}"
}

prompt_for_hardening() {
  local choice=""
  if [[ "${NEEDS_PENTEST_HARDENING}" == "true" || "${NEEDS_PENTEST_HARDENING}" == "false" ]]; then
    log_info "Pentest hardening flag: ${NEEDS_PENTEST_HARDENING}"
    return
  fi
  while true; do
    read -rp "Apply optional pentest VPN/sysctl hardening? (yes/no): " choice </dev/tty || { log_error "Unable to read hardening choice."; exit 1; }
    case "${choice,,}" in
      yes|y)
        NEEDS_PENTEST_HARDENING="true"
        break
        ;;
      no|n)
        NEEDS_PENTEST_HARDENING="false"
        break
        ;;
      *)
        echo "Please answer yes or no." >/dev/tty
        ;;
    esac
  done
  log_info "Pentest hardening: ${NEEDS_PENTEST_HARDENING}"
}

collect_prompt_answers() {
  prompt_for_user
  prompt_for_editor_choice
  prompt_for_hardening
  record_prompt_answers
}

ensure_primary_user() {
  local existing="admin"
  local old_home="/home/${existing}"
  local new_home="/home/${NEW_USER}"

  if id -u "${NEW_USER}" >/dev/null 2>&1; then
    log_info "User ${NEW_USER} already exists."
  elif id -u "${existing}" >/dev/null 2>&1; then
    log_info "Renaming ${existing} to ${NEW_USER}"
    usermod -l "${NEW_USER}" "${existing}"
    if [[ -d "${old_home}" ]]; then
      usermod -d "${new_home}" -m "${NEW_USER}"
    fi
    if getent group "${existing}" >/dev/null 2>&1; then
      groupmod -n "${NEW_USER}" "${existing}" || true
    fi
  else
    log_info "Creating user ${NEW_USER}"
    useradd -m -s /bin/bash "${NEW_USER}"
    log_warn "Password for ${NEW_USER} was not changed automatically; run 'passwd ${NEW_USER}' if needed."
  fi

  if ! id -nG "${NEW_USER}" | grep -qw wheel; then
    usermod -aG wheel "${NEW_USER}"
    log_info "Added ${NEW_USER} to wheel group."
  fi

  id "${NEW_USER}"
  if [[ "${SUDO_USER:-root}" == "root" ]]; then
    log_warn "Provisioning is running as root. Switch to ${NEW_USER} for daily operations."
  fi
}

run_task_prompts() {
  load_previous_answers
  collect_prompt_answers
  ensure_primary_user
  init_installed_tracker
}
