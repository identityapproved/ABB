#!/usr/bin/env bash
set -euo pipefail
umask 022

# Rocky Linux 9.6 provisioning script generated from AGENTS.md playbook.

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE_DEFAULT="/var/log/vps-setup.log"
readonly ANSWERS_FILE="/var/lib/vps-setup/answers.env"
readonly TOOL_BASE_DIR="/opt/vps-tools"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SSH_CONFIG_BACKUP="${SSH_CONFIG}.bak"
readonly SYSCTL_FILE="/etc/sysctl.d/99-rocky-hardening.conf"
readonly RC_LOCAL="/etc/rc.local"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATES_DIR="${REPO_ROOT}/dots"
readonly ZSH_TEMPLATE_DIR="${TEMPLATES_DIR}/zsh"
readonly TMUX_TEMPLATE="${TEMPLATES_DIR}/tmux/tmux.conf"
readonly VIMRC_TEMPLATE="${TEMPLATES_DIR}/vim/.vimrc"
readonly ALIASES_TEMPLATE="${ZSH_TEMPLATE_DIR}/.aliases"
readonly ZSHRC_TEMPLATE="${ZSH_TEMPLATE_DIR}/.zshrc"

LOG_FILE="${LOG_FILE_DEFAULT}"
INSTALLED_TRACK_FILE=""
NEW_USER="${NEW_USER:-}"
AUTH_METHOD="${AUTH_METHOD:-}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
EDITOR_CHOICE="${EDITOR_CHOICE:-}"
NEEDS_PENTEST_HARDENING="${NEEDS_PENTEST_HARDENING:-false}"
MULLVAD_RPM_URL="${MULLVAD_RPM_URL:-}"

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

SYSTEM_PACKAGES=(
  firewalld
  fail2ban
  zsh
  tmux
  vim-enhanced
  neovim
  fzf
  ripgrep
  fd-find
  git
  bat
  chromium
  nmap
  awscli
  jq
  curl
  wget
  unzip
  tar
  bind-utils
  net-tools
  policycoreutils
  policycoreutils-python-utils
  dnf-plugins-core
  zoxide
)

declare -A PIPX_APPS=(
  [waymore]='git+https://github.com/xnl-h4ck3r/waymore.git'
  [xnLinkFinder]='git+https://github.com/xnl-h4ck3r/xnLinkFinder.git'
  [urless]='git+https://github.com/xnl-h4ck3r/urless.git'
  [xnldorker]='git+https://github.com/xnl-h4ck3r/xnldorker.git'
  [reconFTW]='git+https://github.com/six2dez/reconftw.git'
  [JSHawk]='git+https://github.com/utkusen/jshawk.git'
  [Sublist3r]='git+https://github.com/aboul3la/Sublist3r.git'
  [dirsearch]='git+https://github.com/maurosoria/dirsearch.git'
  [sqlmap]='git+https://github.com/sqlmapproject/sqlmap.git'
  [JSParser]='git+https://github.com/nahamsec/JSParser.git'
  [knockpy]='git+https://github.com/guelfoweb/knock.git'
  [asnlookup]='git+https://github.com/yassineaboukir/asnlookup.git'
  [pdtm]='pdtm'
)

declare -A ZSH_PLUGIN_REPOS=(
  [zsh-vi-mode]='https://github.com/jeffreytse/zsh-vi-mode.git'
  [cd-ls]='https://github.com/zshzoo/cd-ls.git'
  [zsh-git-fzf]='https://github.com/alexiszamanidis/zsh-git-fzf.git'
  [alias-tips]='https://github.com/djui/alias-tips.git'
  [fzf-alias]='https://github.com/thirteen37/fzf-alias.git'
  [zsh-history-substring-search]='https://github.com/zsh-users/zsh-history-substring-search.git'
  [zsh-syntax-highlighting]='https://github.com/zsh-users/zsh-syntax-highlighting.git'
  [zsh-autosuggestions]='https://github.com/zsh-users/zsh-autosuggestions.git'
)

