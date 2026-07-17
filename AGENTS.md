# ARKlinux agent instructions

## Authority and truth boundary

- Treat the repository, current commit, executed commands, logs, and retained artifacts as the evidence base.
- Do not claim a capability was implemented, executed, or verified unless the current commit has direct evidence.
- Do not broaden a milestone beyond its stated acceptance criteria.
- Do not perform physical-disk writes, hardware installation, release publication, PR merge, artifact deletion, or real external execution without explicit authorization.
- Stop at the first failing command, preserve the relevant evidence, and identify the exact blocker.

## Operational skills

For recurring tasks, consult the matching skill before acting:

- ISO construction and QEMU live boot: `skills/arklinux-iso-build-proof/SKILL.md`
- PR and evidence review: `skills/arklinux-pr-evidence-review/SKILL.md`
- Permanent ISO release and custody: `skills/arklinux-release-custody/SKILL.md`
- Disposable QEMU installation and installed reboot: `skills/arklinux-qemu-install-proof/SKILL.md`

When more than one skill appears relevant, apply the narrowest skill first and keep each resulting pull request within one milestone boundary.
