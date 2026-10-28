# Active

- [ ] Reboot the VPS and verify the new audit ruleset loads: `auditctl -s` shows `enabled 2` and `loginuid_immutable 1 locked`, `auditctl -l` lists the eight `never` rules before the `always` rules.
- [ ] Check the following evening that `/var/log/audit` now retains days rather than hours, confirming the healthcheck exclusions took effect.
- [ ] Re-initialise the aide database so `aide --check` stops returning a whole-filesystem diff and becomes usable as an intrusion signal again.
- [ ] Patch the box; the last pacman upgrade was 2026-09-05.
- [ ] Match `/etc/audit/rules.d/abb-system-monitoring.rules` on this host to the module output before the reboot, since the hand-edited file still lacks the `-D` preamble and the full exclusion set.
- [ ] Before any full or fresh ABB run: verify and fix `docker/images/wg-vpn/` (`Dockerfile`, `entrypoint.sh`, `rotate-wg.sh`). The `testin` fixes merged 2026-10-28 date from 2025-11-10 (resolvconf handling, sysctl permission denied, compose copy paths) and were never built or tested against current main; the compose file they targeted was removed from main on 2026-03-07. The VPS currently routes container VPN through gluetun, not this image, so nothing in use depends on it. Decide then whether the image stays or is dropped in favour of gluetun.
- [ ] Apply the network-access modes on the contabo VPS via ABB: `sudo ./abb-setup.sh network-access` (migration prompt: switch to `tailscale-sshd`; lockdown yes; forwarding no; port as chosen), then `sudo ./abb-setup.sh verify`. Remove a hand-made `/etc/ssh/sshd_config.d/60-no-forwarding.conf` if present. In the Tailscale console: delete the policy `"ssh"` section (keep the `tcp:22` grant) and enable device approval.
