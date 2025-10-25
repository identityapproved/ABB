# Arch VPS Provisioning Playbook

Arch Linux (btw ♥). Replace the legacy Rocky scripts with an Arch-first workflow. Leverage `pacman` for core packages, `yay` for AUR installs, and keep the automation modular: `arch-setup.sh` must accept `prompts`, `security`, `languages`, `utilities`, `tools`, `dotfiles`, `verify`, and `all`.

## 1. Interactive Prompts
- Ask for the target username. The VPS image ships with `admin`; rename that account when a different name is requested.
- Skip SSH credential prompts. Contabo already injects keys.
- Ask which editor to configure (`vim`, `neovim`, or `both`).
- Persist answers to `/var/lib/vps-setup/answers.env` so re-runs stay idempotent.

## 2. Account Handling
- When the user provides a new name, run:
  ```bash
  sudo usermod -l "${NEW_USER}" admin
  sudo usermod -d "/home/${NEW_USER}" -m "${NEW_USER}"
  sudo groupmod -n "${NEW_USER}" admin || true
  ```
- Ensure the resulting account belongs to `wheel`; warn if provisioning is still happening as `root`.

## 3. System Updates
```bash
sudo pacman -Syu --noconfirm
```
- Reboot if the kernel updates. Re-run the script afterwards (state is cached).

## 4. SSH & Hardening
- Do **not** modify SSH keys or `sshd_config`; Contabo manages them.
- Provide an optional network hardening step (sysctl + iptables) that mirrors the old Rocky logic, but only on request. Skip vpntables if iptables/nftables are absent.

## 5. Logging & Tracking
- Log all stdout/stderr to `/var/log/vps-setup.log` using `tee` while still echoing key status messages.
- Maintain `~${NEW_USER}/installed-tools.txt`, appending each tool once it is installed and detected on `PATH`.

## 6. Language Runtimes (install before tools)
- Python & pipx: `sudo pacman --needed --noconfirm -S python python-pipx`
- Go: `sudo pacman --needed --noconfirm -S go`
- Ruby & build deps: `sudo pacman --needed --noconfirm -S ruby base-devel`
- Run `pipx ensurepath` for the managed user; record versions for logs.

## 7. Yay Bootstrap
- Install `yay` immediately after prompts:
  ```bash
  sudo pacman --needed --noconfirm -S base-devel git
  sudo -u "${NEW_USER}" bash -lc '
    tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    cd "$tmp/yay" && makepkg -si --noconfirm
  '
  ```
- Once `yay` exists, use it for AUR tools that lack official packages.

## 8. System Utilities
- Install (via pacman): `tree`, `tldr` (use the `tealdeer` package), `ripgrep`, `fd`, `zsh`, `fzf`, `bat`, `htop`, `iftop`, `tmux`, `neovim`, `vim`, `git`, `curl`, `wget`, `unzip`, `tar`, `firewalld`, `fail2ban`, `zoxide`.
- Enable services as appropriate (`firewalld`, `fail2ban`). Avoid duplicates—many overlap with the old Rocky list.
- Include optional extras when requested: `mullvad-vpn` via AUR, etc.

## 9. Tool Catalogue
### 9.1 pipx & ProjectDiscovery
- Use `pipx` for: waymore, xnLinkFinder, urless, xnldorker, reconFTW, JSHawk, Sublist3r, dirsearch, sqlmap, JSParser, knockpy, asnlookup.
- Install `pdtm` with pipx, then provision all ProjectDiscovery tools through it (`subfinder`, `dnsx`, `naabu`, `httpx`, `nuclei`, `uncover`, `cloudlist`, `proxify`, `tlsx`, `notify`, `chaos-client`, `shuffledns`, `mapcidr`, `interactsh-server`, `interactsh-client`, `katana`). Place binaries in `~/.local/bin`.

### 9.2 Go Tools
- Use `go install ...@latest` for the remaining recon utilities:
  - Recon: anew, assetfinder, waybackurls, hakrawler, puredns, gau, socialhunter, subzy, getJS, crobat, gowitness, httprobe, gospider, ffuf, gobuster, qsreplace.
  - XSS & parameters: Gxss, bxss, kxss, dalfox, Tok, parameters, Jeeves, galer, quickcert, anti-burl, unfurl, fff, gron.
  - Misc: github-subdomains, gotator, cero, cf-check, otx-url, mrco24-* binaries.
- Deduplicate anything already managed by `pdtm`.

### 9.3 Git/Binary Installs
- Keep cloning into `/opt/vps-tools/<name>` (root:wheel 755). Add wrappers in `/usr/local/bin` when needed.
- Tools: teh_s3_bucketeers, lazys3, virtual-host-discovery, lazyrecon, massdns (build via `make`), SecLists (trim Jhaddix wordlist), Aquatone from release binaries, etc.

## 10. Shells & Editors
- After installing zsh + Oh My Zsh, copy the Arch-friendly `.zshrc` and `.aliases` from `dots/zsh/`.
- Update plugin installer to match the curated plugin list (cd-ls, zsh-git-fzf, alias-tips, fzf-alias, zsh-vi-mode, zsh-history-substring-search, zsh-syntax-highlighting, zsh-autosuggestions, zsh-aur-install).
- Editors:
  - `vim`: copy `dots/vim/.vimrc`.
  - `neovim`: clone LazyVim starter with `git clone https://github.com/LazyVim/starter ~/.config/nvim` and run `nvim --headless '+Lazy! sync' +qa`.
- Copy the tmux config to `~/.tmux.conf`.

## 11. README
- Create an emoji-free README summarizing:
  - Arch prerequisites and the pre-existing `admin` account rename.
  - Modular tasks and how to run them (`./arch-setup.sh prompts`, etc.).
  - Installed languages, yay usage, system utilities, and recon tooling.
  - Log file location and rerun guidance.

## 12. Verification
- Provide a `verify` task that confirms:
  - `pacman -Q` versions for key packages.
  - `yay --version`.
  - `pipx list` output and presence of PD binaries in `~/.local/bin`.
  - Location of `installed-tools.txt` and `/var/log/vps-setup.log`.
- Encourage a reboot after full provisioning.
