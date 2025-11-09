# Docker Stacks

ABB ships opinionated Docker Compose templates under this folder. The provisioning scripts copy everything to `/opt/abb-docker` so you can manage containers without additional wrappers.

## Layout

- `compose/` – individual `docker-compose.<tool>.yml` stacks. Each file focuses on a single tool/service so you can run only what you need.
- `images/` – minimal Dockerfiles for tools that do not publish official images (e.g., Asnlookup, dnsvalidator).
- `scripts/` – helper utilities such as `rotate-wg.sh` for changing WireGuard profiles used by the VPN container.

## Usage

1. Ensure Docker is running (`sudo systemctl status docker`).
2. Bring up the Mullvad-aware WireGuard container:
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.vpn.yml up -d
   ```
3. Start another stack (for example, reconftw) in a separate shell:
   ```bash
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
   Each stack configures `network_mode: "container:wg-vpn"` so traffic egresses via the WireGuard container.
4. Rotate WireGuard exit IPs whenever needed:
   ```bash
   /opt/abb-docker/scripts/rotate-wg.sh
   ```

### Auto Rotation (Optional)

Cron can rotate the active WireGuard profile on a schedule. The following example switches VPN profiles every 15 minutes:

```bash
(crontab -l 2>/dev/null; echo "*/15 * * * * /opt/abb-docker/scripts/rotate-wg.sh >/dev/null 2>&1") | crontab -
```

Refer to the comments inside each compose file for mount points and environment overrides. Build-required stacks (e.g., Asnlookup, dnsvalidator) can be built with `docker compose -f docker-compose.<name>.yml build`.
