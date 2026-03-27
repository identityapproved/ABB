# shellcheck shell=bash

WORDLISTS_HOME=""
WORDLISTS_OWNER=""
WORDLISTS_READY=0
WORDLISTS_AUTO_CHOICE=""
WORDLISTS_ASSETNOTE_CHOICE=""

wordlists_detect_home() {
  if [[ -n "${WORDLISTS_HOME}" ]]; then
    return
  fi
  if [[ -n "${WORDLISTS_HOME_OVERRIDE:-}" ]]; then
    WORDLISTS_HOME="${WORDLISTS_HOME_OVERRIDE}"
    WORDLISTS_OWNER=""
    return
  fi
  local candidate="" home=""
  if [[ -n "${NEW_USER:-}" ]]; then
    candidate="${NEW_USER}"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    candidate="${SUDO_USER}"
  fi
  if [[ -n "${candidate}" ]]; then
    home="$(getent passwd "${candidate}" | cut -d: -f6)"
    WORDLISTS_OWNER="${candidate}"
  fi
  if [[ -z "${home}" ]]; then
    home="${HOME:-/root}"
    WORDLISTS_OWNER=""
  fi
  WORDLISTS_HOME="${home}"
}

wordlists_chown() {
  local path="$1"
  if [[ -n "${WORDLISTS_OWNER}" ]]; then
    chown -R "${WORDLISTS_OWNER}:${WORDLISTS_OWNER}" "${path}" 2>/dev/null || true
  fi
}

wordlists_require_root() {
  if ((WORDLISTS_READY)); then
    return 0
  fi
  wordlists_detect_home
  local root_path="${WORDLISTS_HOME}/wordlists"
  install -d -m 0755 "${root_path}" "${root_path}/custom"
  wordlists_chown "${root_path}"
  WORDLISTS_ROOT="${root_path}"
  WORDLISTS_READY=1
  return 0
}

wordlists_download_asset() {
  local url="$1" dest="$2" label="$3" tool_name="$4" tmp
  wordlists_require_root || return
  if [[ -f "${dest}" ]]; then
    log_info "${label} already present at ${dest}."
    return
  fi
  tmp="$(mktemp)" || { log_warn "Unable to allocate temporary file for ${label}."; return; }
  if curl -fsSL "${url}" -o "${tmp}"; then
    install -D -m 0644 "${tmp}" "${dest}"
    wordlists_chown "${dest}"
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
    "${WORDLISTS_ROOT}/permutations.txt" \
    "permutations wordlist" \
    "wordlist-permutations"
}

wordlists_fetch_resolvers() {
  wordlists_download_asset \
    "https://raw.githubusercontent.com/trickest/resolvers/master/resolvers.txt" \
    "${WORDLISTS_ROOT}/resolvers.txt" \
    "Trickest resolvers list" \
    "wordlist-resolvers"
}

wordlists_fetch_rockyou() {
  wordlists_download_asset \
    "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt" \
    "${WORDLISTS_ROOT}/rockyou.txt" \
    "rockyou wordlist" \
    "wordlist-rockyou"
}

wordlists_fetch_cent_repo() {
  wordlists_require_root || return
  local repo="https://github.com/xm1k3/cent.git"
  local dest="${WORDLISTS_ROOT}/cent"
  if ensure_git_repo "${repo}" "${dest}"; then
    wordlists_chown "${dest}"
    append_installed_tool "wordlist-cent"
  else
    log_warn "Unable to clone cent wordlist repository."
  fi
}

wordlists_fetch_seclists_repo() {
  wordlists_require_root || return
  local repo="https://github.com/danielmiessler/SecLists.git"
  local dest="${WORDLISTS_ROOT}/SecLists"
  if ensure_git_repo "${repo}" "${dest}"; then
    if [[ -f "${dest}/Discovery/DNS/dns-Jhaddix.txt" ]]; then
      head -n -14 "${dest}/Discovery/DNS/dns-Jhaddix.txt" > "${dest}/Discovery/DNS/clean-jhaddix-dns.txt"
    fi
    wordlists_chown "${dest}"
    append_installed_tool "SecLists"
  else
    log_warn "Unable to clone SecLists repository."
  fi
}

