# shellcheck shell=bash

ACTIVE_ACCESS_USER=""
readonly SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
readonly ABB_SSHD_HARDENING_FILE="${SSHD_DROPIN_DIR}/50-abb-hardening.conf"
readonly ABB_SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
readonly ABB_SSHD_BLOCK_BEGIN="# ABB SSH hardening begin"
readonly ABB_SSHD_BLOCK_END="# ABB SSH hardening end"

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

managed_authorized_keys_file() {
  local target_home=""
  target_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${target_home}" ]]; then
    return 1
  fi
  printf '%s\n' "${target_home}/.ssh/authorized_keys"
}

managed_user_has_authorized_keys() {
  local target_file=""
  target_file="$(managed_authorized_keys_file)" || return 1
  [[ -s "${target_file}" ]]
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
      if ! copy_authorized_keys_from_user "${ACTIVE_ACCESS_USER}"; then
        log_error "Unable to seed SSH keys from ${ACTIVE_ACCESS_USER}. Use 'paste' or 'admin' instead."
        return 1
      fi
      ;;
    admin)
      if ! copy_authorized_keys_from_user "admin"; then
        log_error "Unable to seed SSH keys from admin."
        return 1
      fi
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

  if [[ "${SSH_KEY_SOURCE}" != "skip" ]] && ! managed_user_has_authorized_keys; then
    log_error "No authorized_keys were staged for ${NEW_USER}. Refusing to continue with SSH hardening."
    return 1
  fi

  return 0
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


readonly ABB_SSHD_PORT_FILE="${SSHD_DROPIN_DIR}/40-abb-port.conf"
readonly ABB_TS_REVERT_UNIT="abb-ts-ssh-revert"
readonly ABB_TS_SWITCH_UNIT="abb-ts-ssh-off"

# Ports sshd must listen on this run: the chosen one, plus the current ones while a change is unconfirmed.
ABB_SSH_PORTS=()
ABB_SSH_PORT_CHANGE_PENDING="false"

sshd_effective_ports() {
  # OpenSSH 10.x prints keywords CamelCase (Port, AllowUsers); match case-insensitively.
  sshd -T 2>/dev/null | awk 'tolower($1) == "port" { print $2 }' | sort -un
}

join_by_comma() {
  local IFS=,
  printf '%s\n' "$*"
}

reload_sshd() {
  if systemd_available; then
    systemctl reload sshd.service >/dev/null 2>&1 || systemctl reload ssh.service >/dev/null 2>&1 || return 1
  fi
  return 0
}

