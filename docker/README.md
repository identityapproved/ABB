# Docker Stacks

ABB ships opinionated Docker Compose templates under this folder. The provisioning scripts copy everything to `/opt/abb-docker` so you can manage containers without additional wrappers.

## Layout

- `compose/` – individual `docker-compose.<tool>.yml` stacks. Each file focuses on a single tool/service so you can run only what you need.
- `images/` – minimal Dockerfiles for tools that do not publish official images (e.g., Asnlookup, dnsvalidator, the Mullvad VPN helper).
- `scripts/` – helper utilities such as `rotate-wg.sh`, `rotate-gluetun.sh`, and `rotate-openvpn.sh` for changing VPN exit IPs.
- `env/` – sample environment files (for example `env/protonvpn-gluetun.env.example`, `env/openvpn.env.example`).

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

## ProtonVPN Gateway (OpenVPN)

This stack expects you to download ProtonVPN OpenVPN `.ovpn` profiles manually and drop them under `~/openvpn-configs`. Re-run `./abb-setup.sh docker-tools` after adding new configs and the task will move them into `/opt/openvpn-configs` (owned by `root:root`, mode `0700`), overwriting older files with the same name and removing the originals from your home directory. Keep credentials inside the configs or add a `credentials.txt` alongside them; it will be copied securely as well. The resulting `/opt/openvpn-configs` directory is mounted read-only into the container to avoid accidental edits.

1. Prepare the env file (optional overrides for timezone, default config, extra OpenVPN flags):
   ```bash
   cp /opt/abb-docker/env/openvpn.env.example /opt/abb-docker/env/openvpn.env
   nvim /opt/abb-docker/env/openvpn.env
   ```
2. Build and launch the gateway:
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.openvpn.yml up -d --build
   ```
   Runtime state (active config copy, PID, rotation metadata) is written to `/opt/abb-docker/state/openvpn`.
3. Attach dependent services using `network_mode: "service:vpn-gateway"`.
4. Rotate the exit IP without tearing down the container:
   ```bash
   /opt/abb-docker/scripts/rotate-openvpn.sh              # advance to the next config
   /opt/abb-docker/scripts/rotate-openvpn.sh random       # pick a random config
   OPENVPN_TARGET_CONFIG=us-nyc.ovpn OPENVPN_ROTATE_MODE=explicit /opt/abb-docker/scripts/rotate-openvpn.sh
   (crontab -l 2>/dev/null; echo "*/7 * * * * /opt/abb-docker/scripts/rotate-openvpn.sh >/dev/null 2>&1") | crontab -
   ```
   The helper replaces the active config inside the container, then issues `SIGHUP` so OpenVPN re-reads the new profile. Dependent containers keep the `vpn-gateway` namespace while the tunnel re-establishes.

Refer to the comments inside each compose file for mount points and environment overrides. Build-required stacks (e.g., Asnlookup, dnsvalidator) can be built with `docker compose -f docker-compose.<name>.yml build`.
