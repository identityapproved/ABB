# ABB – Arch Bugbounty Bootstrap

> **Warning:** The automation has been manually validated end-to-end only with the `yay` AUR helper. Other helpers are supported, but treat them as experimental and review output carefully.

ABB is an Arch Linux–first automation toolkit for provisioning bug bounty VPS instances. The image provided by Contabo already creates an `admin` user and injects SSH keys, so the scripts focus on guiding any account rename, installing required tooling, and keeping the process modular.

## Prerequisites
- Install `git` ahead of time so you can clone this repository.
- Install `vim` on the VPS before running any ABB tasks: `sudo pacman -S --needed vim`.

## Quick Start
- Log in as `root` (or a wheel user) on the Arch VPS.
- Clone the repo and run `./abb-setup.sh prompts` to answer the interactive questions (username, editor choice, hardening flag, Node manager preference `nvm` or `fnm`, container engine `docker`/`podman`/`none`, feroxbuster installation method `cargo`/`aur`, whether to install trufflehog via the upstream script).
- Execute `./abb-setup.sh accounts` to create the managed user, copy SSH keys from `admin`, enable sudo, and optionally retire the legacy account. The task exits so you can reconnect as the new user. After reconnecting, run `sudo pacman -Syu`, `sudo pacman -S linux`, and `sudo reboot`; once the system is back up, log in as the managed user, rerun `sudo ./abb-setup.sh accounts` to remove `admin`, then move the ABB repo under the new home.
- After reconnecting as the managed user, run `./abb-setup.sh package-manager` to write `/etc/pacman.d/blackarch.conf`, append `Include = /etc/pacman.d/blackarch.conf` to `/etc/pacman.conf`, temporarily set `SigLevel = Never` to install `blackarch-keyring`, restore signature checking, enable multilib (if missing), force `pacman -Syyu`, and install/cache your preferred AUR helper (`yay`, `paru`, `pacaur`, `pikaur`, `aura`, or `aurman`).
- Continue with `./abb-setup.sh all` (or the individual tasks you need) to complete provisioning.
- If you chose Docker during prompts, run `./abb-setup.sh docker-tools` (included in `all`) to sync the compose stacks under `/opt/abb-docker`; manage containers with `docker compose -f /opt/abb-docker/compose/docker-compose.<tool>.yml ...`.
- After `./abb-setup.sh mullvad` completes, review the generated WireGuard profiles, supply Mullvad account details during the one-time `mullvad-wg.sh` run, and connect with `sudo wg-quick up <config>`; verify the tunnel using `curl https://am.i.mullvad.net/json | jq`.
- Review the guidance in `NEXT_STEPS.md` (automatically printed after `all` or `docker-tools`) for manual follow-ups such as seeding the AIDE database and installing ProjectDiscovery binaries via `pdtm`.
- Execute individual tasks (see below) or run the entire workflow with `./abb-setup.sh all`.
- Inspect `/var/log/vps-setup.log` for the consolidated log and `~<user>/installed-tools.txt` for a simple tool inventory.

## Modular Tasks
Each task can be executed independently:

