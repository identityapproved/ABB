# Decisions

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
