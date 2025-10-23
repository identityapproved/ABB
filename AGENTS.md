# Rocky Blue Onyx Provisioning Playbook

Use this playbook to rewrite the legacy `install.sh`, `bounty-vps.sh`, and `additional.tools` automation for Rocky Linux 9.6 (Blue Onyx). Keep the process interactive where requested, install language runtimes before dependent tools, and prefer modern package sources (DNF, pipx, go install, rpm releases) over the Ubuntu/Kali steps in the original scripts.

## 1. Interactive Prompts
- Ask for the non-root username to create. Abort if the answer is empty or `root`.
- Ask whether to authenticate with SSH keys or passwords. If keys are chosen, prompt for the public key and confirm SSH access before disabling passwords.
- Ask which editor to configure: `vim`, `neovim`, or `both`.
- Record answers in the setup log so repeated runs can skip prompts when values already exist.

## 2. Account & Group Setup
```bash
sudo adduser "${NEW_USER}"
sudo passwd "${NEW_USER}"                # prompt for a strong password
sudo usermod -aG wheel "${NEW_USER}"
id "${NEW_USER}"
su - "${NEW_USER}" -c "sudo -l"
```
- Warn if the deployment currently runs as `root`; prefer the new wheel user for all subsequent actions.

## 3. System Updates & Repositories
```bash
sudo dnf -y upgrade
sudo dnf config-manager --set-enabled crb
sudo dnf -y install epel-release
sudo dnf -y update
```
- Reboot if the kernel updates.

## 4. SSH Authentication Policy
- If SSH keys are supplied, place them in `~${NEW_USER}/.ssh/authorized_keys`, fix permissions, and test an SSH login before changing server policy.
- Make a backup of `sshd_config` and then enforce hardened options:
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# Only disable passwords when key access is confirmed
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
if ! grep -q '^AllowUsers' /etc/ssh/sshd_config; then
  echo "AllowUsers ${NEW_USER}" | sudo tee -a /etc/ssh/sshd_config
fi
sudo systemctl reload sshd
```
- When passwords are chosen, leave `PasswordAuthentication` enabled but still forbid root logins.

## 5. SELinux Verification
- Run `getenforce` and `sestatus`; log the results and exit if the mode is not `Enforcing`.

## 6. Optional Bug-Bounty Network Hardening
- Offer to apply the hardened sysctl profile when setting up a pentesting VPS.
- If accepted, create `/etc/sysctl.d/99-rocky-hardening.conf` with the legacy network tweaks, then run `sudo sysctl --system`.
- Preserve original SSH routing when VPN rules are active:
```bash
GW=$(ip route | awk '/^default/ {print $3}')
sudo iptables -t mangle -A OUTPUT -p tcp --sport 22 -j MARK --set-mark 22
sudo ip rule add fwmark 22 table 128
sudo ip route add default via "$GW" table 128
sudo iptables-save | sudo tee /etc/iptables.rules
echo "iptables-restore < /etc/iptables.rules" | sudo tee -a /etc/rc.local
sudo chmod +x /etc/rc.local
```
- Make iptables persistence idempotent; check for existing rules before appending.

## 7. Intrusion Detection & Sudo Logging
```bash
sudo dnf -y install aide rkhunter
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
sudo rkhunter --update
sudo rkhunter --checkall
echo 'Defaults logfile="/var/log/sudo.log",log_input,log_output' | sudo tee /etc/sudoers.d/90-logging
sudo chmod 0440 /etc/sudoers.d/90-logging
```
- Schedule regular `aide --check` and `rkhunter --checkall` runs via cron or systemd timers.

## 8. Logging & Reporting
- Stream essential status messages to stdout, but route command chatter and errors to a log:
```bash
LOG_FILE=/var/log/vps-setup.log
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
```
- Maintain `~/installed-tools.txt` for the new user. Append each successfully installed tool once its binary is verified with `command -v`.

## 9. Language Runtime Stage (install before tools)
- Skip any runtime that already meets the minimum version requirements; record the detected version in the log.

### 9.1 Python 3 + pipx
```bash
sudo dnf install -y python3 python3-pip pipx
pipx ensurepath
python3 --version
pipx --version
```
- Prefer `pipx install` for Python utilities instead of `pip install --user`.

### 9.2 Go
- Check for `/usr/lib/golang` via `dnf info golang`. Install from DNF if the version is recent enough (`sudo dnf install -y golang`).
- When a newer release is required, download from `https://go.dev/dl/`, extract to `/usr/local/go`, export `GOROOT`/`GOPATH`, and update the PATH in the new user’s shell rc.
- Validate with `go version`.

### 9.3 Ruby
- Use `sudo dnf install -y ruby ruby-devel gcc make redhat-rpm-config`.
- Install bundler with `gem install bundler`, then run project-specific `bundle install` inside each tool directory.

### 9.4 Additional Runtimes
- `sudo dnf install -y awscli` (required by the old scripts).
- Offer optional installs for Node.js (`sudo dnf module install nodejs:18`) or Rust (`curl https://sh.rustup.rs -sSf | sh`) when new tools demand them. Document the choice in the log.

