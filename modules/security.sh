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

install_optional_package() {
  local pkg="$1"
  if pacman -Qi "${pkg}" >/dev/null 2>&1; then
    log_info "Package ${pkg} already installed."
    return 0
  fi
  if pacman --noconfirm -Sy --needed "${pkg}"; then
    log_info "Installed ${pkg} via pacman."
    return 0
  fi
  if aur_helper_install "${pkg}"; then
    log_info "Installed ${pkg} via ${PACKAGE_MANAGER}."
    return 0
  fi
  log_warn "Unable to install ${pkg}. Continuing without it."
  return 1
}

setup_intrusion_detection() {
  local aide_installed=0 rkhunter_installed=0
  if install_optional_package aide; then
    aide_installed=1
  fi
  if install_optional_package rkhunter; then
    rkhunter_installed=1
  fi

  if ((aide_installed)) && command_exists aide; then
    if [[ ! -f /var/lib/aide/aide.db.gz ]]; then
      if aide --init; then
        mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
      else
        log_warn "aide --init failed."
      fi
    fi
    append_installed_tool "aide"
  else
    log_warn "AIDE unavailable; file integrity scanning skipped."
  fi

  if ((rkhunter_installed)) && command_exists rkhunter; then
    rkhunter --update || log_warn "rkhunter update failed."
    rkhunter --checkall --sk --nocolors || log_warn "rkhunter check reported issues. Review /var/log/rkhunter.log."
    append_installed_tool "rkhunter"
  else
    log_warn "rkhunter unavailable; rootkit scanning skipped."
  fi

  if [[ ! -f /etc/sudoers.d/90-logging ]]; then
    echo 'Defaults logfile="/var/log/sudo.log",log_input,log_output' > /etc/sudoers.d/90-logging
    chmod 0440 /etc/sudoers.d/90-logging
  fi
}

configure_resolved_hardening() {
  local dropin_dir="/etc/systemd/resolved.conf.d"
  local dropin_file="${dropin_dir}/no-mdns.conf"

  mkdir -p "${dropin_dir}"
  cat > "${dropin_file}" <<'EOF'
[Resolve]
MulticastDNS=no
LLMNR=no
EOF
  chmod 0644 "${dropin_file}"

  if systemd_available && systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
    if systemctl restart systemd-resolved; then
      log_info "Restarted systemd-resolved after disabling mDNS/LLMNR."
    else
      log_warn "Failed to restart systemd-resolved; review system logs."
    fi
  else
    log_warn "systemd-resolved service not found; restart skipped."
  fi
}

run_task_security() {
  ensure_user_context
  ensure_package_manager_ready
  ensure_system_updates
  verify_selinux
  configure_resolved_hardening
  setup_intrusion_detection
}
