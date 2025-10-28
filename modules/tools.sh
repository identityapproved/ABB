# shellcheck shell=bash

declare -A PIPX_APPS=(
  [waymore]='git+https://github.com/xnl-h4ck3r/waymore.git'
  [xnLinkFinder]='git+https://github.com/xnl-h4ck3r/xnLinkFinder.git'
  [urless]='git+https://github.com/xnl-h4ck3r/urless.git'
  [xnldorker]='git+https://github.com/xnl-h4ck3r/xnldorker.git'
  [reconFTW]='git+https://github.com/six2dez/reconftw.git'
  [Sublist3r]='sublist3r'
  [dirsearch]='dirsearch'
  [sqlmap]='sqlmap'
  [knockpy]='knockpy'
  [asnlookup]='asnlookup'
)

declare -A PIPX_EXTRA_ARGS=(
  [waymore]='--include-deps'
  [xnLinkFinder]='--include-deps'
  [urless]='--include-deps'
  [xnldorker]='--include-deps'
  [reconFTW]='--include-deps'
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
  github.com/c3l3si4n/quickcert/cmd/quickcert@latest
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
  github.com/ethicalhackingplayground/bxss/cmd/bxss@latest
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
  [JSHawk]='https://github.com/utkusen/JSHawk.git'
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
      github.com/c3l3si4n/quickcert/cmd/quickcert@latest)
        go_cmd=$(printf 'GOSUMDB=off GONOSUMDB=github.com/c3l3si4n/quickcert GOBIN=$HOME/.local/bin GOPATH=$HOME/go GO111MODULE=on go install %q' "${module}")
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

install_jsparser_wrapper() {
  local wrapper="/usr/local/bin/jsparser"
  cat > "${wrapper}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 /opt/vps-tools/JSParser/JSParser.py "$@"
EOF
  chmod 0755 "${wrapper}"
}

install_jshawk_wrapper() {
  local wrapper="/usr/local/bin/jshawk"
  cat > "${wrapper}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
repo="/opt/vps-tools/JSHawk"
for entry in "JSHawk.py" "jshawk.py" "jshawK.py"; do
  if [[ -f "${repo}/${entry}" ]]; then
    exec python3 "${repo}/${entry}" "$@"
  fi
done
echo "JSHawk entry point not found in ${repo}" >&2
exit 1
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
          install_jsparser_wrapper
          append_installed_tool "JSParser"
          ;;
        JSHawk)
          install_jshawk_wrapper
          append_installed_tool "JSHawk"
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

run_task_tools() {
  ensure_user_context
  ensure_package_manager_ready
  install_language_helpers
  install_projectdiscovery_tools
  install_go_tools
  install_git_python_tools
}
