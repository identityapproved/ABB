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

## 2026-10-19

- Investigated unexplained 2026-10-18 activity found after a near-month absence. Conclusion: no intrusion. The only event was a hypervisor-initiated ACPI power-off at 18:21:24 ("Power key pressed short" with no session present) and power-on at 18:32:25, on an unchanged kernel with no package transaction. Audit, wtmp, btmp and aide all agree: one login since 2026-10-01, today's, over Tailscale; no failed login since 2026-03-17; no file in aide's scope modified in October apart from today's bubblewrap install.
- Found four latent defects in `modules/monitoring.sh`, all present since the module was written: no `-D` preamble, b64-only syscall rules, no noise exclusions against the rotation the same module configures, and no loginuid or ruleset immutability.
- Rewrote the audit ruleset accordingly: `-D`/`-b`/`-f` preamble, eight `never` exclusions, b64/b32 pairs for all syscall rules, `--loginuid-immutable` and `-e 2` last.
- Added `load_system_audit_rules` to handle the immutable case instead of logging a misleading `augenrules --load` failure.
- Added bubblewrap to `ensure_ai_runtime`.
- Filed the repo rename/reframe and the documentation set in `agents/tasks/backlog.md`, with the measured project and deployment dates for the README status claim.
- Noted that the aide database has never been re-initialised since its attribute set changed, so `aide --check` has been returning a whole-filesystem diff (123,825 entries, 43,940 added / 10,827 removed / 66,925 changed) rather than a signal.
