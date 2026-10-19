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
# Flush first: the kernel keeps rules in load order and rejects a duplicate
# with "Rule exists", so reloading onto a live ruleset fails without -D. This
# is also the only way to reorder rules without a reboot. Being the sole file
# in rules.d, -D here wipes nothing else; a second file sorting ahead of this
# one would be erased by it.
-D
-b 8192
-f 1

# Noise exclusions, deliberately ahead of the always rules below, because the
# kernel stops at the first match. The bbdata-postgres container healthcheck
# (runc -> busybox sh -> pg_isready, every 5s) tripped root_action and
# cred_changes about 290,000 times a day by itself, rotating the entire audit
# trail away in roughly 36 hours and leaving a two-week absence uncovered.
# Measured 19.10.2026: /runc alone accounted for 225,192 cred_changes records.
# The cost is that exec inside a container is no longer audited; the healthcheck
# interval belongs to the container repo, not here, so this is the only lever
# ABB has over it.
-a never,exit -F arch=b64 -F exe=/usr/bin/runc
-a never,exit -F arch=b32 -F exe=/usr/bin/runc
-a never,exit -F arch=b64 -F exe=/runc
-a never,exit -F arch=b32 -F exe=/runc
-a never,exit -F arch=b64 -F exe=/bin/busybox
-a never,exit -F arch=b32 -F exe=/bin/busybox
-a never,exit -F arch=b64 -F exe=/usr/local/bin/pg_isready
-a never,exit -F arch=b32 -F exe=/usr/local/bin/pg_isready

# Every syscall rule is paired b64/b32. multilib is enabled on these boxes, so
# a 32-bit binary reaches the same syscalls through a different table and a
# b64-only rule never sees it. The -w watch rules below need no twin; they
# match on path, not on syscall table.
-a always,exit -F arch=b64 -F euid=0 -S execve -k root_action
-a always,exit -F arch=b32 -F euid=0 -S execve -k root_action
-w /etc/shadow -p rwa -k shadow_file
-w /etc/passwd -p rwa -k passwd_file
-w /etc/sudoers -p rwa -k sudoers_file
-w /root/ -p rwa -k root_home
-a always,exit -F arch=b64 -S init_module -S delete_module -k kernel_modules
-a always,exit -F arch=b32 -S init_module -S delete_module -k kernel_modules
-w /lib/modules/ -p wa -k modules_dir
-w /boot/ -p wa -k boot_changes
-a always,exit -F arch=b64 -S ptrace -k ptrace_abuse
-a always,exit -F arch=b32 -S ptrace -k ptrace_abuse
-a always,exit -F arch=b64 -S setuid -S setgid -k cred_changes
-a always,exit -F arch=b32 -S setuid -S setgid -k cred_changes

# Write-once loginuid, so root cannot reset auid and auid=unset can be trusted
# to mean "no login session" rather than "cleared". Drop this line if a
# container runtime starts failing on task credentials after a reboot.
--loginuid-immutable

# Must stay the last line of the concatenated ruleset: it freezes the rules
# until the next reboot.
-e 2
EOF
  chmod 0640 "${ABB_AUDIT_RULES_FILE}"
  log_info "Wrote system audit rules to ${ABB_AUDIT_RULES_FILE}."
}

load_system_audit_rules() {
  command_exists augenrules || return 0

  # -e 2 in the ruleset freezes it until reboot, so a re-run on an already
  # provisioned host cannot reload and augenrules would fail for a reason that
  # is not a fault. Say what is needed instead.
  if auditctl -s 2>/dev/null | grep -qE '^enabled[[:space:]]+2'; then
    log_warn "Audit rules are immutable (enabled 2); reboot to apply ${ABB_AUDIT_RULES_FILE}."
    return 0
  fi

  augenrules --load >/dev/null 2>&1 || log_warn "augenrules --load failed."
}

enable_system_monitoring() {
  install_system_monitoring_packages
  configure_auditd_log_rotation
  write_system_audit_rules
  load_system_audit_rules
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
