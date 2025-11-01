# shellcheck shell=bash

LANGUAGE_PACKAGES=(
  python
  python-pipx
  python-setuptools
  go
  ruby
  base-devel
)

install_language_runtimes() {
  pacman_install_packages "${LANGUAGE_PACKAGES[@]}"
  if ! gem list -i bundler >/dev/null 2>&1; then
    gem install bundler
  fi
  append_installed_tool "python"
  append_installed_tool "pipx"
  append_installed_tool "go"
  append_installed_tool "ruby"

  if ! run_as_user "pipx ensurepath"; then
    log_warn "pipx ensurepath failed for ${NEW_USER}"
  fi
  run_as_user "pipx --version" || log_warn "pipx not available in ${NEW_USER}'s PATH yet."
  go version || log_warn "Go runtime not found in PATH."
}

run_task_languages() {
  ensure_user_context
  ensure_package_manager_ready
  install_language_runtimes
}
