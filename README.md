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
- After `./abb-setup.sh vpn` completes, review the provider-specific instructions: Mullvad users keep `/etc/wireguard/*.conf` for host tunnels, while ProtonVPN users finish `protonvpn-cli` initialization (`sudo protonvpn-cli init && sudo protonvpn-cli connect --fastest`) before relying on the CLI.
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
- **WireGuard ready:** Utilities install `wireguard-tools`/`openresolv`; the VPN task runs `mullvad-wg.sh` (for Mullvad) or bootstraps `protonvpn-cli` (for ProtonVPN). Mullvad configs stay in `/etc/wireguard` with SSH-preserving rules and are listed in `~/wireguard-profiles.txt`, while ProtonVPN installs the CLI and leaves final `sudo protonvpn-cli init`/`connect` steps to the operator. Docker keeps separate identities for Mullvad WireGuard, ProtonVPN (Gluetun), and ProtonVPN OpenVPN so host and container keys remain isolated.
- **BlackArch repo:** The package-manager stage writes `/etc/pacman.d/blackarch.conf`, plugs it into `/etc/pacman.conf`, briefly disables signature checks to install `blackarch-keyring`, restores verification, enables multilib, forces `pacman -Syyu`, and then builds your chosen AUR helper.
- **Container flexibility:** Pick Docker (with lazydocker) or Podman during prompts; utilities enables the requested engine and grants the managed user access, and the `docker-tools` task simply syncs compose stacks so you can run ReconFTW/Asnlookup/dnsvalidator/feroxbuster/trufflehog/CeWL/Amass via standard `docker compose` flows (all stacks can route through the WireGuard container).
- **Rust-ready toolchain:** Languages install `rustup`, set the default stable toolchain, and extend PATHs so cargo-built utilities (including feroxbuster) work out of the box.
- **Trufflehog choice:** Decide once whether to install the upstream trufflehog binary; if the script fails you can opt into a source build or fall back to the docker-compose stack.
- **Release-friendly tools:** JSParser installs through pipx while keeping a local checkout, and the latest JSHawk release script is downloaded directly into `/usr/local/bin/jshawk`.

## Docker Compose Stacks

The repository ships compose templates under `docker/` (copied to `/opt/abb-docker` by `./abb-setup.sh docker-tools`). Typical workflow:

1. Start the WireGuard transport (first run builds the custom image):
   ```bash
   cd /opt/abb-docker/compose
   docker compose -f docker-compose.mullvad-wg.yml up -d
   ```
2. Generate container-only Mullvad configs once per VPS:
   ```bash
   docker exec -it vpn-gateway bootstrap-mullvad
   ```
   Follow the prompts from `mullvad-wg.sh`. Configs are stored under `/opt/abb-docker/state/wg-profiles` for the container only.
3. Run another stack through the VPN container, for example ReconFTW:
   ```bash
   docker compose -f docker-compose.reconftw.yml run --rm reconftw -d example.com -r
   ```
4. The VPN container rotates to a random Mullvad config every 15 minutes automatically. Trigger an immediate change with:
   ```bash
   /opt/abb-docker/scripts/rotate-wg.sh
   ```

Each compose file documents its mounts and environment variables; Asnlookup and dnsvalidator stacks include Dockerfiles under `docker/images/` for repeatable builds.

### ProtonVPN (Gluetun)

1. Copy the ProtonVPN env file and populate credentials:
   ```bash
   cp /opt/abb-docker/env/protonvpn-gluetun.env.example /opt/abb-docker/env/protonvpn-gluetun.env
   nvim /opt/abb-docker/env/protonvpn-gluetun.env
   ```
2. Start the Gluetun container:
   ```bash
   docker compose -f /opt/abb-docker/compose/docker-compose.protonvpn-gluetun.yml up -d
   ```
3. Route stacks through it with `network_mode: "service:vpn-gateway"`.
4. Rotate the exit IP every seven minutes (or on demand):
   ```bash
   /opt/abb-docker/scripts/rotate-gluetun.sh
   (crontab -l 2>/dev/null; echo "*/7 * * * * /opt/abb-docker/scripts/rotate-gluetun.sh >/dev/null 2>&1") | crontab -
   ```

### ProtonVPN Gateway (OpenVPN)

