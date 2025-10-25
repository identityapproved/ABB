# shellcheck shell=bash

LANGUAGE_PACKAGES=(
  python3
  python3-pip
  pipx
  golang
  ruby
  ruby-devel
  gcc
  make
  redhat-rpm-config
)

install_language_runtimes() {
  dnf_install_packages "${LANGUAGE_PACKAGES[@]}"
  if ! gem list -i bundler >/dev/null 2>&1; then
    gem install bundler
  fi
  append_installed_tool "python3"
  append_installed_tool "pipx"
  append_installed_tool "golang"
  append_installed_tool "ruby"

  if ! run_as_user "pipx ensurepath"; then
    log_warn "pipx ensurepath failed for ${NEW_USER}"
  fi
  run_as_user "pipx --version" || log_warn "pipx not available in ${NEW_USER}'s PATH yet."
  go version || log_warn "Go runtime not found in PATH."
}

run_task_languages() {
  ensure_user_context
  install_language_runtimes
}
