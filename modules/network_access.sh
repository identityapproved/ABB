# shellcheck shell=bash

ACTIVE_ACCESS_USER=""
readonly SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
readonly ABB_SSHD_HARDENING_FILE="${SSHD_DROPIN_DIR}/50-abb-hardening.conf"

detect_active_access_user() {
  local candidate=""

  candidate="${SUDO_USER:-}"
  if [[ -z "${candidate}" || "${candidate}" == "root" ]]; then
    candidate="$(logname 2>/dev/null || true)"
  fi
  if [[ -z "${candidate}" ]]; then
    candidate="root"
  fi

  ACTIVE_ACCESS_USER="${candidate}"
}

ensure_managed_ssh_dir() {
  local target_home

  target_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${target_home}" ]]; then
    log_error "Unable to determine home directory for ${NEW_USER}."
    exit 1
  fi

  install -d -m 0700 "${target_home}/.ssh"
  chown "${NEW_USER}:${NEW_USER}" "${target_home}/.ssh"
}

copy_authorized_keys_from_user() {
  local source_user="$1"
  local source_home="" target_home="" source_file="" target_file="" line=""

  if [[ -z "${source_user}" ]] || ! id -u "${source_user}" >/dev/null 2>&1; then
    log_warn "Source user '${source_user}' is unavailable; skipping authorized_keys copy."
    return 1
  fi

  source_home="$(getent passwd "${source_user}" | cut -d: -f6)"
  target_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  source_file="${source_home}/.ssh/authorized_keys"
  target_file="${target_home}/.ssh/authorized_keys"

  if [[ ! -f "${source_file}" ]]; then
    log_warn "No authorized_keys found for ${source_user}; skipping key copy."
    return 1
  fi

  ensure_managed_ssh_dir
  touch "${target_file}"
  chown "${NEW_USER}:${NEW_USER}" "${target_file}"
  chmod 0600 "${target_file}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    if ! grep -Fxq "${line}" "${target_file}" 2>/dev/null; then
      printf '%s\n' "${line}" >> "${target_file}"
    fi
  done < "${source_file}"

  chown "${NEW_USER}:${NEW_USER}" "${target_file}"
  chmod 0600 "${target_file}"
  log_info "Merged authorized_keys from ${source_user} into ${NEW_USER}."
  return 0
}

append_public_key_if_missing() {
  local public_key="$1"
  local target_home="" target_file=""

  target_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  target_file="${target_home}/.ssh/authorized_keys"

  ensure_managed_ssh_dir
  touch "${target_file}"
  chown "${NEW_USER}:${NEW_USER}" "${target_file}"
  chmod 0600 "${target_file}"

  if grep -Fxq "${public_key}" "${target_file}" 2>/dev/null; then
    log_info "SSH public key already present for ${NEW_USER}."
    return 0
  fi

  printf '%s\n' "${public_key}" >> "${target_file}"
  chown "${NEW_USER}:${NEW_USER}" "${target_file}"
  chmod 0600 "${target_file}"
  log_info "Added SSH public key for ${NEW_USER}."
}

prompt_for_public_key() {
  local public_key=""

  while true; do
    read -rp "Paste the SSH public key to authorize for ${NEW_USER}: " public_key </dev/tty || {
      log_error "Unable to read SSH public key."
      exit 1
    }
    public_key="$(printf '%s' "${public_key}" | sed 's/[[:space:]]*$//')"
    if [[ -z "${public_key}" ]]; then
      echo "SSH public key cannot be blank." >/dev/tty
      continue
    fi
    case "${public_key}" in
      ssh-*|ecdsa-*)
        printf '%s\n' "${public_key}"
        return 0
        ;;
      *)
        echo "That does not look like a valid SSH public key." >/dev/tty
        ;;
    esac
  done
}

configure_ssh_access_keys() {
  detect_active_access_user

  case "${SSH_KEY_SOURCE}" in
    current-access)
      copy_authorized_keys_from_user "${ACTIVE_ACCESS_USER}" || true
      ;;
    admin)
      copy_authorized_keys_from_user "admin" || true
      ;;
    paste)
      append_public_key_if_missing "$(prompt_for_public_key)"
      ;;
    skip)
      log_warn "SSH key setup skipped. Ensure ${NEW_USER} already has working authorized_keys before restricting access."
      ;;
    *)
      log_warn "Unknown SSH key source '${SSH_KEY_SOURCE}'."
      ;;
  esac
}

