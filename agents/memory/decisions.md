# Decisions

## 2026-10-28

- Merged `testin` (8 commits, 2025-11-10) into main to keep its `wg-vpn` image fixes. They are old and unverified against current main and must be checked before a full or fresh ABB run (see `agents/tasks/active.md`). The `docker/compose/docker-compose.vpn.yml` they edited stays deleted, as main removed docker asset management on 2026-03-07. Container VPN on the VPS currently runs through gluetun.
- `archive/failed/openvpndocker` was not merged.

- Default access mode is now `tailscale-sshd`: the tailnet carries the traffic, OpenSSH authenticates. Reason: Tailworm (public 25.10.2026, unfixed as of 1.104.x) runs Tailscale SSH forwarding as root inside tailscaled. `tailscale-ssh` stays available behind a warning and a saved `TAILSCALE_SSH_RISK_ACCEPTED`; `plain-ssh` is unchanged.
- Replaces the 2026-03-17 "always `tailscale up --ssh`" decision. Already-up nodes use `tailscale set --ssh=<bool>` rather than `tailscale up`, which demands every non-default flag again.
- New saved answers: `PUBLIC_SSH_LOCKDOWN`, `SSH_FORWARDING` (default off), `SSH_PORT` (default 22). sshd gets `AllowUsers <managed user>` and explicit forwarding lines in `50-abb-hardening.conf`; the port lives in its own `40-abb-port.conf`.
- Lockout safety over speed: every change that can remove the current way in is two-phase (Tailscale SSH off with a systemd-run undo after 10 min; port change keeps the old port until the new one is confirmed). The contabo VPS lesson: a key Tailscale SSH never used turned out to have a forgotten-looking passphrase, so the breakpoint now says to check it.

## 2026-01-22

- Adopted the "router, not storage" AGENTS.md pattern.

## 2026-03-17

- Moved SSH/network handling into a dedicated `network-access` task instead of mixing it into accounts or utilities.
- Made VPN setup opt-in, defaulting to `no`, and added provider selection between `mullvad` and `protonvpn`.
- Kept ProtonVPN on a manual WireGuard import path for the headless VPS workflow instead of forcing a desktop/client flow.
- Removed dedicated feroxbuster and trufflehog prompts; both now install only from the optional `tools` task.
- Removed `fzf`-driven prompts and shell helpers in favor of plain text prompts and simpler aliases.
- After verified SSH/Tailscale access, ABB now disables SSH password auth and root SSH login, and in Tailscale mode restricts SSH to `tailscale0`.
- Tailscale setup now runs `tailscale up --ssh` automatically.

## 2026-10-19

- Audit rules open with `-D`, `-b 8192`, `-f 1`. Without the flush the kernel rejects the first duplicate on any re-run, which had been failing behind a `log_warn` since the module was written.
- Added `never` exclusions for the container healthcheck chain (`/usr/bin/runc`, `/runc`, `/bin/busybox`, `/usr/local/bin/pg_isready`) ahead of the `always` rules. Accepted cost: exec inside a container is no longer audited. Cost of not doing it, measured on this box: ~290,000 records a day, which rotated the entire audit trail away in about 36 hours and left a two-week absence with no coverage.
- Paired every syscall rule `b64`/`b32`, since multilib is enabled. Watch rules stay unpaired because they match on path.
- Chose explicit per-arch `never` rules over dropping `-F arch` to cover both. An exit rule without `-S` does not need an arch, but with `-e 2` in the same file a rejected line would leave a half-loaded, frozen ruleset at boot.
- Added `--loginuid-immutable` so `auid` cannot be reset by root, and a trailing `-e 2` to freeze the ruleset until reboot.
- `load_system_audit_rules` detects `enabled 2` and asks for a reboot instead of reporting a load failure, so re-runs on a provisioned host stay idempotent.
- bubblewrap installs from `ensure_ai_runtime` rather than `SYSTEM_PACKAGES`, because it exists to sandbox the agent CLIs rather than as a general utility.
- Agreed the repo is a VPS provisioning and hardening project with recon tooling as an optional extra, and should be renamed to say so. `arch-box-bootstrap` preferred over `arch-vps-bootstrap`: it keeps ABB as the short name, so `abb-setup.sh`, the banner, every `ABB_*` identifier and all saved aliases survive without an identifier sweep.
- README status claims must use the measured dates, keeping project age and deployment age apart. The code is a year old (first commit 2025-10-21); this VPS has run it for eight months (first pacman transaction 2026-02-15, 36 boots). "No issues" is not claimable given the four defects found in the monitoring module on 2026-10-19.
