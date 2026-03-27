#!/usr/bin/env bash
set -euo pipefail
umask 022

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="${SCRIPT_DIR}"
readonly MODULE_DIR="${SCRIPT_DIR}/modules"

# shellcheck source=modules/common.sh
source "${MODULE_DIR}/common.sh"
# shellcheck source=modules/prompts.sh
source "${MODULE_DIR}/prompts.sh"
# shellcheck source=modules/accounts.sh
source "${MODULE_DIR}/accounts.sh"
# shellcheck source=modules/pkgmgr.sh
source "${MODULE_DIR}/pkgmgr.sh"
# shellcheck source=modules/security.sh
source "${MODULE_DIR}/security.sh"
# shellcheck source=modules/languages.sh
source "${MODULE_DIR}/languages.sh"
# shellcheck source=modules/utilities.sh
source "${MODULE_DIR}/utilities.sh"
# shellcheck source=modules/network_access.sh
source "${MODULE_DIR}/network_access.sh"
# shellcheck source=modules/wordlists.sh
source "${MODULE_DIR}/wordlists.sh"
# shellcheck source=modules/tools.sh
source "${MODULE_DIR}/tools.sh"
# shellcheck source=modules/ai_tools.sh
source "${MODULE_DIR}/ai_tools.sh"
# shellcheck source=modules/monitoring.sh
source "${MODULE_DIR}/monitoring.sh"
# shellcheck source=modules/dotfiles.sh
source "${MODULE_DIR}/dotfiles.sh"
# shellcheck source=modules/verify.sh
source "${MODULE_DIR}/verify.sh"
# shellcheck source=modules/mullvad.sh
source "${MODULE_DIR}/mullvad.sh"

LOG_FILE="${LOG_FILE_DEFAULT}"
INSTALLED_TRACK_FILE=""
NEW_USER="${NEW_USER:-}"
EDITOR_CHOICE="${EDITOR_CHOICE:-}"
NEEDS_PENTEST_HARDENING="${NEEDS_PENTEST_HARDENING:-false}"
PACKAGE_MANAGER="${PACKAGE_MANAGER:-}"
NODE_MANAGER="${NODE_MANAGER:-}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
NETWORK_ACCESS_MODE="${NETWORK_ACCESS_MODE:-}"
SSH_KEY_SOURCE="${SSH_KEY_SOURCE:-}"
USE_VPN="${USE_VPN:-false}"
VPN_PROVIDER="${VPN_PROVIDER:-}"
USE_MONITORING="${USE_MONITORING:-false}"
ENABLE_SYSTEM_MONITORING="${ENABLE_SYSTEM_MONITORING:-false}"
ENABLE_NETWORK_MONITORING="${ENABLE_NETWORK_MONITORING:-false}"
INSTALL_TOOLS="${INSTALL_TOOLS:-}"
INSTALL_WORDLISTS="${INSTALL_WORDLISTS:-}"
SKIP_DOCKER_TASKS="${SKIP_DOCKER_TASKS:-false}"

usage() {
  cat <<'EOF'
Usage: abb-setup.sh [task]

Tasks:
  prompts     Collect answers for the managed user, editor preference, and optional hardening flags.
  accounts    Create the managed user, enable sudo, and optionally retire the admin account.
  package-manager Install and record the preferred AUR helper before continuing with provisioning.
  security    Apply pacman updates, resolver hardening, and install AIDE/rkhunter.
  languages   Install language runtimes (Python/pipx, Go, Ruby, Rust) for the managed user.
  utilities   Install core system utilities (zsh, yay, tree, tldr, ripgrep, fd, firewalld, etc.).
  network-access Configure SSH access keys, fail2ban/firewalld SSH exposure, and optional Tailscale access.
  tools       Install pipx-managed apps, ProjectDiscovery tools via pdtm, Go recon utilities, and git-based tooling.
  ai-tools    Install optional AI tooling for the managed user.
  dotfiles    Install Oh My Zsh, custom plugins, dotfiles, and editor configuration.
  verify      Run post-install sanity checks for the managed user.
  vpn         Configure the selected VPN provider and WireGuard profile staging.
  mullvad     Backward-compatible alias for the vpn task.
  monitoring  Install and configure optional system/network monitoring.
  all         Run every task in the order above (default if no task provided).
  help        Display this message.

Each task reads cached answers from /var/lib/vps-setup/answers.env and will prompt for missing data.
EOF
}

show_next_steps() {
  local next_file="${REPO_ROOT}/NEXT_STEPS.md"
  if [[ -f "${next_file}" ]]; then
    printf '\n=== Next Steps Reference ===\n'
    cat "${next_file}"
    printf '\n'
  fi
}

run_task_all() {
  run_task_prompts
  run_task_accounts
  run_task_package_manager
  run_task_languages
  run_task_utilities
  run_task_network_access
  run_task_security
  run_task_vpn
  run_task_tools
  run_task_ai_tools
  run_task_dotfiles
  run_task_monitoring
  run_task_verify
}

main() {
  require_root
  ensure_log_targets
  local task="${1:-all}"

  case "${task}" in
    help|-h|--help)
      usage
      return 0
      ;;
    prompts)
      log_info "Running prompts task"
      run_task_prompts
      ;;
    accounts)
      log_info "Running accounts task"
      run_task_accounts
      ;;
    package-manager)
      log_info "Running package manager task"
      run_task_package_manager
      ;;
    security)
      log_info "Running security task"
      run_task_security
      ;;
    languages)
      log_info "Running languages task"
      run_task_languages
      ;;
    utilities)
      log_info "Running utilities task"
      run_task_utilities
      ;;
    network-access)
      log_info "Running network access task"
      run_task_network_access
      ;;
    vpn|mullvad)
      log_info "Running VPN task"
      run_task_vpn
      ;;
    tools)
      log_info "Running tools task"
      run_task_tools
      ;;
    ai-tools)
      log_info "Running AI tools task"
      run_task_ai_tools
      ;;
    monitoring)
      log_info "Running monitoring task"
      run_task_monitoring
      ;;
    dotfiles)
      log_info "Running dotfiles task"
      run_task_dotfiles
      ;;
  verify)
    log_info "Running verification task"
    run_task_verify
    ;;
    all)
      log_info "Running full provisioning workflow"
      run_task_all
      ;;
    *)
      log_error "Unknown task: ${task}"
      usage
      exit 1
      ;;
  esac

  log_info "Task '${task}' completed."
  if [[ "${task}" == "all" ]]; then
    show_next_steps
  fi
}

main "$@"
