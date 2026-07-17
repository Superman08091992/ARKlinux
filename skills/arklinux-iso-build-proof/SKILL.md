---
name: arklinux-iso-build-proof
description: Build an ARKlinux ISO from a specific repository ref, verify source and ISO checksums, boot the ISO read-only under QEMU, and produce a bounded evidence record. Use for ISO baseline builds, QEMU live-boot proof, reproducibility checks, or rerunning Milestone 1.
compatibility: Requires git, bash, Docker or an approved Arch build environment, sha256sum, QEMU x86_64, Python 3, and write access only to repository build output.
metadata:
  author: 1TRUE-INC
  version: "1.0.0"
---

# ARKlinux ISO build proof

## Purpose

Produce an actual ISO and evidence proving that the exact tested commit built successfully and reached the defined live-boot marker under QEMU. Do not extend the claim to installation, installed reboot, runtime integration, service completeness, or hardware readiness.

## Required inputs

Obtain or resolve:

- repository and exact commit or branch;
- expected ISO version and filename;
- approved build environment;
- output directory;
- live-boot success marker and timeout;
- evidence destination.

If the ref, output boundary, or success marker is ambiguous, stop and resolve it before building.

## Safety boundary

- Write only inside the repository build directory and disposable QEMU state.
- Do not inspect, infer, mount, partition, format, or write a physical block device.
- Boot the ISO read-only and do not invoke the installer.
- Do not use an earlier artifact as proof for a newer commit.

## Workflow

1. Record the repository, branch, exact head SHA, workflow version, and start time.
2. Confirm the worktree or CI checkout corresponds to the recorded SHA.
3. Generate source checksums using the canonical repository script.
4. Validate the ArchISO profile and all safety assertions.
5. Run the canonical ISO build command with `pipefail` enabled and preserve complete output.
6. Require a non-empty ISO, `SHA256SUMS`, resolved package lock, and complete build log.
7. Run `sha256sum -c` against the produced ISO.
8. Boot that exact ISO under QEMU TCG using the canonical live-boot test.
9. Require an observed success marker, a zero test exit code, and a machine-readable result.
10. Scan the QEMU log for panic, oops, emergency-shell, timeout, and explicit failure markers.
11. Copy the compact evidence files into the versioned evidence directory.
12. Produce an artifact manifest identifying every retained file by path, size, and SHA-256.

## Canonical commands

Use repository commands rather than reconstructing equivalent ad hoc commands:

```bash
bash scripts/source-checksums.sh
bash scripts/validate-iso-profile.sh
bash scripts/build-iso.sh
bash scripts/test-qemu-live-boot.sh build/out/*.iso
sha256sum -c build/out/SHA256SUMS
```

Stop on the first non-zero command.

## Required output

Report:

- repository and exact head SHA;
- ISO filename, size, and SHA-256;
- source checksum file;
- resolved package lock;
- build command and exit code;
- QEMU command and exit code;
- observed boot marker;
- workflow run and artifact identifiers when applicable;
- retained evidence paths;
- known limitations.

Use one of these dispositions:

- `PASS — ISO build and QEMU live boot verified`
- `FAIL — build did not produce a valid ISO`
- `FAIL — checksum verification failed`
- `FAIL — QEMU live boot was not observed`
- `INCOMPLETE — required evidence is missing`

## Stop conditions

Stop and preserve evidence when:

- source validation fails;
- the build writes outside approved output paths;
- the ISO is absent or empty;
- checksum verification fails;
- QEMU exits without the success marker;
- the test times out;
- required proof files are missing;
- a result is only inferred from a previous run.

Classify the blocker as code, dependency, network, permissions, configuration, environment, evidence, or missing information.

## Truth boundary

A pass proves only that the recorded commit produced the recorded ISO and that the ISO reached the live-boot marker in the recorded QEMU test. It does not prove disk installation, installed reboot, Btrfs correctness, systemd service completeness, DREAMER operation, physical-hardware compatibility, or production readiness.
