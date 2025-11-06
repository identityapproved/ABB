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
# shellcheck source=modules/wordlists.sh
source "${MODULE_DIR}/wordlists.sh"
# shellcheck source=modules/tools.sh
source "${MODULE_DIR}/tools.sh"
# shellcheck source=modules/dotfiles.sh
source "${MODULE_DIR}/dotfiles.sh"
# shellcheck source=modules/verify.sh
source "${MODULE_DIR}/verify.sh"
# shellcheck source=modules/docker_tools.sh
source "${MODULE_DIR}/docker_tools.sh"
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
FEROX_INSTALL_METHOD="${FEROX_INSTALL_METHOD:-}"
TRUFFLEHOG_INSTALL="${TRUFFLEHOG_INSTALL:-}"
SKIP_DOCKER_TASKS="${SKIP_DOCKER_TASKS:-false}"

usage() {
  cat <<'EOF'
Usage: abb-setup.sh [task]

Tasks:
  prompts     Collect answers for the managed user, editor preference, and optional hardening flags.
  accounts    Create the managed user, copy SSH keys, enable sudo, and optionally retire the admin account.
  package-manager Install and record the preferred AUR helper before continuing with provisioning.
  security    Apply pacman updates, optional sysctl/iptables hardening, and install AIDE/rkhunter.
  languages   Install language runtimes (Python/pipx, Go, Ruby, Rust) for the managed user.
  utilities   Install core system utilities (zsh, yay, tree, tldr, ripgrep, fd, firewalld, etc.).
  tools       Install pipx-managed apps, ProjectDiscovery tools via pdtm, Go recon utilities, and git-based tooling.
  dotfiles    Install Oh My Zsh, custom plugins, dotfiles, and editor configuration.
  verify      Run post-install sanity checks for the managed user.
  mullvad     Configure Mullvad WireGuard profiles and SSH-preserving rules.
  docker-tools Install Docker-based utilities (ReconFTW, Asnlookup, dnsvalidator, feroxbuster, trufflehog) when Docker is the chosen engine (skipped if Docker was unavailable earlier).
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
  run_task_security
  run_task_utilities
  run_task_mullvad
  run_task_tools
  run_task_dotfiles
  run_task_verify
  if [[ "${SKIP_DOCKER_TASKS}" == "true" ]]; then
    log_warn "Skipping docker-tools task because Docker is unavailable."
  else
    run_task_docker_tools
  fi
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
    mullvad)
      log_info "Running Mullvad WireGuard task"
      run_task_mullvad
      ;;
    tools)
      log_info "Running tools task"
      run_task_tools
      ;;
    dotfiles)
      log_info "Running dotfiles task"
      run_task_dotfiles
      ;;
  verify)
    log_info "Running verification task"
    run_task_verify
    ;;
  docker-tools)
    if [[ "${SKIP_DOCKER_TASKS}" == "true" ]]; then
      log_warn "docker-tools task skipped because Docker was not ready. Reboot and rerun 'abb-setup.sh docker-tools'."
    else
      log_info "Running docker tools task"
      run_task_docker_tools
    fi
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
  if [[ "${task}" == "all" || "${task}" == "docker-tools" ]]; then
    show_next_steps
  fi
}

main "$@"