apply_network_sysctl_hardening() {
  if [[ "${NEEDS_PENTEST_HARDENING}" != "true" ]]; then
    log_info "Optional network/sysctl hardening skipped."
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
  log_info "Applied network/sysctl hardening profile."
}

configure_fail2ban_sshd() {
  if ! systemd_available; then
    log_warn "systemd not detected; skipping fail2ban sshd jail configuration."
    return 0
  fi

  local jail_dir="/etc/fail2ban/jail.d"
  local jail_file="${jail_dir}/sshd.conf"

  mkdir -p "${jail_dir}"
  cat > "${jail_file}" <<'EOF'
[sshd]
enabled = true
port = ssh
backend = systemd
EOF
  chmod 0644 "${jail_file}"
  log_info "Configured fail2ban sshd jail at ${jail_file}."
}

ensure_network_access_prerequisites() {
  pacman_install_packages firewalld fail2ban curl
  enable_unit "firewalld.service" "firewalld" || true
  configure_fail2ban_sshd
  enable_unit "fail2ban.service" "fail2ban" || true
  append_installed_tool "firewalld"
  append_installed_tool "fail2ban"
}

install_tailscale() {
  if command_exists tailscale && command_exists tailscaled; then
    log_info "Tailscale already installed."
    return 0
  fi

  if curl -fsSL https://tailscale.com/install.sh | sh; then
    log_info "Installed Tailscale via the official installer."
    append_installed_tool "tailscale"
    return 0
  fi

  log_error "Failed to install Tailscale."
  return 1
}

ensure_tailscaled_running() {
  if ! enable_unit "tailscaled.service" "tailscaled"; then
    log_error "tailscaled service could not be enabled."
    return 1
  fi
  return 0
}

tailscale_session_active() {
  tailscale ip -4 >/dev/null 2>&1
}

initialize_tailscale_session() {
  if tailscale_session_active; then
    log_info "Tailscale session already active."
    return 0
  fi

  log_info "Running 'tailscale up'. Follow the interactive login URL from the official Tailscale flow."
  if tailscale up; then
    log_info "Tailscale session initialized."
    return 0
  fi

  log_warn "tailscale up did not complete successfully."
  return 1
}

prompt_for_ssh_hardening_confirmation() {
  local choice=""
  cat >/dev/tty <<EOF
Before ABB disables SSH password login and root SSH access, verify a second session works:
  ssh ${NEW_USER}@<host-or-ip>

Return here only after that succeeds with your SSH key.
EOF

  choice="$(prompt_pick_option "Apply SSH hardening now? " "later" yes later no)" || {
    log_warn "Unable to confirm SSH key validation; leaving SSH authentication unchanged."
    return 1
  }

  case "${choice}" in
    yes)
      return 0
      ;;
    later)
      log_info "Leaving SSH password/root access unchanged for now. Reconnect with the new user key, then rerun 'abb-setup.sh network-access'."
      exit 0
      ;;
    no)
      log_warn "SSH hardening skipped."
      return 1
      ;;
  esac

  return 1
}

sshd_supports_dropin_dir() {
  sshd -T >/dev/null 2>&1
}

write_sshd_hardening_dropin() {
  if ! command_exists sshd; then
    log_warn "sshd is not available; skipping SSH hardening."
    return 1
  fi

  if ! sshd_supports_dropin_dir; then
    log_warn "Unable to validate sshd configuration; skipping SSH hardening."
    return 1
  fi

  install -d -m 0755 "${SSHD_DROPIN_DIR}"
  cat > "${ABB_SSHD_HARDENING_FILE}" <<'EOF'
# Managed by ABB after SSH key verification.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
EOF
  chmod 0644 "${ABB_SSHD_HARDENING_FILE}"

  if ! sshd -t; then
    log_warn "sshd configuration test failed; removing ABB SSH hardening drop-in."
    rm -f "${ABB_SSHD_HARDENING_FILE}"
    return 1
  fi

  if systemd_available; then
    systemctl reload sshd.service >/dev/null 2>&1 || systemctl reload ssh.service >/dev/null 2>&1 || {
      log_warn "Unable to reload sshd automatically."
      return 1
    }
  fi

  log_info "Disabled SSH password authentication and root SSH login via ${ABB_SSHD_HARDENING_FILE}."
  return 0
}

