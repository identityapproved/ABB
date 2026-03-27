# shellcheck shell=bash

readonly ABB_AUDIT_RULES_FILE="/etc/audit/rules.d/abb-system-monitoring.rules"
readonly ABB_FALCO_RULES_DIR="/etc/falco/rules.d"
readonly ABB_FALCO_RULES_FILE="${ABB_FALCO_RULES_DIR}/abb-network-rules.yaml"
readonly ABB_FALCO_CONFIG_FILE="/etc/falco/falco.yaml"

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

install_network_monitoring_dependencies() {
  pacman_install_packages git cmake make gcc wget zlib jq yaml-cpp openssl curl c-ares protobuf grpc libyaml bpf linux-headers
}

install_falco() {
  if command_exists falco; then
    append_installed_tool "falco"
    return 0
  fi

  ensure_package_manager_ready
  install_network_monitoring_dependencies

  if aur_helper_install "falco-bin"; then
    append_installed_tool "falco"
    return 0
  fi

  log_error "Failed to install falco-bin via ${PACKAGE_MANAGER}."
  return 1
}

configure_falco_yaml() {
  [[ -f "${ABB_FALCO_CONFIG_FILE}" ]] || return 0

  if grep -q '^json_output:' "${ABB_FALCO_CONFIG_FILE}"; then
    sed -i 's/^json_output:.*/json_output: true/' "${ABB_FALCO_CONFIG_FILE}"
  else
    printf '\njson_output: true\n' >> "${ABB_FALCO_CONFIG_FILE}"
  fi

  if grep -q '^json_include_output_property:' "${ABB_FALCO_CONFIG_FILE}"; then
    sed -i 's/^json_include_output_property:.*/json_include_output_property: true/' "${ABB_FALCO_CONFIG_FILE}"
  else
    printf 'json_include_output_property: true\n' >> "${ABB_FALCO_CONFIG_FILE}"
  fi
}

write_falco_rules() {
  install -d -m 0755 "${ABB_FALCO_RULES_DIR}"
  cat > "${ABB_FALCO_RULES_FILE}" <<'EOF'
- rule: ABB Unexpected outbound connection from shell
  desc: A shell making an outbound network connection
  condition: evt.type=connect and proc.name in (bash,zsh,sh,dash,fish) and fd.sockfamily=ip
  output: >
    shell outbound connection user=%user.name proc=%proc.name pid=%proc.pid cmd=%proc.cmdline
    local=%fd.lip:%fd.lport remote=%fd.rip:%fd.rport proto=%fd.l4proto
  priority: WARNING
  tags: [abb, host, network, shell]

- rule: ABB Curl or wget outbound connection
  desc: curl or wget connected outbound
  condition: evt.type=connect and proc.name in (curl,wget) and fd.sockfamily=ip
  output: >
    web client outbound connection user=%user.name proc=%proc.name pid=%proc.pid cmd=%proc.cmdline
    remote=%fd.rip:%fd.rport proto=%fd.l4proto
  priority: NOTICE
  tags: [abb, host, network, exfil]

- rule: ABB Python outbound connection
  desc: Python initiated a network connection
  condition: evt.type=connect and proc.name in (python,python3) and fd.sockfamily=ip
  output: >
    python outbound connection user=%user.name proc=%proc.name pid=%proc.pid cmd=%proc.cmdline
    remote=%fd.rip:%fd.rport proto=%fd.l4proto cwd=%proc.cwd
  priority: NOTICE
  tags: [abb, host, network, scripting]

- rule: ABB Package manager network connection
  desc: Package manager connected to network
  condition: evt.type=connect and proc.name in (pacman,apt,apt-get,dnf,yum)
  output: >
    package manager network connection proc=%proc.name pid=%proc.pid cmd=%proc.cmdline
    remote=%fd.rip:%fd.rport proto=%fd.l4proto
  priority: INFORMATIONAL
  tags: [abb, host, network, packages]
EOF
  chmod 0644 "${ABB_FALCO_RULES_FILE}"
  log_info "Wrote Falco rules to ${ABB_FALCO_RULES_FILE}."
}

enable_falco_service() {
  if systemd_available; then
    if systemctl list-unit-files "falco-modern-bpf.service" >/dev/null 2>&1; then
      if enable_unit "falco-modern-bpf.service" "Falco modern BPF"; then
        sleep 2
        if systemctl is-active --quiet falco-modern-bpf.service; then
          log_info "Falco modern BPF service is active."
          return 0
        fi
        log_warn "Falco modern BPF service failed after startup; falling back to falco.service."
        systemctl disable --now falco-modern-bpf.service >/dev/null 2>&1 || true
      fi
    fi

    if systemctl list-unit-files "falco.service" >/dev/null 2>&1; then
      if enable_unit "falco.service" "Falco"; then
        sleep 2
        if systemctl is-active --quiet falco.service; then
          log_info "Falco service is active."
          return 0
        fi
        log_warn "Falco service failed after startup."
      fi
    fi
  fi

  log_warn "Falco service unit could not be enabled automatically."
  return 1
}

enable_network_monitoring() {
  install_falco || return 1
  configure_falco_yaml
  write_falco_rules
  enable_falco_service || true
  log_info "Network monitoring enabled with Falco."
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

  if [[ "${ENABLE_NETWORK_MONITORING}" == "true" ]]; then
    enable_network_monitoring
  else
    log_info "Network monitoring skipped."
  fi
}
