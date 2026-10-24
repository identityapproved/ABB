# Branches

Current branch context:

- main_branch: main
- active_branch: fix/tmux-osc52-yank
- last_checked: 2026-10-24

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
  status: active
  notes: created 2026-10-24

## Branch workflow notes

- Record new task branches here when created.
- Mark branch status as active, paused, merged, or archived.
- Add a short reason before switching branch strategy.
- Planned, not yet created (named in `agents/tasks/backlog.md`): `refactor/repo-rename-hardening-first` for the rename and reframe, `docs/vps-project-documentation` for the documentation set.
- The 2026-10-19 monitoring fixes were made directly on `main` alongside unrelated in-progress dotfiles work; stage by explicit path when committing them.