## 10. Tool Catalogue & Installation Notes
Separate the tooling into system utilities, language managers, and bug-bounty/hacking suites. The lists below consolidate `install.sh`, `bounty-vps.sh`, and `additional.tools`.

### 10.1 System Utilities (DNF/RPM)
- firewalld, fail2ban, aide, rkhunter (already installed above).
- zsh, oh-my-zsh (use the official installer), tmux (copy `dots/tmux/tmux.conf` to `~${NEW_USER}/.tmux.conf`).
- mullvad-vpn (install from Mullvad’s RPM and enable the service when needed).
- bat, neovim, vim, fzf, ripgrep, fd-find (`dnf install -y fd-find`), git.
- chromium from EPEL (`sudo dnf install -y chromium`). Replace the Ubuntu snap step.

### 10.2 Programming Language Helpers
- pipx-managed: waymore, xnLinkFinder, urless, xnldorker (install via `pipx install git+https://github.com/...` and capture versions in `installed-tools.txt`).
- pdtm (ProjectDiscovery Tool Manager) to manage PD binaries (`pipx install pdtm` and use it for `subfinder`, `httpx`, `dnsx`, `mapcidr`, `chaos`, `nuclei`, `notify`, `katana`, `shuffledns`).

### 10.3 Go Binaries (from `bounty-vps.sh`)
- Install with `go install ...@latest` under the new user so the binaries land in `${HOME}/go/bin`. Key tools include:
  - ProjectDiscovery: subfinder, katana, dnsx, shuffledns, mapcidr, chaos, interactsh-client, nuclei, notify, cent.
  - Recon helpers: anew, assetfinder, waybackurls, hakrawler, puredns, gau, socialhunter, subzy, getJS, crobat, gowitness, httpx, httprobe, gospider, ffuf, gobuster, qsreplace.
  - XSS & parameter tools: Gxss, bxss, kxss, dalfox, Tok, parameters, Jeeves, gal er (galer), quickcert, anti-burl, unfurl, fff, gron.
  - Misc: github-subdomains, amass, chaos-client, gotator, cero, cf-check, otx-url, mrco24-* utilities, gowitness.
- Replace duplicate install entries (e.g., `shuffledns` listed twice) and log skipped duplicates.

### 10.4 Git-Based & Python Tools (from `install.sh`)
- Clone into `/opt/<tool>` (owned by root with group write for the wheel group) rather than the user’s home. Add wrapper scripts or aliases into `/usr/local/bin`.
- Tools to migrate: recon_profile (copy desired aliases instead of sourcing whole file), JSParser, Sublist3r, teh_s3_bucketeers, dirsearch, lazys3, virtual-host-discovery, sqlmap, knock.py, lazyrecon, massdns (build with `make`), asnlookup (install requirements via pipx run or virtualenv), Aquatone (prefer the official release from GitHub).
- wpscan requires Ruby bundler; configure an update command and capture the installed version.

### 10.5 Additional Packages
- Install `awscli` (already covered), `nmap`, `chromium`, and any extra wordlists or dependencies needed by the cloned tools.
- Document tools that no longer make sense on Rocky (e.g., Kali repositories); mark them as removed and delete the legacy sections from the old scripts after migrating functionality.

## 11. Shells, Editors & Dotfiles
- After `zsh` and Oh My Zsh install, copy `.zshrc` and `.aliases` templates from the repository into the new user’s home, adjust ownership, and extend `PATH` with `${HOME}/.local/bin`, `${HOME}/.local/pipx`, and `${HOME}/go/bin`.
- Editor selection:
  - `vim` or `both`: copy the maintained `.vimrc` into `~${NEW_USER}/.vimrc`.
  - `neovim`: install the LazyVim starter (`git clone https://github.com/LazyVim/starter ~/.config/nvim`) and run `nvim` once to sync plugins.
- Ensure tmux configuration is copied from `dots/tmux/tmux.conf` when tmux is installed.

## 12. Cleanup & Documentation
- Retire or rewrite the Ubuntu/Kali-specific logic in `install.sh` and `bounty-vps.sh` once their contents are covered by the new Rocky-focused automation.
- Remove obsolete files after confirming the new workflow, keeping changes tracked in version control.
- Produce a README (no emoji, (^_^) style kaomoji allowed) summarizing:
  - Created user and access method.
  - Applied hardening measures.
  - Language runtimes and key tool versions.
  - Log file location and how to rerun sections safely.

## 13. Verification
- Reboot and confirm:
  - SSH access works for the new user (keys/password as chosen).
  - `getenforce` returns `Enforcing`.
  - Required tools appear in `${HOME}/go/bin` or `/usr/local/bin`.
  - `installed-tools.txt` and `/var/log/vps-setup.log` exist and are readable by the wheel group.
- Document outstanding manual steps, if any, before handing off the VPS. (^_^)
