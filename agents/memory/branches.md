# Branches

Current branch context:

- main_branch: main
- active_branch: main
- last_checked: 2026-10-28

## Branch registry

Use this list to track branches and their intent/state.

- branch: main
  purpose: primary integration branch
  status: active
  notes: contains the merged hardening workflow as of 2026-03-17

- branch: hardening
  purpose: account/network/VPN hardening and prompt cleanup
  status: merged
  notes: merged into main at commit 0da5017 on 2026-03-17

- branch: fix/tmux-osc52-yank
  purpose: replace the nonexistent ojroques/tmux-yank plugin with native copy-mode-vi yank binds over OSC 52
  status: merged
  notes: created 2026-10-24; fast-forwarded into main 2026-10-28

- branch: feature/network-access-modes
  purpose: selectable SSH transport/auth modes (plain-ssh, tailscale-sshd, tailscale-ssh), public lockdown, forwarding and port prompts; move the contabo VPS off Tailscale SSH via ABB
  status: merged
  notes: created 2026-10-28 from main; merged into main 2026-10-28

- branch: fix/network-access-sshd-parse
  purpose: parse OpenSSH 10.x CamelCase `sshd -T` keywords; detect a Tailscale SSH session from tailscale's own lose-ssh refusal (tmux hides the process chain) and schedule the switch with --accept-risk=lose-ssh
  status: merged
  notes: found on the first VPS run 2026-10-28; fast-forwarded into main the same day

## Branch workflow notes

- Record new task branches here when created.
- Mark branch status as active, paused, merged, or archived.
- Add a short reason before switching branch strategy.
- Planned, not yet created (named in `agents/tasks/backlog.md`): `refactor/repo-rename-hardening-first` for the rename and reframe, `docs/vps-project-documentation` for the documentation set.
- The 2026-10-19 monitoring fixes were made directly on `main` alongside unrelated in-progress dotfiles work; stage by explicit path when committing them.