wordlists_fetch_auto_wordlists() {
  if [[ "${WORDLISTS_AUTO_CHOICE}" != "yes" ]]; then
    log_info "Skipping Auto_Wordlists clone (preference: ${WORDLISTS_AUTO_CHOICE:-no})."
    return
  fi
  wordlists_require_root || return
  local repo="https://github.com/carlospolop/Auto_Wordlists.git"
  local dest="${WORDLISTS_ROOT}/Auto_Wordlists"
  if ensure_git_repo "${repo}" "${dest}"; then
    wordlists_chown "${dest}"
    append_installed_tool "wordlist-auto-wordlists"
  else
    log_warn "Unable to clone Auto_Wordlists repository."
  fi
}

wordlists_fetch_assetnote() {
  if [[ "${WORDLISTS_ASSETNOTE_CHOICE}" != "yes" ]]; then
    log_info "Skipping Assetnote wordlist mirror (preference: ${WORDLISTS_ASSETNOTE_CHOICE:-no})."
    return
  fi
  wordlists_require_root || return
  if ! command_exists wget; then
    log_warn "wget not available; skipping Assetnote wordlist sync."
    return
  fi
  local base_url="https://wordlists-cdn.assetnote.io/data/"
  local dest="${WORDLISTS_ROOT}/assetnote"
  mkdir -p "${dest}"
  if wget -r --no-parent -R "index.html*" -e robots=off "${base_url}" -nH -P "${dest}" >/dev/null 2>&1; then
    wordlists_chown "${dest}"
    append_installed_tool "wordlist-assetnote"
  else
    log_warn "Failed to mirror Assetnote wordlists. Check network access and rerun later."
  fi
}

wordlists_prompt_preferences() {
  local answer=""
  if [[ -z "${WORDLISTS_AUTO_CHOICE}" ]]; then
    while true; do
      read -rp "Clone the Auto_Wordlists repository (large download)? (yes/no) [no]: " answer </dev/tty || { WORDLISTS_AUTO_CHOICE="no"; break; }
      answer="${answer,,}"
      if [[ -z "${answer}" || "${answer}" == "no" || "${answer}" == "n" ]]; then
        WORDLISTS_AUTO_CHOICE="no"
        break
      fi
      if [[ "${answer}" == "yes" || "${answer}" == "y" ]]; then
        WORDLISTS_AUTO_CHOICE="yes"
        break
      fi
      echo "Please answer yes or no." >/dev/tty
    done
  fi

  if [[ -z "${WORDLISTS_ASSETNOTE_CHOICE}" ]]; then
    while true; do
      read -rp "Mirror the Assetnote wordlists (very large download)? (yes/no) [no]: " answer </dev/tty || { WORDLISTS_ASSETNOTE_CHOICE="no"; break; }
      answer="${answer,,}"
      if [[ -z "${answer}" || "${answer}" == "no" || "${answer}" == "n" ]]; then
        WORDLISTS_ASSETNOTE_CHOICE="no"
        break
      fi
      if [[ "${answer}" == "yes" || "${answer}" == "y" ]]; then
        WORDLISTS_ASSETNOTE_CHOICE="yes"
        break
      fi
      echo "Please answer yes or no." >/dev/tty
    done
  fi
}

wordlists_refresh_static_assets() {
  wordlists_require_root || return
  wordlists_fetch_seclists_repo
  wordlists_fetch_cent_repo
  wordlists_fetch_permutations
  wordlists_fetch_resolvers
  wordlists_fetch_rockyou
  wordlists_fetch_auto_wordlists
  wordlists_fetch_assetnote
}

run_task_wordlists() {
  wordlists_prompt_preferences
  wordlists_refresh_static_assets
}
