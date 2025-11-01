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
)

declare -A PIPX_EXTRA_ARGS=(
  [waymore]='--include-deps'
  [xnLinkFinder]='--include-deps'
  [urless]='--include-deps'
  [xnldorker]='--include-deps'
  [knockpy]='--include-deps'
)

PDTM_TOOLS=(
  subfinder
  dnsx
  naabu
  httpx
  nuclei
  uncover
  cloudlist
  proxify
  tlsx
  notify
  chaos-client
  shuffledns
  mapcidr
  interactsh-server
  interactsh-client
  katana
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
)

declare -A GIT_TOOLS=(
  [teh_s3_bucketeers]='https://github.com/tomdev/teh_s3_bucketeers.git'
  [lazys3]='https://github.com/nahamsec/lazys3.git'
  [virtual-host-discovery]='https://github.com/jobertabma/virtual-host-discovery.git'
  [lazyrecon]='https://github.com/nahamsec/lazyrecon.git'
  [massdns]='https://github.com/blechschmidt/massdns.git'
  [SecLists]='https://github.com/danielmiessler/SecLists.git'
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
  if ! run_as_user "command -v pdtm >/dev/null 2>&1"; then
    log_warn "pdtm not found; ProjectDiscovery tool installs skipped."
    return
  fi
  for app in "${PDTM_TOOLS[@]}"; do
    local cmd
    cmd=$(printf 'PDTM_BIN_DIR="$HOME/.local/bin" pdtm install --force %q' "${app}")
    if run_as_user "${cmd}"; then
      append_installed_tool "${app}"
    else
      log_warn "pdtm install failed for ${app}"
    fi
  done
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

ensure_wordlist_workspace() {
  local user_home wordlist_root
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  [[ -z "${user_home}" ]] && return
  wordlist_root="${user_home}/wordlists"
  run_as_user "$(printf 'mkdir -p %q %q' "${wordlist_root}" "${wordlist_root}/custom")"
  if [[ -d "${TOOL_BASE_DIR}/SecLists" ]]; then
    run_as_user "$(printf 'ln -snf %q %q' "${TOOL_BASE_DIR}/SecLists" "${wordlist_root}/seclists")"
  fi
}

install_jshawk_release() {
  local url="https://github.com/Mah3Sec/JSHawk/releases/latest/download/JSHawk.sh"
  local dest="${TOOL_BASE_DIR}/JSHawk"
  if [[ -x /usr/local/bin/jshawk ]]; then
    append_installed_tool "JSHawk"
    log_info "JSHawk wrapper already present; skipping download."
    return
  fi
  install -d -m 0755 "${dest}"
  if curl -fsSL "${url}" -o "${dest}/JSHawk.sh"; then
    chmod 0755 "${dest}/JSHawk.sh"
    install -m 0755 "${dest}/JSHawk.sh" /usr/local/bin/jshawk
    append_installed_tool "JSHawk"
    log_info "Installed JSHawk shell wrapper from release archive."
  else
    log_warn "Failed to download JSHawk release script."
  fi
}

install_git_python_tools() {
  local tool repo dest
  install -d -m 0755 "${TOOL_BASE_DIR}"
  for tool in "${!GIT_TOOLS[@]}"; do
    repo="${GIT_TOOLS[$tool]}"
    dest="${TOOL_BASE_DIR}/${tool}"
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
        SecLists)
          if [[ -f "${dest}/Discovery/DNS/dns-Jhaddix.txt" ]]; then
            head -n -14 "${dest}/Discovery/DNS/dns-Jhaddix.txt" > "${dest}/Discovery/DNS/clean-jhaddix-dns.txt"
          fi
          append_installed_tool "SecLists"
          ensure_wordlist_workspace
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
  local pipx_keys=() pipx_sorted=() pd_sorted=() go_names=() go_sorted=() system_sorted=()
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

  if ((${#PDTM_TOOLS[@]})); then
    IFS=$'\n' pd_sorted=($(printf '%s\n' "${PDTM_TOOLS[@]}" | sort))
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

  {
    printf "Arch Bugbounty Bootstrap Tool Overview\n"
    printf "=======================================\n\n"
    printf "Managed user: %s\n" "${NEW_USER}"
    printf "Package manager: %s\n" "${package_manager_display}"
    printf "Node manager: %s\n" "${node_manager_display}"
    printf "Container engine: %s\n\n" "${CONTAINER_ENGINE:-not selected}"

    printf "System Utilities (pacman)\n"
    printf "-------------------------\n"
    if ((${#system_sorted[@]})); then
      for module in "${system_sorted[@]}"; do
        printf " - %s\n" "${module}"
      done
    else
      printf " - (none recorded)\n"
    fi
    printf "\n"

    printf "Language Runtimes\n"
    printf "-----------------\n"
    printf " - Python  (pacman: python, python-pipx)\n"
    printf " - Go      (pacman: go)\n"
    printf " - Ruby    (pacman: ruby, base-devel)\n\n"

    printf "pipx Applications\n"
    printf "-----------------\n"
    if ((${#pipx_sorted[@]})); then
      for module in "${pipx_sorted[@]}"; do
        printf " - %s\n" "${module}"
      done
    else
      printf " - (none installed)\n"
    fi
    printf "\n"

    printf "ProjectDiscovery (pdtm)\n"
    printf "-----------------------\n"
    if ((${#pd_sorted[@]})); then
      for module in "${pd_sorted[@]}"; do
        printf " - %s\n" "${module}"
      done
    else
      printf " - (none installed)\n"
    fi
    printf "\n"

    printf "Go-Based Utilities\n"
    printf "------------------\n"
    if ((${#go_sorted[@]})); then
      for module in "${go_sorted[@]}"; do
        printf " - %s\n" "${module}"
      done
    else
      printf " - (none installed)\n"
    fi
    printf "\n"

    printf "Git / Binary Tools\n"
    printf "------------------\n"
    for module in "${!GIT_TOOLS[@]}"; do
      printf " - %s\n" "${module}"
    done
    printf "\n"

    printf "Tracking Files\n"
    printf "--------------\n"
    printf " - %s/installed-tools.txt (one tool per line)\n" "${user_home}"
    printf " - %s (this summary)\n" "${overview_file}"
    printf " - /var/log/vps-setup.log (provisioning log)\n"
  } > "${tmp_file}"

  install -m 0644 "${tmp_file}" "${overview_file}"
  chown "${NEW_USER}:${NEW_USER}" "${overview_file}" || true
  rm -f "${tmp_file}"
  log_info "Wrote tool overview to ${overview_file}."
}

run_task_tools() {
  ensure_user_context
  ensure_package_manager_ready
  install_language_helpers
  install_projectdiscovery_tools
  install_go_tools
  install_git_python_tools
  install_jshawk_release
  write_tool_overview
}
