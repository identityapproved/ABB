# shellcheck shell=bash

sanitize_vpn_bypass_mode() {
  case "${VPN_BYPASS_MODE}" in
    iptables|none)
      return
      ;;
    *)
      VPN_BYPASS_MODE=""
      ;;
  esac
}

prompt_for_vpn_bypass_mode() {
  local choice="" reuse=""
  sanitize_vpn_bypass_mode
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
  local -a required_modules=("ip_tables" "iptable_filter" "iptable_mangle" "iptable_nat")

  pacman_install_packages iptables iproute2

  if ! iptables -t mangle -L >/dev/null 2>&1; then
    if command_exists modprobe; then
      local module=""
      for module in "${required_modules[@]}"; do
        local already_loaded=0
        if command_exists lsmod && lsmod | awk '{print $1}' | grep -qx "${module}"; then
          already_loaded=1
        fi
        if ((already_loaded == 0)); then
          if modprobe "${module}" >/dev/null 2>&1; then
            log_info "Loaded kernel module ${module}."
          else
            log_warn "Unable to load kernel module ${module}; iptables mangle table may remain unavailable."
          fi
        fi
      done
    else
      log_warn "modprobe not available; cannot auto-load iptables kernel modules."
    fi
  fi

  if ! iptables -t mangle -L >/dev/null 2>&1; then
    log_error "iptables mangle table unavailable. Load the iptable_mangle module (e.g., 'sudo modprobe iptable_mangle') or ensure iptables-nft is installed/enabled, then rerun this task."
    return 1
  fi

  ssh_port="$(ss -ltnp | awk '/sshd/ {print $4}' | awk -F':' '{print $NF}' | head -n1)"
  [[ -z "${ssh_port}" ]] && ssh_port="22"
  log_info "Detected SSH port: ${ssh_port}"

  local mark_hex
  mark_hex="$(printf '0x%x' "${ssh_port}")"

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

  while iptables -t mangle -D OUTPUT -p tcp --sport "${ssh_port}" -j MARK --set-mark "${ssh_port}" >/dev/null 2>&1; do
    log_info "Removed existing iptables mark rule for SSH port ${ssh_port}."
  done
  while ip rule del fwmark "${ssh_port}" table 128 >/dev/null 2>&1; do
    log_info "Removed existing fwmark ${mark_hex} rule from table 128."
  done
  ip route flush table 128 >/dev/null 2>&1 || true

  local iptables_err_file
  iptables_err_file="$(mktemp)"
  if ! iptables -t mangle -A OUTPUT -p tcp --sport "${ssh_port}" -j MARK --set-mark "${ssh_port}" 2>"${iptables_err_file}"; then
    local iptables_err=""
    iptables_err="$(<"${iptables_err_file}")"
    rm -f "${iptables_err_file}"
    log_error "Failed to set iptables mark rule. Details: ${iptables_err}"
    log_error "Ensure iptable_mangle is loaded and the kernel supports iptables (legacy or nft)."
    return 1
  fi
  rm -f "${iptables_err_file}"
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
ExecStart=/usr/bin/ip rule replace fwmark ${ssh_port} table 128
ExecStart=/usr/bin/ip route replace default via ${pub_gateway} dev ${pub_iface} table 128
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
