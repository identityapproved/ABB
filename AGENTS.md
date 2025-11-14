# ABB – Arch Bugbounty Bootstrap Playbook

Arch Linux (btw ♥). ABB automates bug bounty VPS provisioning end-to-end. Leverage `pacman` for core packages, the selected AUR helper for community packages, and keep the automation modular: `abb-setup.sh` must accept `prompts`, `accounts`, `package-manager`, `security`, `languages`, `utilities`, `tools`, `dotfiles`, `verify`, `docker-tools`, and `all`.

## 1. Interactive Prompts
- Ask for the target username. The VPS image ships with `admin`; capture the new account name and record it for automation.
- Skip SSH credential prompts. Contabo already injects keys.
- Ask which editor to configure (`vim`, `neovim`, or `both`).
- Ask which Node version manager to deploy (`nvm` or `fnm`).
- Persist answers to `/var/lib/vps-setup/answers.env` so re-runs stay idempotent.

## 2. Account Handling
- When a new managed username is requested, provision it with:
  ```bash
  sudo useradd -m -s /bin/bash "${NEW_USER}"
  sudo passwd "${NEW_USER}"
  sudo usermod -aG wheel "${NEW_USER}"
  sudo sed -i 's/^[[:space:]]*#\s*\(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
  sudo mkdir -p "/home/${NEW_USER}/.ssh"
  sudo cp /home/admin/.ssh/authorized_keys "/home/${NEW_USER}/.ssh/"
  sudo chown -R "${NEW_USER}:${NEW_USER}" "/home/${NEW_USER}/.ssh"
  sudo chmod 700 "/home/${NEW_USER}/.ssh"
  sudo chmod 600 "/home/${NEW_USER}/.ssh/authorized_keys"
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
- Before installing the helper, offer the operator the choice to integrate the BlackArch repository. If they decline, skip the rest of this section. When accepted:
  - Write `/etc/pacman.d/blackarch.conf` with:
  ```
  [blackarch]
  Server = ${BLACKARCH_MIRROR:-https://www.blackarch.org/blackarch}/$repo/os/$arch
  ```
    (ABB automatically substitutes `BLACKARCH_MIRROR` if the operator exports it; otherwise it falls back to the upstream URL.)
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

## 5. SSH & Hardening
- Do **not** modify SSH keys or `sshd_config`; Contabo manages them.
- Provide an optional network hardening step (sysctl + iptables) and offer it only on request. Skip vpntables if iptables/nftables are absent.

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
- Install (via pacman): `tree`, `tldr` (use the `tealdeer` package), `ripgrep`, `fd`, `zsh`, `fzf`, `bat`, `htop`, `iftop`, `lsof`, `tmux`, `neovim`, `vim`, `curl`, `wget`, `unzip`, `tar`, `firewalld`, `fail2ban`, `zoxide`, `wireguard-tools`, `openresolv`.
- Enable services as appropriate (`firewalld`, `fail2ban`). Avoid duplicates across the curated package list.
- Install the requested Node manager (`nvm` or `fnm`) for the managed user.

## 9. VPN Providers

### Mullvad WireGuard
- Verify the kernel is ≥5.11 before configuring Mullvad WireGuard.
- Download `mullvad-wg.sh` to a temporary location, execute it once to generate profiles, and remove the script immediately afterwards.
- Keep the VPS-focused Mullvad configs under `/etc/wireguard` but inject the SSH-preserving `PostUp`/`PreDown` rules directly there. The legacy Mullvad container assets remain under `docker/images/wg-vpn` (with rotation helper scripts under `docker/scripts/`) in case you reintroduce that workflow later, but the default Docker path now assumes the namespace-based OpenVPN flow.
- Maintain `~/wireguard-profiles.txt` (one profile per line) so helper scripts can pick a config, and remind the operator to connect with `sudo wg-quick up <profile>` / `curl https://am.i.mullvad.net/json | jq`.

- Install `openvpn`, `openresolv`, and related tooling for the managed user, keeping `.ovpn` profiles under `/opt/openvpn-configs`. Document that the helper syncs from `~/openvpn-configs` automatically.
- Provide `scripts/openvpn-connect.sh` to manage OpenVPN directly on the host (start/stop/status/rotate/list/sync). The script must:
  - Sync configs from `~/openvpn-configs`.
  - Read credentials from `credentials.txt` (or `credentials.text`) under `/opt/openvpn-configs` and enforce `chmod 600`.
  - Preserve basic connectivity by pinning a host route for the VPN gateway before `openvpn` adjusts the default route, restoring everything on stop.
  - Log to `/var/log/openvpn-host.log`, track state under `/var/run/openvpn-host`, and use `/etc/openvpn/update-resolv-conf`.
- Keep `scripts/openvpn-rotate.sh` as a compatibility wrapper that simply calls the new host script.
- Ship `scripts/ssh-bypass.sh` so operators can configure a persistent iptables/ip rule bypass for SSH (default port 22, mark 22, table 128) and restore it later; follow the manual snippet provided by the user (iptables-save to `/etc/iptables.rules`, ensure `/etc/rc.local` runs `iptables-restore`).
- Update README / NEXT_STEPS / docker docs to describe the host wrapper workflow and remove references to ProtonVPN namespaces or custom Docker sockets.

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
- Prompt the operator to decide whether to install trufflehog via the official script (`curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin`). Honour the saved preference on reruns.
- If the script fails (or the operator declines), offer to build from source or point to the docker-compose stack (`docker-compose.trufflehog.yml`) inside `/opt/abb-docker`.

### 10.4 Git/Binary Installs
- Keep cloning into `/opt/vps-tools/<name>` (root:wheel 755). Add wrappers in `/usr/local/bin` when needed.
- Tools & data: teh_s3_bucketeers, lazys3, virtual-host-discovery, lazyrecon, massdns (build via `make`), masscan (build via `make -j && make install`), SecLists (trim Jhaddix wordlist and keep under `~/wordlists/SecLists`), cent wordlists (`~/wordlists/cent`), permutations/resolvers text files, JSParser (install via pipx; wrapper under `/usr/local/bin/jsparser`), DNSCewl (downloaded to `/usr/local/bin/DNSCewl`), Aquatone from release binaries, etc. Run `./abb-setup.sh wordlists` whenever you need to refresh SecLists/cent/permutations/resolvers/rockyou, or opt into the heavier Auto_Wordlists and Assetnote mirrors via the prompts shown during that module.

### 10.5 Docker Assets
- Instead of installing CLI wrappers, copy the entire `docker/` folder to `/opt/abb-docker` so the operator can run stacks with `docker compose -f /opt/abb-docker/compose/docker-compose.<tool>.yml ...`.
- Provide compose files for the WireGuard VPN, ReconFTW, Asnlookup, dnsvalidator, feroxbuster, trufflehog, CeWL, Amass, and the lightweight test client stack. Asnlookup/dnsvalidator compose files rely on the accompanying Dockerfiles under `docker/images/`.
- Ship helper scripts (e.g., `rotate-wg.sh`) under `docker/scripts/` and ensure they are executable after syncing.
- Compose files should rely on Docker's default bridge networking; remove references to custom namespace sockets or bespoke network-mode environment variables.

### 10.6 Recon Packages
- Install `amass` via pacman (`pacman --needed --noconfirm -S amass`).
- Feroxbuster is handled separately based on the operator's chosen installation method (`cargo` or selected AUR helper). Document the prompt and ensure reruns honour the saved choice.

## 11. Shells & Editors
- After installing zsh + Oh My Zsh, copy the Arch-friendly `.zshrc` and `.aliases` from `dots/zsh/`.
- Update plugin installer to match the curated plugin list (cd-ls, zsh-git-fzf, alias-tips, fzf-alias, zsh-vi-mode, zsh-history-substring-search, zsh-syntax-highlighting, zsh-autosuggestions, zsh-aur-install).
- Editors:
  - `vim`: copy `dots/vim/.vimrc`.
  - `neovim`: clone LazyVim starter with `git clone https://github.com/LazyVim/starter ~/.config/nvim` and run `nvim --headless '+Lazy! sync' +qa`.
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