PDTM_TOOLS=(
  subfinder
  dnsx
  httpx
  notify
  nuclei
  katana
  mapcidr
  chaos
  shuffledns
  cent
)

GO_TOOLS=(
  github.com/tomnomnom/anew@latest
  github.com/tomnomnom/assetfinder@latest
  github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  github.com/projectdiscovery/katana/cmd/katana@latest
  github.com/tomnomnom/waybackurls@latest
  github.com/hakluke/hakrawler@latest
  github.com/d3mondev/puredns/v2@latest
  github.com/projectdiscovery/dnsx/cmd/dnsx@latest
  github.com/lc/gau/v2/cmd/gau@latest
  github.com/utkusen/socialhunter@latest
  github.com/PentestPad/subzy@latest
  github.com/003random/getJS/v2@latest
  github.com/gwen001/github-subdomains@latest
  github.com/cgboal/sonarsearch/cmd/crobat@latest
  github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest
  github.com/projectdiscovery/chaos-client/cmd/chaos@latest
  github.com/Josue87/gotator@latest
  github.com/glebarez/cero@latest
  github.com/dwisiswant0/galer@latest
  github.com/c3l3si4n/quickcert@latest
  github.com/sensepost/gowitness@latest
  github.com/projectdiscovery/httpx/cmd/httpx@latest
  github.com/tomnomnom/httprobe@latest
  github.com/jaeles-project/gospider@latest
  github.com/mrco24/parameters@latest
  github.com/tomnomnom/gf@latest
  github.com/mrco24/otx-url@latest
  github.com/ffuf/ffuf@latest
  github.com/OJ/gobuster/v3@latest
  github.com/mrco24/mrco24-lfi@latest
  github.com/mrco24/open-redirect@latest
  github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest
  github.com/hahwul/dalfox/v2@latest
  github.com/Emoe/kxss@latest
  github.com/KathanP19/Gxss@latest
  github.com/ethicalhackingplayground/bxss@latest
  github.com/ferreiraklet/Jeeves@latest
  github.com/mrco24/time-sql@latest
  github.com/mrco24/mrco24-error-sql@latest
  github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
  github.com/projectdiscovery/notify/cmd/notify@latest
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
)

