# shellcheck shell=bash

SYSTEM_PACKAGES=(
  firewalld
  fail2ban
  zsh
  tmux
  vim-enhanced
  neovim
  fzf
  ripgrep
  fd-find
  git
  bat
  chromium
  nmap
  jq
  curl
  wget
  unzip
  tar
  bind-utils
  net-tools
  policycoreutils
  policycoreutils-python-utils
  dnf-plugins-core
  zoxide
)

install_mullvad() {
  if rpm -q mullvad-vpn >/dev/null 2>&1; then
    log_info "mullvad-vpn already installed."
    append_installed_tool "mullvad-vpn"
    return
  fi
  if [[ -z "${MULLVAD_RPM_URL}" ]]; then
    log_warn "MULLVAD_RPM_URL not provided; skipping Mullvad installation."
    return
  fi
  local tmpdir
  tmpdir="$(mktemp -d)"
  if curl -fsSL "${MULLVAD_RPM_URL}" -o "${tmpdir}/mullvad.rpm"; then
    if dnf install -y "${tmpdir}/mullvad.rpm"; then
      append_installed_tool "mullvad-vpn"
      systemctl enable --now mullvad-daemon >/dev/null 2>&1 || log_warn "Unable to enable mullvad-daemon."
    else
      log_warn "Failed to install Mullvad from ${MULLVAD_RPM_URL}"
    fi
  else
    log_warn "Unable to download Mullvad package from ${MULLVAD_RPM_URL}"
  fi
  rm -rf "${tmpdir}"
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
  dnf_install_packages "${SYSTEM_PACKAGES[@]}"
  systemctl enable --now firewalld >/dev/null 2>&1 || log_warn "Failed to enable firewalld."
  systemctl enable --now fail2ban >/dev/null 2>&1 || log_warn "Failed to enable fail2ban."

  if command_exists fdfind && ! command_exists fd; then
    ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
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
  append_installed_tool "fd-find"
  append_installed_tool "git"
  append_installed_tool "bat"
  append_installed_tool "chromium"
  append_installed_tool "nmap"
  append_installed_tool "zoxide"
}

run_task_utilities() {
  ensure_user_context
  install_system_utilities
}
