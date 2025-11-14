# shellcheck shell=bash

declare -A PIPX_APPS=(
  [waymore]='git+https://github.com/xnl-h4ck3r/waymore.git'
  [xnLinkFinder]='git+https://github.com/xnl-h4ck3r/xnLinkFinder.git'
  [urless]='git+https://github.com/xnl-h4ck3r/urless.git'
  [xnldorker]='git+https://github.com/xnl-h4ck3r/xnldorker.git'
  [Sublist3r]='sublist3r'
  [dirsearch]='dirsearch'
  [sqlmap]='sqlmap'
  [knockpy]='git+https://github.com/guelfoweb/knock.git'
  [webscreenshot]='webscreenshot'
)

declare -A PIPX_EXTRA_ARGS=(
  [waymore]='--include-deps'
  [xnLinkFinder]='--include-deps'
  [urless]='--include-deps'
  [xnldorker]='--include-deps'
  [knockpy]='--include-deps'
  [webscreenshot]='--include-deps'
)

GO_TOOLS=(
  github.com/tomnomnom/anew@latest
  github.com/tomnomnom/assetfinder@latest
  github.com/tomnomnom/waybackurls@latest
  github.com/hakluke/hakrawler@latest
  github.com/d3mondev/puredns/v2@latest
  github.com/lc/gau/v2/cmd/gau@latest
  github.com/utkusen/socialhunter@latest
  github.com/PentestPad/subzy@latest
  github.com/003random/getJS/v2@latest
  github.com/gwen001/github-subdomains@latest
  github.com/cgboal/sonarsearch/cmd/crobat@latest
  github.com/Josue87/gotator@latest
  github.com/glebarez/cero@latest
  github.com/dwisiswant0/galer@latest
  github.com/c3l3si4n/quickcert@HEAD
  github.com/sensepost/gowitness@latest
  github.com/tomnomnom/httprobe@latest
  github.com/jaeles-project/gospider@latest
  github.com/mrco24/parameters@latest
  github.com/tomnomnom/gf@latest
  github.com/mrco24/otx-url@latest
  github.com/ffuf/ffuf@latest
  github.com/OJ/gobuster/v3@latest
  github.com/mrco24/mrco24-lfi@latest
  github.com/mrco24/open-redirect@latest
  github.com/hahwul/dalfox/v2@latest
  github.com/Emoe/kxss@latest
  github.com/KathanP19/Gxss@latest
  github.com/ethicalhackingplayground/bxss/v2/cmd/bxss@latest
  github.com/ferreiraklet/Jeeves@latest
  github.com/mrco24/time-sql@latest
  github.com/mrco24/mrco24-error-sql@latest
  github.com/mrco24/tok@latest
  github.com/tomnomnom/hacks/anti-burl@latest
  github.com/tomnomnom/unfurl@latest
  github.com/tomnomnom/fff@latest
  github.com/tomnomnom/gron@latest
  github.com/tomnomnom/qsreplace@latest
  github.com/dwisiswant0/cf-check@latest
  github.com/Cgboal/exclude-cdn@latest
  github.com/m4dm0e/dirdar@latest
  github.com/bp0lr/gauplus@latest
  github.com/hakluke/hakrevdns@latest
  github.com/six2dez/ipcdn@latest
  github.com/tomnomnom/meg@latest
  github.com/sa7mon/s3scanner@latest
  github.com/musana/fuzzuli@latest
)

RECON_PACKAGES=(
)

BLACKARCH_ONLY_PACKAGES=(
  amass
)

AUR_RECON_PACKAGES=(
)

declare -A GIT_TOOLS=(
  [teh_s3_bucketeers]='https://github.com/tomdev/teh_s3_bucketeers.git'
  [lazys3]='https://github.com/nahamsec/lazys3.git'
  [virtual-host-discovery]='https://github.com/jobertabma/virtual-host-discovery.git'
  [lazyrecon]='https://github.com/nahamsec/lazyrecon.git'
  [massdns]='https://github.com/blechschmidt/massdns.git'
  [masscan]='https://github.com/robertdavidgraham/masscan.git'
  [JSParser]='https://github.com/nahamsec/JSParser.git'
)