| Task | Description |
| ---- | ----------- |
| `prompts` | Capture answers for the managed user, editor preference, and hardening toggle; cache responses in `/var/lib/vps-setup/answers.env`. |
| `accounts` | Create the managed user, ensure wheel access, copy SSH credentials from `admin`, prompt for password, instruct you to run `sudo pacman -Syu`, `sudo pacman -S linux`, and reboot before continuing, then offer to remove `admin` after switching. |
| `package-manager` | Install the selected AUR helper once (`yay`, `paru`, `pacaur`, `pikaur`, `aura`, or `aurman`) and cache the choice for later tasks. |
| `security` | Run `pacman -Syu`, apply optional sysctl/iptables hardening, and install/configure AIDE + rkhunter with sudo logging. |
| `languages` | Install Python, pipx, setuptools, Go, Ruby, base build tools, and Rust via `rustup` (defaulting to the stable toolchain). |
| `utilities` | Install core system utilities (tree, tealdeer (`tldr`), ripgrep, fd, zsh, fzf, bat, htop, iftop, tmux, wireguard-tools/openresolv, yazi, lazygit, firewalld, fail2ban, zoxide, etc.), enable services, bootstrap the chosen Node manager (`nvm` or `fnm`), and configure the selected container engine (`docker` + `lazydocker` or `podman`). |
| `mullvad` | Ensure WireGuard prerequisites, run `mullvad-wg.sh` once (and remove it afterward), add SSH-preserving `PostUp`/`PreDown` rules, and remind you to verify connectivity. |
| `tools` | Use pipx for recon utilities (waymore, Sublist3r, webscreenshot, etc.), install `pdtm` via Go (ABB only installs the `pdtm` launcher; run `pdtm install …` or `pdtm install-all` yourself to pull ProjectDiscovery binaries), `go install` for the remaining recon/XSS helpers (anew, gauplus, ipcdn, s3scanner, fuzzuli, and more), handle recon packages via pacman (`amass`), install feroxbuster via `cargo install --locked --force feroxbuster` or the selected AUR helper based on your prompt choice, optionally install trufflehog via the official script (with source/Docker fallbacks), and clone/git-sync tooling and wordlists (massdns, masscan, SecLists, cent, permutations/resolvers, JSParser, lazyrecon, etc.) into `/opt/vps-tools`. |
| `dotfiles` | Install Oh My Zsh, sync Arch-specific `.zshrc` and `.aliases`, install curated Zsh plugins, copy tmux/vim configs, and bootstrap LazyVim if requested. |
| `verify` | Run post-install checks (`pacman -Q` for key packages, `<aur-helper> --version`, `pipx list`, `go version`) and point to log locations. |
| `docker-tools` | Sync the curated compose stacks from `docker/` into `/opt/abb-docker`. Use those compose files (vpn, reconftw, asnlookup, dnsvalidator, feroxbuster, trufflehog, CeWL, Amass, etc.) with `docker compose`—no shell wrappers are installed. |
## Highlights
- **AUR helper first:** The package-manager stage installs and caches the selected helper (`yay` by default) before any tooling that depends on it.
- **Tool tracking:** Each successful install is appended to `~<user>/installed-tools.txt` so you can review or diff between runs.
- **No SSH tweaks:** Contabo already provisions keys; the script leaves `sshd_config` untouched while still offering optional sysctl/iptables hardening on demand.
- **Arch-friendly dotfiles:** Zsh configuration includes Arch paths, tealdeer integration for `tldr`, zoxide initialisation, guarded Node manager/LazyVim hooks, plus helpers like the `wgup` profile picker for WireGuard.
- **tmux ready:** Configuration lands in `~/.config/tmux/tmux.conf`, keeps `C-b` as the prefix, enables clipboard sync, and bootstraps TPM automatically on first launch.
- **Wordlist workspace:** `SecLists` lives in `/opt/vps-tools/SecLists` with a symlink at `~/wordlists/seclists`; the tools stage also syncs the cent repository and fetches permutations/resolvers lists alongside `~/wordlists/custom` for personal mutations.
- **WireGuard ready:** Utilities install `wireguard-tools`/`openresolv`; the dedicated `mullvad` task runs `mullvad-wg.sh` once (removing the script afterwards), normalizes the resulting `/etc/wireguard/*.conf` files with SSH-preserving rules, and records them under `~/wireguard-profiles.txt` for manual `wg-quick` sessions. Docker gets its own Mullvad identities by running the script inside the VPN container, keeping host and container keys separated.
- **BlackArch repo:** The package-manager stage writes `/etc/pacman.d/blackarch.conf`, plugs it into `/etc/pacman.conf`, briefly disables signature checks to install `blackarch-keyring`, restores verification, enables multilib, forces `pacman -Syyu`, and then builds your chosen AUR helper.
- **Container flexibility:** Pick Docker (with lazydocker) or Podman during prompts; utilities enables the requested engine and grants the managed user access, and the `docker-tools` task simply syncs compose stacks so you can run ReconFTW/Asnlookup/dnsvalidator/feroxbuster/trufflehog/CeWL/Amass via standard `docker compose` flows (all stacks can route through the WireGuard container).
- **Rust-ready toolchain:** Languages install `rustup`, set the default stable toolchain, and extend PATHs so cargo-built utilities (including feroxbuster) work out of the box.
- **Trufflehog choice:** Decide once whether to install the upstream trufflehog binary; if the script fails you can opt into a source build or fall back to the docker-compose stack.
- **Release-friendly tools:** JSParser installs through pipx while keeping a local checkout, and the latest JSHawk release script is downloaded directly into `/usr/local/bin/jshawk`.

