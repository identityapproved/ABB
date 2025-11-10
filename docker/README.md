# Docker Stacks

ABB ships opinionated Docker Compose templates under this folder. The provisioning scripts copy everything to `/opt/abb-docker` so you can manage containers without additional wrappers.

## Layout

- `compose/` – individual `docker-compose.<tool>.yml` stacks. Each file focuses on a single tool/service so you can run only what you need.
- `images/` – minimal Dockerfiles for tools that do not publish official images (e.g., Asnlookup, dnsvalidator).
- `scripts/` – helper utilities such as `rotate-wg.sh` for changing WireGuard profiles used by the VPN container.

## Usage

1. Ensure Docker is running (`sudo systemctl status docker`).
2. Bring up the Mullvad-aware WireGuard container (first run builds the custom image):
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.vpn.yml up -d
   ```
3. Generate container-only Mullvad configs:
   ```bash
   docker exec -it wg-vpn bootstrap-mullvad
   ```
   Follow the prompts from `mullvad-wg.sh`; the configs are stored under `/opt/abb-docker/state/wg-profiles` and never touch the host.
4. Start another stack (for example, reconftw) in a separate shell:
   ```bash
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
   Each stack configures `network_mode: "container:wg-vpn"` so traffic egresses via the WireGuard container.
5. The VPN container rotates to a random Mullvad config every 15 minutes automatically. Trigger an immediate change if needed:
   ```bash
   /opt/abb-docker/scripts/rotate-wg.sh
   ```

Refer to the comments inside each compose file for mount points and environment overrides. Build-required stacks (e.g., Asnlookup, dnsvalidator) can be built with `docker compose -f docker-compose.<name>.yml build`.