configure_fail2ban_sshd() {
  if ! systemd_available; then
    log_warn "systemd not detected; skipping fail2ban sshd jail configuration."
    return 0
  fi

  local jail_dir="/etc/fail2ban/jail.d"
  local jail_file="${jail_dir}/sshd.conf"
  local -a ports=("$@")
  ((${#ports[@]})) || ports=("${SSH_PORT:-22}")

  mkdir -p "${jail_dir}"
  cat > "${jail_file}" <<EOF
[sshd]
enabled = true
port = $(join_by_comma "${ports[@]}")
backend = systemd
EOF
  chmod 0644 "${jail_file}"
  if systemctl is-active --quiet fail2ban.service; then
    systemctl restart fail2ban.service >/dev/null 2>&1 || log_warn "Unable to restart fail2ban after updating ${jail_file}."
  fi
  log_info "Configured fail2ban sshd jail at ${jail_file} (ports ${ports[*]})."
}

ensure_network_access_prerequisites() {
  pacman_install_packages firewalld fail2ban curl
  enable_unit "firewalld.service" "firewalld" || true
  enable_unit "fail2ban.service" "fail2ban" || true
  append_installed_tool "firewalld"
  append_installed_tool "fail2ban"
}

plan_ssh_ports() {
  local desired="${SSH_PORT:-22}" port=""
  local -a current=()

  mapfile -t current < <(sshd_effective_ports)
  ((${#current[@]} == 0)) && current=(22)

  if [[ "${#current[@]}" -eq 1 && "${current[0]}" == "${desired}" ]]; then
    ABB_SSH_PORTS=("${desired}")
    ABB_SSH_PORT_CHANGE_PENDING="false"
    return 0
  fi

  ABB_SSH_PORTS=("${desired}")
  for port in "${current[@]}"; do
    [[ "${port}" != "${desired}" ]] && ABB_SSH_PORTS+=("${port}")
  done
  ABB_SSH_PORT_CHANGE_PENDING="true"
  log_info "SSH port change pending: sshd listens on ${current[*]}, target ${desired}. Both stay open until a session on ${desired} is confirmed."
}

write_sshd_port_dropin() {
  local port=""

  if ! command_exists sshd || ! sshd_supports_dropin_dir; then
    log_warn "Unable to validate sshd configuration; leaving SSH port unchanged."
    return 1
  fi

  install -d -m 0755 "${SSHD_DROPIN_DIR}"
  {
    echo "# Managed by ABB network-access (SSH_PORT)."
    for port in "${ABB_SSH_PORTS[@]}"; do
      echo "Port ${port}"
    done
  } > "${ABB_SSHD_PORT_FILE}"
  chmod 0644 "${ABB_SSHD_PORT_FILE}"

  if ! sshd -t; then
    log_warn "sshd rejected ${ABB_SSHD_PORT_FILE}; removing it."
    rm -f "${ABB_SSHD_PORT_FILE}"
    return 1
  fi
  reload_sshd || { log_warn "Unable to reload sshd after writing ${ABB_SSHD_PORT_FILE}."; return 1; }

  if [[ "$(sshd_effective_ports | sort -n | tr '\n' ' ')" != "$(printf '%s\n' "${ABB_SSH_PORTS[@]}" | sort -un | tr '\n' ' ')" ]]; then
    log_warn "sshd listens on $(sshd_effective_ports | tr '\n' ' '), expected ${ABB_SSH_PORTS[*]}. An uncommented Port line in ${ABB_SSHD_CONFIG_FILE} adds to the drop-in; remove it."
    return 1
  fi
  log_info "sshd ports: ${ABB_SSH_PORTS[*]}"
  return 0
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

tailscale_runssh_enabled() {
  tailscale debug prefs 2>/dev/null | grep -Eq '"RunSSH":[[:space:]]*true'
}

wanted_tailscale_ssh() {
  if [[ "${NETWORK_ACCESS_MODE}" == "tailscale-ssh" ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

# A Tailscale SSH login has tailscaled as an ancestor instead of sshd.
session_served_by_tailscaled() {
  local pid="$$" comm=""

  while [[ -n "${pid}" && "${pid}" -gt 1 ]]; do
    comm="$(ps -o comm= -p "${pid}" 2>/dev/null | tr -d '[:space:]')"
    [[ "${comm}" == "tailscaled" ]] && return 0
    [[ "${comm}" == "sshd" || "${comm}" == sshd-* ]] && return 1
    pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d '[:space:]')"
  done
  return 1
}

tailscale_revert_armed() {
  systemctl is-active --quiet "${ABB_TS_REVERT_UNIT}.timer" 2>/dev/null
}

disarm_tailscale_revert() {
  systemctl stop "${ABB_TS_REVERT_UNIT}.timer" >/dev/null 2>&1 || true
  systemctl reset-failed "${ABB_TS_REVERT_UNIT}.service" >/dev/null 2>&1 || true
}

confirm_openssh_over_tailnet() {
  local tailscale_ip="" choice="" ts_bin=""

  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  ts_bin="$(command -v tailscale)"
  cat >/dev/tty <<EOF
Tailscale SSH is off; sshd now answers on the tailnet. From a second terminal:
  ssh -v -p ${SSH_PORT:-22} ${NEW_USER}@${tailscale_ip:-<tailscale-ip>} true
It must show "remote software version OpenSSH_" and "Authenticated ... publickey".
A key that Tailscale SSH never needed may have a passphrase you no longer know;
check it first with: ssh-keygen -y -f <key> >/dev/null   (or ssh-add it).
An automatic undo (${ABB_TS_REVERT_UNIT}) turns Tailscale SSH back on unless you confirm.
EOF

  choice="$(prompt_pick_option "Did the OpenSSH session work? " "no" yes no)" || choice="no"
  if [[ "${choice}" == "yes" ]]; then
    disarm_tailscale_revert
    log_info "OpenSSH over the tailnet confirmed; automatic undo disarmed."
    return 0
  fi

  "${ts_bin}" set --ssh=true || log_warn "Unable to re-enable Tailscale SSH; the ${ABB_TS_REVERT_UNIT} timer still will."
  disarm_tailscale_revert
  log_warn "Tailscale SSH re-enabled. Fix sshd/key access, then rerun 'abb-setup.sh network-access'."
  return 1
}

# Tailworm: turning Tailscale SSH off moves logins to sshd; armed with a timed undo so a bad key cannot lock the box.
switch_tailscale_ssh_off_safely() {
  local ts_bin="" tailscale_ip=""

  ts_bin="$(command -v tailscale)"
  if ! systemd_available || ! command_exists systemd-run; then
    log_warn "systemd-run unavailable; refusing to turn Tailscale SSH off without an automatic undo."
    return 1
  fi
  if ! systemctl is-active --quiet sshd.service; then
    log_warn "sshd is not running; leaving Tailscale SSH on."
    return 1
  fi
  if ! managed_user_has_authorized_keys; then
    log_warn "${NEW_USER} has no authorized_keys; leaving Tailscale SSH on."
    return 1
  fi

  disarm_tailscale_revert
  systemd-run --quiet --unit="${ABB_TS_REVERT_UNIT}" --on-active=10min "${ts_bin}" set --ssh=true || {
    log_warn "Unable to arm the automatic undo; leaving Tailscale SSH on."
    return 1
  }

  if session_served_by_tailscaled; then
    schedule_tailscale_ssh_off "${ts_bin}"
    return 1
  fi

  # tailscale refuses (lose-ssh) when this session is Tailscale SSH but the process chain hid it, e.g. inside tmux.
  local out=""
  if ! out="$("${ts_bin}" set --ssh=false 2>&1)"; then
    if grep -q 'lose-ssh' <<<"${out}"; then
      schedule_tailscale_ssh_off "${ts_bin}"
    fi
    disarm_tailscale_revert
    log_warn "tailscale set --ssh=false failed: ${out}"
    return 1
  fi
  confirm_openssh_over_tailnet
}

schedule_tailscale_ssh_off() {
  local ts_bin="$1" tailscale_ip=""

  systemctl stop "${ABB_TS_SWITCH_UNIT}.timer" >/dev/null 2>&1 || true
  systemctl reset-failed "${ABB_TS_SWITCH_UNIT}.service" >/dev/null 2>&1 || true
  systemd-run --quiet --unit="${ABB_TS_SWITCH_UNIT}" --on-active=20s "${ts_bin}" set --ssh=false --accept-risk=lose-ssh || {
    disarm_tailscale_revert
    log_warn "Unable to schedule the switch; leaving Tailscale SSH on."
    return 1
  }
  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  cat >/dev/tty <<EOF
This session runs over Tailscale SSH and will drop in about 20 seconds, when
Tailscale SSH is turned off (tmux sessions keep running, the connection does not).
Then reconnect through sshd:
  ssh -v -p ${SSH_PORT:-22} ${NEW_USER}@${tailscale_ip:-<tailscale-ip>}
It must show "remote software version OpenSSH_". Then rerun
'sudo ./abb-setup.sh network-access' within 10 minutes to confirm.
Without that, ${ABB_TS_REVERT_UNIT} turns Tailscale SSH back on.
EOF
  exit 0
}

initialize_tailscale_session() {
  local want=""
  want="$(wanted_tailscale_ssh)"

  if [[ "${want}" == "true" ]]; then
    log_warn "${TAILWORM_NOTE}"
  fi

  if ! tailscale_session_active; then
    log_info "Running 'tailscale up --ssh=${want}'. Follow the interactive login URL from the official Tailscale flow."
    if tailscale up --ssh="${want}"; then
      log_info "Tailscale session initialized (Tailscale SSH: ${want})."
      return 0
    fi
    log_warn "tailscale up --ssh=${want} did not complete successfully."
    return 1
  fi

  if [[ "${want}" == "true" ]]; then
    tailscale_runssh_enabled || tailscale set --ssh=true || return 1
    log_info "Tailscale session active with Tailscale SSH enabled."
    return 0
  fi

  if tailscale_runssh_enabled; then
    switch_tailscale_ssh_off_safely
    return
  fi
  if tailscale_revert_armed; then
    confirm_openssh_over_tailnet
    return
  fi
  log_info "Tailscale session active; Tailscale SSH off, sshd serves the tailnet."
  return 0
}

prompt_for_ssh_hardening_confirmation() {
  local choice=""
  cat >/dev/tty <<EOF
Before ABB disables SSH password login and root SSH access, verify a second session works:
  ssh -p ${SSH_PORT:-22} ${NEW_USER}@<host-or-ip>

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

sshd_effective_value() {
  local key="$1"
  sshd -T 2>/dev/null | awk -v key="${key}" 'tolower($1) == tolower(key) { print $2; exit }'
}

sshd_forwarding_value() {
  if [[ "${SSH_FORWARDING}" == "true" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

sshd_hardening_lines() {
  local fwd=""
  fwd="$(sshd_forwarding_value)"
  cat <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
AllowUsers ${NEW_USER}
AllowTcpForwarding ${fwd}
AllowStreamLocalForwarding ${fwd}
AllowAgentForwarding ${fwd}
X11Forwarding ${fwd}
EOF
}

sshd_hardening_is_effective() {
  local fwd=""
  fwd="$(sshd_forwarding_value)"
  [[ "$(sshd_effective_value passwordauthentication)" == "no" ]] || return 1
  [[ "$(sshd_effective_value kbdinteractiveauthentication)" == "no" ]] || return 1
  [[ "$(sshd_effective_value permitrootlogin)" == "no" ]] || return 1
  [[ "$(sshd_effective_value allowusers)" == "${NEW_USER}" ]] || return 1
  [[ "$(sshd_effective_value allowtcpforwarding)" == "${fwd}" ]] || return 1
  [[ "$(sshd_effective_value allowstreamlocalforwarding)" == "${fwd}" ]] || return 1
  return 0
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
  {
    echo "# Managed by ABB after SSH key verification."
    sshd_hardening_lines
  } > "${ABB_SSHD_HARDENING_FILE}"
  chmod 0644 "${ABB_SSHD_HARDENING_FILE}"

  if ! sshd -t; then
    log_warn "sshd configuration test failed; removing ABB SSH hardening drop-in."
    rm -f "${ABB_SSHD_HARDENING_FILE}"
    return 1
  fi

  reload_sshd || { log_warn "Unable to reload sshd automatically."; return 1; }

  log_info "Applied SSH hardening via ${ABB_SSHD_HARDENING_FILE} (key-only, no root, AllowUsers ${NEW_USER}, forwarding $(sshd_forwarding_value))."
  return 0
}

write_sshd_hardening_main_config() {
  local tmp_file

  if [[ ! -f "${ABB_SSHD_CONFIG_FILE}" ]]; then
    log_warn "Missing ${ABB_SSHD_CONFIG_FILE}; unable to apply SSH hardening fallback."
    return 1
  fi

  tmp_file="$(mktemp)" || {
    log_warn "Unable to create temporary file for sshd_config fallback."
    return 1
  }

  awk -v begin="${ABB_SSHD_BLOCK_BEGIN}" -v end="${ABB_SSHD_BLOCK_END}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "${ABB_SSHD_CONFIG_FILE}" > "${tmp_file}"

  {
    echo
    echo "${ABB_SSHD_BLOCK_BEGIN}"
    sshd_hardening_lines
    echo "${ABB_SSHD_BLOCK_END}"
  } >> "${tmp_file}"

  if ! sshd -t -f "${tmp_file}"; then
    log_warn "sshd_config fallback validation failed."
    rm -f "${tmp_file}"
    return 1
  fi

  cat "${tmp_file}" > "${ABB_SSHD_CONFIG_FILE}"
  chmod 0600 "${ABB_SSHD_CONFIG_FILE}" || true
  rm -f "${tmp_file}"

  reload_sshd || { log_warn "Unable to reload sshd after main-config hardening fallback."; return 1; }

  log_info "Applied SSH hardening fallback directly in ${ABB_SSHD_CONFIG_FILE}."
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
  if ! sshd_hardening_is_effective; then
    log_warn "SSH hardening drop-in is not taking effect; applying fallback in ${ABB_SSHD_CONFIG_FILE}."
    write_sshd_hardening_main_config || return 1
  fi
  if ! sshd_hardening_is_effective; then
    log_warn "SSH hardening still is not effective after fallback."
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
  ssh -p ${SSH_PORT:-22} ${NEW_USER}@${tailscale_ip:-<tailscale-ip>}

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
      log_warn "Public SSH stays enabled for this run. Set PUBLIC_SSH_LOCKDOWN=false in ${ANSWERS_FILE} to keep it open permanently."
      return 1
      ;;
  esac

  return 1
}

ssh_reject_rule() {
  printf 'rule family="ipv4" port port="%s" protocol="tcp" reject\n' "$1"
}

non_trusted_zones() {
  firewall-cmd --permanent --get-zones 2>/dev/null | tr ' ' '\n' | grep -vx -e '' -e trusted
}

tailscale_lockdown_already_applied() {
  local zone="" port=""

  command_exists firewall-cmd || return 1
  firewall-cmd --permanent --zone=trusted --query-interface=tailscale0 >/dev/null 2>&1 || return 1

  while IFS= read -r zone; do
    firewall-cmd --permanent --zone="${zone}" --query-service=ssh >/dev/null 2>&1 && return 1
    for port in "${ABB_SSH_PORTS[@]}"; do
      firewall-cmd --permanent --zone="${zone}" --query-port="${port}/tcp" >/dev/null 2>&1 && return 1
      firewall-cmd --permanent --zone="${zone}" --query-rich-rule="$(ssh_reject_rule "${port}")" >/dev/null 2>&1 || return 1
    done
  done < <(non_trusted_zones)

  return 0
}

restrict_public_ssh_to_tailscale() {
  local zone="" port=""

  if tailscale_lockdown_already_applied; then
    log_info "Public SSH is already restricted to Tailscale (ports ${ABB_SSH_PORTS[*]})."
    return 0
  fi

  if ! command_exists firewall-cmd; then
    log_warn "firewall-cmd not available; unable to restrict SSH to Tailscale safely."
    return 1
  fi

  # tailscale0 sits in the trusted zone, which accepts every port, so sshd on any port stays reachable over the tailnet.
  firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 >/dev/null 2>&1 || true
  while IFS= read -r zone; do
    firewall-cmd --permanent --zone="${zone}" --remove-service=ssh >/dev/null 2>&1 || true
    for port in "${ABB_SSH_PORTS[@]}"; do
      firewall-cmd --permanent --zone="${zone}" --remove-port="${port}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --permanent --zone="${zone}" --add-rich-rule="$(ssh_reject_rule "${port}")" >/dev/null 2>&1 || true
    done
  done < <(non_trusted_zones)

  if firewall-cmd --reload >/dev/null 2>&1; then
    if tailscale_lockdown_already_applied; then
      log_info "Restricted SSH access to the Tailscale interface."
      return 0
    fi
    log_warn "firewalld reloaded, but SSH still appears exposed outside Tailscale."
    return 1
  fi

  log_warn "Failed to reload firewalld; review firewall rules before disconnecting."
  return 1
}

open_public_ssh() {
  local zone="" port="" default_zone=""

  if ! command_exists firewall-cmd; then
    log_warn "firewall-cmd not available; public SSH ports are not managed."
    return 1
  fi

  default_zone="$(firewall-cmd --get-default-zone 2>/dev/null)"
  while IFS= read -r zone; do
    for port in "${ABB_SSH_PORTS[@]}"; do
      firewall-cmd --permanent --zone="${zone}" --remove-rich-rule="$(ssh_reject_rule "${port}")" >/dev/null 2>&1 || true
    done
  done < <(non_trusted_zones)
  for port in "${ABB_SSH_PORTS[@]}"; do
    if [[ "${port}" == "22" ]]; then
      firewall-cmd --permanent --zone="${default_zone}" --add-service=ssh >/dev/null 2>&1 || true
    else
      firewall-cmd --permanent --zone="${default_zone}" --add-port="${port}/tcp" >/dev/null 2>&1 || true
    fi
  done

  firewall-cmd --reload >/dev/null 2>&1 || { log_warn "Failed to reload firewalld."; return 1; }
  log_info "Public SSH open in zone ${default_zone} on ports ${ABB_SSH_PORTS[*]}."
  return 0
}

# After the new port is confirmed: drop the old ones from firewalld (the reject rules for them stay, harmless).
close_old_ssh_ports() {
  local zone="" port="" desired="${SSH_PORT:-22}"
  command_exists firewall-cmd || return 0

  while IFS= read -r zone; do
    for port in "$@"; do
      [[ "${port}" == "${desired}" ]] && continue
      firewall-cmd --permanent --zone="${zone}" --remove-port="${port}/tcp" >/dev/null 2>&1 || true
      [[ "${port}" == "22" ]] && firewall-cmd --permanent --zone="${zone}" --remove-service=ssh >/dev/null 2>&1 || true
    done
  done < <(non_trusted_zones)
  firewall-cmd --reload >/dev/null 2>&1 || log_warn "Failed to reload firewalld after closing old SSH ports."
}

apply_ssh_firewall() {
  if tailscale_access_mode && [[ "${PUBLIC_SSH_LOCKDOWN}" == "true" ]]; then
    if tailscale_lockdown_already_applied; then
      restrict_public_ssh_to_tailscale
      return
    fi
    show_tailscale_breakpoint || return 1
    restrict_public_ssh_to_tailscale
    return
  fi
  open_public_ssh
}

finish_ssh_port_change() {
  local choice="" desired="${SSH_PORT:-22}" host_hint="<host-or-ip>"
  local -a old_ports=()

  [[ "${ABB_SSH_PORT_CHANGE_PENDING}" == "true" ]] || return 0
  old_ports=("${ABB_SSH_PORTS[@]:1}")
  tailscale_access_mode && host_hint="$(tailscale ip -4 2>/dev/null | head -n1 || echo '<tailscale-ip>')"

  cat >/dev/tty <<EOF
sshd now listens on ${ABB_SSH_PORTS[*]}. From a second terminal:
  ssh -p ${desired} ${NEW_USER}@${host_hint} true
Update the client too (Port ${desired} in ~/.ssh/config). Port(s) ${old_ports[*]} close only after you confirm.
EOF
  choice="$(prompt_pick_option "Did the session on port ${desired} work? " "later" yes later)" || choice="later"
  if [[ "${choice}" != "yes" ]]; then
    log_info "Old SSH port(s) ${old_ports[*]} stay open. Rerun 'abb-setup.sh network-access' after testing port ${desired}."
    return 0
  fi

  ABB_SSH_PORTS=("${desired}")
  ABB_SSH_PORT_CHANGE_PENDING="false"
  write_sshd_port_dropin || return 1
  configure_fail2ban_sshd "${desired}"
  close_old_ssh_ports "${old_ports[@]}"
  log_info "SSH moved to port ${desired}; closed ${old_ports[*]}."
  if [[ "${USE_VPN}" == "true" ]]; then
    log_warn "VPN profiles still carry 'sport ${old_ports[*]}' rules. Rerun 'abb-setup.sh vpn' and restart the tunnel (or ssh-bypass.sh setup) so replies on port ${desired} leave via the main table."
  fi
}

configure_plain_ssh_access() {
  log_info "Using plain SSH mode (public sshd)."
  open_public_ssh || true
  if sshd_hardening_is_effective || prompt_for_ssh_hardening_confirmation; then
    apply_verified_ssh_hardening || true
  fi
}

configure_tailscale_access() {
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
  if ! apply_ssh_firewall; then
    log_warn "SSH firewall changes did not complete. Public SSH may still be reachable."
    return 1
  fi
  # With lockdown the breakpoint (or an earlier run) already proved a second session; otherwise ask as plain-ssh does.
  if [[ "${PUBLIC_SSH_LOCKDOWN}" == "true" ]] || sshd_hardening_is_effective || prompt_for_ssh_hardening_confirmation; then
    if ! apply_verified_ssh_hardening; then
      log_warn "SSH hardening did not complete after Tailscale verification."
      return 1
    fi
  fi
}

run_task_network_access() {
  ensure_user_context
  ensure_package_manager_ready
  ensure_network_access_prerequisites
  if ! configure_ssh_access_keys; then
    exit 1
  fi
  apply_network_sysctl_hardening

  plan_ssh_ports
  write_sshd_port_dropin || log_warn "SSH port drop-in not applied; continuing on the current port."
  configure_fail2ban_sshd "${ABB_SSH_PORTS[@]}"

  case "${NETWORK_ACCESS_MODE}" in
    plain-ssh)
      configure_plain_ssh_access
      ;;
    tailscale-sshd|tailscale-ssh)
      configure_tailscale_access
      ;;
    *)
      log_warn "Unknown network access mode '${NETWORK_ACCESS_MODE}'."
      ;;
  esac

  finish_ssh_port_change
}
