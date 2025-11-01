# shellcheck shell=bash

prompt_for_vpn_bypass_mode() {
  local choice="" reuse=""
  if [[ -n "${VPN_BYPASS_MODE}" ]]; then
    while true; do
      read -rp "VPN bypass mode is currently '${VPN_BYPASS_MODE}'. Keep this selection? (yes/no): " reuse </dev/tty || { log_error "Unable to read VPN bypass confirmation."; exit 1; }
      case "${reuse,,}" in
        yes|y)
          return
          ;;
        no|n)
          VPN_BYPASS_MODE=""
          break
          ;;
        *)
          echo "Please answer yes or no." >/dev/tty
          ;;
      esac
    done
  fi

  while [[ -z "${VPN_BYPASS_MODE}" ]]; do
    read -rp "Select VPN bypass approach (mullvad/iptables/skip): " choice </dev/tty || { log_error "Unable to read VPN bypass selection."; exit 1; }
    case "${choice,,}" in
      mullvad)
        VPN_BYPASS_MODE="mullvad"
        ;;
      iptables)
        VPN_BYPASS_MODE="iptables"
        ;;
      skip|none)
        VPN_BYPASS_MODE="none"
        ;;
      *)
        echo "Valid options: mullvad, iptables, or skip." >/dev/tty
        ;;
    esac
  done
  log_info "VPN bypass mode set to ${VPN_BYPASS_MODE}"
}

configure_mullvad_bypass() {
  local -a candidates=("/usr/bin/sshd" "/usr/bin/ssh" "/usr/bin/pacman")
  local helper_path=""
  local entry=""
  declare -A seen=()

  if ! command_exists mullvad; then
    log_error "Mullvad CLI not detected. Run 'abb-setup.sh utilities' (with Mullvad enabled) before selecting this mode."
    return 1
  fi

  if ! enable_unit "mullvad-daemon.service" "Mullvad daemon"; then
    log_error "Unable to enable Mullvad daemon. Ensure the service is available and running."
    return 1
  fi

  local status_output=""
  status_output="$(mullvad status 2>/dev/null || true)"
  if grep -qi "not logged in" <<<"${status_output}"; then
    log_error "Mullvad CLI reports it is not logged in. Run 'mullvad account login <account-code>' and rerun the optional task."
    return 1
  fi

  if ! mullvad split-tunnel set on >/dev/null 2>&1; then
    log_error "Failed to enable Mullvad split tunneling. Ensure your account permits split-tunnel and rerun after 'mullvad account login <account-code>'."
    return 1
  fi

  if [[ -n "${PACKAGE_MANAGER}" ]]; then
    helper_path="$(command -v "${PACKAGE_MANAGER}" 2>/dev/null || true)"
    if [[ -n "${helper_path}" ]]; then
      candidates+=("${helper_path}")
    fi
  fi

  for entry in "${candidates[@]}"; do
    [[ ! -e "${entry}" ]] && continue
    if [[ -z "${seen[${entry}]}" ]]; then
      if mullvad split-tunnel add "${entry}" >/dev/null 2>&1; then
        log_info "Excluded ${entry} from Mullvad tunnel."
      else
        log_warn "Could not exclude ${entry}; it may already be configured."
      fi
      seen["${entry}"]=1
    fi
  done

  mullvad split-tunnel list || log_warn "Unable to list Mullvad split-tunnel configuration."
  if mullvad connect >/dev/null 2>&1; then
    log_info "Mullvad VPN connected."
  else
    log_warn "Unable to connect to Mullvad automatically. Run 'mullvad login' and 'mullvad connect' manually if required."
  fi
  if mullvad status >/dev/null 2>&1; then
    log_info "Mullvad status: $(mullvad status 2>/dev/null | head -n1)"
  else
    log_warn "Mullvad daemon responsive but not connected; authenticate with 'mullvad login' if required."
  fi
  log_info "Mullvad SSH bypass configuration completed."
  return 0
}

configure_iptables_bypass() {
  local ssh_port="" pub_iface="" pub_gateway="" service_file="/etc/systemd/system/ssh-vpn-bypass.service"

  pacman_install_packages iptables iproute2

  ssh_port="$(ss -ltnp | awk '/sshd/ {print $4}' | awk -F':' '{print $NF}' | head -n1)"
  [[ -z "${ssh_port}" ]] && ssh_port="22"
  log_info "Detected SSH port: ${ssh_port}"

  pub_iface="$(ip route | awk '/default/ {print $5}' | head -n1)"
  if [[ -z "${pub_iface}" ]]; then
    log_error "Unable to determine default network interface."
    return 1
  fi
  log_info "Detected default interface: ${pub_iface}"

  pub_gateway="$(ip route | awk '/default/ {print $3}' | head -n1)"
  if [[ -z "${pub_gateway}" ]]; then
    log_error "Unable to determine default gateway."
    return 1
  fi
  log_info "Detected default gateway: ${pub_gateway}"

  iptables -t mangle -D OUTPUT -p tcp --sport "${ssh_port}" -j MARK --set-mark "${ssh_port}" >/dev/null 2>&1 || true
  ip rule del fwmark "${ssh_port}" table 128 >/dev/null 2>&1 || true
  ip route flush table 128 >/dev/null 2>&1 || true

  if ! iptables -t mangle -A OUTPUT -p tcp --sport "${ssh_port}" -j MARK --set-mark "${ssh_port}"; then
    log_error "Failed to set iptables mark rule."
    return 1
  fi
  if ! ip rule add fwmark "${ssh_port}" table 128; then
    log_error "Failed to add policy routing rule."
    return 1
  fi
  if ! ip route add default via "${pub_gateway}" dev "${pub_iface}" table 128; then
    log_error "Failed to configure routing table 128."
    return 1
  fi

  mkdir -p /etc/iptables
  if iptables-save > /etc/iptables/iptables.rules; then
    enable_unit "iptables.service" "iptables persistence" || true
  else
    log_warn "Unable to persist iptables rules to /etc/iptables/iptables.rules."
  fi

  cat > "${service_file}" <<EOF
[Unit]
Description=Maintain SSH route bypass when VPN is active
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ip rule add fwmark ${ssh_port} table 128
ExecStart=/usr/bin/ip route add default via ${pub_gateway} dev ${pub_iface} table 128
ExecStop=/usr/bin/ip rule del fwmark ${ssh_port} table 128
ExecStop=/usr/bin/ip route flush table 128
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 "${service_file}"
  if systemd_available; then
    systemctl daemon-reload >/dev/null 2>&1 || log_warn "systemctl daemon-reload failed."
  else
    log_warn "systemd not detected; skipping daemon-reload for ssh-vpn-bypass."
  fi
  enable_unit "ssh-vpn-bypass.service" "ssh-vpn-bypass service" || true

  log_info "iptables-based SSH bypass configured. Verify with 'ip rule show' and 'ip route show table 128'."
  return 0
}

run_task_optional() {
  load_previous_answers
  prompt_for_vpn_bypass_mode
  record_prompt_answers

  case "${VPN_BYPASS_MODE}" in
    mullvad)
      if ! configure_mullvad_bypass; then
        log_error "Mullvad bypass configuration failed."
      fi
      ;;
    iptables)
      if ! configure_iptables_bypass; then
        log_error "iptables bypass configuration failed."
      fi
      ;;
    none)
      log_info "VPN bypass configuration skipped."
      ;;
    *)
      log_warn "Unknown VPN bypass mode '${VPN_BYPASS_MODE}'. Nothing to do."
      ;;
  esac
}
