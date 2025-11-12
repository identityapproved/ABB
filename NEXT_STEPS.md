# Next Steps Checklist

Some tasks intentionally require manual follow-up after ABB finishes provisioning. Keep this reference handy after reconnecting as your managed user.

## AIDE Baseline

1. Review `/etc/aide.conf` and adjust any paths or exclusions you need.
2. Validate the configuration syntax:
   ```bash
   sudo aide -D
   ```
3. Seed the database (this can take several minutes on large filesystems):
   ```bash
   sudo aide --init
   ```
4. Promote the generated database:
   ```bash
   sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
   ```
5. For recurring integrity checks:
   ```bash
   sudo systemctl enable --now aidecheck.timer
   ```
   Inspect results with `sudo journalctl -abu aidecheck` or `/var/log/aide.log`.

## ProjectDiscovery via pdtm

ABB installs `pdtm` but does not auto-install every ProjectDiscovery binary. After your shell picks up the new PATH entries (`source ~/.bashrc` or start a new session), run:
```bash
PATH="$HOME/.pdtm/go/bin:$HOME/.local/bin:$PATH" pdtm install --force subfinder dnsx naabu httpx nuclei uncover cloudlist proxify tlsx notify chaos-client shuffledns mapcidr interactsh-client interactsh-server katana
```
Repeat as needed to install additional tools announced by ProjectDiscovery.

## ProtonVPN CLI

If you selected ProtonVPN during prompts, finish the CLI bootstrap manually (it is interactive and stores credentials locally):

```bash
sudo protonvpn-cli login <protonvpn-username>
sudo protonvpn-cli init
sudo protonvpn-cli connect --fastest
```

Use `protonvpn-cli status` or `protonvpn-cli list --countries` to verify connectivity and browse endpoints. Re-run `sudo protonvpn-cli connect --fastest` whenever you need a fresh exit IP on the VPS itself.
If you want to maintain an active SSH session while toggling ProtonVPN, use the bundled helper:
```bash
sudo proton-safe-connect -- --fastest
```
It adds a static route for your SSH client IP before invoking `protonvpn-cli`.

## Docker Helpers

If you selected Docker, the compose stacks live under `/opt/abb-docker`:
- Start the VPN transport (builds on first run): `docker compose -f /opt/abb-docker/compose/docker-compose.mullvad-wg.yml up -d`.
- Generate container-only Mullvad configs: `docker exec -it vpn-gateway bootstrap-mullvad`.
- Run a tool through the VPN: `docker compose -f /opt/abb-docker/compose/docker-compose.reconftw.yml run --rm reconftw -d example.com -r`.
- Trigger an immediate Mullvad rotation (the container already rotates every 15 minutes automatically): `/opt/abb-docker/scripts/rotate-wg.sh`.
- ProtonVPN/Gluetun: copy `/opt/abb-docker/env/protonvpn-gluetun.env.example` to `.env`, edit credentials, then run `docker compose -f /opt/abb-docker/compose/docker-compose.protonvpn-gluetun.yml up -d`. Rotate the exit IP every seven minutes with `(crontab -l 2>/dev/null; echo "*/7 * * * * /opt/abb-docker/scripts/rotate-gluetun.sh >/dev/null 2>&1") | crontab -` or fire `/opt/abb-docker/scripts/rotate-gluetun.sh` manually.
- ProtonVPN CLI gateway: copy `/opt/abb-docker/env/protonvpn-cli.env.example` to `.env`, adjust options, then run `docker compose -f /opt/abb-docker/compose/docker-compose.protonvpn-cli.yml up -d --build`. Initialize via `docker exec -it vpn-gateway protonvpn init` followed by `docker exec -it vpn-gateway protonvpn connect --fastest`, attach dependent containers via `network_mode: "service:vpn-gateway"`, and rotate IPs with `/opt/abb-docker/scripts/rotate-protonvpn-cli.sh` (or a cron job `*/7 * * * * /opt/abb-docker/scripts/rotate-protonvpn-cli.sh >/dev/null 2>&1`).
- Build/update stacks that ship local Dockerfiles (Asnlookup, dnsvalidator) with `docker compose -f docker-compose.<tool>.yml build`.

Refresh images periodically with `docker pull` (WireGuard, ReconFTW, feroxbuster, trufflehog, CeWL, Amass) and rebuild the custom images when upstream repos change.

- Mullvad configs for the VPS host live exclusively under `/etc/wireguard` (with SSH-preserving rules baked in). The Docker VPN container keeps its own copies inside `/opt/abb-docker/state/wg-profiles`. Bring up a host-side tunnel with `sudo wg-quick up <profile>` and confirm connectivity:
  ```bash
  curl https://am.i.mullvad.net/json | jq
  ```
- The utilities task already injects SSH-preserving `PostUp`/`PreDown` rules; adjust the port if you run SSH on a non-standard port.
- The setup task removes `mullvad-wg.sh` after execution. Re-run `abb-setup.sh vpn` whenever you need to regenerate Mullvad profiles or reinstall the ProtonVPN CLI.
