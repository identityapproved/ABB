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
    read -rp "Enable iptables-based SSH/VPN bypass? (yes/no): " choice </dev/tty || { log_error "Unable to read VPN bypass selection."; exit 1; }
    case "${choice,,}" in
      yes|y)
        VPN_BYPASS_MODE="iptables"
        ;;
      no|n|skip|none)
        VPN_BYPASS_MODE="none"
        ;;
      *)
        echo "Please answer yes or no." >/dev/tty
        ;;
    esac
  done
  log_info "VPN bypass mode set to ${VPN_BYPASS_MODE}"
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

run_task_vpn_bypass() {
  load_previous_answers
  prompt_for_vpn_bypass_mode
  record_prompt_answers

  case "${VPN_BYPASS_MODE}" in
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
