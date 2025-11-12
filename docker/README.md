# Docker Stacks

ABB ships opinionated Docker Compose templates under this folder. The provisioning scripts copy everything to `/opt/abb-docker` so you can manage containers without additional wrappers.

## Layout

- `compose/` – individual `docker-compose.<tool>.yml` stacks. Each file focuses on a single tool/service so you can run only what you need.
- `images/` – minimal Dockerfiles for tools that do not publish official images (e.g., Asnlookup, dnsvalidator, the Mullvad VPN helper).
- `scripts/` – helper utilities such as `rotate-wg.sh`, `rotate-gluetun.sh`, and `rotate-protonvpn-cli.sh` for changing VPN exit IPs.
- `env/` – sample environment files (for example `env/protonvpn-gluetun.env.example`, `env/protonvpn-cli.env.example`).

## Mullvad WireGuard Transport

1. Ensure Docker is running (`sudo systemctl status docker`).
2. Bring up the Mullvad-aware WireGuard container (first run builds the custom image):
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.mullvad-wg.yml up -d
   ```
3. Generate container-only Mullvad configs:
   ```bash
   docker exec -it vpn-gateway bootstrap-mullvad
   ```
   Follow the prompts from `mullvad-wg.sh`; the configs are stored under `/opt/abb-docker/state/wg-profiles` and never touch the host.
4. Start another stack (for example, reconftw) in a separate shell:
   ```bash
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
   Each stack configures `network_mode: "container:vpn-gateway"` so traffic egresses via the WireGuard container.
5. The VPN container rotates to a random Mullvad config every 15 minutes automatically. Trigger an immediate change if needed:
   ```bash
   /opt/abb-docker/scripts/rotate-wg.sh
   ```

## ProtonVPN (Gluetun) Transport

1. Copy and edit the env file with your Proton credentials:
   ```bash
   cp /opt/abb-docker/env/protonvpn-gluetun.env.example /opt/abb-docker/env/protonvpn-gluetun.env
   nvim /opt/abb-docker/env/protonvpn-gluetun.env
   ```
2. Start the ProtonVPN container:
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.protonvpn-gluetun.yml up -d
   ```
3. Route other stacks through the ProtonVPN container with `network_mode: "service:vpn-gateway"`.
4. Rotate the exit IP by restarting the container every seven minutes (or on demand):
   ```bash
   /opt/abb-docker/scripts/rotate-gluetun.sh             # manual restart
   (crontab -l 2>/dev/null; echo "*/7 * * * * /opt/abb-docker/scripts/rotate-gluetun.sh >/dev/null 2>&1") | crontab -
   ```

## ProtonVPN Gateway (CLI)

1. Copy and edit the CLI env file:
   ```bash
   cp /opt/abb-docker/env/protonvpn-cli.env.example /opt/abb-docker/env/protonvpn-cli.env
   nvim /opt/abb-docker/env/protonvpn-cli.env
   ```
2. Build and launch the gateway:
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.protonvpn-cli.yml up -d --build
   ```
   State is stored under `/opt/abb-docker/state/protonvpn-cli`.
3. Initialize the CLI interactively (once per VPS):
   ```bash
   docker exec -it vpn-gateway protonvpn init
   docker exec -it vpn-gateway protonvpn connect --fastest
   ```
4. Attach dependent services using `network_mode: "service:vpn-gateway"`.
5. Rotate the exit IP manually or via cron:
   ```bash
   /opt/abb-docker/scripts/rotate-protonvpn-cli.sh
   (crontab -l 2>/dev/null; echo "*/7 * * * * /opt/abb-docker/scripts/rotate-protonvpn-cli.sh >/dev/null 2>&1") | crontab -
   ```

Refer to the comments inside each compose file for mount points and environment overrides. Build-required stacks (e.g., Asnlookup, dnsvalidator) can be built with `docker compose -f docker-compose.<name>.yml build`.
