# shellcheck shell=bash

readonly WG_PROFILE_LIST="wireguard-profiles.txt"

ensure_wireguard_kernel() {
  local kernel_raw kernel_version compare_result
  kernel_raw="$(uname -r)"
  kernel_version="${kernel_raw%%-*}"
  if command_exists vercmp; then
    compare_result=$(vercmp "${kernel_version}" "5.11")
  else
    compare_result=$(printf '%s\n%s\n' "${kernel_version}" "5.11" | sort -V | head -n1)
    if [[ "${compare_result}" == "5.11" ]]; then
      compare_result=0
    elif [[ "${compare_result}" == "${kernel_version}" ]]; then
      compare_result=-1
    else
      compare_result=1
    fi
  fi

  if [[ "${compare_result}" == -1 ]]; then
    log_warn "Detected kernel ${kernel_raw}. Mullvad WireGuard recommends 5.11 or newer."
  else
    log_info "Kernel ${kernel_raw} meets Mullvad WireGuard requirements."
  fi
}

normalize_wireguard_profile() {
  local cfg="$1"
  local need_postup=1 need_predown=1 tmp
  if grep -Eq '^PostUp[[:space:]]*=[[:space:]]*ip rule add sport 22 lookup main' "${cfg}"; then
    need_postup=0
  fi
  if grep -Eq '^PreDown[[:space:]]*=[[:space:]]*ip rule delete sport 22 lookup main' "${cfg}"; then
    need_predown=0
  fi
  if ((need_postup == 0 && need_predown == 0)); then
    return
  fi
  tmp="$(mktemp)" || { log_warn "Unable to create temporary file while updating ${cfg}."; return; }
  awk -v need_postup="${need_postup}" -v need_predown="${need_predown}" '
    {
      print
      if ($0 ~ /^\[Interface\]/ && inserted == 0) {
        if (need_postup)  print "PostUp = ip rule add sport 22 lookup main"
        if (need_predown) print "PreDown = ip rule delete sport 22 lookup main"
        inserted = 1
      }
    }
    END {
      if (inserted == 0 && (need_postup || need_predown)) {
        print "[Interface]"
        if (need_postup)  print "PostUp = ip rule add sport 22 lookup main"
        if (need_predown) print "PreDown = ip rule delete sport 22 lookup main"
      }
    }
  ' "${cfg}" > "${tmp}"
  mv "${tmp}" "${cfg}"
  chmod 0600 "${cfg}" || true
}

update_vps_wireguard_rules() {
  shopt -s nullglob
  local configs=("/etc/wireguard/"*.conf)
  shopt -u nullglob
  if ((${#configs[@]} == 0)); then
    log_warn "No WireGuard configuration files detected when updating SSH-preserving rules."
    return
  fi
  for cfg in "${configs[@]}"; do
    normalize_wireguard_profile "${cfg}"
  done
  log_info "Ensured SSH-preserving PostUp/PreDown rules exist in /etc/wireguard profiles for VPS use."
}

write_wireguard_profile_inventory() {
  local user_home list_file
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_warn "Unable to determine home directory for ${NEW_USER}; skipping wireguard profile list."
    return
  fi
  list_file="${user_home}/${WG_PROFILE_LIST}"
  : > "${list_file}"

  shopt -s nullglob
  local configs=("/etc/wireguard/"*.conf)
  shopt -u nullglob
  if ((${#configs[@]} == 0)); then
    log_warn "No WireGuard configuration files detected in /etc/wireguard after mullvad-wg run."
    return
  fi

  for cfg in "${configs[@]}"; do
    local base
    base="$(basename "${cfg}")"
    printf '%s\n' "${base%.conf}" >> "${list_file}"
  done

  sort -u -o "${list_file}" "${list_file}"
  chown "${NEW_USER}:${NEW_USER}" "${list_file}" || true
  chmod 0644 "${list_file}" || true
  log_info "Recorded WireGuard profiles in ${list_file}."
}

run_mullvad_wg_script_once() {
  local script_tmp
  script_tmp="$(mktemp)" || { log_warn "Unable to allocate temporary file for mullvad-wg.sh."; return 1; }
  if ! curl -fsSL "https://raw.githubusercontent.com/mullvad/mullvad-wg.sh/main/mullvad-wg.sh" -o "${script_tmp}"; then
    log_warn "Failed to download mullvad-wg.sh."
    rm -f "${script_tmp}"
    return 1
  fi
  chmod 0755 "${script_tmp}"
  if "${script_tmp}"; then
    append_installed_tool "mullvad-wg"
    log_info "Executed mullvad-wg.sh to configure WireGuard profiles."
    rm -f "${script_tmp}"
    return 0
  fi
  log_warn "mullvad-wg.sh exited with a non-zero status. Review output above."
  rm -f "${script_tmp}"
  return 1
}

configure_mullvad_wireguard() {
  pacman_install_packages openresolv wireguard-tools
  ensure_wireguard_kernel
  run_mullvad_wg_script_once || true
  update_vps_wireguard_rules
  write_wireguard_profile_inventory
  log_info "WireGuard setup complete for the VPS host. Docker VPN configs are generated and rotated inside the dedicated container."
}

protonvpn_cli_installed() {
  run_as_user "pipx list 2>/dev/null | grep -Fq 'protonvpn-cli'" >/dev/null 2>&1
}

install_protonvpn_cli() {
  if ! command_exists pipx; then
    log_warn "pipx is not available yet. Run 'abb-setup.sh languages' before installing ProtonVPN CLI."
    return 1
  fi
  pacman_install_packages openvpn wireguard-tools openresolv dialog
  if protonvpn_cli_installed; then
    log_info "protonvpn-cli already installed for ${NEW_USER}."
  else
    if run_as_user "pipx install --force protonvpn-cli"; then
      log_info "Installed protonvpn-cli via pipx for ${NEW_USER}."
    else
      log_warn "pipx failed to install protonvpn-cli. Review pipx output and try again."
      return 1
    fi
  fi
  append_installed_tool "protonvpn-cli"
  return 0
}

summarize_protonvpn_next_steps() {
  cat <<'EOF'
ProtonVPN CLI was installed. Complete the initialization manually:
  1. Log in:   sudo protonvpn-cli login <username>
  2. Init:     sudo protonvpn-cli init
  3. Connect:  sudo protonvpn-cli connect --fastest
You can list servers with: protonvpn-cli list --countries
EOF
}

configure_protonvpn_cli() {
  if install_protonvpn_cli; then
    summarize_protonvpn_next_steps | while IFS= read -r line; do log_info "${line}"; done
  else
    log_warn "ProtonVPN CLI installation encountered issues."
  fi
}

run_task_vpn() {
  ensure_user_context
  ensure_package_manager_ready
  case "${VPN_PROVIDER}" in
    protonvpn)
      configure_protonvpn_cli
      ;;
    mullvad|"")
      configure_mullvad_wireguard
      ;;
    *)
      log_warn "VPN provider '${VPN_PROVIDER}' is not supported yet. Skipping VPN task."
      ;;
  esac
}