1. Drop ProtonVPN OpenVPN profiles (`.ovpn`) plus any `credentials.txt` files under `~/openvpn-configs`, then rerun `./abb-setup.sh docker-tools` (or `./abb-setup.sh all`) so ABB can move them into `/opt/openvpn-configs` with the right permissions:
   ```bash
   mkdir -p ~/openvpn-configs
   cp ~/Downloads/protonvpn/*.ovpn ~/openvpn-configs/
   cp ~/Downloads/protonvpn/credentials.txt ~/openvpn-configs/  # optional
   ./abb-setup.sh docker-tools
   ```
   The task copies everything into `/opt/openvpn-configs` (root:root 0700), overwriting existing files with the same name and removing the originals from your home directory so credentials never linger there. If a `credentials.txt` file exists in that directory (or you set `OPENVPN_AUTH_FILE` / `OPENVPN_AUTH_USER` / `OPENVPN_AUTH_PASS` in the env file), the container automatically feeds it to OpenVPN so no interactive prompts occur.
2. Copy the env template (timezone, preferred config, extra OpenVPN flags) and adjust as needed:
   ```bash
   cp /opt/abb-docker/env/openvpn.env.example /opt/abb-docker/env/openvpn.env
   nvim /opt/abb-docker/env/openvpn.env
   ```
3. Launch the gateway (builds on first run):
   ```bash
   docker compose -f /opt/abb-docker/compose/docker-compose.openvpn.yml up -d --build
   ```
   Runtime state (active config copy, PID, metadata) is stored under `/opt/abb-docker/state/openvpn`.
4. Attach other workloads via `network_mode: "service:vpn-gateway"` so they inherit the same namespace.
5. Rotate exit IPs without stopping the container:
   ```bash
   /opt/abb-docker/scripts/rotate-openvpn.sh             # advance to the next config alphabetically
   /opt/abb-docker/scripts/rotate-openvpn.sh random      # pick a random config
   OPENVPN_ROTATE_MODE=explicit OPENVPN_TARGET_CONFIG=us-nyc.ovpn /opt/abb-docker/scripts/rotate-openvpn.sh
   (crontab -l 2>/dev/null; echo "*/7 * * * * /opt/abb-docker/scripts/rotate-openvpn.sh >/dev/null 2>&1") | crontab -
   ```
   The helper copies the requested profile into the container’s active slot and issues `SIGHUP`, so dependent stacks remain attached while the tunnel renegotiates.

## WireGuard Helpers

- VPS configs live solely in `/etc/wireguard` (with SSH-preserving rules injected automatically), and manual connections use the `wgup` helper plus `~/wireguard-profiles.txt`. ProtonVPN installs the CLI via pipx; complete the login/init/connect flow manually to start the host tunnel. The Mullvad Docker container manages its own identities—run `docker exec -it vpn-gateway bootstrap-mullvad` once to seed dedicated profiles, and it will rotate them every 15 minutes automatically (tune via `WG_ROTATE_SECONDS`). ProtonVPN Docker workflows either use Gluetun (WireGuard) or the new OpenVPN gateway fed by `/opt/openvpn-configs`.
- Trigger Mullvad rotations with `/opt/abb-docker/scripts/rotate-wg.sh`, ProtonVPN/Gluetun rotations with `/opt/abb-docker/scripts/rotate-gluetun.sh`, and ProtonVPN OpenVPN rotations with `/opt/abb-docker/scripts/rotate-openvpn.sh` (add cron entries such as `*/7 * * * * /opt/abb-docker/scripts/rotate-<vpn>.sh >/dev/null 2>&1` for continuous cycling).
- The `proton-safe-connect` helper lives in `/usr/local/bin`; run `sudo proton-safe-connect` to preserve your SSH route before invoking `protonvpn-cli connect`, especially when working in long-lived SSH sessions.
- `~/wireguard-profiles.txt` lists every available profile. The `wgup` alias (defined in `.aliases`) lets you fuzzy-pick a profile via `fzf` and run `sudo wg-quick up <profile>` in one step.
- Trigger an immediate container rotation with `/opt/abb-docker/scripts/rotate-wg.sh`; it simply shells into the running `vpn-gateway` container and invokes the same rotate helper the entrypoint uses.

## Rerun Guidance
- Re-running any task is safe; prompts are cached in `/var/lib/vps-setup/answers.env`.
- If kernel or core packages update, reboot and rerun `verify` to confirm paths and versions.
- Use your configured AUR helper (e.g., `yay -Syu`) between provisioning runs to keep AUR packages in sync.
