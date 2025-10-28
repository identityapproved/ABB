# shellcheck shell=bash

declare -A ZSH_PLUGIN_REPOS=(
  [zsh-vi-mode]='https://github.com/jeffreytse/zsh-vi-mode.git'
  [cd-ls]='https://github.com/zshzoo/cd-ls.git'
  [zsh-git-fzf]='https://github.com/alexiszamanidis/zsh-git-fzf.git'
  [alias-tips]='https://github.com/djui/alias-tips.git'
  [fzf-alias]='https://github.com/thirteen37/fzf-alias.git'
  [zsh-history-substring-search]='https://github.com/zsh-users/zsh-history-substring-search.git'
  [zsh-syntax-highlighting]='https://github.com/zsh-users/zsh-syntax-highlighting.git'
  [zsh-autosuggestions]='https://github.com/zsh-users/zsh-autosuggestions.git'
)

install_custom_zsh_plugins() {
  local user_home="$1"
  local zsh_custom="${user_home}/.oh-my-zsh/custom"
  local plugin repo dest

  if [[ ! -d "${zsh_custom}" ]]; then
    log_warn "Oh My Zsh custom directory not found, skipping plugin installation."
    return
  fi

  run_as_user "$(printf 'mkdir -p %q' "${zsh_custom}/plugins")"

  for plugin in "${!ZSH_PLUGIN_REPOS[@]}"; do
    repo="${ZSH_PLUGIN_REPOS[$plugin]}"
    dest="${zsh_custom}/plugins/${plugin}"
    if [[ -d "${dest}/.git" ]]; then
      if ! run_as_user "$(printf 'git -C %q pull --ff-only' "${dest}")"; then
        log_warn "Failed to update Zsh plugin ${plugin}"
      fi
    else
      if ! run_as_user "$(printf 'git clone %q %q' "${repo}" "${dest}")"; then
        log_warn "Failed to clone Zsh plugin ${plugin} from ${repo}"
        continue
      fi
    fi
  done

  local template_plugin="${ZSH_TEMPLATE_DIR}/plugins/zsh-aur-install"
  local template_target="${zsh_custom}/plugins/zsh-aur-install"
  if [[ -d "${template_plugin}" && ! -d "${template_target}" ]]; then
    cp -r "${template_plugin}" "${template_target}"
    chown -R "${NEW_USER}:${NEW_USER}" "${template_target}"
  fi
}

configure_shells_and_editors() {
  local user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  [[ -z "${user_home}" ]] && return

  if [[ ! -d "${user_home}/.oh-my-zsh" ]]; then
    if ! run_as_user "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no KEEP_ZSHRC=yes sh"; then
      log_warn "Oh My Zsh installation failed."
    fi
  fi

  if [[ -f "${ZSHRC_TEMPLATE}" ]]; then
    install -m 0644 "${ZSHRC_TEMPLATE}" "${user_home}/.zshrc"
    chown "${NEW_USER}:${NEW_USER}" "${user_home}/.zshrc"
  else
    log_warn "Missing Zsh template at ${ZSHRC_TEMPLATE}"
  fi

  if command_exists zsh; then
    chsh -s /usr/bin/zsh "${NEW_USER}" || log_warn "Unable to set zsh as default shell for ${NEW_USER}"
  fi

  if [[ -f "${ALIASES_TEMPLATE}" ]]; then
    install -m 0644 "${ALIASES_TEMPLATE}" "${user_home}/.aliases"
    chown "${NEW_USER}:${NEW_USER}" "${user_home}/.aliases"
  fi

  if [[ -f "${TMUX_TEMPLATE}" ]]; then
    install -m 0644 "${TMUX_TEMPLATE}" "${user_home}/.tmux.conf"
    chown "${NEW_USER}:${NEW_USER}" "${user_home}/.tmux.conf"
  fi

  if [[ "${EDITOR_CHOICE}" == "vim" || "${EDITOR_CHOICE}" == "both" ]]; then
    if [[ -f "${VIMRC_TEMPLATE}" ]]; then
      install -m 0644 "${VIMRC_TEMPLATE}" "${user_home}/.vimrc"
      chown "${NEW_USER}:${NEW_USER}" "${user_home}/.vimrc"
    else
      log_warn "Missing Vim template at ${VIMRC_TEMPLATE}"
    fi
  fi

  if [[ "${EDITOR_CHOICE}" == "neovim" || "${EDITOR_CHOICE}" == "both" ]]; then
    if [[ ! -d "${user_home}/.config/nvim" ]]; then
      if run_as_user "git clone https://github.com/LazyVim/starter ~/.config/nvim"; then
        append_installed_tool "LazyVim"
      else
        log_warn "Failed to clone LazyVim starter."
      fi
    else
      run_as_user "git -C ~/.config/nvim pull --ff-only" || log_warn "Unable to update LazyVim starter."
    fi
    run_as_user "nvim --headless '+Lazy! sync' +qa" || log_warn "Neovim plugin sync did not complete cleanly."
  fi

  install_custom_zsh_plugins "${user_home}"
}

run_task_dotfiles() {
  ensure_user_context
  ensure_package_manager_ready
  configure_shells_and_editors
}
