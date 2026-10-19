# Progress

Current focus:

- Land the monitoring/audit hardening and confirm it survives a reboot.

Blocked:

- The new audit ruleset is written but not loaded. The kernel still holds the ruleset from the 2026-10-18 boot; the single load attempt on 2026-10-19 at 22:50:35 failed (`op=add_rule key="root_action" res=0`) because the file then lacked `-D`. `-e 2` never applied, so the box is still mutable and the rules land either on a successful `augenrules --load` or at the next reboot.

Next:

- After reboot, confirm `auditctl -s` reports `enabled 2` and `loginuid_immutable 1 locked`, and that `auditctl -l` lists the eight `never` rules first.
- Confirm audit volume drops from ~290,000 records a day and that `/var/log/audit` retains days rather than ~36 hours.
- Re-initialise the aide database so `aide --check` reports real changes again.
- Patch the box; the last pacman upgrade was 2026-09-05.
- Re-test full provisioning on a fresh Arch VPS from `main`.
- Confirm the post-verification SSH hardening path on both plain SSH and Tailscale.
- Clean up any README/banner formatting the operator wants to refine further.
