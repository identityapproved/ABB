# Backlog

- [ ] Rename and reframe the repo around provisioning and hardening, with recon tooling optional
  - Why: bug bounty work all runs in containers now, so the recon catalogue in
    AGENTS.md section 10 is no longer what this repo is for. What actually gets
    used is Arch VPS provisioning, the admin-to-managed-user migration, network
    access, and hardening (auditd rules, aide, fail2ban, firewalld, sysctl).
    The name leads with the part that has become optional.
  - Name: `arch-vps-bootstrap` describes it plainly and is what someone would
    search for. `arch-box-bootstrap` keeps ABB as the short name, so
    `abb-setup.sh`, the banner, `ABB_*` variables and every existing note and
    alias survive the rename untouched. Prefer the second unless a full
    identifier sweep is worth doing.
  - Description: drop the bug-bounty lead in favour of "Modular Arch Linux VPS
    provisioning and hardening, with optional recon tooling".
  - Touch: repo name and remote description, README intro, AGENTS.md title and
    the framing in sections 1 and 10, banner in `abb-setup.sh`.
  - Structure, if it is being opened up anyway: promote hardening out of
    `security` into its own task, and demote the section 10 tool catalogue to
    an explicitly optional stage. Keep the `monitoring` and `verify` task names.
  - Before renaming, run `rg -il 'bug ?bounty|bugbounty'` and `rg -l 'ABB'` to
    size the sweep, and keep `abb-setup.sh` as the entry point (symlink if the
    script itself is renamed) so saved commands keep working.
  - Branch: `refactor/repo-rename-hardening-first`

- [ ] Write the documentation set, treating the repo as a VPS project rather than a script collection
  - Scope: README rewrite, an architecture overview (agents/architecture.md
    already sketches it), a page per task module, and runbooks for what needs
    attention after provisioning: audit rules, aide, firewalld, fail2ban, and
    the Tailscale SSH cutover.
  - Status claim, with the measured dates behind it. First commit 2025-10-21,
    so the project turns one year old on 2026-10-21. This VPS has run it since
    the first pacman transaction on 2026-02-15, across 36 recorded boots, and
    the provisioning path has not changed since the last commit on 2026-05-23.
    "Tested, a year in production with no issues" is wrong on two counts: the
    box is eight months old rather than twelve, and the monitoring module
    carried real bugs for all of it. "Running unchanged on a live Arch VPS
    since February 2026, across 36 boots" is true and says more.
  - Known issues to document rather than bury, all found 19.10.2026:
    - `write_system_audit_rules` emitted no `-D`, so `augenrules --load` failed
      with "Rule exists" on every re-run. The warn was swallowed and the
      boot-time load always worked, which is why it stayed invisible.
    - Audit rules were b64 only while multilib is enabled.
    - `root_action` plus `cred_changes` with no exclusions, against the
      50MB x 10 rotation in auditd.conf, destroys the audit trail in about 36
      hours once a container with a 5s healthcheck lands on the box. A
      two-week absence ended up with no audit coverage at all.
    - The aide database was never re-initialised after its attribute set
      changed, so `aide --check` returns a whole-filesystem diff and the IDS
      has been effectively non-functional.
  - Because the repo was generated rather than written, the documentation pass
    is the review pass: write each page from the code as it stands, not from
    what it was meant to do, and fix or file whatever does not match.
  - Branch: `docs/vps-project-documentation`
