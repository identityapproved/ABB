# shellcheck shell=bash

ensure_system_updates() {
  log_info "Updating base system packages"
  if ! pacman --noconfirm -Syu; then
    log_error "pacman -Syu failed."
    exit 1
  fi
  log_info "System packages updated."
}

verify_selinux() {
  if command_exists getenforce; then
    local mode
    mode="$(getenforce)"
    log_info "SELinux mode: ${mode}"
  else
    log_info "SELinux not detected on this Arch system; skipping check."
  fi
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

setup_intrusion_detection() {
  pacman_install_packages aide rkhunter
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

run_task_security() {
  ensure_user_context
  ensure_system_updates
  verify_selinux
  apply_optional_hardening
  setup_intrusion_detection
}
