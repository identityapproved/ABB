# History

## 2026-01-22

- Initialized repo router structure.

## 2026-03-17

- Added the `network-access` module and wired it into `abb-setup.sh`.
- Added VPN prompts/state and converted the old Mullvad-only flow into an opt-in provider-based VPN task.
- Hardened SSH after key verification, including password-auth disablement, root SSH disablement, and Tailscale-only SSH lockdown.
- Fixed the prompt crash caused by uninitialized install flags.
- Removed the feroxbuster and trufflehog install prompts and folded them into the optional `tools` workflow.
- Removed `fzf` from prompts and shell setup.
- Added a README banner placeholder.
- Merged `hardening` into `main` and pushed `main` to origin at merge commit `0da5017`.
