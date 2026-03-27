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

## BlackArch Repository (optional)

ABB leaves the BlackArch repository disabled so you can opt in manually:

1. Once provisioning is complete, run:
   ```bash
   sudo ./scripts/blackarch-enable.sh
   ```
2. The helper writes `/etc/pacman.d/blackarch.conf`, links it into `/etc/pacman.conf`, installs `blackarch-keyring`, enables multilib, and refreshes `pacman`. Review the script output for any warnings.
3. To switch mirrors later, edit `/etc/pacman.d/blackarch.conf` directly and rerun `sudo pacman -Syyu`.

With the repository enabled, install packages (e.g., `sudo pacman -S amass`) or fall back to the included Docker compose stack/`yay` packages if you prefer not to enable it.

## Docker Helpers

If you selected Docker, the compose stacks live under `/opt/abb-docker`:
- Start the host-level VPN if you want container traffic tunneled: `sudo scripts/openvpn-connect.sh start`.
- Launch stacks normally: `docker compose -f /opt/abb-docker/compose/docker-compose.reconftw.yml run --rm reconftw -d example.com -r`.
- Build/update stacks that ship local Dockerfiles (Asnlookup, dnsvalidator) with `docker compose -f docker-compose.<tool>.yml build`.
- Use `docker-compose.test-client.yml` to print the current exit IP every minute and verify routing.

Refresh images periodically with `docker pull` (WireGuard, ReconFTW, feroxbuster, trufflehog, CeWL, Amass) and rebuild the custom images when upstream repos change.

- Mullvad configs for the VPS host live exclusively under `/etc/wireguard` (with SSH-preserving rules baked in). Bring up a host-side tunnel with `sudo wg-quick up <profile>` and confirm connectivity:
  ```bash
  curl https://am.i.mullvad.net/json | jq
  ```
- The utilities task already injects SSH-preserving `PostUp`/`PreDown` rules; adjust the port if you run SSH on a non-standard port.
- The setup task removes `mullvad-wg.sh` after execution. Re-run `abb-setup.sh mullvad` whenever you need to regenerate profiles.

## OpenVPN (Host Wrapper)

Use `scripts/openvpn-connect.sh` when you need the VPS tunneled through `.ovpn` profiles without breaking SSH:

1. Drop `.ovpn` files plus `credentials.txt` (or `credentials.text`) into `~/openvpn-configs`.
2. (Optional) Persist SSH bypass so the host always keeps the Contabo route:
   ```bash
   sudo scripts/ssh-bypass.sh setup
   ```
3. Start the tunnel: `sudo scripts/openvpn-connect.sh start`
3. Check status/rotate: `sudo scripts/openvpn-connect.sh status`, `sudo scripts/openvpn-connect.sh rotate us-nyc.ovpn` (or `sudo scripts/openvpn-rotate.sh`).
4. Stop and restore the original routes when done: `sudo scripts/openvpn-connect.sh stop`

The wrapper syncs configs to `/opt/openvpn-configs`, pins routes for the VPN gateway and your current SSH client, and wires up `/etc/openvpn/update-resolv-conf` so DNS follows the tunnel.
