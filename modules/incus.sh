# shellcheck shell=bash

readonly INCUS_BRIDGE="incusbr0"
readonly INCUS_BRIDGE_CIDR="10.77.0.1/24"
readonly INCUS_POOL="default"
readonly DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

ensure_incus_idmap() {
  local file
  for file in /etc/subuid /etc/subgid; do
    if ! grep -q '^root:' "${file}" 2>/dev/null; then
      echo 'root:1000000:1000000000' >> "${file}"
      log_info "Added root id range to ${file} for Incus."
    fi
  done
}

ensure_incus_storage() {
  local driver="dir"
  incus storage show "${INCUS_POOL}" >/dev/null 2>&1 && { log_info "Incus storage pool ${INCUS_POOL} present."; return 0; }
  mkdir -p /var/lib/incus
  [[ "$(findmnt -no FSTYPE --target /var/lib/incus 2>/dev/null)" == "btrfs" ]] && driver="btrfs"
  if incus storage create "${INCUS_POOL}" "${driver}" source="/var/lib/incus/storage-pools/${INCUS_POOL}" >/dev/null; then
    log_info "Created Incus storage pool ${INCUS_POOL} (${driver})."
  else
    log_warn "Failed to create Incus storage pool ${INCUS_POOL}."
    return 1
  fi
}

ensure_incus_network() {
  incus network show "${INCUS_BRIDGE}" >/dev/null 2>&1 && { log_info "Incus network ${INCUS_BRIDGE} present."; return 0; }
  if ip route show to match "${INCUS_BRIDGE_CIDR%/*}" | grep -qv '^default'; then
    log_warn "${INCUS_BRIDGE_CIDR} overlaps an existing route; not creating ${INCUS_BRIDGE}."
    return 1
  fi
  if incus network create "${INCUS_BRIDGE}" ipv4.address="${INCUS_BRIDGE_CIDR}" ipv4.nat=true ipv6.address=none >/dev/null; then
    log_info "Created Incus network ${INCUS_BRIDGE} (${INCUS_BRIDGE_CIDR})."
  else
    log_warn "Failed to create Incus network ${INCUS_BRIDGE}."
    return 1
  fi
}

ensure_incus_profile() {
  local devices
  devices="$(incus profile device list default 2>/dev/null)"
  if ! grep -qx root <<<"${devices}"; then
    incus profile device add default root disk path=/ pool="${INCUS_POOL}" >/dev/null || log_warn "Failed to add root disk to Incus default profile."
  fi
  if ! grep -qx eth0 <<<"${devices}"; then
    incus profile device add default eth0 nic network="${INCUS_BRIDGE}" name=eth0 >/dev/null || log_warn "Failed to add eth0 to Incus default profile."
  fi
}

# Without this, firewalld drops the containers' DHCP and DNS to dnsmasq on the bridge.
ensure_incus_firewalld() {
  command_exists firewall-cmd || return 0
  systemctl is-active --quiet firewalld.service || { log_warn "firewalld inactive; put ${INCUS_BRIDGE} in the trusted zone once it runs."; return 0; }
  firewall-cmd --permanent --zone=trusted --query-interface="${INCUS_BRIDGE}" >/dev/null 2>&1 && return 0
  firewall-cmd --permanent --zone=trusted --add-interface="${INCUS_BRIDGE}" >/dev/null 2>&1 || { log_warn "Failed to add ${INCUS_BRIDGE} to the trusted zone."; return 1; }
  firewall-cmd --reload >/dev/null 2>&1 || log_warn "Failed to reload firewalld."
  log_info "Added ${INCUS_BRIDGE} to the firewalld trusted zone."
}

# Docker sets the iptables FORWARD policy to DROP, which blackholes Incus container traffic.
ensure_docker_forward_no_drop() {
  local tmp
  command_exists docker || return 0
  if [[ -f "${DOCKER_DAEMON_JSON}" ]] && jq -e '."ip-forward-no-drop" == true' "${DOCKER_DAEMON_JSON}" >/dev/null 2>&1; then
    log_info "Docker already keeps the FORWARD policy (ip-forward-no-drop)."
    return 0
  fi
  mkdir -p "$(dirname "${DOCKER_DAEMON_JSON}")"
  tmp="$(mktemp)"
  if [[ -s "${DOCKER_DAEMON_JSON}" ]]; then
    jq '. + {"ip-forward-no-drop": true}' "${DOCKER_DAEMON_JSON}" > "${tmp}" || { rm -f "${tmp}"; log_warn "Unable to parse ${DOCKER_DAEMON_JSON}; set ip-forward-no-drop manually."; return 1; }
  else
    printf '{\n  "ip-forward-no-drop": true\n}\n' > "${tmp}"
  fi
  install -m 0644 "${tmp}" "${DOCKER_DAEMON_JSON}"
  rm -f "${tmp}"
  log_warn "Restarting Docker to apply ip-forward-no-drop; running containers restart per their restart policy."
  systemctl restart docker.service || log_warn "Docker restart failed; review 'journalctl -u docker'."
  # A restart does not undo a DROP policy Docker already set.
  command_exists iptables && iptables -P FORWARD ACCEPT || true
  log_info "Docker no longer drops forwarded traffic."
}

install_incus() {
  [[ "${INSTALL_INCUS}" == "true" ]] || return 0
  pacman_install_packages incus
  ensure_incus_idmap
  enable_unit "incus.socket" "Incus socket" || true
  groupadd -f incus-admin >/dev/null 2>&1 || true
  if usermod -aG incus-admin "${NEW_USER}" >/dev/null 2>&1; then
    log_info "Added ${NEW_USER} to incus-admin (takes effect on next login)."
  else
    log_warn "Failed to add ${NEW_USER} to incus-admin."
  fi
  if ! incus info >/dev/null 2>&1; then
    log_warn "Incus daemon not reachable; skipping storage/network/profile setup."
    return 0
  fi
  ensure_incus_storage || true
  ensure_incus_network || true
  ensure_incus_profile
  ensure_incus_firewalld || true
  ensure_docker_forward_no_drop || true
  append_installed_tool "incus"
}
