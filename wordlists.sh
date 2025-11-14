#!/usr/bin/env bash
set -euo pipefail
umask 022

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
MODULE_DIR="${REPO_ROOT}/modules"

# shellcheck source=modules/common.sh
source "${MODULE_DIR}/common.sh"
# shellcheck source=modules/wordlists.sh
source "${MODULE_DIR}/wordlists.sh"

LOG_FILE="${LOG_FILE_DEFAULT}"
INSTALLED_TRACK_FILE=""
AUTO_WORDLISTS_CLONE="${AUTO_WORDLISTS_CLONE:-}"
ENABLE_ASSETNOTE_WORDLISTS="${ENABLE_ASSETNOTE_WORDLISTS:-}"

main() {
  require_root
  ensure_log_targets
  run_task_wordlists
}

main "$@"
