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
  chromium
)

install_mullvad() {
  if pacman -Qi mullvad-vpn >/dev/null 2>&1; then
    log_info "mullvad-vpn already installed."
    append_installed_tool "mullvad-vpn"
    return
  fi
  if ! command_exists yay || [[ "${PACKAGE_MANAGER}" != "yay" ]]; then
    log_warn "Configured package manager does not support Mullvad installation."
    return
  fi
  if run_as_user "yay -S --noconfirm mullvad-vpn"; then
    append_installed_tool "mullvad-vpn"
    systemctl enable --now mullvad-daemon >/dev/null 2>&1 || log_warn "Unable to enable mullvad-daemon."
  else
    log_warn "Failed to install Mullvad VPN via yay."
  fi
}

ensure_fnm() {
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

install_system_utilities() {
  ensure_package_manager_ready
  pacman_install_packages "${SYSTEM_PACKAGES[@]}"
  systemctl enable --now firewalld >/dev/null 2>&1 || log_warn "Failed to enable firewalld."
  systemctl enable --now fail2ban >/dev/null 2>&1 || log_warn "Failed to enable fail2ban."

  install_mullvad
  ensure_fnm

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
  append_installed_tool "chromium"
  append_installed_tool "nmap"
  append_installed_tool "zoxide"
  append_installed_tool "tree"
  append_installed_tool "tealdeer"
  append_installed_tool "htop"
  append_installed_tool "iftop"
}

run_task_utilities() {
  ensure_user_context
  install_system_utilities
}
