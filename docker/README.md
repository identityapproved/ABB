# Docker Stacks

ABB ships opinionated Docker Compose templates under this folder. The provisioning scripts copy everything to `/opt/abb-docker` so you can manage containers without additional wrappers.

## Layout

- `compose/` – individual `docker-compose.<tool>.yml` stacks. Each file focuses on a single tool/service so you can run only what you need.
- `images/` – minimal Dockerfiles for tools that do not publish official images (e.g., Asnlookup, dnsvalidator).
- `scripts/` – helper utilities such as `rotate-wg.sh` for changing WireGuard profiles used by the VPN container.

## Usage

1. Create the ProtonVPN namespace once: `sudo scripts/vpnspace.sh setup`.
2. Whenever you need Docker traffic tunneled, start the dedicated daemon in that namespace and point your client at it:
   ```bash
   sudo scripts/vpnspace-dockerd.sh start
   export DOCKER_HOST=unix:///run/docker-vpnspace.sock
   ```
3. Launch any stack normally. Example:
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
4. Need to verify the exit IP? Start the tester stack:
   ```bash
   docker compose -f docker-compose.test-client.yml up
   ```
   It prints the current egress IP every minute.

Every compose file honours the `ABB_NETWORK_MODE` environment variable (default `bridge`). Override it if you spin up a custom network inside the namespace. The legacy Mullvad container assets remain under `images/wg-vpn` for operators who still rely on that workflow, but they are no longer part of the default instructions above. Refer to the compose comments for additional mounts/environment overrides, and build-required stacks (Asnlookup, dnsvalidator) with `docker compose -f docker-compose.<name>.yml build`.
