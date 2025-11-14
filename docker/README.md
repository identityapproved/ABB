# Docker Stacks

ABB ships opinionated Docker Compose templates under this folder. The provisioning scripts copy everything to `/opt/abb-docker` so you can manage containers without additional wrappers.

## Layout

- `compose/` – individual `docker-compose.<tool>.yml` stacks. Each file focuses on a single tool/service so you can run only what you need.
- `images/` – minimal Dockerfiles for tools that do not publish official images (e.g., Asnlookup, dnsvalidator).
- `scripts/` – helper utilities such as `rotate-wg.sh` for changing WireGuard profiles used by the VPN container.

## Usage

1. Bring up the host-level VPN if you want container traffic tunneled:
   ```bash
   sudo scripts/openvpn-connect.sh start
   ```
2. Launch any stack normally. Example:
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
3. Need to verify the exit IP? Start the tester stack:
   ```bash
   docker compose -f docker-compose.test-client.yml up
   ```
   It prints the current egress IP every minute.

Refer to each compose file for mounts/environment overrides, and build-required stacks (Asnlookup, dnsvalidator) with `docker compose -f docker-compose.<name>.yml build`. The legacy Mullvad container assets remain under `images/wg-vpn` should you need them later.
