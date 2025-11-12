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

prompt_for_node_manager() {
  local choice=""
  if [[ -n "${NODE_MANAGER}" ]]; then
    log_info "Node manager selection: ${NODE_MANAGER}"
    return
  fi
  while true; do
    read -rp "Select Node version manager (nvm/fnm): " choice </dev/tty || { log_error "Unable to read Node manager choice."; exit 1; }
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
    read -rp "Install which container engine (docker/podman/none): " choice </dev/tty || { log_error "Unable to read container engine choice."; exit 1; }
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

prompt_for_vpn_provider() {
  local choice=""
  if [[ -n "${VPN_PROVIDER}" ]]; then
    log_info "VPN provider selection: ${VPN_PROVIDER}"
    return
  fi
  while true; do
    read -rp "Select VPN provider for this VPS (mullvad/protonvpn) [protonvpn]: " choice </dev/tty || { log_error "Unable to read VPN provider choice."; exit 1; }
    choice="${choice,,}"
    if [[ -z "${choice}" || "${choice}" == "protonvpn" ]]; then
      VPN_PROVIDER="protonvpn"
      break
    fi
    case "${choice}" in
      mullvad)
        VPN_PROVIDER="mullvad"
        break
        ;;
      *)
        echo "Please answer mullvad or protonvpn." >/dev/tty
        ;;
    esac
  done
  log_info "VPN provider selection: ${VPN_PROVIDER}"
}

prompt_for_ferox_method() {
  local choice=""
  if [[ -n "${FEROX_INSTALL_METHOD}" ]]; then
    log_info "Feroxbuster installation method: ${FEROX_INSTALL_METHOD}"
    return
  fi
  while true; do
    read -rp "Install feroxbuster via cargo or AUR helper? (cargo/aur) [cargo]: " choice </dev/tty || { log_error "Unable to read feroxbuster install choice."; exit 1; }
    choice="${choice,,}"
    if [[ -z "${choice}" || "${choice}" == "cargo" ]]; then
      FEROX_INSTALL_METHOD="cargo"
      break
    fi
    case "${choice}" in
      aur)
        FEROX_INSTALL_METHOD="aur"
        break
        ;;
      *)
        echo "Please answer cargo or aur." >/dev/tty
        ;;
    esac
  done
  log_info "Feroxbuster installation method: ${FEROX_INSTALL_METHOD}"
}

prompt_for_trufflehog_install() {
  local choice=""
  if [[ -n "${TRUFFLEHOG_INSTALL}" ]]; then
    log_info "Trufflehog installation preference: ${TRUFFLEHOG_INSTALL}"
    return
  fi
  while true; do
    read -rp "Install trufflehog via official install script? (yes/no) [yes]: " choice </dev/tty || { log_error "Unable to read trufflehog preference."; exit 1; }
    choice="${choice,,}"
    if [[ -z "${choice}" || "${choice}" == "yes" || "${choice}" == "y" ]]; then
      TRUFFLEHOG_INSTALL="yes"
      break
    fi
    case "${choice}" in
      no|n)
        TRUFFLEHOG_INSTALL="no"
        break
        ;;
      *)
        echo "Please answer yes or no." >/dev/tty
        ;;
    esac
  done
  log_info "Trufflehog installation preference: ${TRUFFLEHOG_INSTALL}"
}

collect_prompt_answers() {
  prompt_for_user
  prompt_for_editor_choice
  prompt_for_hardening
  prompt_for_node_manager
  prompt_for_container_engine
  prompt_for_vpn_provider
  prompt_for_ferox_method
  prompt_for_trufflehog_install
  record_prompt_answers
}

run_task_prompts() {
  load_previous_answers
  collect_prompt_answers
  log_info "Prompt data captured for user ${NEW_USER}. Run 'abb-setup.sh accounts' to provision the account if needed."
}
