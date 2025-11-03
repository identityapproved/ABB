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
- If you chose Docker during prompts, run `./abb-setup.sh docker-tools` (included in `all`) to pull/build containerized helpers like ReconFTW, Asnlookup, dnsvalidator, feroxbuster, trufflehog, CeWL, and Amass.
- After `./abb-setup.sh utilities` completes, inspect the generated WireGuard profiles, add any required Mullvad account details via the `mullvad-wg.sh` prompts, and connect with `sudo wg-quick up <config>`; verify the tunnel using `curl https://am.i.mullvad.net/json | jq`.
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
| `utilities` | Install core system utilities (tree, tealdeer (`tldr`), ripgrep, fd, zsh, fzf, bat, htop, iftop, tmux, wireguard-tools/openresolv, yazi, lazygit, firewalld, fail2ban, zoxide, etc.), enable services, bootstrap the chosen Node manager (`nvm` or `fnm`), configure the selected container engine (`docker` + `lazydocker` or `podman`), and automate Mullvad WireGuard provisioning. |
| `tools` | Use pipx for recon utilities (waymore, Sublist3r, webscreenshot, etc.), install `pdtm` via Go to manage ProjectDiscovery binaries (subfinder, dnsx, naabu, httpx, nuclei, uncover, cloudlist, proxify, tlsx, notify, chaos-client, shuffledns, mapcidr, interactsh-server/client, katana), `go install` for the remaining recon/XSS helpers (anew, gauplus, ipcdn, s3scanner, fuzzuli, and more), handle recon packages via pacman (`amass`), install feroxbuster via `cargo install --locked --force feroxbuster` or the selected AUR helper based on your prompt choice, optionally install trufflehog via the official script, and clone/git-sync tooling and wordlists (massdns, masscan, SecLists, cent, permutations/resolvers, JSParser, lazyrecon, Mullvad-CLI, etc.) into `/opt/vps-tools`. The dnsvalidator helper is covered by the Docker task when Docker is selected. |
| `dotfiles` | Install Oh My Zsh, sync Arch-specific `.zshrc` and `.aliases`, install curated Zsh plugins, copy tmux/vim configs, and bootstrap LazyVim if requested. |
| `verify` | Run post-install checks (`pacman -Q` for key packages, `<aur-helper> --version`, `pipx list`, `go version`) and point to log locations. |
| `docker-tools` | Pull or build Docker-based helpers (ReconFTW image + wrapper, Asnlookup Dockerfile, dnsvalidator Dockerfile, feroxbuster Docker wrapper, trufflehog Docker wrapper, Amass + CeWL image wrappers) when Docker is the chosen container engine. ReconFTW also downloads `reconftw.cfg`, seeds it under `/opt/vps-tools/reconftw/`, copies it to `~/.config/reconftw/reconftw.cfg`, and the wrapper mounts the config plus an output directory (default `ReconFTW/`) into the container. The feroxbuster wrapper respects `~/.config/feroxbuster/ferox-config.toml` and is aliased as `feroxbuster`; use `trufflehog-docker` to run the containerised trufflehog scanner. |
## Highlights
- **AUR helper first:** The package-manager stage installs and caches the selected helper (`yay` by default) before any tooling that depends on it.
- **Tool tracking:** Each successful install is appended to `~<user>/installed-tools.txt` so you can review or diff between runs.
- **No SSH tweaks:** Contabo already provisions keys; the script leaves `sshd_config` untouched while still offering optional sysctl/iptables hardening on demand.
- **Arch-friendly dotfiles:** Zsh configuration includes Arch paths, tealdeer integration for `tldr`, zoxide initialisation, guarded Node manager/LazyVim hooks, and a ready-to-use `feroxbuster` alias that drives the Docker wrapper.
- **tmux ready:** Configuration lands in `~/.config/tmux/tmux.conf`, keeps `C-b` as the prefix, enables clipboard sync, and bootstraps TPM automatically on first launch.
- **Wordlist workspace:** `SecLists` lives in `/opt/vps-tools/SecLists` with a symlink at `~/wordlists/seclists`; the tools stage also syncs the cent repository and fetches permutations/resolvers lists alongside `~/wordlists/custom` for personal mutations.
- **WireGuard ready:** Utilities install `wireguard-tools`/`openresolv`, run `mullvad-wg.sh`, patch WireGuard configs to keep SSH on the main table, and drop the Mullvad CLI helper in `~/bin`.
- **BlackArch repo:** The package-manager stage writes `/etc/pacman.d/blackarch.conf`, plugs it into `/etc/pacman.conf`, briefly disables signature checks to install `blackarch-keyring`, restores verification, enables multilib, forces `pacman -Syyu`, and then builds your chosen AUR helper.
- **Container flexibility:** Pick Docker (with lazydocker) or Podman during prompts; utilities enables the requested engine and grants the managed user access, and the `docker-tools` task adds ReconFTW (with managed `reconftw.cfg` + writable output mapping), Asnlookup, dnsvalidator, feroxbuster (config-aware wrapper), trufflehog, CeWL, and Amass when Docker is present.
- **Rust-ready toolchain:** Languages install `rustup`, set the default stable toolchain, and extend PATHs so cargo-built utilities (including feroxbuster) work out of the box.
- **Trufflehog choice:** Decide once whether to install the upstream trufflehog binary; if you skip it, the Docker wrapper remains available (`trufflehog-docker`).
- **Release-friendly tools:** JSParser installs through pipx while keeping a local checkout, and the latest JSHawk release script is downloaded directly into `/usr/local/bin/jshawk`.

## Rerun Guidance
- Re-running any task is safe; prompts are cached in `/var/lib/vps-setup/answers.env`.
- If kernel or core packages update, reboot and rerun `verify` to confirm paths and versions.
- Use your configured AUR helper (e.g., `yay -Syu`) between provisioning runs to keep AUR packages in sync.
