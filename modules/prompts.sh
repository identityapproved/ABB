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

prompt_for_auth_method() {
  local choice=""
  if [[ -n "${AUTH_METHOD}" ]]; then
    log_info "Using saved authentication method: ${AUTH_METHOD}"
  else
    while true; do
      read -rp "Choose SSH authentication (password/ssh-key): " choice </dev/tty || { log_error "Unable to read authentication method."; exit 1; }
      case "${choice,,}" in
        password|p)
          AUTH_METHOD="password"
          break
          ;;
        ssh|ssh-key|key)
          AUTH_METHOD="ssh"
          break
          ;;
        *)
          echo "Please answer password or ssh-key." >/dev/tty
          ;;
      esac
    done
  fi
  if [[ "${AUTH_METHOD}" == "ssh" && -z "${SSH_PUBLIC_KEY}" ]]; then
    echo "Paste the public SSH key for ${NEW_USER} (single line):" >/dev/tty
    read -r SSH_PUBLIC_KEY </dev/tty || { log_error "Failed to read SSH public key."; exit 1; }
    if [[ -z "${SSH_PUBLIC_KEY}" ]]; then
      log_error "Public key cannot be empty."
      exit 1
    fi
  fi
  log_info "Authentication method: ${AUTH_METHOD}"
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
  prompt_for_auth_method
  prompt_for_editor_choice
  prompt_for_hardening
  record_prompt_answers
}

create_user_and_groups() {
  local user_created=0
  if ! id -u "${NEW_USER}" >/dev/null 2>&1; then
    log_info "Creating user ${NEW_USER}"
    useradd -m -s /bin/bash "${NEW_USER}"
    user_created=1
  else
    log_info "User ${NEW_USER} already exists."
  fi

  if ((user_created)); then
    log_info "Setting password for ${NEW_USER}"
    passwd "${NEW_USER}"
  else
    log_info "Skipping password change for existing user ${NEW_USER}. Run 'passwd ${NEW_USER}' if you need to update it."
  fi

  if ! id -nG "${NEW_USER}" | grep -qw wheel; then
    usermod -aG wheel "${NEW_USER}"
    log_info "Added ${NEW_USER} to wheel group."
  else
    log_info "${NEW_USER} already in wheel group."
  fi

  id "${NEW_USER}"
  if [[ "${SUDO_USER:-root}" == "root" ]]; then
    log_warn "Provisioning is running as root. Switch to ${NEW_USER} for daily operations."
  fi
}

run_task_prompts() {
  load_previous_answers
  collect_prompt_answers
  create_user_and_groups
  init_installed_tracker
}
