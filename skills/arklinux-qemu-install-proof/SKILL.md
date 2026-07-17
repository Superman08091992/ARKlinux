---
name: arklinux-qemu-install-proof
description: Install ARKlinux only onto an explicitly created disposable QEMU disk, then boot from the installed disk without the ISO and verify UEFI, systemd-boot, Btrfs, fstab, and base system state. Use for Milestone 2 installation and installed-reboot proof.
compatibility: Requires a verified ARKlinux ISO, QEMU x86_64, OVMF, qemu-img, bash, jq or Python 3, and an isolated environment with no physical block-device passthrough.
metadata:
  author: 1TRUE-INC
  version: "1.0.0"
---

# ARKlinux disposable QEMU installation proof

## Purpose

Prove that a verified ARKlinux ISO can install to a fresh virtual disk and that the installed system can reboot under UEFI without the ISO. This skill must never target a physical disk.

## Required inputs

Resolve:

- exact ISO path and verified SHA-256;
- repository and exact commit;
- virtual-disk format and size;
- generated unique test serial;
- canonical Btrfs layout;
- expected installed boot marker;
- evidence output directory;
- timeout values.

## Absolute safety rules

- Create the virtual disk inside the approved build or test directory.
- Do not pass through host block devices, USB storage, NVMe devices, LVM volumes, or raw `/dev/*` paths.
- The installer must receive an explicit target path, expected serial, disposable-disk assertion, and typed destructive confirmation.
- Reject ambiguous targets and any serial mismatch.
- The live ISO must not be the installation target.
- Detach the ISO before the installed-boot test.

A conceptual installer contract is:

```text
ark-install \
  --target /dev/vda \
  --expected-serial ARKTEST-<commit> \
  --disposable-test-disk \
  --confirm DESTROY-ARKTEST-<commit>
```

The repository implementation may differ, but it must enforce equivalent checks.

## Workflow

1. Verify the ISO hash and record its source commit and evidence reference.
2. Create a new qcow2 or raw virtual disk with a unique generated serial.
3. Record the virtual-disk path, size, format, hash or creation metadata, and serial.
4. Start QEMU with OVMF, the ISO as read-only media, and only the disposable virtual disk as writable storage.
5. Positively identify the target inside the guest by serial and device properties.
6. Invoke the installer with the explicit safety contract.
7. Require successful partitioning, formatting, mounting, file copy, initramfs generation, bootloader installation, and clean unmount.
8. Power off the live environment.
9. Start a new QEMU process using the installed virtual disk and OVMF state, with the ISO absent.
10. Require the installed boot marker and an operational systemd target.
11. Capture and verify:
    - `lsblk -f`;
    - `blkid`;
    - `findmnt`;
    - `btrfs subvolume list /`;
    - `/etc/fstab`;
    - `bootctl status`;
    - `systemctl is-system-running`;
    - `systemctl --failed`;
    - `uname -a`;
    - `/etc/os-release`;
    - required ARK base-directory ownership and modes.
12. Confirm that the observed Btrfs layout matches the one canonical documented layout.
13. Scan both serial logs for panic, oops, emergency mode, mount failure, bootloader failure, installer target mismatch, and explicit failure markers.
14. Produce machine-readable installation and installed-reboot summaries.

## Pass conditions

All are required:

- the ISO hash is verified;
- the created disposable disk is the only writable installation target;
- target serial and typed confirmation checks pass;
- installation exits successfully;
- the ISO is absent during installed reboot;
- UEFI firmware starts the installed system;
- systemd-boot reports a valid installed configuration;
- fstab resolves and required filesystems mount;
- the exact canonical Btrfs subvolumes exist;
- the selected operational systemd target is reached;
- no unexpected base units fail;
- all required evidence files exist and are non-empty.

## Required output

Report:

- repository and head SHA;
- ISO filename and SHA-256;
- QEMU and OVMF versions;
- virtual-disk path, format, size, and serial;
- installer command and exit result;
- installed-boot command and exit result;
- partition, filesystem, Btrfs, fstab, bootloader, and systemd findings;
- complete evidence paths and hashes;
- known limitations.

Use one disposition:

- `PASS — disposable installation and installed reboot verified`
- `FAIL — target safety validation failed`
- `FAIL — installation failed`
- `FAIL — installed disk did not boot without ISO`
- `FAIL — installed layout or bootloader verification failed`
- `INCOMPLETE — required evidence is missing`

## Stop conditions

Stop immediately if a host device could be exposed, target identity is uncertain, confirmation does not match, partitioning affects an unexpected device, installation requires the ISO after reboot, or any result is inferred rather than observed.

## Truth boundary

A pass proves disposable QEMU installation and installed reboot for the recorded ISO and configuration. It does not prove full ARK service operation, DREAMER integration, agent execution, evidence persistence across application workflows, networking policy correctness beyond observed checks, or HP Z4 G4 hardware readiness.
