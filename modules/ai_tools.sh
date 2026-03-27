# shellcheck shell=bash

AI_NPM_PACKAGES=(
  @openai/codex
)

ensure_ai_runtime() {
  pacman_install_packages nodejs npm
}

install_npm_global_for_user() {
  local package="$1"
  local tool_name="$2"
  local cmd=""

  cmd=$(cat <<EOF
mkdir -p "\$HOME/.local/bin" "\$HOME/.local/lib" "\$HOME/.local/share"
NPM_CONFIG_PREFIX="\$HOME/.local" npm install -g ${package@Q}
EOF
)

  if run_as_user "${cmd}"; then
    append_installed_tool "${tool_name}"
    return 0
  fi

  log_warn "Failed to install ${tool_name} via npm."
  return 1
}

install_openai_codex() {
  if run_as_user "command -v codex >/dev/null 2>&1"; then
    append_installed_tool "openai-codex"
    log_info "OpenAI Codex CLI already installed."
    return 0
  fi

  if install_npm_global_for_user "@openai/codex" "openai-codex"; then
    log_info "Installed OpenAI Codex CLI. Run 'codex --login' as ${NEW_USER} to authenticate."
    return 0
  fi

  return 1
}

run_task_ai_tools() {
  ensure_user_context
  ensure_ai_runtime
  install_openai_codex
}
