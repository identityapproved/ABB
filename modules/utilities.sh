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
  openresolv
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

  configure_wireguard_stack
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
  append_installed_tool "openresolv"
  append_installed_tool "rsync"
  append_installed_tool "yazi"
  append_installed_tool "lazygit"
}

run_task_utilities() {
  ensure_user_context
  install_system_utilities
}
ensure_wireguard_kernel() {
  local kernel_raw kernel_version compare_result
  kernel_raw="$(uname -r)"
  kernel_version="${kernel_raw%%-*}"
  if command_exists vercmp; then
    compare_result=$(vercmp "${kernel_version}" "5.11")
  else
    compare_result=$(printf '%s\n%s\n' "${kernel_version}" "5.11" | sort -V | head -n1)
    if [[ "${compare_result}" == "5.11" ]]; then
      compare_result=0
    elif [[ "${compare_result}" == "${kernel_version}" ]]; then
      compare_result=-1
    else
      compare_result=1
    fi
  fi

  if [[ "${compare_result}" == -1 ]]; then
    log_warn "Detected kernel ${kernel_raw}. Mullvad WireGuard recommends 5.11 or newer."
  else
    log_info "Kernel ${kernel_raw} meets Mullvad WireGuard requirements."
  fi
}

add_wireguard_ssh_rules() {
  local cfg_dir="/etc/wireguard"
  local cfg
  local -a configs=()

  if [[ ! -d "${cfg_dir}" ]]; then
    log_warn "WireGuard directory ${cfg_dir} not found; skip PostUp/PreDown updates."
    return
  fi

  shopt -s nullglob
  configs=("${cfg_dir}"/*.conf)
  shopt -u nullglob
  if ((${#configs[@]} == 0)); then
    log_warn "No WireGuard configuration files detected in ${cfg_dir}."
    return
  fi

  for cfg in "${configs[@]}"; do
    local need_postup=1 need_predown=1 inserted=0 tmp
    if grep -Eq '^PostUp[[:space:]]*=[[:space:]]*ip rule add sport 22 lookup main' "${cfg}"; then
      need_postup=0
    fi
    if grep -Eq '^PreDown[[:space:]]*=[[:space:]]*ip rule delete sport 22 lookup main' "${cfg}"; then
      need_predown=0
    fi
    if ((need_postup == 0 && need_predown == 0)); then
      continue
    fi
    tmp="$(mktemp)" || { log_warn "Unable to create temporary file while updating ${cfg}."; continue; }
    awk -v need_postup="${need_postup}" -v need_predown="${need_predown}" '
      {
        print
        if ($0 ~ /^\[Interface\]/ && inserted == 0) {
          if (need_postup)  print "PostUp = ip rule add sport 22 lookup main"
          if (need_predown) print "PreDown = ip rule delete sport 22 lookup main"
          inserted = 1
        }
      }
      END {
        if (inserted == 0 && (need_postup || need_predown)) {
          print "[Interface]"
          if (need_postup)  print "PostUp = ip rule add sport 22 lookup main"
          if (need_predown) print "PreDown = ip rule delete sport 22 lookup main"
        }
      }
    ' "${cfg}" > "${tmp}"
    if mv "${tmp}" "${cfg}"; then
      chmod 0600 "${cfg}" || true
      log_info "Updated SSH rules in ${cfg}."
    else
      log_warn "Failed to update ${cfg}."
      rm -f "${tmp}"
    fi
  done
}

install_mullvad_wireguard_cli() {
  local repo="https://github.com/danielzeev/Mullvad-CLI.git"
  local dest="${TOOL_BASE_DIR}/Mullvad-CLI"
  local path_export='export PATH="$HOME/bin:$PATH"'

  if ensure_git_repo "${repo}" "${dest}"; then
    chown -R root:wheel "${dest}" || true
    chmod -R 0755 "${dest}" || true
    if [[ -f "${dest}/mull" ]]; then
      chmod 0755 "${dest}/mull" || true
    else
      log_warn "mull script not found in ${dest}."
    fi
    run_as_user "$(printf '%s' "line=${path_export@Q}; mkdir -p ~/bin; for rc in ~/.bashrc ~/.zshrc; do touch \"\$rc\"; if ! grep -Fq \"\$line\" \"\$rc\" 2>/dev/null; then printf '\n%s\n' \"\$line\" >> \"\$rc\"; fi; done")"
    if [[ -f "${dest}/mull" ]]; then
      run_as_user "$(printf 'ln -sf %q ~/bin/mull' "${dest}/mull")"
      append_installed_tool "Mullvad-CLI"
    fi
  else
    log_warn "Failed to clone Mullvad-CLI repository."
  fi
}

configure_wireguard_stack() {
  pacman_install_packages openresolv wireguard-tools
  ensure_wireguard_kernel

  local script_path="/usr/local/bin/mullvad-wg.sh"
  if curl -fsSL "https://raw.githubusercontent.com/mullvad/mullvad-wg.sh/main/mullvad-wg.sh" -o "${script_path}"; then
    chmod 0755 "${script_path}"
    if "${script_path}"; then
      append_installed_tool "mullvad-wg"
      log_info "Executed mullvad-wg.sh to configure WireGuard profiles."
    else
      log_warn "mullvad-wg.sh exited with a non-zero status. Review output above."
    fi
  else
    log_warn "Failed to download mullvad-wg.sh."
  fi

  add_wireguard_ssh_rules
  install_mullvad_wireguard_cli
  log_info "WireGuard setup complete. Connect with 'sudo wg-quick up <config>' then verify via 'curl https://am.i.mullvad.net/json | jq'."
}