install_pdtm() {
  if run_as_user "command -v pdtm >/dev/null 2>&1"; then
    append_installed_tool "pdtm"
    return
  fi

  if ! run_as_user "mkdir -p ~/.local/bin"; then
    log_warn "Unable to create ~/.local/bin for ${NEW_USER}"
  fi

  local cmd='GOBIN=$HOME/.local/bin GOPATH=$HOME/go GO111MODULE=on go install github.com/projectdiscovery/pdtm/cmd/pdtm@latest'
  if run_as_user "${cmd}"; then
    append_installed_tool "pdtm"
  else
    log_warn "Failed to install pdtm via Go."
  fi
}

install_projectdiscovery_tools() {
  install_pdtm
  if run_as_user "command -v pdtm >/dev/null 2>&1"; then
    log_info "pdtm installed. Use 'pdtm install --force <tool>' after sourcing ~/.bashrc to pull ProjectDiscovery binaries."
  fi
}

install_language_helpers() {
  local app package args cmd
  for app in "${!PIPX_APPS[@]}"; do
    package="${PIPX_APPS[$app]}"
    args="${PIPX_EXTRA_ARGS[$app]:-}"
    cmd="GIT_TERMINAL_PROMPT=0 pipx install --force"
    if [[ -n "${args}" ]]; then
      cmd+=" ${args}"
    fi
    cmd=$(printf "%s %q" "${cmd}" "${package}")
    if run_as_user "${cmd}"; then
      append_installed_tool "${app}"
    else
      log_warn "pipx installation failed for ${app}"
    fi
  done
}

install_go_tools() {
  local module tool tool_name go_cmd
  run_as_user "mkdir -p ~/.local/bin"
  for module in "${GO_TOOLS[@]}"; do
    tool="${module%@*}"
    tool_name="${tool##*/}"
    case "${module}" in
      github.com/c3l3si4n/quickcert@HEAD)
        go_cmd=$(printf 'GOSUMDB=off GONOSUMDB=github.com/c3l3si4n/quickcert GOBIN=$HOME/.local/bin GOPATH=$HOME/go GO111MODULE=on go install %q' "${module}")
        ;;
      github.com/ethicalhackingplayground/bxss/v2/cmd/bxss@latest)
        go_cmd=$(printf 'GOBIN=$HOME/.local/bin GOPATH=$HOME/go GO111MODULE=on go install -v %q' "${module}")
        ;;
      *)
        go_cmd=$(printf 'GOBIN=$HOME/.local/bin GOPATH=$HOME/go GO111MODULE=on go install %q' "${module}")
        ;;
    esac
    if run_as_user "${go_cmd}"; then
      append_installed_tool "${tool_name}"
    else
      log_warn "Failed to install Go tool ${module}"
    fi
  done
}

ensure_jsparser_env() {
  if run_as_user "pipx list --short | grep -Eq '^jsparser '"; then
    return 0
  fi
  local install_cmd='pipx install --force --include-deps git+https://github.com/nahamsec/JSParser.git'
  if run_as_user "${install_cmd}"; then
    return 0
  fi
  log_warn "pipx installation failed for JSParser."
  return 1
}

install_jsparser_wrapper() {
  local wrapper="/usr/local/bin/jsparser"
  cat > "${wrapper}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec pipx run jsparser "$@"
EOF
  chmod 0755 "${wrapper}"
}

install_jshawk_release() {
  local repo="https://github.com/Mah3Sec/JSHawk.git"
  local repo_dir="${TOOL_BASE_DIR}/JSHawk"
  if [[ -x /usr/local/bin/jshawk ]]; then
    append_installed_tool "JSHawk"
    log_info "JSHawk wrapper already present; skipping update."
    return
  fi
  if ensure_git_repo "${repo}" "${repo_dir}"; then
    if [[ -f "${repo_dir}/JSHawk.sh" ]]; then
      chmod 0755 "${repo_dir}/JSHawk.sh" || log_warn "Failed to mark JSHawk.sh executable."
      install -m 0755 "${repo_dir}/JSHawk.sh" /usr/local/bin/jshawk
      append_installed_tool "JSHawk"
      log_info "Installed JSHawk shell wrapper from development repository."
    else
      log_warn "JSHawk.sh not found in cloned repository."
    fi
  else
    log_warn "Unable to clone JSHawk repository."
  fi
}

