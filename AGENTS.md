# ABB - Arch Bugbounty Bootstrap Playbook

Arch Linux (btw ^_^). ABB automates bug bounty VPS provisioning end-to-end. Leverage `pacman` for core packages, the selected AUR helper for community packages, and keep the automation modular: `abb-setup.sh` must accept `prompts`, `accounts`, `package-manager`, `security`, `languages`, `utilities`, `network-access`, `tools`, `ai-tools`, `dotfiles`, `monitoring`, `verify`, and `all`.

## Related AGENTS Files

- Architecture notes: `agents/architecture.md`
- AGENTS next steps and branch tasks: `agents/next-steps.md`
- Repo-level AGENTS rules: `agents/rules.md`
- Working memory:
  - `agents/memory/branches.md`
  - `agents/memory/decisions.md`
  - `agents/memory/history.md`
  - `agents/memory/progress.md`
- Task tracking:
  - `agents/tasks/active.md`
  - `agents/tasks/backlog.md`
  - `agents/tasks/done.md`

## 1. Interactive Prompts
- Ask for the target username. The VPS image ships with `admin`; capture the new account name and record it for automation.
- Skip SSH credential prompts. Contabo already injects keys.
- Ask which editor to configure (`vim`, `neovim`, or `both`).
- Ask which Node version manager to deploy (`nvm` or `fnm`).
- Ask whether access should remain plain SSH or move to Tailscale-backed SSH.
- Ask how ABB should seed `authorized_keys` for the managed user (`current-access`, `admin`, `paste`, or `skip`).
- Ask whether VPN support should be configured at all. Default to `no`.
- If VPN is enabled, ask which provider to use (`mullvad` or `protonvpn`).
- Ask whether monitoring should be installed at all. Default to `no`.
- If monitoring is enabled, ask whether to enable system monitoring (`auditd` / `auditctl`).
- Persist answers to `/var/lib/vps-setup/answers.env` so re-runs stay idempotent.

## 2. Account Handling
- When a new managed username is requested, provision it with:
  ```bash
  sudo useradd -m -s /bin/bash "${NEW_USER}"
  sudo passwd "${NEW_USER}"
  sudo usermod -aG wheel "${NEW_USER}"
  sudo sed -i 's/^[[:space:]]*#\s*\(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
  ```
- Suggest reconnecting via SSH as `${NEW_USER}`, relocating the ABB repository under their home, and then offer to remove the legacy `admin` account:
  ```bash
  sudo deluser --remove-home admin || true
  sudo userdel -r admin
  ```
- After logging in as `${NEW_USER}`, require the operator to update and reboot before continuing:
  ```bash
  sudo pacman -Syu
  sudo pacman -S linux
  sudo reboot
  ```
- Ensure the resulting account belongs to `wheel`; warn if provisioning is still happening as `root`.

## 3. Package Manager
- Before installing the helper, integrate the BlackArch repository:
  - Write `/etc/pacman.d/blackarch.conf` with:
  ```
  [blackarch]
  Server = https://www.blackarch.org/blackarch/$repo/os/$arch
  ```
  - Append `Include = /etc/pacman.d/blackarch.conf` to `/etc/pacman.conf` if it is not already present.
  - Temporarily add `SigLevel = Never` to the BlackArch stanza, run `pacman -Sy blackarch-keyring`, then remove the override and force-refresh pacman with `pacman -Syyu`.
  - Enable `multilib` in `/etc/pacman.conf` if missing. Do **not** install the `blackarch` meta-package.
- After reconnecting as the managed user, install and cache the preferred AUR helper (choices: `yay`, `paru`, `pacaur`, `pikaur`, `aura`, `aurman`) and persist the choice so future runs skip reinstallation:
  ```bash
  sudo pacman --needed --noconfirm -S base-devel
  sudo -u "${NEW_USER}" bash -lc '
    tmp=$(mktemp -d)
    helper_pkg="<aur-package-name>" # yay, paru-bin, pacaur, etc.
    git clone "https://aur.archlinux.org/${helper_pkg}.git" "$tmp/${helper_pkg}"
    cd "$tmp/${helper_pkg}" && makepkg -si --noconfirm --needed
  '
  ```
- Store the helper selection in `/var/lib/vps-setup/answers.env` so subsequent tasks rely on it instead of reinstalling.

## 4. System Updates
```bash
sudo pacman -Syu --noconfirm
```
- Reboot if the kernel updates. Re-run the script afterwards (state is cached).

## 5. Network Access
- Keep SSH access management in a dedicated `network-access` task.
- Do **not** modify `sshd_config`; Contabo manages it.
- Support either plain SSH or Tailscale-backed SSH, driven by a prompt saved in `answers.env`.
- Allow ABB to seed `authorized_keys` by copying from the current access user, copying from `admin`, or appending a pasted SSH public key.
- If Tailscale is selected, install it via the official installer flow, bring up `tailscaled`, and pause for explicit operator confirmation before removing public SSH exposure.
- Restrict SSH with firewall rules rather than `sshd_config`, allowing SSH on `tailscale0` while removing public SSH from the default zone only after the operator has validated a second session.
- Optional sysctl hardening lives here, not in `security`.

## 6. Logging & Tracking
- Log all stdout/stderr to `/var/log/vps-setup.log` using `tee` while still echoing key status messages.
- Maintain `~${NEW_USER}/installed-tools.txt`, appending each tool once it is installed and detected on `PATH`.

## 7. Language Runtimes (install before tools)
- Python & pipx: `sudo pacman --needed --noconfirm -S python python-pipx python-setuptools`
- Go: `sudo pacman --needed --noconfirm -S go`
- Ruby & build deps: `sudo pacman --needed --noconfirm -S ruby base-devel`
- Rust: `sudo pacman --needed --noconfirm -S rustup` then `rustup default stable` for the managed user.
- Run `pipx ensurepath` for the managed user; record versions for logs.

