# Tasks

## New Branch: Cleanup

- Separate tools from other provisioning concerns.
- Decide which parts should be installed by default.
- Ensure modules from `common` through `languages` are always installed and contain only language/runtime baseline work (no extra utility/tool packages).
- Ensure dotfiles are linked/copied by the dotfiles task.
- Clean Docker integration so it contains only compose files (no wrapper binaries/scripts).

## Security/Hardening Branch

- Add a new `vpn` module that can manage Mullvad and/or Tailscale.
- Install and initialize Tailscale using the official Tailscale script path (opt-in behavior).

## Notification: Review Before Merge

Do not forget to review these findings:

1. High: `security` modifies SSH config despite policy saying not to touch `sshd_config`.
- AGENTS policy says not to modify SSH keys or `sshd_config`.
- `modules/security.sh` writes SSH hardening config and restarts `sshd`.
- This behavior runs in `run_task_security()` and can risk lockout.

2. Medium: `verify` checks Docker wrapper binaries even though Docker is compose-only.
- Policy says Docker assets should be compose-based without wrapper commands.
- `modules/docker_tools.sh` syncs compose assets only.
- `modules/verify.sh` checks wrapper-style commands, causing false warnings.

3. Low: README quick start uses non-`sudo` examples for root-required tasks.
- README examples show `./abb-setup.sh package-manager` and `./abb-setup.sh all`.
- `abb-setup.sh` enforces root and exits for non-root execution.
- Users following README literally can hit immediate failures.