## Docker Compose Stacks

The repository ships compose templates under `docker/` (copied to `/opt/abb-docker` by `./abb-setup.sh docker-tools`). Workflow:

1. Bring up the host-level OpenVPN tunnel (see next section) if you want Docker traffic routed through the VPN; otherwise, use the Contabo egress IP.
2. Run any stack normally. Example (ReconFTW):
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
3. Need a quick sanity check to confirm the tunnel? Use the tester stack:
   ```bash
   docker compose -f docker-compose.test-client.yml up
   ```
   It prints the current egress IP every minute.

Each compose file documents its mounts and environment variables; Asnlookup and dnsvalidator stacks include Dockerfiles under `docker/images/` for repeatable builds. The legacy Mullvad assets remain under `docker/images/wg-vpn` for future use but are no longer part of the default workflow.

## OpenVPN (host wrapper)

Drop your `.ovpn` profiles plus `credentials.txt` (or `credentials.text`) into `~/openvpn-configs`, then use the host wrapper to connect without disrupting your SSH session. The script syncs configs into `/opt/openvpn-configs`, pins routes for the VPN gateway and your SSH client, and restores everything on stop.

1. Start or select a profile (defaults to the first file):
   ```bash
   sudo scripts/openvpn-connect.sh start
   sudo scripts/openvpn-connect.sh status
   ```
   If you need SSH to keep using the Contabo gateway permanently, run once:
   ```bash
   sudo scripts/ssh-bypass.sh setup   # adds iptables/ip rule + persistence
   ```
2. Rotate exits without dropping the tunnel:
   ```bash
   sudo scripts/openvpn-connect.sh rotate us-nyc.ovpn
   # or use the compatibility wrapper:
   sudo scripts/openvpn-rotate.sh
   ```
3. List / sync configs:
   ```bash
   sudo scripts/openvpn-connect.sh list
   sudo scripts/openvpn-connect.sh sync
   ```
4. Tear down and restore the original routes when finished:
   ```bash
   sudo scripts/openvpn-connect.sh stop
   ```

The wrapper automatically reads `credentials.txt` from `/opt/openvpn-configs`, enforces `chmod 600`, and wires up `/etc/openvpn/update-resolv-conf` so DNS follows the tunnel.

## WireGuard Helpers

- VPS configs live solely in `/etc/wireguard` (with SSH-preserving rules injected automatically), and manual connections use the `wgup` helper plus `~/wireguard-profiles.txt`.
- `~/wireguard-profiles.txt` lists every available profile. The `wgup` alias (defined in `.aliases`) lets you fuzzy-pick a profile via `fzf` and run `sudo wg-quick up <profile>` in one step.
- If you still rely on Mullvad-specific tooling (for example to regenerate configs with `mullvad-wg.sh`), the scripts and Dockerfile remain under `docker/images/wg-vpn`, but they are no longer part of the default compose workflow.

## Rerun Guidance
- Re-running any task is safe; prompts are cached in `/var/lib/vps-setup/answers.env`.
- If kernel or core packages update, reboot and rerun `verify` to confirm paths and versions.
- Use your configured AUR helper (e.g., `yay -Syu`) between provisioning runs to keep AUR packages in sync.