log_info() { printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"; }
log_warn() { printf '[%s] WARN: %s\n' "$(date --iso-8601=seconds)" "$*"; }
log_error() { printf '[%s] ERROR: %s\n' "$(date --iso-8601=seconds)" "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

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

dnf_install_packages() {
  local packages=("$@")
  local to_install=()
  local pkg
  for pkg in "${packages[@]}"; do
    if [[ -n "${pkg}" ]] && ! rpm -q "${pkg}" >/dev/null 2>&1; then
      to_install+=("${pkg}")
    fi
  done
  if ((${#to_install[@]})); then
    log_info "Installing packages: ${to_install[*]}"
    if ! dnf install -y "${to_install[@]}"; then
      log_error "dnf install failed for: ${to_install[*]}"
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
  local cmd="$1"
  runuser -l "${NEW_USER}" -- bash -lc "${cmd}"
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
    printf 'AUTH_METHOD=%q\n' "${AUTH_METHOD}"
    printf 'SSH_PUBLIC_KEY=%q\n' "${SSH_PUBLIC_KEY}"
    printf 'EDITOR_CHOICE=%q\n' "${EDITOR_CHOICE}"
    printf 'NEEDS_PENTEST_HARDENING=%q\n' "${NEEDS_PENTEST_HARDENING}"
  } > "${ANSWERS_FILE}"
  chmod 0600 "${ANSWERS_FILE}"
  log_info "Saved prompt answers to ${ANSWERS_FILE}"
}

read_from_tty() {
  local __prompt="$1"
  local __var_name="$2"
  local __input=""
  while true; do
    read -rp "${__prompt}" __input </dev/tty || return 1
    if [[ -n "${__input}" ]]; then
      printf -v "${__var_name}" '%s' "${__input}"
      return 0
    fi
    echo "Value cannot be empty." >/dev/tty
  done
}

prompt_for_user() {
  if [[ -n "${NEW_USER}" ]]; then
    log_info "Using existing user selection: ${NEW_USER}"
    return
  fi
  local input=""
  while true; do
    read -rp "Enter name for the new non-root user: " input </dev/tty || { log_error "Unable to read username."; exit 1; }
    input="$(echo "${input}" | tr -d '[:space:]')"
    if [[ -z "${input}" ]]; then
      echo "Username cannot be blank." >/dev/tty
      continue
    fi
    if [[ "${input}" == "root" ]]; then
      echo "Do not use root for the managed account." >/dev/tty
      continue
    fi
    NEW_USER="${input}"
    break
  done
  log_info "Selected user: ${NEW_USER}"
}

prompt_for_auth_method() {
  local choice=""
  if [[ -n "${AUTH_METHOD}" ]]; then
    log_info "Using saved authentication method: ${AUTH_METHOD}"
  else
    while true; do
      read -rp "Choose SSH authentication (password/ssh-key): " choice </dev/tty || { log_error "Unable to read authentication method."; exit 1; }
      case "${choice,,}" in
        password|p)
          AUTH_METHOD="password"
          break
          ;;
        ssh|ssh-key|key)
          AUTH_METHOD="ssh"
          break
          ;;
        *)
          echo "Please answer password or ssh-key." >/dev/tty
          ;;
      esac
    done
  fi
  if [[ "${AUTH_METHOD}" == "ssh" && -z "${SSH_PUBLIC_KEY}" ]]; then
    echo "Paste the public SSH key for ${NEW_USER} (single line):" >/dev/tty
    read -r SSH_PUBLIC_KEY </dev/tty || { log_error "Failed to read SSH public key."; exit 1; }
    if [[ -z "${SSH_PUBLIC_KEY}" ]]; then
      log_error "Public key cannot be empty."
      exit 1
    fi
  fi
  log_info "Authentication method: ${AUTH_METHOD}"
}

prompt_for_editor_choice() {
  local choice=""
  if [[ -n "${EDITOR_CHOICE}" ]]; then
    log_info "Editor preference: ${EDITOR_CHOICE}"
    return
  fi
  while true; do
    read -rp "Configure which editor (vim/neovim/both): " choice </dev/tty || { log_error "Unable to read editor choice."; exit 1; }
    case "${choice,,}" in
      vim)
        EDITOR_CHOICE="vim"
        break
        ;;
      neovim|nvim)
        EDITOR_CHOICE="neovim"
        break
        ;;
      both)
        EDITOR_CHOICE="both"
        break
        ;;
      *)
        echo "Please answer vim, neovim, or both." >/dev/tty
        ;;
    esac
  done
  log_info "Editor selection: ${EDITOR_CHOICE}"
}

prompt_for_hardening() {
  local choice=""
  if [[ "${NEEDS_PENTEST_HARDENING}" == "true" || "${NEEDS_PENTEST_HARDENING}" == "false" ]]; then
    log_info "Pentest hardening flag: ${NEEDS_PENTEST_HARDENING}"
    return
  fi
  while true; do
    read -rp "Apply optional pentest VPN/sysctl hardening? (yes/no): " choice </dev/tty || { log_error "Unable to read hardening choice."; exit 1; }
    case "${choice,,}" in
      yes|y)
        NEEDS_PENTEST_HARDENING="true"
        break
        ;;
      no|n)
        NEEDS_PENTEST_HARDENING="false"
        break
        ;;
      *)
        echo "Please answer yes or no." >/dev/tty
        ;;
    esac
  done
  log_info "Pentest hardening: ${NEEDS_PENTEST_HARDENING}"
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

