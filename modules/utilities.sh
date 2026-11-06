# shellcheck shell=bash

SYSTEM_PACKAGES=(
  tree
  tealdeer
  ripgrep
  fd
  zsh
  bat
  htop
  iftop
  lsof
  tmux
  vim
  fzf
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
  rsync
  yazi
  lazygit
)

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

# Untrusted tools run in Docker; keep containers off the trusted zone (tailnet peers, Incus bridge).
ensure_docker_isolation() {
  local policy="abb-docker-isolate"
  command_exists firewall-cmd || return 0
  systemctl is-active --quiet firewalld.service || { log_warn "firewalld inactive; Docker isolation policy not applied."; return 0; }
  firewall-cmd --permanent --info-policy="${policy}" >/dev/null 2>&1 && { log_info "Docker isolation policy present."; return 0; }
  if ! firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -qx docker; then
    log_warn "firewalld has no docker zone; restart Docker with firewalld running, then rerun utilities."
    return 1
  fi
  firewall-cmd --permanent --new-policy="${policy}" >/dev/null &&
    firewall-cmd --permanent --policy="${policy}" --add-ingress-zone=docker >/dev/null &&
    firewall-cmd --permanent --policy="${policy}" --add-egress-zone=trusted >/dev/null &&
    firewall-cmd --permanent --policy="${policy}" --set-target=DROP >/dev/null ||
    { log_warn "Failed to create firewalld policy ${policy}."; return 1; }
  firewall-cmd --reload >/dev/null 2>&1 || log_warn "Failed to reload firewalld."
  log_info "Docker containers can no longer reach the trusted zone (tailscale0, incusbr0)."
}

install_container_engine() {
  case "${CONTAINER_ENGINE}" in
  docker)
    pacman_install_packages docker docker-compose lazydocker
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
    if ! command_exists docker || ! systemctl is-active --quiet docker.service; then
      local answer="" skip_docker=false
      while true; do
        read -rp "Docker is not ready. Reboot now to finalize setup? (yes/no): " answer </dev/tty || {
          answer="no"
          skip_docker=true
          break
        }
        case "${answer,,}" in
        yes | y)
          log_info "Rebooting now to finalize Docker setup."
          systemctl reboot
          exit 0
          ;;
        no | n)
          skip_docker=true
          break
          ;;
        *)
          echo "Please answer yes or no." >/dev/tty
          ;;
        esac
      done
      if [[ "${skip_docker}" == "true" || ("${answer,,}" != "yes" && "${answer,,}" != "y") ]]; then
        SKIP_DOCKER_TASKS="true"
        log_warn "Docker CLI or daemon unavailable. Reboot and rerun 'abb-setup.sh utilities' or 'abb-setup.sh all' when ready."
      fi
    fi
    [[ "${SKIP_DOCKER_TASKS}" == "true" ]] || ensure_docker_isolation || true
    append_installed_tool "docker"
    append_installed_tool "docker-compose"
    append_installed_tool "lazydocker"
    ;;
  podman)
    pacman_install_packages podman podman-compose
    enable_unit "podman.socket" "Podman socket" || true
    append_installed_tool "podman"
    append_installed_tool "podman-compose"
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

  ensure_node_manager
  install_container_engine
  install_incus

  append_installed_tool "firewalld"
  append_installed_tool "fail2ban"
  append_installed_tool "zsh"
  append_installed_tool "tmux"
  append_installed_tool "neovim"
  append_installed_tool "vim"
  append_installed_tool "ripgrep"
  append_installed_tool "fd"
  append_installed_tool "bat"
  append_installed_tool "nmap"
  append_installed_tool "zoxide"
  append_installed_tool "tree"
  append_installed_tool "tealdeer"
  append_installed_tool "htop"
  append_installed_tool "iftop"
  append_installed_tool "rsync"
  append_installed_tool "yazi"
  append_installed_tool "lazygit"
}

run_task_utilities() {
  ensure_user_context
  install_system_utilities
}
