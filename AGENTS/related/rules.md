# Rules

Project rules live here and are referenced by AGENTS.md. Keep this file authoritative and update it when rules change.

## Core rules

- Do not modify anything under /private unless explicitly asked.
- Prefer minimal diffs and preserve existing note content.
- Never rewrite notes unless explicitly requested.
- Treat content as canonical; scripts and config adapt to it.
- Do not use emojis in this repo.
- Do not use numbered lists unless explicitly asked.
- When asked to update memory, store required rules, flow, tasks, history, updates, decisions, and progress in the memory files using best practices.
- When the user says "update memory", update all AGENTS-related files to reflect the current state and rules.
- Until the user says otherwise, treat publish as the main branch and keep main unchanged.

## Git Guard / Branch Manager

- Always assume work must happen on a new branch.
- Before any modification, check the current branch.
- If it is a main branch (main, master, dev, stable, production, etc.), require creation of a new branch.
- If changes exist (uncommitted, committed but not pushed, or pushed already), still recommend creating a new branch for further work.
- Only exception is when the user explicitly says "continue working in the current branch" or "stay on this branch," then do not suggest creating a new branch.
- Always warn if work is about to be done on a non-feature branch.
- Always suggest a branch name based on task: feature/<name>, docs/<name>, fix/<name>, refactor/<name>, experiment/<name>.
- When starting any task, ask what branch is currently checked out.
- If not a task-specific branch, propose: git checkout -b <suggested-branch-name>.
- If there are new changes in other local branches, ask whether to sync them into the current branch.
- When working on docs/* or feature/* branches, ask whether to sync changes from other local branches to keep them current.
- Only handle local git operations. For network operations like fetch, pull, or push, suggest the command and let the user run it.
- Never stash unless the user explicitly asks.
- Ensure the repo uses hooks from .githooks by running:
  - git config core.hooksPath .githooks
- Do not use absolute paths with the username; use ~ or $HOME instead.
- Before sharing changes (especially before add/commit/push), remove username paths from files.

## Path Sanitization

All filesystem paths must be presented using:
- ~ or $HOME instead of /home/<username>
- Relative paths when possible

Never expose:
- Absolute home directory paths
- Usernames embedded in paths

## Codex Utilities

- Codex utility scripts are global and live under `$HOME/.codex/scripts`.
- Do not call Codex utilities as repo-local `scripts/...` paths.
- Use `$HOME/.codex/scripts/init-repo-router.sh` when referring to the repo router bootstrap script.
