# First pull request: reproducible ISO and QEMU live boot

## Scope

- Add the repository/architecture audit artifacts.
- Establish one canonical ISO build command.
- Generate source checksums from included files.
- Validate the profile without touching disks.
- Boot the generated ISO using QEMU TCG and capture the serial console.
- Upload the actual ISO, hashes and logs from CI.

## Explicit non-scope

No disk installation, installed-system reboot, runtime integration, service-completeness claim, hardware installation, release publication, or PR readiness/merge.

## Exit criteria

The draft PR remains incomplete until its CI run provides an ISO artifact, ISO SHA-256, source checksum list, complete mkarchiso log, QEMU log and passing test summary. A failed build stops the work at that exact command.

