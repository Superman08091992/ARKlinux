# Build and test plan

## Safety invariant

Default build and test commands may create files only under `build/`, the configured output directory, and disposable QEMU images. They must never infer, select, partition, format, mount, or write a host block device.

## Milestone sequence

1. **ISO baseline (this PR):** validate profile, build in a pinned Arch container, calculate source and ISO SHA-256, boot read-only ISO under QEMU TCG, retain console/build logs.
2. **Disposable installation:** create an explicit virtual disk, boot ISO, require target plus typed confirmation containing the QEMU disk identity, install, verify Btrfs/systemd-boot, and reboot from disk.
3. **Host services:** install sysusers/tmpfiles, Unix sockets, nftables, required service units, and assert no failed required units.
4. **Local runtime:** package the current Python runtime with pinned dependencies; replace stub responses with real or `not_implemented` contracts.
5. **Evidence/policy:** hash-chain append-only evidence, default-deny capabilities, human approval records, tamper tests.
6. **Agents/UI:** enforce the canonical stage ledger and connect UI state only to observed service/runtime data.
7. **HP Z4 G4 readiness:** collect hardware inventory and build a separate hardware compatibility report. Physical installation remains prohibited until milestones 1–6 pass in QEMU.

## Canonical commands for milestone 1

```bash
bash scripts/source-checksums.sh
bash scripts/validate-iso-profile.sh
bash scripts/build-iso.sh
bash scripts/test-qemu-live-boot.sh build/out/*.iso
```

CI performs the same operations in a clean runner and uploads:

- ISO and `SHA256SUMS`;
- `SOURCE_SHA256SUMS`;
- mkarchiso output;
- QEMU serial console log;
- machine-readable test summary.

## Stop conditions

Stop on the first non-zero command. Preserve the full relevant log and classify the blocker as code, dependency, network, permission, hardware, configuration, or missing information. Do not advance a milestone after a failure.
