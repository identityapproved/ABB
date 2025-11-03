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
  local cfg_dir="${TOOL_BASE_DIR}/reconftw"
  local cfg_file="${cfg_dir}/reconftw.cfg"
  local user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  install -d -m 0755 "${cfg_dir}"
  if docker pull "${image}" >/dev/null 2>&1; then
    local fetch_ok=0
    if command_exists curl && curl -fsSL "https://raw.githubusercontent.com/six2dez/reconftw/main/reconftw.cfg" -o "${cfg_file}.tmp"; then
      fetch_ok=1
    elif command_exists wget && wget -qO "${cfg_file}.tmp" "https://raw.githubusercontent.com/six2dez/reconftw/main/reconftw.cfg"; then
      fetch_ok=1
    fi
    if ((fetch_ok)); then
      mv "${cfg_file}.tmp" "${cfg_file}"
      chmod 0644 "${cfg_file}"
      if [[ -n "${user_home}" ]]; then
        run_as_user "$(printf 'mkdir -p %q && { [[ -f %q ]] || cp %q %q; }' "${user_home}/.config/reconftw" "${user_home}/.config/reconftw/reconftw.cfg" "${cfg_file}" "${user_home}/.config/reconftw/reconftw.cfg")" || \
          log_warn "Could not stage reconftw.cfg in ${NEW_USER}'s config directory."
      fi
    else
      rm -f "${cfg_file}.tmp" 2>/dev/null || true
      log_warn "Failed to download default reconftw.cfg"
    fi
    cat > /usr/local/bin/reconftw <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
image="six2dez/reconftw:main"
default_cfg="/opt/vps-tools/reconftw/reconftw.cfg"
user_cfg="${RECONFTW_CONFIG:-$HOME/.config/reconftw/reconftw.cfg}"
output_dir="${RECONFTW_OUTPUT:-$PWD/ReconFTW}"

if [[ -f "${default_cfg}" ]]; then
  mkdir -p "$(dirname "${user_cfg}")"
  if [[ ! -f "${user_cfg}" ]]; then
    cp "${default_cfg}" "${user_cfg}"
  fi
fi

mkdir -p "${output_dir}"
chmod 0777 "${output_dir}" 2>/dev/null || true

exec docker run --rm -it \
  -v "${user_cfg}:/reconftw/reconftw.cfg" \
  -v "${output_dir}:/reconftw/Recon/" \
  "${image}" "$@"
WRAP
    chmod 0755 /usr/local/bin/reconftw
    append_installed_tool "reconftw-docker"
    log_info "ReconFTW docker wrapper installed."
  else
    log_warn "Failed to pull ${image}."
  fi
}

install_cewl_container() {
  local image="ghcr.io/digininja/cewl:latest"
  if docker pull "${image}" >/dev/null 2>&1; then
    cat > /usr/local/bin/cewl <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
workdir="${CEWL_WORKDIR:-$PWD}"
mkdir -p "${workdir}"
image="ghcr.io/digininja/cewl:latest"
exec docker run --rm -it -v "${workdir}:/host" "${image}" "$@"
WRAP
    chmod 0755 /usr/local/bin/cewl
    append_installed_tool "cewl-docker"
    log_info "CeWL docker wrapper installed."
  else
    log_warn "Failed to pull ${image}."
  fi
}

install_amass_container() {
  local image="owaspamass/amass:latest"
  if docker pull "${image}" >/dev/null 2>&1; then
    docker tag "${image}" amass:latest >/dev/null 2>&1 || log_warn "Failed to tag ${image} as amass:latest."
    cat > /usr/local/bin/amass <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
config_dir="${AMASS_CONFIG:-$HOME/.config/amass}"
mkdir -p "${config_dir}"
exec docker run --rm -it -v "${config_dir}:/root/.config/amass" amass:latest "$@"
WRAP
    chmod 0755 /usr/local/bin/amass
    append_installed_tool "amass-docker"
    log_info "Amass docker wrapper installed."
  else
    log_warn "Failed to pull ${image}."
  fi
}

