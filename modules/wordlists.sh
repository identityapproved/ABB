# shellcheck shell=bash

AUTO_WORDLISTS_CLONE="${AUTO_WORDLISTS_CLONE:-}"
ENABLE_ASSETNOTE_WORDLISTS="${ENABLE_ASSETNOTE_WORDLISTS:-}"
WORDLIST_ROOT="/opt/wordlists"
WORDLISTS_READY=0
WORDLIST_PREF_FILE="/var/lib/vps-setup/wordlists.env"

wordlists_set_owner() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    chmod -R 0755 "${path}" 2>/dev/null || true
  else
    chmod 0644 "${path}" 2>/dev/null || true
  fi
}

wordlists_require_root() {
  if ((WORDLISTS_READY)); then
    return 0
  fi
  install -d -m 0755 "${WORDLIST_ROOT}" "${WORDLIST_ROOT}/custom"
  wordlists_set_owner "${WORDLIST_ROOT}"
  wordlists_set_owner "${WORDLIST_ROOT}/custom"

  local link_home=""
  if [[ -n "${WORDLISTS_HOME_OVERRIDE:-}" ]]; then
    link_home="${WORDLISTS_HOME_OVERRIDE}"
  elif [[ -n "${NEW_USER:-}" ]]; then
    link_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    link_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  else
    link_home="${HOME:-/root}"
  fi

  if [[ -n "${link_home}" ]]; then
    install -d -m 0755 "${link_home}"
    ln -snf "${WORDLIST_ROOT}" "${link_home}/wordlists" || log_warn "Unable to link ${link_home}/wordlists."
  fi

  WORDLISTS_READY=1
  return 0
}

wordlists_download_asset() {
  local url="$1" dest="$2" label="$3" tool_name="$4" tmp
  if ! wordlists_require_root; then
    return
  fi
  if [[ -f "${dest}" ]]; then
    log_info "${label} already present at ${dest}."
    return
  fi
  tmp="$(mktemp)" || { log_warn "Unable to allocate temporary file for ${label}."; return; }
  if curl -fsSL "${url}" -o "${tmp}"; then
    install -D -m 0644 "${tmp}" "${dest}"
    wordlists_set_owner "${dest}"
    append_installed_tool "${tool_name}"
    log_info "Fetched ${label}."
  else
    log_warn "Failed to download ${label}."
  fi
  rm -f "${tmp}"
}

wordlists_fetch_permutations() {
  wordlists_download_asset \
    "https://gist.github.com/six2dez/ffc2b14d283e8f8eff6ac83e20a3c4b4/raw" \
    "${WORDLIST_ROOT}/permutations.txt" \
    "permutations wordlist" \
    "wordlist-permutations"
}

wordlists_fetch_resolvers() {
  wordlists_download_asset \
    "https://raw.githubusercontent.com/trickest/resolvers/master/resolvers.txt" \
    "${WORDLIST_ROOT}/resolvers.txt" \
    "Trickest resolvers list" \
    "wordlist-resolvers"
}

wordlists_fetch_rockyou() {
  wordlists_download_asset \
    "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt" \
    "${WORDLIST_ROOT}/rockyou.txt" \
    "rockyou wordlist" \
    "wordlist-rockyou"
}

wordlists_fetch_cent_repo() {
  if ! wordlists_require_root; then
    return
  fi
  local repo="https://github.com/xm1k3/cent.git"
  local dest="${WORDLIST_ROOT}/cent"
  if ensure_git_repo "${repo}" "${dest}"; then
    wordlists_set_owner "${dest}"
    append_installed_tool "wordlist-cent"
  else
    log_warn "Unable to clone cent wordlist repository."
  fi
}

wordlists_fetch_auto_wordlists() {
  if [[ "${AUTO_WORDLISTS_CLONE}" != "yes" ]]; then
    log_info "Skipping Auto_Wordlists clone (preference: ${AUTO_WORDLISTS_CLONE:-no})."
    return
  fi
  if ! wordlists_require_root; then
    return
  fi
  local repo="https://github.com/carlospolop/Auto_Wordlists.git"
  local dest="${WORDLIST_ROOT}/Auto_Wordlists"
  if ensure_git_repo "${repo}" "${dest}"; then
    wordlists_set_owner "${dest}"
    append_installed_tool "wordlist-auto-wordlists"
  else
    log_warn "Unable to clone Auto_Wordlists repository."
  fi
}