install_git_python_tools() {
  local tool repo dest
  install -d -m 0755 "${TOOL_BASE_DIR}"
  for tool in "${!GIT_TOOLS[@]}"; do
    repo="${GIT_TOOLS[$tool]}"
    dest="${TOOL_BASE_DIR}/${tool}"
    if [[ "${tool}" == "SecLists" ]]; then
      if wordlists_require_root; then
        dest="${WORDLIST_ROOT}/seclists"
      fi
    fi
    if ensure_git_repo "${repo}" "${dest}"; then
      chown -R root:wheel "${dest}" || true
      chmod -R 0755 "${dest}" || true
      case "${tool}" in
        massdns)
          if make -C "${dest}" >/dev/null 2>&1; then
            install -m 0755 "${dest}/bin/massdns" /usr/local/bin/massdns
            append_installed_tool "massdns"
          else
            log_warn "Failed to build massdns."
          fi
          ;;
        masscan)
          local jobs
          jobs=$(nproc 2>/dev/null || echo 4)
          if make -C "${dest}" -j "${jobs}" >/dev/null 2>&1; then
            if make -C "${dest}" install >/dev/null 2>&1; then
              append_installed_tool "masscan"
            else
              log_warn "masscan make install failed."
            fi
          else
            log_warn "Failed to compile masscan."
          fi
          ;;
        JSParser)
          if ensure_jsparser_env; then
            install_jsparser_wrapper
            append_installed_tool "JSParser"
          else
            log_warn "JSParser wrapper not installed due to pipx failure."
          fi
          ;;
        lazyrecon)
          chmod +x "${dest}/lazyrecon.sh" || true
          ln -sf "${dest}/lazyrecon.sh" /usr/local/bin/lazyrecon
          append_installed_tool "lazyrecon"
          ;;
        *)
          append_installed_tool "${tool}"
          ;;
      esac
    fi
  done
}