install_dnsvalidator_container() {
  local repo="https://github.com/vortexau/dnsvalidator.git"
  local dest="${TOOL_BASE_DIR}/dnsvalidator"
  if ensure_git_repo "${repo}" "${dest}"; then
    chown -R root:wheel "${dest}" || true
    chmod -R 0755 "${dest}" || true
    if docker build -t dnsvalidator:latest "${dest}" >/dev/null 2>&1; then
      cat > /usr/local/bin/dnsvalidator <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
output_dir="${DNSVALIDATOR_OUTPUT:-$PWD}"
mkdir -p "${output_dir}"
exec docker run --rm -it -v "${output_dir}:/dnsvalidator/output" dnsvalidator:latest "$@"
WRAP
      chmod 0755 /usr/local/bin/dnsvalidator
      append_installed_tool "dnsvalidator-docker"
      log_info "dnsvalidator Docker image ready (dnsvalidator:latest)."
    else
      log_warn "Failed to build dnsvalidator Docker image."
    fi
  fi
}

install_feroxbuster_container() {
  local image="epi052/feroxbuster:latest"
  local cfg_dir="${TOOL_BASE_DIR}/feroxbuster"
  local default_cfg="${cfg_dir}/ferox-config.toml"
  local user_home
  install -d -m 0755 "${cfg_dir}"
  if [[ ! -f "${default_cfg}" ]]; then
    cat > "${default_cfg}" <<'EOF'
# ferox-config.toml
# Generated by ABB for Docker-based feroxbuster runs. Customise and copy to ~/.config/feroxbuster/ferox-config.toml.
threads = 50
wordlist = "~/wordlists/seclists/Discovery/Web-Content/common.txt"
use-slash = true
EOF
  fi

  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -n "${user_home}" ]]; then
    run_as_user "$(printf 'mkdir -p %q && { [[ -f %q ]] || cp %q %q; }' "${user_home}/.config/feroxbuster" "${user_home}/.config/feroxbuster/ferox-config.toml" "${default_cfg}" "${user_home}/.config/feroxbuster/ferox-config.toml")" || \
      log_warn "Unable to stage feroxbuster config for ${NEW_USER}."
  fi

  if docker pull "${image}" >/dev/null 2>&1; then
    cat > /usr/local/bin/feroxbuster-docker <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
image="${FEROX_IMAGE:-epi052/feroxbuster:latest}"
default_cfg="/opt/vps-tools/feroxbuster/ferox-config.toml"
config_dir="${FEROX_CONFIG_DIR:-$HOME/.config/feroxbuster}"
config_file="${FEROX_CONFIG_PATH:-${config_dir}/ferox-config.toml}"
mkdir -p "${config_dir}"
if [[ -f "${default_cfg}" && ! -f "${config_file}" ]]; then
  cp "${default_cfg}" "${config_file}"
fi
if [[ -f "${config_file}" ]]; then
  exec docker run --init --rm -it -v "${config_file}:/etc/feroxbuster/ferox-config.toml" "${image}" "$@"
else
  exec docker run --init --rm -it -v "${config_dir}:/root/.config/feroxbuster" "${image}" "$@"
fi
WRAP
    chmod 0755 /usr/local/bin/feroxbuster-docker
    append_installed_tool "feroxbuster-docker"
    log_info "feroxbuster Docker wrapper installed."
  else
    log_warn "Failed to pull ${image}."
  fi
}

install_trufflehog_container() {
  local image="trufflesecurity/trufflehog:latest"
  if docker pull "${image}" >/dev/null 2>&1; then
    cat > /usr/local/bin/trufflehog-docker <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
image="${TRUFFLEHOG_IMAGE:-trufflesecurity/trufflehog:latest}"
workdir="${TRUFFLEHOG_WORKDIR:-$PWD}"
mkdir -p "${workdir}"
exec docker run --rm -it -v "${workdir}:/pwd" "${image}" "$@"
WRAP
    chmod 0755 /usr/local/bin/trufflehog-docker
    append_installed_tool "trufflehog-docker"
    log_info "trufflehog Docker wrapper installed."
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
  install_cewl_container
  install_amass_container
  install_dnsvalidator_container
  install_feroxbuster_container
  install_trufflehog_container
}
