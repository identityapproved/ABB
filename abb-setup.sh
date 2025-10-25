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
# shellcheck source=modules/security.sh
source "${MODULE_DIR}/security.sh"
# shellcheck source=modules/languages.sh
source "${MODULE_DIR}/languages.sh"
# shellcheck source=modules/utilities.sh
source "${MODULE_DIR}/utilities.sh"
# shellcheck source=modules/tools.sh
source "${MODULE_DIR}/tools.sh"
# shellcheck source=modules/dotfiles.sh
source "${MODULE_DIR}/dotfiles.sh"
# shellcheck source=modules/verify.sh
source "${MODULE_DIR}/verify.sh"

LOG_FILE="${LOG_FILE_DEFAULT}"
INSTALLED_TRACK_FILE=""
NEW_USER="${NEW_USER:-}"
EDITOR_CHOICE="${EDITOR_CHOICE:-}"
NEEDS_PENTEST_HARDENING="${NEEDS_PENTEST_HARDENING:-false}"

usage() {
  cat <<'EOF'
Usage: abb-setup.sh [task]

Tasks:
  prompts     Collect answers, rename the default admin user if needed, and prepare tracking files.
  security    Apply pacman updates, optional sysctl/iptables hardening, and install AIDE/rkhunter.
  languages   Install language runtimes (Python/pipx, Go, Ruby) for the managed user.
  utilities   Install core system utilities (zsh, yay, tree, tldr, ripgrep, fd, firewalld, etc.).
  tools       Install pipx-managed apps, ProjectDiscovery tools via pdtm, Go recon utilities, and git-based tooling.
  dotfiles    Install Oh My Zsh, custom plugins, dotfiles, and editor configuration.
  verify      Run post-install sanity checks for the managed user.
  all         Run every task in the order above (default if no task provided).
  help        Display this message.

Each task reads cached answers from /var/lib/vps-setup/answers.env and will prompt for missing data.
EOF
}

run_task_all() {
  run_task_prompts
  run_task_security
  run_task_languages
  run_task_utilities
  run_task_tools
  run_task_dotfiles
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
}

main "$@"
