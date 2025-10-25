# shellcheck shell=bash

prompt_for_user() {
  if [[ -n "${NEW_USER}" ]]; then
    log_info "Using existing user selection: ${NEW_USER}"
    return
  fi
  local input=""
  while true; do
    read -rp "Enter name for the managed non-root user: " input </dev/tty || { log_error "Unable to read username."; exit 1; }
    input="$(echo "${input}" | tr -d '[:space:]')"
    if [[ -z "${input}" ]]; then
      echo "Username cannot be blank." >/dev/tty
      continue
    fi
    if [[ "${input}" == "root" ]]; then
      cat >/dev/tty <<'EOF'
The provisioning workflow must target a non-root account.
Create one with:
  sudo useradd -m -s /bin/bash <username>
  sudo passwd <username>
  sudo usermod -aG wheel <username>

Then rerun this prompt and provide the new username.
EOF
      continue
    fi
    if [[ "${input}" == "admin" ]]; then
      cat >/dev/tty <<'EOF'
The default Contabo account is "admin". To rename it manually, run:
  sudo usermod -l <newname> admin
  sudo usermod -d /home/<newname> -m <newname>
  sudo groupmod -n <newname> admin || true

You can continue using "admin" for provisioning, or rename it first and rerun.
EOF
      local confirm=""
      read -rp "Continue using admin? (yes/no): " confirm </dev/tty || { log_error "Unable to read confirmation."; exit 1; }
      case "${confirm,,}" in
        yes|y)
          NEW_USER="admin"
          break
          ;;
        no|n)
          continue
          ;;
        *)
          echo "Please answer yes or no." >/dev/tty
          continue
          ;;
      esac
    else
      NEW_USER="${input}"
      break
    fi
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
  if [[ "${NEW_USER}" == "root" ]]; then
    log_error "Refusing to manage the root account. Create a dedicated user and rerun the prompts."
    exit 1
  fi
  if ! id -u "${NEW_USER}" >/dev/null 2>&1; then
    if id -u admin >/dev/null 2>&1; then
      cat <<EOF
User '${NEW_USER}' does not exist yet.
Rename the default account with:
  sudo usermod -l ${NEW_USER} admin
  sudo usermod -d /home/${NEW_USER} -m ${NEW_USER}
  sudo groupmod -n ${NEW_USER} admin || true

Rerun abb-setup.sh prompts after completing the rename.
EOF
    else
      cat <<EOF
User '${NEW_USER}' does not exist.
Create it with:
  sudo useradd -m -s /bin/bash ${NEW_USER}
  sudo passwd ${NEW_USER}
  sudo usermod -aG wheel ${NEW_USER}

Rerun abb-setup.sh prompts afterwards.
EOF
    fi
    exit 1
  fi
  if [[ "${NEW_USER}" == "admin" ]]; then
    log_warn "Continuing with the default 'admin' account. Rename it later if desired."
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
