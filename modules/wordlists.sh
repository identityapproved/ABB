# shellcheck shell=bash

WORDLIST_ROOT=""

wordlists_require_root() {
  if [[ -n "${WORDLIST_ROOT}" ]]; then
    return 0
  fi
  local user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_warn "Unable to determine home directory for ${NEW_USER}; skipping wordlist bootstrap."
    return 1
  fi
  WORDLIST_ROOT="${user_home}/wordlists"
  if ! run_as_user "$(printf 'mkdir -p %q %q' "${WORDLIST_ROOT}" "${WORDLIST_ROOT}/custom")"; then
    log_warn "Failed to create wordlist directories under ${WORDLIST_ROOT}."
    WORDLIST_ROOT=""
    return 1
  fi
  return 0
}

wordlists_symlink_repo() {
  local source="$1" link_name="$2"
  if [[ ! -d "${source}" ]]; then
    log_warn "Wordlist source ${source} not found; skipping ${link_name} symlink."
    return 1
  fi
  if ! wordlists_require_root; then
    return 1
  fi
  if ! run_as_user "$(printf 'ln -snf %q %q' "${source}" "${WORDLIST_ROOT}/${link_name}")"; then
    log_warn "Failed to link ${link_name} wordlist directory."
    return 1
  fi
  return 0
}

wordlists_register_seclists() {
  local repo_path="$1"
  wordlists_symlink_repo "${repo_path}" "seclists" || true
}

wordlists_fetch_cent_repo() {
  if ! wordlists_require_root; then
    return
  fi
  local repo="https://github.com/xm1k3/cent.git"
  local dest="${TOOL_BASE_DIR}/cent"
  if ensure_git_repo "${repo}" "${dest}"; then
    chown -R root:wheel "${dest}" || true
    chmod -R 0755 "${dest}" || true
    if wordlists_symlink_repo "${dest}" "cent"; then
      append_installed_tool "wordlist-cent"
    fi
  else
    log_warn "Unable to clone cent wordlist repository."
  fi
}

wordlists_download_asset() {
  local url="$1" dest="$2" label="$3" tool_name="$4"
  if ! wordlists_require_root; then
    return
  fi
  if run_as_user "$(printf 'test -f %q' "${dest}")"; then
    log_info "${label} already present at ${dest}."
    return
  fi
  if run_as_user "$(printf 'curl -fsSL %q -o %q' "${url}" "${dest}")"; then
    append_installed_tool "${tool_name}"
    log_info "Fetched ${label}."
  else
    log_warn "Failed to download ${label}."
  fi
}

wordlists_fetch_permutations() {
  local target
  if ! wordlists_require_root; then
    return
  fi
  target="${WORDLIST_ROOT}/permutations.txt"
  wordlists_download_asset \
    "https://gist.github.com/six2dez/ffc2b14d283e8f8eff6ac83e20a3c4b4/raw" \
    "${target}" \
    "permutations wordlist" \
    "wordlist-permutations"
}

wordlists_fetch_resolvers() {
  local target
  if ! wordlists_require_root; then
    return
  fi
  target="${WORDLIST_ROOT}/resolvers.txt"
  wordlists_download_asset \
    "https://raw.githubusercontent.com/trickest/resolvers/master/resolvers.txt" \
    "${target}" \
    "Trickest resolvers list" \
    "wordlist-resolvers"
}

wordlists_refresh_static_assets() {
  wordlists_fetch_cent_repo
  wordlists_fetch_permutations
  wordlists_fetch_resolvers
  wordlists_fetch_rockyou
  wordlists_fetch_auto_wordlists
  wordlists_fetch_assetnote
}

wordlists_refresh_static_assets() {
  wordlists_fetch_cent_repo
  wordlists_fetch_permutations
  wordlists_fetch_resolvers
  wordlists_fetch_rockyou
  wordlists_fetch_auto_wordlists
  wordlists_fetch_assetnote
}

wordlists_fetch_rockyou() {
  local target
  if ! wordlists_require_root; then
    return
  fi
  target="${WORDLIST_ROOT}/rockyou.txt"
  wordlists_download_asset     "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt"     "${target}"     "rockyou wordlist"     "wordlist-rockyou"
}

wordlists_fetch_auto_wordlists() {
  if ! wordlists_require_root; then
    return
  fi
  local repo="https://github.com/carlospolop/Auto_Wordlists.git"
  local dest="${TOOL_BASE_DIR}/Auto_Wordlists"
  if ensure_git_repo "${repo}" "${dest}"; then
    chown -R root:wheel "${dest}" || true
    chmod -R 0755 "${dest}" || true
    if wordlists_symlink_repo "${dest}" "auto-wordlists"; then
      append_installed_tool "wordlist-auto-wordlists"
    fi
  else
    log_warn "Unable to clone Auto_Wordlists repository."
  fi
}

wordlists_fetch_assetnote() {
  if ! wordlists_require_root; then
    return
  fi
  if ! command_exists wget; then
    log_warn "wget not available; skipping Assetnote wordlist sync."
    return
  fi
  local base_url="https://wordlists-cdn.assetnote.io/data/"
  local dest="${TOOL_BASE_DIR}/assetnote-wordlists"
  mkdir -p "${dest}"
  if wget -r --no-parent -R "index.html*" -e robots=off "${base_url}" -nH -P "${dest}" >/dev/null 2>&1; then
    chown -R root:wheel "${dest}" || true
    chmod -R 0755 "${dest}" || true
    if wordlists_symlink_repo "${dest}/data" "assetnote"; then
      append_installed_tool "wordlist-assetnote"
    fi
  else
    log_warn "Failed to mirror Assetnote wordlists. Check network access and rerun later."
  fi
}
