# shellcheck shell=bash

prompt_uses_fzf() {
  command_exists fzf
}

prompt_pick_option() {
  local prompt="$1"
  local default_value="$2"
  shift 2
  local options=("$@")
  local choice=""
  local option_list=""

  if prompt_uses_fzf; then
    choice="$(printf '%s\n' "${options[@]}" | fzf --prompt "${prompt}" --height 40% --reverse --border --select-1 --exit-0 </dev/tty)"
    if [[ -n "${choice}" ]]; then
      printf '%s\n' "${choice}"
      return 0
    fi
  fi

  option_list="$(IFS=/; printf '%s' "${options[*]}")"
  read -rp "${prompt}${option_list}${default_value:+ [${default_value}]}: " choice </dev/tty || return 1
  choice="$(echo "${choice}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ -z "${choice}" ]]; then
    choice="${default_value}"
  fi
  printf '%s\n' "${choice}"
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local choice=""

  while true; do
    choice="$(prompt_pick_option "${prompt}" "${default_value}" yes no)" || {
      log_error "Unable to read yes/no choice."
      exit 1
    }
    case "${choice,,}" in
      yes|y)
        printf 'true\n'
        return 0
        ;;
      no|n)
        printf 'false\n'
        return 0
        ;;
    esac
    echo "Please answer yes or no." >/dev/tty
  done
}

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
      echo "Select a new account name different from 'admin'." >/dev/tty
      continue
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
    choice="$(prompt_pick_option "Configure which editor: " "" vim neovim both)" || { log_error "Unable to read editor choice."; exit 1; }
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
  if [[ "${NEEDS_PENTEST_HARDENING}" == "true" || "${NEEDS_PENTEST_HARDENING}" == "false" ]]; then
    log_info "Pentest hardening flag: ${NEEDS_PENTEST_HARDENING}"
    return
  fi
  NEEDS_PENTEST_HARDENING="$(prompt_yes_no "Apply optional pentest VPN/sysctl hardening? " "no")"
  log_info "Pentest hardening: ${NEEDS_PENTEST_HARDENING}"
}

prompt_for_node_manager() {
  local choice=""
  if [[ -n "${NODE_MANAGER}" ]]; then
    log_info "Node manager selection: ${NODE_MANAGER}"
    return
  fi
  while true; do
    choice="$(prompt_pick_option "Select Node version manager: " "" nvm fnm)" || { log_error "Unable to read Node manager choice."; exit 1; }
    case "${choice,,}" in
      nvm|fnm)
        NODE_MANAGER="${choice,,}"
        break
        ;;
      *)
        echo "Please answer nvm or fnm." >/dev/tty
        ;;
    esac
  done
  log_info "Node manager selection: ${NODE_MANAGER}"
}

prompt_for_container_engine() {
  local choice=""
  if [[ -n "${CONTAINER_ENGINE}" ]]; then
    log_info "Container engine preference: ${CONTAINER_ENGINE}"
    return
  fi
  while true; do
    choice="$(prompt_pick_option "Install which container engine: " "" docker podman none)" || { log_error "Unable to read container engine choice."; exit 1; }
    case "${choice,,}" in
      docker|podman)
        CONTAINER_ENGINE="${choice,,}"
        break
        ;;
      none|skip)
        CONTAINER_ENGINE="none"
        break
        ;;
      *)
        echo "Please answer docker, podman, or none." >/dev/tty
        ;;
    esac
  done
  log_info "Container engine selection: ${CONTAINER_ENGINE}"
}

prompt_for_network_access_mode() {
  local choice=""
  if [[ -n "${NETWORK_ACCESS_MODE}" ]]; then
    log_info "Network access mode: ${NETWORK_ACCESS_MODE}"
    return
  fi
  while true; do
    choice="$(prompt_pick_option "Use which remote access mode: " "plain-ssh" plain-ssh tailscale-ssh)" || { log_error "Unable to read network access mode."; exit 1; }
    case "${choice,,}" in
      plain-ssh|tailscale-ssh)
        NETWORK_ACCESS_MODE="${choice,,}"
        break
        ;;
      *)
        echo "Please answer plain-ssh or tailscale-ssh." >/dev/tty
        ;;
    esac
  done
  log_info "Network access mode: ${NETWORK_ACCESS_MODE}"
}

prompt_for_ssh_key_source() {
  local choice=""
  if [[ -n "${SSH_KEY_SOURCE}" ]]; then
    log_info "SSH key source: ${SSH_KEY_SOURCE}"
    return
  fi
  while true; do
    choice="$(prompt_pick_option "Seed SSH access using: " "current-access" current-access admin paste skip)" || { log_error "Unable to read SSH key source."; exit 1; }
    case "${choice,,}" in
      current-access|admin|paste|skip)
        SSH_KEY_SOURCE="${choice,,}"
        break
        ;;
      *)
        echo "Please answer current-access, admin, paste, or skip." >/dev/tty
        ;;
    esac
  done
  log_info "SSH key source: ${SSH_KEY_SOURCE}"
}

prompt_for_trufflehog_install() {
  if [[ -n "${TRUFFLEHOG_INSTALL}" ]]; then
    log_info "Trufflehog installation preference: ${TRUFFLEHOG_INSTALL}"
    return
  fi
  if [[ "$(prompt_yes_no "Install trufflehog via official install script? " "yes")" == "true" ]]; then
    TRUFFLEHOG_INSTALL="yes"
  else
    TRUFFLEHOG_INSTALL="no"
  fi
  log_info "Trufflehog installation preference: ${TRUFFLEHOG_INSTALL}"
}

prompt_for_tools_install() {
  if [[ "${INSTALL_TOOLS}" == "true" || "${INSTALL_TOOLS}" == "false" ]]; then
    log_info "Tools installation enabled: ${INSTALL_TOOLS}"
    return
  fi
  INSTALL_TOOLS="$(prompt_yes_no "Install the tools module now? " "no")"
  log_info "Tools installation enabled: ${INSTALL_TOOLS}"
}

prompt_for_wordlists_install() {
  if [[ "${INSTALL_WORDLISTS}" == "true" || "${INSTALL_WORDLISTS}" == "false" ]]; then
    log_info "Wordlist installation enabled: ${INSTALL_WORDLISTS}"
    return
  fi
  INSTALL_WORDLISTS="$(prompt_yes_no "Install/sync wordlists now? " "no")"
  log_info "Wordlist installation enabled: ${INSTALL_WORDLISTS}"
}

collect_prompt_answers() {
  prompt_for_user
  prompt_for_editor_choice
  prompt_for_hardening
  prompt_for_node_manager
  prompt_for_container_engine
  prompt_for_network_access_mode
  prompt_for_ssh_key_source
  prompt_for_trufflehog_install
  prompt_for_tools_install
  prompt_for_wordlists_install
  record_prompt_answers
}

run_task_prompts() {
  load_previous_answers
  collect_prompt_answers
  log_info "Prompt data captured for user ${NEW_USER}. Run 'abb-setup.sh accounts' to provision the account if needed."
}
