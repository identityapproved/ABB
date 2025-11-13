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

## Docker Helpers

If you selected Docker, the compose stacks live under `/opt/abb-docker`:
- Start the VPN transport (builds on first run): `docker compose -f /opt/abb-docker/compose/docker-compose.vpn.yml up -d`.
- Generate container-only Mullvad configs: `docker exec -it wg-vpn bootstrap-mullvad`.
- Run a tool through the VPN: `docker compose -f /opt/abb-docker/compose/docker-compose.reconftw.yml run --rm reconftw -d example.com -r`.
- Trigger an immediate VPN rotation (the container already rotates every 15 minutes automatically): `/opt/abb-docker/scripts/rotate-wg.sh`.
- Build/update stacks that ship local Dockerfiles (Asnlookup, dnsvalidator) with `docker compose -f docker-compose.<tool>.yml build`.

Refresh images periodically with `docker pull` (WireGuard, ReconFTW, feroxbuster, trufflehog, CeWL, Amass) and rebuild the custom images when upstream repos change.

- Mullvad configs for the VPS host live exclusively under `/etc/wireguard` (with SSH-preserving rules baked in). The Docker VPN container keeps its own copies inside `/opt/abb-docker/state/wg-profiles`. Bring up a host-side tunnel with `sudo wg-quick up <profile>` and confirm connectivity:
  ```bash
  curl https://am.i.mullvad.net/json | jq
  ```
- The utilities task already injects SSH-preserving `PostUp`/`PreDown` rules; adjust the port if you run SSH on a non-standard port.
- The setup task removes `mullvad-wg.sh` after execution. Re-run `abb-setup.sh mullvad` whenever you need to regenerate profiles.

## ProtonVPN Namespace

Use the bundled helpers under `scripts/` when you need ProtonVPN CLI on the VPS without losing SSH (and when you want docker workloads tunneled):

1. Create the namespace once: `sudo scripts/vpnspace.sh setup`
2. Connect via ProtonVPN: `sudo scripts/vpnspace.sh connect` (or pass additional CLI flags such as `c --cc NL`)
3. Open a tunneled shell for ad-hoc tooling: `sudo scripts/vpnspace.sh shell`
4. Start the dedicated docker daemon inside the namespace: `sudo scripts/vpnspace-dockerd.sh start` then `export DOCKER_HOST=unix:///run/docker-vpnspace.sock` before running docker/compose commands.
5. Rotate exit IPs anytime with `sudo scripts/protonvpn-rotate.sh` (defaults to `reconnect`; pass additional args such as `c -r` for random).
6. Leave the namespace up (SSH is unaffected) or disconnect/teardown when done:
   ```bash
   sudo scripts/vpnspace.sh disconnect
   sudo scripts/vpnspace.sh teardown
   ```
