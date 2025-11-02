# ABB – Arch Bugbounty Bootstrap

ABB is an Arch Linux–first automation toolkit for provisioning bug bounty VPS instances. The image provided by Contabo already creates an `admin` user and injects SSH keys, so the scripts focus on guiding any account rename, installing required tooling, and keeping the process modular.

## Prerequisites
- Install `git` ahead of time so you can clone this repository.
- Install `vim` on the VPS before running any ABB tasks: `sudo pacman -S --needed vim`.

## Quick Start
- Log in as `root` (or a wheel user) on the Arch VPS.
- Clone the repo and run `./abb-setup.sh prompts` to answer the interactive questions (username, editor choice, hardening flag, Node manager preference `nvm` or `fnm`, container engine `docker`/`podman`/`none`).
- Execute `./abb-setup.sh accounts` to create the managed user, copy SSH keys from `admin`, enable sudo, and optionally retire the legacy account. The task exits so you can reconnect as the new user. After reconnecting, run `sudo pacman -Syu`, `sudo pacman -S linux`, and `sudo reboot`; once the system is back up, log in as the managed user, rerun `sudo ./abb-setup.sh accounts` to remove `admin`, then move the ABB repo under the new home.
- After reconnecting as the managed user, run `./abb-setup.sh package-manager` to install and cache your preferred AUR helper (`yay`, `paru`, `pacaur`, `pikaur`, `aura`, or `aurman`).
- Continue with `./abb-setup.sh all` (or the individual tasks you need) to complete provisioning.
- If you chose Docker during prompts, run `./abb-setup.sh docker-tools` (included in `all`) to pull/build containerized helpers like ReconFTW and Asnlookup.
- Finish with `./abb-setup.sh vpn-bypass` (automatically included in `all`) if you want an iptables policy route that preserves SSH reachability while a VPN is active.
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
| `languages` | Install Python, pipx, setuptools, Go, Ruby, and base build tools. |
| `utilities` | Install core system utilities (tree, tealdeer (`tldr`), ripgrep, fd, zsh, fzf, bat, htop, iftop, tmux, wireguard-tools, yazi, lazygit, firewalld, fail2ban, zoxide, etc.), enable services, install `mullvad-vpn-bin`, bootstrap the chosen Node manager (`nvm` or `fnm`), and configure the selected container engine (`docker` + `lazydocker` or `podman`). |
| `tools` | Use pipx for recon utilities (waymore, Sublist3r, dnsvalidator, webscreenshot, etc.), install `pdtm` via Go to manage ProjectDiscovery binaries (subfinder, dnsx, naabu, httpx, nuclei, uncover, cloudlist, proxify, tlsx, notify, chaos-client, shuffledns, mapcidr, interactsh-server/client, katana), `go install` for the remaining recon/XSS helpers (anew, gauplus, ipcdn, s3scanner, trufflehog, fuzzuli, and more), manage pacman recon packages (`amass`, `masscan`, `feroxbuster`), and clone/git-sync tooling and wordlists (massdns, SecLists, cent, permutations/resolvers, JSParser, lazyrecon, etc.) into `/opt/vps-tools`. |
| `dotfiles` | Install Oh My Zsh, sync Arch-specific `.zshrc` and `.aliases`, install curated Zsh plugins, copy tmux/vim configs, and bootstrap LazyVim if requested. |
| `verify` | Run post-install checks (`pacman -Q` for key packages, `<aur-helper> --version`, `pipx list`, `go version`) and point to log locations. |
| `docker-tools` | Pull or build Docker-based helpers (ReconFTW image + wrapper, Asnlookup Dockerfile, CeWL image wrapper) when Docker is the chosen container engine. |
| `vpn-bypass` | Configure an iptables-based policy route so SSH traffic remains outside the VPN tunnel. |

## Highlights
- **AUR helper first:** The package-manager stage installs and caches the selected helper (`yay` by default) before any tooling that depends on it.
- **Tool tracking:** Each successful install is appended to `~<user>/installed-tools.txt` so you can review or diff between runs.
- **No SSH tweaks:** Contabo already provisions keys; the script leaves `sshd_config` untouched while still offering optional sysctl/iptables hardening on demand.
- **Arch-friendly dotfiles:** Zsh configuration includes Arch paths, tealdeer integration for `tldr`, zoxide initialisation, and guarded Node manager/LazyVim hooks.
- **tmux ready:** Configuration lands in `~/.config/tmux/tmux.conf`, keeps `C-b` as the prefix, enables clipboard sync, and bootstraps TPM automatically on first launch.
- **Wordlist workspace:** `SecLists` lives in `/opt/vps-tools/SecLists` with a symlink at `~/wordlists/seclists`; the tools stage also syncs the cent repository and fetches permutations/resolvers lists alongside `~/wordlists/custom` for personal mutations.
- **VPN bypass:** The `vpn-bypass` task offers a reusable iptables policy route so SSH sessions survive VPN activation.
- **Container flexibility:** Pick Docker (with lazydocker) or Podman during prompts; utilities enables the requested engine and grants the managed user access, and the `docker-tools` task adds ReconFTW, Asnlookup, and CeWL wrappers when Docker is present.
- **Release-friendly tools:** JSParser installs through pipx while keeping a local checkout, and the latest JSHawk release script is downloaded directly into `/usr/local/bin/jshawk`.

## Rerun Guidance
- Re-running any task is safe; prompts are cached in `/var/lib/vps-setup/answers.env`.
- If kernel or core packages update, reboot and rerun `verify` to confirm paths and versions.
- Use your configured AUR helper (e.g., `yay -Syu`) between provisioning runs to keep AUR packages in sync.
