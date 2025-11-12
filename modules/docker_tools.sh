# shellcheck shell=bash

DOCKER_ASSETS_DIR="/opt/abb-docker"

sync_docker_assets() {
  if [[ ! -d "${REPO_ROOT}/docker" ]]; then
    log_warn "Docker assets directory not found in repository."
    return 1
  fi
  install -d -m 0755 "${DOCKER_ASSETS_DIR}"
  rsync -a --delete "${REPO_ROOT}/docker/" "${DOCKER_ASSETS_DIR}/"
  install -d -m 0755 "${DOCKER_ASSETS_DIR}/state/wg-profiles" "${DOCKER_ASSETS_DIR}/state/gluetun" "${DOCKER_ASSETS_DIR}/env"
  chown -R "${NEW_USER}:${NEW_USER}" "${DOCKER_ASSETS_DIR}" || true
  log_info "Docker compose stacks synced to ${DOCKER_ASSETS_DIR}."
  log_info "Use 'docker compose -f ${DOCKER_ASSETS_DIR}/compose/<file>.yml up' to start the desired service."
  for script in rotate-wg.sh rotate-gluetun.sh; do
    if [[ -f "${DOCKER_ASSETS_DIR}/scripts/${script}" ]]; then
      chmod 0755 "${DOCKER_ASSETS_DIR}/scripts/${script}"
    fi
  done
}

ensure_docker_available() {
  if [[ "${CONTAINER_ENGINE}" != "docker" ]]; then
    log_info "Container engine '${CONTAINER_ENGINE}' is not docker; skipping docker asset sync."
    return 1
  fi
  if ! command_exists docker; then
    log_warn "Docker CLI not found. Run 'abb-setup.sh utilities' with docker selected and rerun this task."
    return 1
  fi
  return 0
}

run_task_docker_tools() {
  if [[ "${SKIP_DOCKER_TASKS}" == "true" ]]; then
    log_warn "Skipping docker-tools task because Docker was unavailable earlier. Reboot, ensure Docker is running, then rerun this task."
    return 0
  fi
  ensure_user_context
  if ! ensure_docker_available; then
    return 0
  fi
  sync_docker_assets
}
