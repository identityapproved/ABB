# ABB – Arch Bugbounty Bootstrap Playbook

Arch Linux (btw ♥). ABB automates bug bounty VPS provisioning end-to-end. Leverage `pacman` for core packages, the selected AUR helper for community packages, and keep the automation modular: `abb-setup.sh` must accept `prompts`, `accounts`, `package-manager`, `security`, `languages`, `utilities`, `tools`, `dotfiles`, `verify`, `docker-tools`, `vpn-bypass`, and `all`.

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
- Ensure the resulting account belongs to `wheel`; warn if provisioning is still happening as `root`.

## 3. Package Manager
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
- Run `pipx ensurepath` for the managed user; record versions for logs.

## 8. System Utilities
- Install (via pacman): `tree`, `tldr` (use the `tealdeer` package), `ripgrep`, `fd`, `zsh`, `fzf`, `bat`, `htop`, `iftop`, `tmux`, `neovim`, `vim`, `curl`, `wget`, `unzip`, `tar`, `firewalld`, `fail2ban`, `zoxide`, `wireguard-tools`.
- Enable services as appropriate (`firewalld`, `fail2ban`). Avoid duplicates across the curated package list.
- Include optional extras when requested: `mullvad-vpn-bin` via the configured AUR helper, etc.
- Install the requested Node manager (`nvm` or `fnm`) for the managed user.

## 9. Tool Catalogue
### 9.1 pipx & ProjectDiscovery
- Use `pipx` for: waymore, xnLinkFinder, urless, xnldorker, Sublist3r, dirsearch, sqlmap, knockpy.
- Install `pdtm` with pipx, then provision all ProjectDiscovery tools through it (`subfinder`, `dnsx`, `naabu`, `httpx`, `nuclei`, `uncover`, `cloudlist`, `proxify`, `tlsx`, `notify`, `chaos-client`, `shuffledns`, `mapcidr`, `interactsh-server`, `interactsh-client`, `katana`). Place binaries in `~/.local/bin`.

### 9.2 Go Tools
- Use `go install ...@latest` for the remaining recon utilities:
  - Recon: anew, assetfinder, waybackurls, hakrawler, puredns, gau, socialhunter, subzy, getJS, crobat, gowitness, httprobe, gospider, ffuf, gobuster, qsreplace.
  - XSS & parameters: Gxss, bxss, kxss, dalfox, Tok, parameters, Jeeves, galer, quickcert, anti-burl, unfurl, fff, gron.
  - Misc: github-subdomains, gotator, cero, cf-check, otx-url, mrco24-* binaries.
- Deduplicate anything already managed by `pdtm`.

### 9.3 Git/Binary Installs
- Keep cloning into `/opt/vps-tools/<name>` (root:wheel 755). Add wrappers in `/usr/local/bin` when needed.
- Tools: teh_s3_bucketeers, lazys3, virtual-host-discovery, lazyrecon, massdns (build via `make`), SecLists (trim Jhaddix wordlist and surface under `~/wordlists`), JSParser (install via pipx; wrapper under `/usr/local/bin/jsparser`), Aquatone from release binaries, etc.

### 9.4 Docker Helpers
- When Docker is selected, offer wrappers for ReconFTW (`docker pull six2dez/reconftw:main`) and Asnlookup (build from the repository Dockerfile) that execute the containers via `/usr/local/bin/reconftw` and `/usr/local/bin/asnlookup`.

## 10. Shells & Editors
- After installing zsh + Oh My Zsh, copy the Arch-friendly `.zshrc` and `.aliases` from `dots/zsh/`.
- Update plugin installer to match the curated plugin list (cd-ls, zsh-git-fzf, alias-tips, fzf-alias, zsh-vi-mode, zsh-history-substring-search, zsh-syntax-highlighting, zsh-autosuggestions, zsh-aur-install).
- Editors:
  - `vim`: copy `dots/vim/.vimrc`.
  - `neovim`: clone LazyVim starter with `git clone https://github.com/LazyVim/starter ~/.config/nvim` and run `nvim --headless '+Lazy! sync' +qa`.
- Copy the tmux config to `~/.config/tmux/tmux.conf` and bootstrap TPM if missing.

## 11. README
- Create an emoji-free README summarizing:
  - Arch prerequisites and the workflow for migrating away from the pre-existing `admin` account.
  - Modular tasks and how to run them (`./abb-setup.sh prompts`, etc.).
  - Installed languages, yay usage, system utilities, and recon tooling.
  - Log file location and rerun guidance.

## 12. Verification
- Provide a `verify` task that confirms:
  - `pacman -Q` versions for key packages.
  - `yay --version`.
  - `pipx list` output and presence of PD binaries in `~/.local/bin`.
  - Location of `installed-tools.txt` and `/var/log/vps-setup.log`.
- Encourage a reboot after full provisioning.
