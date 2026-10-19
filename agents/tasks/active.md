# Active

- [ ] Reboot the VPS and verify the new audit ruleset loads: `auditctl -s` shows `enabled 2` and `loginuid_immutable 1 locked`, `auditctl -l` lists the eight `never` rules before the `always` rules.
- [ ] Check the following evening that `/var/log/audit` now retains days rather than hours, confirming the healthcheck exclusions took effect.
- [ ] Re-initialise the aide database so `aide --check` stops returning a whole-filesystem diff and becomes usable as an intrusion signal again.
- [ ] Patch the box; the last pacman upgrade was 2026-09-05.
- [ ] Match `/etc/audit/rules.d/abb-system-monitoring.rules` on this host to the module output before the reboot, since the hand-edited file still lacks the `-D` preamble and the full exclusion set.
