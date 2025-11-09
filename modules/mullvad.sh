# shellcheck shell=bash

readonly WG_ROOT="/opt/wg-configs"
readonly WG_SOURCE_DIR="${WG_ROOT}/source"
readonly WG_POOL_DIR="${WG_ROOT}/pool"
readonly WG_ACTIVE_DIR="${WG_ROOT}/active"

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

copy_wireguard_profiles() {
  local user_home list_file default_profile=""
  user_home="$(getent passwd "${NEW_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    log_warn "Unable to determine home directory for ${NEW_USER}; skipping wireguard profile export."
    return
  }
  list_file="${user_home}/wireguard-profiles.txt"

  install -d -m 0755 "${WG_SOURCE_DIR}" "${WG_POOL_DIR}" "${WG_ACTIVE_DIR}"
  : > "${list_file}"

  shopt -s nullglob
  local configs=("/etc/wireguard/"*.conf)
  shopt -u nullglob
  if ((${#configs[@]} == 0)); then
    log_warn "No WireGuard configuration files detected in /etc/wireguard."
    return
  fi

  for cfg in "${configs[@]}"; do
    local base
    base="$(basename "${cfg}")"
    cp -f "${cfg}" "${WG_SOURCE_DIR}/${base}"
    cp -f "${WG_SOURCE_DIR}/${base}" "${WG_POOL_DIR}/${base}"
    normalize_wireguard_profile "${WG_POOL_DIR}/${base}"
    printf '%s\n' "${base%.conf}" >> "${list_file}"
    [[ -z "${default_profile}" ]] && default_profile="${base}"
  done

  if [[ -n "${default_profile}" ]]; then
    cp -f "${WG_POOL_DIR}/${default_profile}" "${WG_ACTIVE_DIR}/wg0.conf"
    chmod 0600 "${WG_ACTIVE_DIR}/wg0.conf" || true
  fi

  sort -u -o "${list_file}" "${list_file}"
  chown "${NEW_USER}:${NEW_USER}" "${list_file}" || true
  chmod 0644 "${list_file}" || true
  log_info "Staged WireGuard profiles under ${WG_ROOT} (originals preserved in ${WG_SOURCE_DIR})."
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
  copy_wireguard_profiles
  log_info "WireGuard setup complete. Connect with 'sudo wg-quick up <config>' then verify via 'curl https://am.i.mullvad.net/json | jq'."
}

run_task_mullvad() {
  ensure_user_context
  ensure_package_manager_ready
  configure_mullvad_wireguard
}
