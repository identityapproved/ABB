# shellcheck shell=bash

install_asnlookup_container() {
  local repo="https://github.com/yassineaboukir/Asnlookup.git"
  local dest="${TOOL_BASE_DIR}/Asnlookup"
  if ensure_git_repo "${repo}" "${dest}"; then
    chown -R root:wheel "${dest}" || true
    chmod -R 0755 "${dest}" || true
    if docker build -t asnlookup:latest "${dest}" >/dev/null 2>&1; then
      cat > /usr/local/bin/asnlookup <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
output_dir="${ASNLOOKUP_OUTPUT:-$PWD}"
exec docker run --rm -it -v "${output_dir}:/workspace" asnlookup:latest "$@"
WRAP
      chmod 0755 /usr/local/bin/asnlookup
      append_installed_tool "asnlookup-docker"
      log_info "Asnlookup Docker image ready (asnlookup:latest)."
    else
      log_warn "Failed to build Asnlookup Docker image."
    fi
  fi
}

install_reconftw_container() {
  local image="six2dez/reconftw:main"
  if docker pull "${image}" >/dev/null 2>&1; then
    cat > /usr/local/bin/reconftw <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
output_dir="${RECONFTW_OUTPUT:-$PWD/ReconFTW}"
mkdir -p "${output_dir}"
image="six2dez/reconftw:main"
exec docker run --rm -it -v "${output_dir}:/reconftw/Recon" "${image}" "$@"
WRAP
    chmod 0755 /usr/local/bin/reconftw
    append_installed_tool "reconftw-docker"
    log_info "ReconFTW docker wrapper installed."
  else
    log_warn "Failed to pull ${image}."
  fi
}

ensure_docker_available() {
  if [[ "${CONTAINER_ENGINE}" != "docker" ]]; then
    log_info "Container engine '${CONTAINER_ENGINE}' is not docker; skipping docker tool setup."
    return 1
  fi
  if ! command_exists docker; then
    log_warn "Docker CLI not found. Run 'abb-setup.sh utilities' with docker selected and rerun this task."
    return 1
  fi
  return 0
}

run_task_docker_tools() {
  ensure_user_context
  if ! ensure_docker_available; then
    return 0
  fi
  install_reconftw_container
  install_asnlookup_container
}
