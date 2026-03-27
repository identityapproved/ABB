# shellcheck shell=bash

readonly ABB_AUDIT_RULES_FILE="/etc/audit/rules.d/abb-system-monitoring.rules"

install_system_monitoring_packages() {
  pacman_install_packages audit jq linux-headers
}

configure_auditd_log_rotation() {
  local conf="/etc/audit/auditd.conf"
  [[ -f "${conf}" ]] || return 0

  sed -i \
    -e 's/^[#[:space:]]*max_log_file[[:space:]]*=.*/max_log_file = 50/' \
    -e 's/^[#[:space:]]*num_logs[[:space:]]*=.*/num_logs = 10/' \
    -e 's/^[#[:space:]]*max_log_file_action[[:space:]]*=.*/max_log_file_action = ROTATE/' \
    -e 's/^[#[:space:]]*space_left_action[[:space:]]*=.*/space_left_action = SYSLOG/' \
    -e 's/^[#[:space:]]*admin_space_left_action[[:space:]]*=.*/admin_space_left_action = SUSPEND/' \
    "${conf}"
}

write_system_audit_rules() {
  cat > "${ABB_AUDIT_RULES_FILE}" <<'EOF'
-a always,exit -F arch=b64 -F euid=0 -S execve -k root_action
-w /etc/shadow -p rwa -k shadow_file
-w /etc/passwd -p rwa -k passwd_file
-w /etc/sudoers -p rwa -k sudoers_file
-w /root/ -p rwa -k root_home
-a always,exit -F arch=b64 -S init_module -S delete_module -k kernel_modules
-w /lib/modules/ -p wa -k modules_dir
-w /boot/ -p wa -k boot_changes
-a always,exit -F arch=b64 -S ptrace -k ptrace_abuse
-a always,exit -F arch=b64 -S setuid -S setgid -k cred_changes
EOF
  chmod 0640 "${ABB_AUDIT_RULES_FILE}"
  log_info "Wrote system audit rules to ${ABB_AUDIT_RULES_FILE}."
}

enable_system_monitoring() {
  install_system_monitoring_packages
  configure_auditd_log_rotation
  write_system_audit_rules
  if command_exists augenrules; then
    augenrules --load >/dev/null 2>&1 || log_warn "augenrules --load failed."
  fi
  enable_unit "auditd.service" "auditd" || true
  append_installed_tool "audit"
  log_info "System monitoring enabled with auditd/auditctl."
}

run_task_monitoring() {
  ensure_user_context

  if [[ "${USE_MONITORING}" != "true" ]]; then
    log_info "Monitoring setup skipped because USE_MONITORING=${USE_MONITORING}."
    return 0
  fi

  if [[ "${ENABLE_SYSTEM_MONITORING}" == "true" ]]; then
    enable_system_monitoring
  else
    log_info "System monitoring skipped."
  fi
}