ensure_system_updates() {
  log_info "Updating base system packages"
  if ! rpm -q dnf-plugins-core >/dev/null 2>&1; then
    if ! dnf -y install dnf-plugins-core; then
      log_error "Failed to install dnf-plugins-core."
      exit 1
    fi
  fi
  if ! dnf -y upgrade; then
    log_error "dnf upgrade failed."
    exit 1
  fi
  if ! dnf config-manager --set-enabled crb >/dev/null 2>&1; then
    log_warn "Unable to enable CRB repository (may already be enabled)."
  fi
  if ! rpm -q epel-release >/dev/null 2>&1; then
    if ! dnf -y install epel-release; then
      log_error "Failed to install epel-release."
      exit 1
    fi
  fi
  if ! dnf -y update; then
    log_error "dnf update failed."
    exit 1
  fi
  log_info "System packages updated."
}

create_user_and_groups() {
  if ! id -u "${NEW_USER}" >/dev/null 2>&1; then
    log_info "Creating user ${NEW_USER}"
    useradd -m -s /bin/bash "${NEW_USER}"
  else
    log_info "User ${NEW_USER} already exists."
  fi

  log_info "Setting password for ${NEW_USER}"
  passwd "${NEW_USER}"

  if ! id -nG "${NEW_USER}" | grep -qw wheel; then
    usermod -aG wheel "${NEW_USER}"
    log_info "Added ${NEW_USER} to wheel group."
  else
    log_info "${NEW_USER} already in wheel group."
  fi

  id "${NEW_USER}"
  if [[ "${SUDO_USER:-root}" == "root" ]]; then
    log_warn "Provisioning is running as root. Switch to ${NEW_USER} for daily operations."
  fi
}

configure_ssh_policy() {
  local user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  [[ -z "${user_home}" ]] && return

  if [[ "${AUTH_METHOD}" == "ssh" ]]; then
    install -d -m 700 "${user_home}/.ssh"
    if [[ -n "${SSH_PUBLIC_KEY}" ]]; then
      if [[ ! -f "${user_home}/.ssh/authorized_keys" ]] || ! grep -Fxq "${SSH_PUBLIC_KEY}" "${user_home}/.ssh/authorized_keys"; then
        echo "${SSH_PUBLIC_KEY}" >> "${user_home}/.ssh/authorized_keys"
      fi
    fi
    chmod 600 "${user_home}/.ssh/authorized_keys"
    chown -R "${NEW_USER}:${NEW_USER}" "${user_home}/.ssh"
  fi

  if [[ ! -f "${SSH_CONFIG_BACKUP}" ]]; then
    cp "${SSH_CONFIG}" "${SSH_CONFIG_BACKUP}"
    log_info "Backed up ${SSH_CONFIG} to ${SSH_CONFIG_BACKUP}"
  fi

  if grep -q '^PermitRootLogin' "${SSH_CONFIG}"; then
    sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' "${SSH_CONFIG}"
  else
    echo 'PermitRootLogin no' >> "${SSH_CONFIG}"
  fi

  if [[ "${AUTH_METHOD}" == "ssh" ]]; then
    if grep -q '^PasswordAuthentication' "${SSH_CONFIG}"; then
      sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "${SSH_CONFIG}"
    else
      echo 'PasswordAuthentication no' >> "${SSH_CONFIG}"
    fi
  else
    if grep -q '^PasswordAuthentication' "${SSH_CONFIG}"; then
      sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' "${SSH_CONFIG}"
    else
      echo 'PasswordAuthentication yes' >> "${SSH_CONFIG}"
    fi
  fi

  if grep -q '^AllowUsers' "${SSH_CONFIG}"; then
    if ! grep -q "^AllowUsers .*\\b${NEW_USER}\\b" "${SSH_CONFIG}"; then
      sed -i "s/^AllowUsers.*/& ${NEW_USER}/" "${SSH_CONFIG}"
    fi
  else
    echo "AllowUsers ${NEW_USER}" >> "${SSH_CONFIG}"
  fi

  systemctl reload sshd
  log_info "SSHD configuration updated and reloaded."
}

