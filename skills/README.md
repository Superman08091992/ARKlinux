# ARKlinux operational skills

This directory contains portable Agent Skills for recurring ARKlinux engineering and evidence tasks. Each skill is intentionally narrow. Combine skills only when the requested work actually spans more than one gate.

## Current skills

- `arklinux-iso-build-proof`: Build an ARKlinux ISO and prove read-only QEMU live boot.
- `arklinux-pr-evidence-review`: Review a pull request, CI run, and artifacts against a bounded milestone claim.
- `arklinux-release-custody`: Preserve a verified ISO as a release asset and maintain independent custody records.
- `arklinux-qemu-install-proof`: Install only to an explicitly identified disposable QEMU disk and prove installed reboot.

## Use principles

1. Evidence precedes completion claims.
2. A successful earlier run does not prove the current commit.
3. Route, service, or file presence does not prove functional implementation.
4. A checksum verifies bytes that exist; it cannot reconstruct a missing artifact.
5. Never infer permission for destructive actions.
6. Never merge, publish, delete, install to hardware, or enable real execution without explicit authorization.
7. Keep each pull request within one milestone boundary.

## Structure

Every skill directory contains a standards-compatible `SKILL.md` with YAML frontmatter and Markdown instructions. Supporting scripts or references may be added when they make the workflow more deterministic.

Validate the library with:

```bash
python3 scripts/validate-agent-skills.py
```