wordlists_fetch_assetnote() {
  if [[ "${ENABLE_ASSETNOTE_WORDLISTS}" != "yes" ]]; then
    log_info "Skipping Assetnote wordlist mirror (preference: ${ENABLE_ASSETNOTE_WORDLISTS:-no})."
    return
  fi
  if ! wordlists_require_root; then
    return
  fi
  if ! command_exists wget; then
    log_warn "wget not available; skipping Assetnote wordlist sync."
    return
  fi
  local base_url="https://wordlists-cdn.assetnote.io/data/"
  local dest="${WORDLIST_ROOT}/assetnote"
  mkdir -p "${dest}"
  if wget -r --no-parent -R "index.html*" -e robots=off "${base_url}" -nH -P "${dest}" >/dev/null 2>&1; then
    wordlists_set_owner "${dest}"
    append_installed_tool "wordlist-assetnote"
  else
    log_warn "Failed to mirror Assetnote wordlists. Check network access and rerun later."
  fi
}

wordlists_refresh_static_assets() {
  wordlists_require_root || return
  wordlists_fetch_cent_repo
  wordlists_fetch_permutations
  wordlists_fetch_resolvers
  wordlists_fetch_rockyou
  wordlists_fetch_auto_wordlists
  wordlists_fetch_assetnote
}

wordlists_load_preferences() {
  load_previous_answers
  if [[ -f "${WORDLIST_PREF_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORDLIST_PREF_FILE}"
  fi
}

wordlists_save_preferences() {
  install -d -m 0755 "$(dirname "${WORDLIST_PREF_FILE}")"
  cat > "${WORDLIST_PREF_FILE}" <<EOF
AUTO_WORDLISTS_CLONE=${AUTO_WORDLISTS_CLONE}
ENABLE_ASSETNOTE_WORDLISTS=${ENABLE_ASSETNOTE_WORDLISTS}
EOF
}

wordlists_prompt_preferences() {
  local answer="" updated="false"
  wordlists_load_preferences

  if [[ -z "${AUTO_WORDLISTS_CLONE}" ]]; then
    while true; do
      read -rp "Clone the Auto_Wordlists repository (large download)? (yes/no) [no]: " answer </dev/tty || { AUTO_WORDLISTS_CLONE="no"; break; }
      answer="${answer,,}"
      if [[ -z "${answer}" || "${answer}" == "no" || "${answer}" == "n" ]]; then
        AUTO_WORDLISTS_CLONE="no"
        break
      fi
      if [[ "${answer}" == "yes" || "${answer}" == "y" ]]; then
        AUTO_WORDLISTS_CLONE="yes"
        break
      fi
      echo "Please answer yes or no." >/dev/tty
    done
    updated="true"
  fi

  if [[ -z "${ENABLE_ASSETNOTE_WORDLISTS}" ]]; then
    while true; do
      read -rp "Mirror the Assetnote wordlists (very large download)? (yes/no) [no]: " answer </dev/tty || { ENABLE_ASSETNOTE_WORDLISTS="no"; break; }
      answer="${answer,,}"
      if [[ -z "${answer}" || "${answer}" == "no" || "${answer}" == "n" ]]; then
        ENABLE_ASSETNOTE_WORDLISTS="no"
        break
      fi
      if [[ "${answer}" == "yes" || "${answer}" == "y" ]]; then
        ENABLE_ASSETNOTE_WORDLISTS="yes"
        break
      fi
      echo "Please answer yes or no." >/dev/tty
    done
    updated="true"
  fi

  if [[ "${updated}" == "true" ]]; then
    wordlists_save_preferences
  fi
}

run_task_wordlists() {
  wordlists_prompt_preferences
  wordlists_refresh_static_assets
}