verify_selinux() {
  local mode
  mode="$(getenforce)"
  log_info "SELinux mode: ${mode}"
  if [[ "${mode}" != "Enforcing" ]]; then
    log_warn "SELinux is not enforcing."
  fi
  sestatus || true
}

apply_optional_hardening() {
  if [[ "${NEEDS_PENTEST_HARDENING}" != "true" ]]; then
    log_info "Pentest network hardening skipped."
    return
  fi
  cat > "${SYSCTL_FILE}" <<'EOF'
# network protections
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# misc
kernel.kptr_restrict = 2
fs.suid_dumpable = 0
EOF
  chmod 0644 "${SYSCTL_FILE}"
  sysctl --system
  log_info "Applied sysctl hardening profile."

  if command_exists iptables; then
    if ! iptables-save | grep -q 'MARK --set-mark 22'; then
      local gw
      gw="$(ip route | awk '/^default/ {print $3; exit}')"
      if [[ -n "${gw}" ]]; then
        iptables -t mangle -A OUTPUT -p tcp --sport 22 -j MARK --set-mark 22
        ip rule add fwmark 22 table 128 >/dev/null 2>&1 || true
        ip route add default via "${gw}" table 128 >/dev/null 2>&1 || true
      else
        log_warn "Unable to determine default gateway; SSH bypass rules not added."
      fi
    fi
    iptables-save > /etc/iptables.rules
    if [[ ! -f "${RC_LOCAL}" ]]; then
      cat > "${RC_LOCAL}" <<'EOF'
#!/usr/bin/env bash
iptables-restore < /etc/iptables.rules
exit 0
EOF
    else
      if ! grep -q 'iptables-restore < /etc/iptables.rules' "${RC_LOCAL}"; then
        sed -i '/^exit 0$/d' "${RC_LOCAL}"
        echo 'iptables-restore < /etc/iptables.rules' >> "${RC_LOCAL}"
        echo 'exit 0' >> "${RC_LOCAL}"
      fi
    fi
    chmod +x "${RC_LOCAL}"
    log_info "Persisted iptables rules."
  else
    log_warn "iptables not available; skip VPN routing rules."
  fi
}

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

install_mullvad() {
  if rpm -q mullvad-vpn >/dev/null 2>&1; then
    log_info "mullvad-vpn already installed."
    append_installed_tool "mullvad-vpn"
    return
  fi
  if [[ -z "${MULLVAD_RPM_URL}" ]]; then
    log_warn "MULLVAD_RPM_URL not provided; skipping Mullvad installation."
    return
  fi
  local tmpdir
  tmpdir="$(mktemp -d)"
  if curl -fsSL "${MULLVAD_RPM_URL}" -o "${tmpdir}/mullvad.rpm"; then
    if dnf install -y "${tmpdir}/mullvad.rpm"; then
      append_installed_tool "mullvad-vpn"
      systemctl enable --now mullvad-daemon >/dev/null 2>&1 || log_warn "Unable to enable mullvad-daemon."
    else
      log_warn "Failed to install Mullvad from ${MULLVAD_RPM_URL}"
    fi
  else
    log_warn "Unable to download Mullvad package from ${MULLVAD_RPM_URL}"
  fi
  rm -rf "${tmpdir}"
}

ensure_fnm() {
  if run_as_user "command -v fnm >/dev/null 2>&1"; then
    append_installed_tool "fnm"
    return
  fi
  local install_cmd='curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir ~/.local/share/fnm --skip-shell'
  if run_as_user "${install_cmd}"; then
    run_as_user "mkdir -p ~/.local/bin && ln -sf ~/.local/share/fnm/fnm ~/.local/bin/fnm"
    append_installed_tool "fnm"
    log_info "Installed fnm for ${NEW_USER}"
  else
    log_warn "Failed to install fnm. Node version management will be unavailable."
  fi
}