## 8. System Utilities
- Install (via pacman): `tree`, `tldr` (use the `tealdeer` package), `ripgrep`, `fd`, `zsh`, `bat`, `htop`, `iftop`, `tmux`, `neovim`, `vim`, `curl`, `wget`, `unzip`, `tar`, `firewalld`, `fail2ban`, `zoxide`, `wireguard-tools`, `openresolv`.
- Enable services as appropriate (`firewalld`, `fail2ban`). Avoid duplicates across the curated package list.
- Install the requested Node manager (`nvm` or `fnm`) for the managed user.

## 9. VPN
- VPN support must be opt-in and default to `no`.
- Verify the kernel is >=5.11 before configuring WireGuard-backed VPN access.
- For Mullvad, download `mullvad-wg.sh` to a temporary location, execute it once to generate profiles, and remove the script immediately afterwards.
- For ProtonVPN, prepare for manual WireGuard config import instead of forcing a desktop/client install path on a headless VPS.
- Copy pristine profiles into `/opt/wg-configs/source`, duplicate them into `/opt/wg-configs/pool`, and inject the SSH-preserving `PostUp`/`PreDown` rules only into the pooled copies (leave `/etc/wireguard/*.conf` untouched). Point `/opt/wg-configs/active/wg0.conf` at the profile currently used by Docker.
- Maintain `~/wireguard-profiles.txt` (one profile per line) so helper scripts can pick a config.

## 10. Tool Catalogue
### 10.1 pipx & ProjectDiscovery
- Use `pipx` for: waymore, xnLinkFinder, urless, xnldorker, Sublist3r, dirsearch, sqlmap, knockpy, webscreenshot.
- Install `pdtm` via Go and remind the operator to run `pdtm install ...` (or `pdtm install-all`) manually after the environment is ready; ABB does not auto-install ProjectDiscovery binaries.

### 10.2 Go Tools
- Use `go install ...@latest` for the remaining recon utilities:
  - Recon: anew, assetfinder, gau, gauplus, waybackurls, hakrawler, hakrevdns, ipcdn, puredns, socialhunter, subzy, getJS, crobat, gotator, gowitness, httprobe, gospider, ffuf, gobuster, qsreplace, meg, s3scanner.
  - XSS & parameters: Gxss, bxss, kxss, dalfox, Tok, parameters, Jeeves, galer, quickcert, fuzzuli, anti-burl, unfurl, fff, gron.
  - Misc: github-subdomains, exclude-cdn, dirdar, cero, cf-check, otx-url, mrco24-* binaries.
- Deduplicate anything already managed by `pdtm`.

### 10.3 Trufflehog
- Install trufflehog from the `tools` task via the official script (`curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin`).
- If the script fails, offer to build from source or point to the operator's external container/compose repository.

### 10.4 Git/Binary Installs
- Keep cloning into `/opt/vps-tools/<name>` (root:wheel 755). Add wrappers in `/usr/local/bin` when needed.
- Tools & data: teh_s3_bucketeers, lazys3, virtual-host-discovery, lazyrecon, massdns (build via `make`), masscan (build via `make -j && make install`), SecLists (trim Jhaddix wordlist and surface under `~/wordlists`), cent wordlists (symlink to `~/wordlists/cent`), permutations/resolvers text files, JSParser (install via pipx; wrapper under `/usr/local/bin/jsparser`), DNSCewl (downloaded to `/usr/local/bin/DNSCewl`), Aquatone from release binaries, etc.

### 10.5 Docker Assets
- ABB only installs/configures the selected container engine (`docker`, `podman`, or none).
- Docker/container assets, compose files, images, and helper scripts live outside ABB in the operator's dedicated container repository.
- ABB must not sync compose files, Dockerfiles, or wrapper scripts into `/opt` or any ABB-owned path.

### 10.6 Recon Packages
- Install `amass` via pacman (`pacman --needed --noconfirm -S amass`).
- Install feroxbuster from the `tools` task without a separate prompt path.

## 11. Shells & Editors
- After installing zsh + Oh My Zsh, copy the Arch-friendly `.zshrc` and `.aliases` from `dots/zsh/`.
- Update plugin installer to match the curated plugin list (cd-ls, alias-tips, zsh-vi-mode, zsh-history-substring-search, zsh-syntax-highlighting, zsh-autosuggestions, zsh-aur-install).
- Editors:
  - `vim`: copy `dots/vim/.vimrc`.
  - `neovim`: clone LazyVim starter with `git clone https://github.com/LazyVim/starter ~/.config/nvim`, overlay ABB-managed plugin files from `dots/nvim/`, and run `nvim --headless '+Lazy! sync' +qa`.
- Copy the tmux config to `~/.config/tmux/tmux.conf` and bootstrap TPM if missing.

## 12. README
- Create an emoji-free README summarizing:
  - Arch prerequisites and the workflow for migrating away from the pre-existing `admin` account.
  - Modular tasks and how to run them (`./abb-setup.sh prompts`, etc.).
  - Installed languages, yay usage, system utilities, and recon tooling.
  - Log file location and rerun guidance.

## 13. Verification
- Provide a `verify` task that confirms:
  - `pacman -Q` versions for key packages.
  - `yay --version`.
  - `pipx list` output.
  - Location of `installed-tools.txt` and `/var/log/vps-setup.log`.
- Encourage a reboot after full provisioning.

## 14. Monitoring
- Monitoring must be a dedicated final-stage module that runs after the other installation/configuration work.
- Keep monitoring focused on system auditing via `auditd/auditctl`.