disable_root_authorized_keys() {
  local root_keys="/root/.ssh/authorized_keys"
  local backup="/root/.ssh/authorized_keys.abb-disabled"

  if [[ ! -f "${root_keys}" ]]; then
    return 0
  fi
  if [[ -f "${backup}" ]]; then
    rm -f "${root_keys}"
    log_info "Root authorized_keys already archived."
    return 0
  fi

  mv "${root_keys}" "${backup}"
  chmod 0600 "${backup}" || true
  log_info "Archived root SSH authorized_keys to ${backup}."
  return 0
}

apply_verified_ssh_hardening() {
  if ! write_sshd_hardening_dropin; then
    return 1
  fi
  disable_root_authorized_keys || true
  return 0
}

show_tailscale_breakpoint() {
  local tailscale_ip="" choice=""

  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  cat >/dev/tty <<EOF
Tailscale is configured.

Before ABB closes public SSH, verify a second session works over Tailscale:
  ssh ${NEW_USER}@${tailscale_ip:-<tailscale-ip>}

Return here only after that succeeds.
EOF

  choice="$(prompt_pick_option "Proceed with public SSH lockdown now? " "later" yes later no)" || {
    log_warn "Unable to confirm Tailscale validation; leaving public SSH unchanged."
    return 1
  }

  case "${choice}" in
    yes)
      return 0
      ;;
    later)
      log_info "Leaving public SSH enabled for now. Reconnect over Tailscale, then rerun 'abb-setup.sh network-access' to finish lockdown."
      exit 0
      ;;
    no)
      log_warn "Public SSH will remain enabled."
      return 1
      ;;
  esac

  return 1
}

tailscale_lockdown_already_applied() {
  local zone=""

  if ! command_exists firewall-cmd; then
    return 1
  fi

  if ! firewall-cmd --permanent --zone=trusted --query-interface=tailscale0 >/dev/null 2>&1; then
    return 1
  fi
  if ! firewall-cmd --permanent --zone=trusted --query-service=ssh >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r zone; do
    [[ -z "${zone}" || "${zone}" == "trusted" ]] && continue
    if firewall-cmd --permanent --zone="${zone}" --query-service=ssh >/dev/null 2>&1; then
      return 1
    fi
  done < <(firewall-cmd --permanent --get-zones 2>/dev/null | tr ' ' '\n')

  return 0
}

restrict_public_ssh_to_tailscale() {
  local zone=""

  if tailscale_lockdown_already_applied; then
    log_info "Public SSH is already restricted to Tailscale."
    return 0
  fi

  if ! command_exists firewall-cmd; then
    log_warn "firewall-cmd not available; unable to restrict SSH to Tailscale safely."
    return 1
  fi

  firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 >/dev/null 2>&1 || true
  firewall-cmd --permanent --zone=trusted --add-service=ssh >/dev/null 2>&1 || true
  while IFS= read -r zone; do
    [[ -z "${zone}" || "${zone}" == "trusted" ]] && continue
    firewall-cmd --permanent --zone="${zone}" --remove-service=ssh >/dev/null 2>&1 || true
  done < <(firewall-cmd --permanent --get-zones 2>/dev/null | tr ' ' '\n')

  if firewall-cmd --reload >/dev/null 2>&1; then
    log_info "Restricted public SSH to the Tailscale interface."
    return 0
  fi

  log_warn "Failed to reload firewalld; review firewall rules before disconnecting."
  return 1
}

configure_plain_ssh_access() {
  log_info "Using plain SSH mode. Public SSH exposure remains unchanged."
  if prompt_for_ssh_hardening_confirmation; then
    apply_verified_ssh_hardening || true
  fi
}

configure_tailscale_ssh_access() {
  if ! install_tailscale; then
    return 1
  fi
  if ! ensure_tailscaled_running; then
    return 1
  fi
  if ! initialize_tailscale_session; then
    log_warn "Tailscale initialization did not complete. Public SSH remains unchanged."
    return 1
  fi
  append_installed_tool "tailscale"
  if show_tailscale_breakpoint; then
    restrict_public_ssh_to_tailscale || true
    apply_verified_ssh_hardening || true
  fi
}

run_task_network_access() {
  ensure_user_context
  ensure_package_manager_ready
  ensure_network_access_prerequisites
  configure_ssh_access_keys
  apply_network_sysctl_hardening

  case "${NETWORK_ACCESS_MODE}" in
    plain-ssh)
      configure_plain_ssh_access
      ;;
    tailscale-ssh)
      configure_tailscale_ssh_access
      ;;
    *)
      log_warn "Unknown network access mode '${NETWORK_ACCESS_MODE}'."
      ;;
  esac
}
