# shellcheck shell=bash

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

add_wireguard_ssh_rules() {
  local cfg_dir="/etc/wireguard"
  local cfg
  local -a configs=()
  local user_home config_record

  if [[ ! -d "${cfg_dir}" ]]; then
    log_warn "WireGuard directory ${cfg_dir} not found; skip PostUp/PreDown updates."
    return
  fi

  shopt -s nullglob
  configs=("${cfg_dir}"/*.conf)
  shopt -u nullglob
  if ((${#configs[@]} == 0)); then
    log_warn "No WireGuard configuration files detected in ${cfg_dir}."
    return
  fi

  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  config_record="${user_home}/wireguard-profiles.txt"
  : > "${config_record}"

  for cfg in "${configs[@]}"; do
    local need_postup=1 need_predown=1 inserted=0 tmp
    if grep -Eq '^PostUp[[:space:]]*=[[:space:]]*ip rule add sport 22 lookup main' "${cfg}"; then
      need_postup=0
    fi
    if grep -Eq '^PreDown[[:space:]]*=[[:space:]]*ip rule delete sport 22 lookup main' "${cfg}"; then
      need_predown=0
    fi
    if ((need_postup == 0 && need_predown == 0)); then
      continue
    fi
    tmp="$(mktemp)" || { log_warn "Unable to create temporary file while updating ${cfg}."; continue; }
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
    if mv "${tmp}" "${cfg}"; then
      chmod 0600 "${cfg}" || true
      log_info "Updated SSH rules in ${cfg}."
    else
      log_warn "Failed to update ${cfg}."
      rm -f "${tmp}"
    fi
    printf '%s\n' "$(basename "${cfg}" .conf)" >> "${config_record}"
  done

  if [[ -n "${user_home}" ]]; then
    chown "${NEW_USER}:${NEW_USER}" "${config_record}" || true
    chmod 0644 "${config_record}" || true
    log_info "Wrote WireGuard profile list to ${config_record}."
  fi
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
  add_wireguard_ssh_rules
  log_info "WireGuard setup complete. Connect with 'sudo wg-quick up <config>' then verify via 'curl https://am.i.mullvad.net/json | jq'."
}

run_task_mullvad() {
  ensure_user_context
  ensure_package_manager_ready
  configure_mullvad_wireguard
}