install_system_utilities() {
  dnf_install_packages "${SYSTEM_PACKAGES[@]}"
  systemctl enable --now firewalld >/dev/null 2>&1 || log_warn "Failed to enable firewalld."
  systemctl enable --now fail2ban >/dev/null 2>&1 || log_warn "Failed to enable fail2ban."

  if command_exists fdfind && ! command_exists fd; then
    ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
  install_mullvad
  ensure_fnm

  append_installed_tool "firewalld"
  append_installed_tool "fail2ban"
  append_installed_tool "zsh"
  append_installed_tool "tmux"
  append_installed_tool "neovim"
  append_installed_tool "vim"
  append_installed_tool "fzf"
  append_installed_tool "ripgrep"
  append_installed_tool "fd-find"
  append_installed_tool "git"
  append_installed_tool "bat"
  append_installed_tool "chromium"
  append_installed_tool "nmap"
  append_installed_tool "awscli"
  append_installed_tool "zoxide"
}

install_language_helpers() {
  local app package cmd
  for app in "${!PIPX_APPS[@]}"; do
    package="${PIPX_APPS[$app]}"
    if [[ "${package}" == "pdtm" ]]; then
      cmd=$(printf "pipx install --force %q" "${package}")
    else
      cmd=$(printf "pipx install --force %q" "${package}")
    fi
    if run_as_user "${cmd}"; then
      append_installed_tool "${app}"
    else
      log_warn "pipx installation failed for ${app}"
    fi
  done

  if run_as_user "command -v pdtm >/dev/null"; then
    for app in "${PDTM_TOOLS[@]}"; do
      cmd=$(printf "pdtm install %q" "${app}")
      if run_as_user "${cmd}"; then
        append_installed_tool "${app}"
      else
        log_warn "pdtm install failed for ${app}"
      fi
    done
  else
    log_warn "pdtm not found; ProjectDiscovery tool installs skipped."
  fi
}

