# shellcheck shell=bash

readonly LOG_FILE_DEFAULT="/var/log/vps-setup.log"
readonly ANSWERS_FILE="/var/lib/vps-setup/answers.env"
readonly TOOL_BASE_DIR="/opt/vps-tools"
readonly SYSCTL_FILE="/etc/sysctl.d/99-arch-hardening.conf"
readonly RC_LOCAL="/etc/rc.local"
readonly TEMPLATES_DIR="${REPO_ROOT}/dots"
readonly ZSH_TEMPLATE_DIR="${TEMPLATES_DIR}/zsh"
readonly TMUX_TEMPLATE="${TEMPLATES_DIR}/tmux/tmux.conf"
readonly VIMRC_TEMPLATE="${TEMPLATES_DIR}/vim/.vimrc"
readonly ALIASES_TEMPLATE="${ZSH_TEMPLATE_DIR}/.aliases"
readonly ZSHRC_TEMPLATE="${ZSH_TEMPLATE_DIR}/.zshrc"

log_info() { printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"; }
log_warn() { printf '[%s] WARN: %s\n' "$(date --iso-8601=seconds)" "$*"; }
log_error() { printf '[%s] ERROR: %s\n' "$(date --iso-8601=seconds)" "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

systemd_available() {
  if ! command_exists systemctl; then
    return 1
  fi
  systemctl list-unit-files >/dev/null 2>&1
}

enable_unit() {
  local unit="$1" description="${2:-$1}"
  if ! systemd_available; then
    log_warn "systemd not detected; skipping enablement for ${description}."
    return 1
  fi
  if ! systemctl list-unit-files "${unit}" >/dev/null 2>&1; then
    log_warn "Unit ${unit} not found; unable to enable ${description}."
    return 1
  fi
  if systemctl is-enabled "${unit}" >/dev/null 2>&1 && systemctl is-active "${unit}" >/dev/null 2>&1; then
    log_info "${description} already enabled."
    return 0
  fi
  if systemctl enable --now "${unit}" >/dev/null 2>&1; then
    log_info "Enabled ${description}."
    return 0
  fi
  log_warn "Failed to enable ${description}; review system logs for details."
  return 1
}

append_installed_tool() {
  local tool="$1"
  [[ -z "${INSTALLED_TRACK_FILE}" || -z "${tool}" ]] && return 0
  if [[ -f "${INSTALLED_TRACK_FILE}" ]] && grep -Fxq "${tool}" "${INSTALLED_TRACK_FILE}"; then
    return 0
  fi
  echo "${tool}" >> "${INSTALLED_TRACK_FILE}"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log_error "${SCRIPT_NAME} must run as root."
    exit 1
  fi
}

ensure_log_targets() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  touch "${LOG_FILE}"
  chmod 0640 "${LOG_FILE}"
  exec > >(tee -a "${LOG_FILE}") 2> >(tee -a "${LOG_FILE}" >&2)
}

pacman_install_packages() {
  local packages=("$@")
  local to_install=()
  local pkg
  for pkg in "${packages[@]}"; do
    if [[ -n "${pkg}" ]] && ! pacman -Qi "${pkg}" >/dev/null 2>&1; then
      to_install+=("${pkg}")
    fi
  done
  if ((${#to_install[@]})); then
    log_info "Installing packages: ${to_install[*]}"
    if ! pacman --noconfirm -Sy --needed "${to_install[@]}"; then
      log_error "pacman install failed for: ${to_install[*]}"
      exit 1
    fi
  else
    log_info "Packages already present: ${packages[*]}"
  fi
}

ensure_git_repo() {
  local repo_url="$1"
  local dest="$2"
  if [[ -d "${dest}/.git" ]]; then
    log_info "Updating $(basename "${dest}")"
    if ! git -C "${dest}" pull --ff-only; then
      log_warn "Git pull failed for ${dest}; keeping existing copy."
    fi
  else
    log_info "Cloning ${repo_url} into ${dest}"
    rm -rf "${dest}"
    if ! git clone "${repo_url}" "${dest}"; then
      log_warn "Failed to clone ${repo_url}"
      return 1
    fi
  fi
  return 0
}

run_as_user() {
  local cmd="$1" user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if command_exists setpriv; then
    setpriv --reuid="${NEW_USER}" --regid="${NEW_USER}" --init-groups \
      /usr/bin/env -i HOME="${user_home}" SHELL=/bin/bash PATH="/usr/local/bin:/usr/bin:/bin:${user_home}/.local/bin:${user_home}/.pdtm/go/bin" \
      /bin/bash -lc "${cmd}"
  else
    runuser -l "${NEW_USER}" -- env PATH="/usr/local/bin:/usr/bin:/bin:${user_home}/.local/bin:${user_home}/.pdtm/go/bin" bash -lc "${cmd}"
  fi
}

load_previous_answers() {
  if [[ -f "${ANSWERS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ANSWERS_FILE}"
    log_info "Loaded previous responses from ${ANSWERS_FILE}"
  fi
}

record_prompt_answers() {
  mkdir -p "$(dirname "${ANSWERS_FILE}")"
  {
    printf 'NEW_USER=%q\n' "${NEW_USER}"
    printf 'EDITOR_CHOICE=%q\n' "${EDITOR_CHOICE}"
    printf 'NEEDS_PENTEST_HARDENING=%q\n' "${NEEDS_PENTEST_HARDENING}"
    printf 'PACKAGE_MANAGER=%q\n' "${PACKAGE_MANAGER}"
    printf 'NODE_MANAGER=%q\n' "${NODE_MANAGER}"
    printf 'CONTAINER_ENGINE=%q\n' "${CONTAINER_ENGINE}"
    printf 'VPN_BYPASS_MODE=%q\n' "${VPN_BYPASS_MODE}"
  } > "${ANSWERS_FILE}"
  chmod 0600 "${ANSWERS_FILE}"
  log_info "Saved prompt answers to ${ANSWERS_FILE}"
}

init_installed_tracker() {
  local user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_error "Unable to determine home directory for ${NEW_USER}"
    exit 1
  fi
  INSTALLED_TRACK_FILE="${user_home}/installed-tools.txt"
  touch "${INSTALLED_TRACK_FILE}"
  chown "${NEW_USER}:${NEW_USER}" "${INSTALLED_TRACK_FILE}"
  chmod 0644 "${INSTALLED_TRACK_FILE}"
  log_info "Tracking installed tools in ${INSTALLED_TRACK_FILE}"
}

ensure_user_context() {
  local user_home needs_flag_missing=0 node_manager_missing=0 container_engine_missing=0
  load_previous_answers
  if [[ "${NEEDS_PENTEST_HARDENING}" != "true" && "${NEEDS_PENTEST_HARDENING}" != "false" ]]; then
    needs_flag_missing=1
  fi
  if [[ -z "${NODE_MANAGER}" ]]; then
    node_manager_missing=1
  fi
  if [[ -z "${CONTAINER_ENGINE}" ]]; then
    container_engine_missing=1
  fi
  if [[ -z "${NEW_USER}" || -z "${EDITOR_CHOICE}" || ${needs_flag_missing} -eq 1 || ${node_manager_missing} -eq 1 || ${container_engine_missing} -eq 1 ]]; then
    collect_prompt_answers
  fi

  verify_managed_user_ready

  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_error "Unable to determine home directory for ${NEW_USER}"
    exit 1
  fi
  if ! id -nG "${NEW_USER}" | grep -qw wheel; then
    usermod -aG wheel "${NEW_USER}"
    log_info "Ensured ${NEW_USER} is in the wheel group."
  fi

  init_installed_tracker
}