write_tool_overview() {
  local user_home overview_file tmp_file package_manager_display node_manager_display
  local pipx_keys=() pipx_sorted=() go_names=() go_sorted=() system_sorted=() recon_sorted=() aur_recon_sorted=()
  local -a blackarch_sorted=()
  local module tool_name

  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_warn "Unable to determine home directory for ${NEW_USER}; skipping tool overview."
    return
  fi

  overview_file="${user_home}/ABB-tool-overview.txt"
  tmp_file="$(mktemp)" || { log_warn "Failed to allocate temp file for tool overview."; return; }

  package_manager_display="${PACKAGE_MANAGER:-not configured}"
  node_manager_display="${NODE_MANAGER:-not selected}"

  for module in "${!PIPX_APPS[@]}"; do
    pipx_keys+=("${module}")
  done
  if ((${#pipx_keys[@]})); then
    IFS=$'\n' pipx_sorted=($(printf '%s\n' "${pipx_keys[@]}" | sort))
    unset IFS
  fi

  declare -A go_seen=()
  for module in "${GO_TOOLS[@]}"; do
    tool_name="${module%@*}"
    tool_name="${tool_name##*/}"
    if [[ -n "${tool_name}" && -z "${go_seen[${tool_name}]:-}" ]]; then
      go_seen["${tool_name}"]=1
      go_names+=("${tool_name}")
    fi
  done
  if ((${#go_names[@]})); then
    IFS=$'\n' go_sorted=($(printf '%s\n' "${go_names[@]}" | sort))
    unset IFS
  fi
  unset go_seen

  if ((${#SYSTEM_PACKAGES[@]})); then
    IFS=$'\n' system_sorted=($(printf '%s\n' "${SYSTEM_PACKAGES[@]}" | sort))
    unset IFS
  fi

  if ((${#RECON_PACKAGES[@]})); then
    IFS=$'\n' recon_sorted=($(printf '%s\n' "${RECON_PACKAGES[@]}" | sort -u))
    unset IFS
  fi

  if ((${#AUR_RECON_PACKAGES[@]})); then
    IFS=$'\n' aur_recon_sorted=($(printf '%s\n' "${AUR_RECON_PACKAGES[@]}" | sort -u))
    unset IFS
  fi

  if ((${#BLACKARCH_ONLY_PACKAGES[@]})); then
    IFS=$'\n' blackarch_sorted=($(printf '%s\n' "${BLACKARCH_ONLY_PACKAGES[@]}" | sort -u))
    unset IFS
  else
    blackarch_sorted=()
  fi

  {
    printf '%s\n' "Arch Bugbounty Bootstrap Tool Overview"
    printf '%s\n\n' "======================================="
    printf 'Managed user: %s\n' "${NEW_USER}"
    printf 'Package manager: %s\n' "${package_manager_display}"
    printf 'Node manager: %s\n' "${node_manager_display}"
    printf 'Container engine: %s\n\n' "${CONTAINER_ENGINE:-not selected}"

    printf '%s\n' "System Utilities (pacman)"
    printf '%s\n' "-------------------------"
    if ((${#system_sorted[@]})); then
      for module in "${system_sorted[@]}"; do
        printf ' - %s\n' "${module}"
      done
    else
      printf '%s\n' " - (none recorded)"
    fi
    printf '\n'

    printf '%s\n' "Recon Packages (pacman)"
    printf '%s\n' "-----------------------"
    if ((${#recon_sorted[@]})); then
      for module in "${recon_sorted[@]}"; do
        printf ' - %s\n' "${module}"
      done
    else
    printf '%s\n' " - (none recorded)"
    fi
    printf '\n'

    printf '%s\n' "Recon Packages (AUR)"
    printf '%s\n' "--------------------"
    if ((${#aur_recon_sorted[@]})); then
      for module in "${aur_recon_sorted[@]}"; do
        printf ' - %s\n' "${module}"
      done
    else
      printf '%s\n' " - (none recorded)"
    fi
    printf '\n'

    printf '%s\n' "BlackArch Packages (pacman)"
    printf '%s\n' "---------------------------"
    if ((${#blackarch_sorted[@]})); then
      if [[ "${ENABLE_BLACKARCH_REPO}" == "yes" ]]; then
        for module in "${blackarch_sorted[@]}"; do
          printf ' - %s\n' "${module}"
        done
      else
        for module in "${blackarch_sorted[@]}"; do
          printf ' - %s (requires BlackArch repo)\n' "${module}"
        done
      fi
    else
      printf '%s\n' " - (none recorded)"
    fi
    printf '\n'

    printf '%s\n' "Language Runtimes"
    printf '%s\n' "-----------------"
    printf '%s\n' " - Python  (pacman: python, python-pipx, python-setuptools)"
    printf '%s\n' " - Go      (pacman: go)"
    printf '%s\n' " - Ruby    (pacman: ruby, base-devel)"
    printf '%s\n\n' " - Rust    (pacman: rustup; toolchain via rustup default stable)"

    printf '%s\n' "pipx Applications"
    printf '%s\n' "-----------------"
    if ((${#pipx_sorted[@]})); then
      for module in "${pipx_sorted[@]}"; do
        printf ' - %s\n' "${module}"
      done
    else
      printf '%s\n' " - (none installed)"
    fi
    printf '\n'

    printf '%s\n' "Go-Based Utilities"
    printf '%s\n' "------------------"
    if ((${#go_sorted[@]})); then
      for module in "${go_sorted[@]}"; do
        printf ' - %s\n' "${module}"
      done
    else
      printf '%s\n' " - (none installed)"
    fi
    printf '\n'

    printf '%s\n' "Git / Binary Tools"
    printf '%s\n' "------------------"
    for module in "${!GIT_TOOLS[@]}"; do
      printf ' - %s\n' "${module}"
    done
    printf '\n'

    printf '%s\n' "Tracking Files"
    printf '%s\n' "--------------"
    printf ' - %s/installed-tools.txt (one tool per line)\n' "${user_home}"
    printf ' - %s (this summary)\n' "${overview_file}"
    printf '%s\n' " - /var/log/vps-setup.log (provisioning log)"
  } > "${tmp_file}"

  install -m 0644 "${tmp_file}" "${overview_file}"
  chown "${NEW_USER}:${NEW_USER}" "${overview_file}" || true
  rm -f "${tmp_file}"
  log_info "Wrote tool overview to ${overview_file}."
}

run_task_tools() {
  ensure_user_context
  ensure_package_manager_ready
  install_system_recon_packages
  install_blackarch_only_packages
  install_aur_recon_packages
  install_language_helpers
  install_feroxbuster
  install_trufflehog
  install_projectdiscovery_tools
  install_go_tools
  install_git_python_tools
  install_dnscEwl
  install_jshawk_release
  write_tool_overview
}
install_system_recon_packages() {
  local pkg
  if ((${#RECON_PACKAGES[@]})); then
    pacman_install_packages "${RECON_PACKAGES[@]}"
    for pkg in "${RECON_PACKAGES[@]}"; do
      append_installed_tool "${pkg}"
    done
  fi
}

install_blackarch_only_packages() {
  local pkg
  if ((${#BLACKARCH_ONLY_PACKAGES[@]} == 0)); then
    return
  fi
  if [[ "${ENABLE_BLACKARCH_REPO}" != "yes" ]]; then
    log_info "BlackArch repository disabled; skipping packages: ${BLACKARCH_ONLY_PACKAGES[*]}"
    return
  fi
  blackarch_ensure_ready
  pacman_install_packages "${BLACKARCH_ONLY_PACKAGES[@]}"
  for pkg in "${BLACKARCH_ONLY_PACKAGES[@]}"; do
    append_installed_tool "${pkg}"
  done
}

install_aur_recon_packages() {
  local pkg
  if ((${#AUR_RECON_PACKAGES[@]})); then
    for pkg in "${AUR_RECON_PACKAGES[@]}"; do
      if aur_helper_install "${pkg}"; then
        append_installed_tool "${pkg}"
      fi
    done
  fi
}

install_feroxbuster() {
  local method="${FEROX_INSTALL_METHOD:-cargo}"
  local user_home default_cfg cfg_dir

  case "${method}" in
    aur)
      if [[ -z "${PACKAGE_MANAGER}" ]]; then
        log_warn "Feroxbuster AUR installation requested but no helper configured."
      elif aur_helper_install "feroxbuster"; then
        log_info "Installed feroxbuster via ${PACKAGE_MANAGER}."
      elif ! pacman -Qi feroxbuster >/dev/null 2>&1; then
        log_warn "Failed to install feroxbuster via ${PACKAGE_MANAGER}."
      fi
      ;;
    cargo|*)
      if ! run_as_user "command -v cargo >/dev/null 2>&1"; then
        log_warn "Cargo not available for ${NEW_USER}; skipping feroxbuster cargo install."
      elif run_as_user "cargo install --locked --force feroxbuster"; then
        log_info "Installed feroxbuster via cargo."
      else
        log_warn "Failed to install feroxbuster via cargo."
      fi
      ;;
  esac

  if run_as_user "command -v feroxbuster >/dev/null 2>&1"; then
    append_installed_tool "feroxbuster"
  else
    log_warn "feroxbuster binary not detected after installation attempts."
  fi

  cfg_dir="${TOOL_BASE_DIR}/feroxbuster"
  default_cfg="${cfg_dir}/ferox-config.toml"
  install -d -m 0755 "${cfg_dir}"
  if [[ ! -f "${default_cfg}" ]]; then
    cat > "${default_cfg}" <<'EOF'
# ferox-config.toml
# Generated by ABB. Copy to ~/.config/feroxbuster/ferox-config.toml to customise feroxbuster.
# Refer to https://github.com/epi052/feroxbuster for full configuration options.
threads = 50
wordlist = "~/wordlists/seclists/Discovery/Web-Content/common.txt"
use-slash = true
EOF
  fi

  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -n "${user_home}" ]]; then
    run_as_user "$(printf 'mkdir -p %q && { [[ -f %q ]] || cp %q %q; }' "${user_home}/.config/feroxbuster" "${user_home}/.config/feroxbuster/ferox-config.toml" "${default_cfg}" "${user_home}/.config/feroxbuster/ferox-config.toml")" || \
      log_warn "Unable to seed feroxbuster config for ${NEW_USER}."
  fi
}

install_trufflehog() {
  if [[ "${TRUFFLEHOG_INSTALL}" != "yes" ]]; then
    log_info "Trufflehog installation skipped by operator preference."
    return
  fi
  if command_exists trufflehog; then
    append_installed_tool "trufflehog"
    return
  fi

  if [[ -n "${PACKAGE_MANAGER}" ]] && command_exists "${PACKAGE_MANAGER}"; then
    if aur_helper_install "trufflehog"; then
      append_installed_tool "trufflehog"
      log_info "Installed trufflehog via ${PACKAGE_MANAGER}."
      return
    fi
    log_warn "Failed to install trufflehog via ${PACKAGE_MANAGER}; falling back to alternate methods."
  fi

  if run_trufflehog_install_script; then
    append_installed_tool "trufflehog"
    log_info "Installed trufflehog via official install script."
    return
  fi

  if install_trufflehog_from_source; then
    append_installed_tool "trufflehog"
    log_info "Installed trufflehog from source."
    return
  fi

  notify_trufflehog_docker_fallback
}

run_trufflehog_install_script() {
  local installer tmp
  tmp="$(mktemp)" || {
    log_warn "Unable to allocate temporary file for trufflehog installer."
    return 1
  }
  if ! command_exists curl; then
    log_warn "curl not available; skipping trufflehog installer."
    rm -f "${tmp}"
    return 1
  fi
  installer="https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh"
  if curl -fsSL "${installer}" -o "${tmp}"; then
    if sh "${tmp}" -s -- -b /usr/local/bin >/dev/null 2>&1; then
      rm -f "${tmp}"
      return 0
    fi
    log_warn "Trufflehog install script failed."
  else
    log_warn "Failed to download trufflehog install script."
  fi
  rm -f "${tmp}"
  return 1
}

install_trufflehog_from_source() {
  local cmd
  cmd=$(cat <<'EOF'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone https://github.com/trufflesecurity/trufflehog.git "$tmp/trufflehog" >/dev/null 2>&1 || exit 1
cd "$tmp/trufflehog" || exit 1
go install ./cmd/trufflehog >/dev/null 2>&1
EOF
)
  if run_as_user "${cmd}"; then
    if run_as_user "command -v trufflehog >/dev/null 2>&1"; then
      return 0
    fi
  fi
  log_warn "Failed to build trufflehog from source."
  return 1
}

notify_trufflehog_docker_fallback() {
  if [[ "${CONTAINER_ENGINE}" == "docker" ]] && command_exists docker && [[ "${SKIP_DOCKER_TASKS}" != "true" ]]; then
    log_info "Trufflehog binary not installed; use 'trufflehog-docker' after running the docker-tools task."
  else
    log_warn "Trufflehog is unavailable. Review https://github.com/trufflesecurity/trufflehog for manual installation instructions."
  fi
}

install_dnscEwl() {
  local target="/usr/local/bin/DNSCewl"
  local tmp
  if [[ -x "${target}" ]]; then
    log_info "DNSCewl already present."
    append_installed_tool "DNSCewl"
    return
  fi
  tmp="$(mktemp)" || {
    log_warn "Unable to create temporary file for DNSCewl download."
    return
  }
  if curl -fsSL "https://github.com/codingo/DNSCewl/raw/master/DNScewl" -o "${tmp}"; then
    install -m 0755 "${tmp}" "${target}"
    append_installed_tool "DNSCewl"
    log_info "Installed DNSCewl helper to ${target}."
  else
    log_warn "Failed to download DNSCewl binary."
  fi
  rm -f "${tmp}"
}