install_go_tools() {
  local module tool tool_name
  for module in "${GO_TOOLS[@]}"; do
    tool="${module%@*}"
    tool_name="${tool##*/}"
    if run_as_user "$(printf "GOBIN=\$HOME/go/bin GOPATH=\$HOME/go GO111MODULE=on go install %q" "${module}")"; then
      append_installed_tool "${tool_name}"
    else
      log_warn "Failed to install Go tool ${module}"
    fi
  done
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

setup_intrusion_detection() {
  dnf_install_packages aide rkhunter
  if [[ ! -f /var/lib/aide/aide.db.gz ]]; then
    if aide --init; then
      mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    else
      log_warn "aide --init failed."
    fi
  fi
  rkhunter --update || log_warn "rkhunter update failed."
  rkhunter --checkall --sk --nocolors || log_warn "rkhunter check reported issues. Review /var/log/rkhunter.log."

  if [[ ! -f /etc/sudoers.d/90-logging ]]; then
    echo 'Defaults logfile="/var/log/sudo.log",log_input,log_output' > /etc/sudoers.d/90-logging
    chmod 0440 /etc/sudoers.d/90-logging
  fi
  append_installed_tool "aide"
  append_installed_tool "rkhunter"
}

configure_shells_and_editors() {
  local user_home
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  [[ -z "${user_home}" ]] && return

  if [[ ! -d "${user_home}/.oh-my-zsh" ]]; then
    if ! run_as_user "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no KEEP_ZSHRC=yes sh"; then
      log_warn "Oh My Zsh installation failed."
    fi
  fi

  if [[ -f "${ZSHRC_TEMPLATE}" ]]; then
    install -m 0644 "${ZSHRC_TEMPLATE}" "${user_home}/.zshrc"
    chown "${NEW_USER}:${NEW_USER}" "${user_home}/.zshrc"
  else
    log_warn "Missing Zsh template at ${ZSHRC_TEMPLATE}"
  fi
  if [[ -f "${ALIASES_TEMPLATE}" ]]; then
    install -m 0644 "${ALIASES_TEMPLATE}" "${user_home}/.aliases"
    chown "${NEW_USER}:${NEW_USER}" "${user_home}/.aliases"
  fi

  if [[ -f "${TMUX_TEMPLATE}" ]]; then
    install -m 0644 "${TMUX_TEMPLATE}" "${user_home}/.tmux.conf"
    chown "${NEW_USER}:${NEW_USER}" "${user_home}/.tmux.conf"
  fi

  if [[ "${EDITOR_CHOICE}" == "vim" || "${EDITOR_CHOICE}" == "both" ]]; then
    if [[ -f "${VIMRC_TEMPLATE}" ]]; then
      install -m 0644 "${VIMRC_TEMPLATE}" "${user_home}/.vimrc"
      chown "${NEW_USER}:${NEW_USER}" "${user_home}/.vimrc"
    else
      log_warn "Missing Vim template at ${VIMRC_TEMPLATE}"
    fi
  fi

  if [[ "${EDITOR_CHOICE}" == "neovim" || "${EDITOR_CHOICE}" == "both" ]]; then
    if [[ ! -d "${user_home}/.config/nvim" ]]; then
      if run_as_user "git clone https://github.com/LazyVim/starter ~/.config/nvim"; then
        append_installed_tool "LazyVim"
      else
        log_warn "Failed to clone LazyVim starter."
      fi
    else
      run_as_user "git -C ~/.config/nvim pull --ff-only" || log_warn "Unable to update LazyVim starter."
    fi
    run_as_user "nvim --headless '+Lazy! sync' +qa" || log_warn "Neovim plugin sync did not complete cleanly."
  fi

  install_custom_zsh_plugins "${user_home}"
}

install_custom_zsh_plugins() {
  local user_home="$1"
  local zsh_custom="${user_home}/.oh-my-zsh/custom"
  local plugin repo dest

  if [[ ! -d "${zsh_custom}" ]]; then
    log_warn "Oh My Zsh custom directory not found, skipping plugin installation."
    return
  fi

  run_as_user "$(printf 'mkdir -p %q' "${zsh_custom}/plugins")"

  for plugin in "${!ZSH_PLUGIN_REPOS[@]}"; do
    repo="${ZSH_PLUGIN_REPOS[$plugin]}"
    dest="${zsh_custom}/plugins/${plugin}"
    if [[ -d "${dest}/.git" ]]; then
      if ! run_as_user "$(printf 'git -C %q pull --ff-only' "${dest}")"; then
        log_warn "Failed to update Zsh plugin ${plugin}"
      fi
    else
      if ! run_as_user "$(printf 'git clone %q %q' "${repo}" "${dest}")"; then
        log_warn "Failed to clone Zsh plugin ${plugin} from ${repo}"
        continue
      fi
    fi
  done
}

final_verification() {
  log_info "Verification summary:"
  getenforce || true
  run_as_user "command -v go && go version" || log_warn "Go runtime not found for ${NEW_USER}"
  run_as_user "pipx list" || log_warn "pipx list failed."
  if [[ -f "${INSTALLED_TRACK_FILE}" ]]; then
    log_info "Installed tools recorded in ${INSTALLED_TRACK_FILE}"
  fi
  log_info "Provisioning log: ${LOG_FILE}"
}

main() {
  require_root
  ensure_log_targets
  log_info "Starting ${SCRIPT_NAME}"

  load_previous_answers
  prompt_for_user
  prompt_for_auth_method
  prompt_for_editor_choice
  prompt_for_hardening
  record_prompt_answers

  create_user_and_groups
  init_installed_tracker

  ensure_system_updates
  configure_ssh_policy
  verify_selinux
  apply_optional_hardening
  setup_intrusion_detection

  install_language_runtimes
  install_system_utilities
  install_language_helpers
  install_go_tools
  install_git_python_tools

  configure_shells_and_editors
  final_verification

  log_info "Provisioning completed."
}

main "$@"
