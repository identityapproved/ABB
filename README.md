# ABB – Arch Bugbounty Bootstrap

ABB is an Arch Linux–first automation toolkit for provisioning bug bounty VPS instances. The image provided by Contabo already creates an `admin` user and injects SSH keys, so the scripts focus on guiding any account rename, installing required tooling, and keeping the process modular.

## Quick Start
- Log in as `root` (or a wheel user) on the Arch VPS.
- Ensure git is available for cloning: `sudo pacman -S --needed git`.
- Clone the repo and run `./abb-setup.sh prompts` to answer the interactive questions (username, editor choice, hardening flag).
- Execute `./abb-setup.sh accounts` to create the managed user, copy SSH keys from `admin`, enable sudo, and optionally retire the legacy account. After logging in as the new user, rerun the accounts task to remove `admin`, and move the ABB repo under the new home.
- Execute individual tasks (see below) or run the entire workflow with `./abb-setup.sh all`.
- Inspect `/var/log/vps-setup.log` for the consolidated log and `~<user>/installed-tools.txt` for a simple tool inventory.

## Modular Tasks
Each task can be executed independently:

| Task | Description |
| ---- | ----------- |
| `prompts` | Capture answers for the managed user, editor preference, and hardening toggle; cache responses in `/var/lib/vps-setup/answers.env`. |
| `accounts` | Create the managed user, ensure wheel access, copy SSH credentials from `admin`, prompt for password, and offer to remove `admin` after switching. |
| `security` | Run `pacman -Syu`, apply optional sysctl/iptables hardening, and install/configure AIDE + rkhunter with sudo logging. |
| `languages` | Install Python, pipx, Go, Ruby, and base build tools. |
| `utilities` | Install yay (AUR helper), tree, tealdeer (`tldr`), ripgrep, fd, zsh, fzf, bat, htop, iftop, tmux, firewalld, fail2ban, zoxide, chromium, and supporting CLI tools. Services are enabled where appropriate. |
| `tools` | Use pipx for recon utilities, pdtm for ProjectDiscovery binaries (subfinder, dnsx, naabu, httpx, nuclei, uncover, cloudlist, proxify, tlsx, notify, chaos-client, shuffledns, mapcidr, interactsh-server/client, katana), `go install` for the remaining recon/XSS helpers, and clone git-based tooling into `/opt/vps-tools`. |
| `dotfiles` | Install Oh My Zsh, sync Arch-specific `.zshrc` and `.aliases`, install curated Zsh plugins, copy tmux/vim configs, and bootstrap LazyVim if requested. |
| `verify` | Run post-install checks (`pacman -Q` for key packages, `yay --version`, `pipx list`, `go version`) and point to log locations. |

## Highlights
- **Yay first:** The utilities stage ensures `yay` is available before touching AUR packages such as `mullvad-vpn`.
- **Tool tracking:** Each successful install is appended to `~<user>/installed-tools.txt` so you can review or diff between runs.
- **No SSH tweaks:** Contabo already provisions keys; the script leaves `sshd_config` untouched while still offering optional sysctl/iptables hardening on demand.
- **Arch-friendly dotfiles:** Zsh configuration includes Arch paths, tealdeer integration for `tldr`, zoxide initialisation, and guarded `fnm`/LazyVim hooks.

## Rerun Guidance
- Re-running any task is safe; prompts are cached in `/var/lib/vps-setup/answers.env`.
- If kernel or core packages update, reboot and rerun `verify` to confirm paths and versions.
- Use `yay -Syu` between provisioning runs to keep AUR packages in sync.

Happy Arching (¬‿¬)
