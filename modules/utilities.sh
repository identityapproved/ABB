# shellcheck shell=bash

SYSTEM_PACKAGES=(
  tree
  tealdeer
  ripgrep
  fd
  zsh
  fzf
  bat
  htop
  iftop
  tmux
  vim
  neovim
  firewalld
  fail2ban
  zoxide
  curl
  wget
  unzip
  tar
  nmap
  jq
  wireguard-tools
  rsync
  yazi
  lazygit
)

install_mullvad() {
  local pkg="mullvad-vpn-bin"
  if command_exists mullvad; then
    log_info "Mullvad CLI already present."
    append_installed_tool "${pkg}"
    return
  fi
  if aur_helper_install "${pkg}"; then
    append_installed_tool "${pkg}"
    if command_exists mullvad; then
      run_as_user "mullvad --version" >/dev/null 2>&1 || true
    fi
    enable_unit "mullvad-daemon.service" "Mullvad daemon" || true
  else
    log_warn "Failed to install Mullvad VPN via ${PACKAGE_MANAGER}."
  fi
}

install_fnm() {
  if run_as_user "command -v fnm >/dev/null 2>&1"; then
    append_installed_tool "fnm"
    return
  fi
  local install_cmd='curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir ~/.local/share/fnm --skip-shell'
  if run_as_user "${install_cmd}"; then
    run_as_user "mkdir -p ~/.local/bin && ln -sf ~/.local/share/fnm/fnm ~/.local/bin/fnm"
    append_installed_tool "fnm"
    log_info "Installed fnm for ${NEW_USER}"
  else
    log_warn "Failed to install fnm. Node version management will be unavailable."
  fi
}

install_nvm() {
  if run_as_user "[[ -s ~/.nvm/nvm.sh ]]"; then
    append_installed_tool "nvm"
    return
  fi
  local install_cmd='curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
  if run_as_user "${install_cmd}"; then
    append_installed_tool "nvm"
    log_info "Installed nvm for ${NEW_USER}"
  else
    log_warn "Failed to install nvm."
  fi
}

ensure_node_manager() {
  case "${NODE_MANAGER}" in
    fnm)
      install_fnm
      ;;
    nvm)
      install_nvm
      ;;
    *)
      log_warn "Unknown Node manager preference '${NODE_MANAGER}'; skipping installation."
      ;;
  esac
}

install_container_engine() {
  case "${CONTAINER_ENGINE}" in
    docker)
      pacman_install_packages docker lazydocker
      groupadd -f docker >/dev/null 2>&1 || true
      if getent group docker >/dev/null 2>&1; then
        if usermod -aG docker "${NEW_USER}" >/dev/null 2>&1; then
          log_info "Added ${NEW_USER} to docker group."
        else
          log_warn "Failed to add ${NEW_USER} to docker group."
        fi
      else
        log_warn "docker group not found; ensure it exists to grant non-root access."
      fi
      if ! enable_unit "docker.service" "Docker service"; then
        if ! enable_unit "docker.socket" "Docker socket"; then
          log_warn "Docker will need to be started manually when required."
        fi
      fi
      append_installed_tool "docker"
      append_installed_tool "lazydocker"
      ;;
    podman)
      pacman_install_packages podman
      enable_unit "podman.socket" "Podman socket" || true
      append_installed_tool "podman"
      ;;
    none)
      log_info "Container engine installation skipped."
      ;;
    *)
      log_warn "Unknown container engine preference '${CONTAINER_ENGINE}'; skipping container setup."
      ;;
  esac
}

install_system_utilities() {
  ensure_package_manager_ready
  pacman_install_packages "${SYSTEM_PACKAGES[@]}"
  enable_unit "firewalld.service" "firewalld" || true
  enable_unit "fail2ban.service" "fail2ban" || true

  install_mullvad
  ensure_node_manager
  install_container_engine

  append_installed_tool "firewalld"
  append_installed_tool "fail2ban"
  append_installed_tool "zsh"
  append_installed_tool "tmux"
  append_installed_tool "neovim"
  append_installed_tool "vim"
  append_installed_tool "fzf"
  append_installed_tool "ripgrep"
  append_installed_tool "fd"
  append_installed_tool "bat"
  append_installed_tool "nmap"
  append_installed_tool "zoxide"
  append_installed_tool "tree"
  append_installed_tool "tealdeer"
  append_installed_tool "htop"
  append_installed_tool "iftop"
  append_installed_tool "wireguard-tools"
  append_installed_tool "rsync"
  append_installed_tool "yazi"
  append_installed_tool "lazygit"
}

run_task_utilities() {
  ensure_user_context
  install_system_utilities
}
