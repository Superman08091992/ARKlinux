# ARKlinux External-Drive Installation

This procedure installs ARKlinux onto a USB flash drive or external SSD while leaving the laptop's internal disk untouched.

Canonical release branch: `release/native-ark-v0.1`  
Canonical installed A.R.K. root: `/ark`  
Canonical root Btrfs subvolume: `@ark`

## 1. Hardware layout

Use two separate removable devices when possible:

1. **Installer media** — USB drive containing the ARKlinux ISO.
2. **Target media** — the flash drive or external SSD that will become the installed ARKlinux system.

Do not intentionally use the same physical device as both installer media and installation target. The installer destroys the target partition table.

An external SSD is preferable to an inexpensive flash drive for a persistent system because write performance and endurance are usually better.

## 2. Preserve the repositories on the laptop

On a Windows Yoga laptop with GitHub CLI and Git installed:

```powershell
gh auth login
gh repo clone Superman08091992/ARK_GENESIS
gh repo clone Superman08091992/ARKlinux

cd ARK_GENESIS
git fetch --all --tags --prune
git status

cd ..\ARKlinux
git fetch --all --tags --prune
git switch release/native-ark-v0.1
git status
```

For kernel-v2 development before merge, use:

```powershell
cd ..\ARK_GENESIS
git switch feature/tradeanalyzer-risk-kernel-v2

cd ..\ARKlinux
git switch feature/external-arklinux-install-v1
```

Cloning the repositories is separate from writing the bootable ISO. The repositories remain on the laptop as source/provenance even if the external system is later rebuilt.

## 3. Obtain and verify the ISO

Use the published ARKlinux release artifact or a CI artifact produced from the exact branch/commit you intend to test. Record the commit SHA used to produce the image.

Verify the ISO SHA-256 against its published `SHA256SUMS` before writing it.

Windows PowerShell:

```powershell
Get-FileHash .\arklinux-1.0.1-x86_64.iso -Algorithm SHA256
Get-Content .\SHA256SUMS
```

Linux:

```bash
sha256sum -c SHA256SUMS
```

Do not proceed when the digest differs.

## 4. Write the installer USB

Use a raw-image-capable writer such as Rufus or balenaEtcher on Windows. Select the ARKlinux ISO and the **installer USB**, not the future ARKlinux target drive.

On Linux, an equivalent raw write is possible:

```bash
sudo dd if=arklinux-1.0.1-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

`/dev/sdX` must be the whole installer USB. `dd` will destroy the selected device.

## 5. Boot the Yoga from the installer USB

Use the Lenovo firmware boot menu and select the UEFI entry for the installer USB. The exact key varies by Yoga model; commonly it is exposed through the boot-menu/Novo interface.

The current ARKlinux repository does not document a Secure Boot signing/enrollment chain. If the firmware refuses to boot the image with Secure Boot enabled, disable Secure Boot for this test rather than assuming the image is Secure-Boot trusted.

Do not change the internal-disk boot order permanently unless desired. A one-time boot-menu selection is sufficient.

## 6. Identify the target by model and serial

After the live environment boots, attach the separate target drive and run:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,TRAN,RM,HOTPLUG,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
```

Identify the target using **size + model + serial + transport**, not the device letter alone. Device names such as `/dev/sda` and `/dev/sdb` may change between boots.

Example only:

```text
NAME  PATH      SIZE TYPE TRAN RM HOTPLUG MODEL            SERIAL
sda   /dev/sda  1.8T disk      0       0 Internal NVMe    ...
sdb   /dev/sdb  465G disk usb  0       1 External SSD     ABC123
sdc   /dev/sdc 14.6G disk usb  1       1 Installer USB    XYZ789
```

In that example `/dev/sdb` is the target. Never copy the example device name without checking the real machine.

## 7. Install to the external target

On an ISO containing the guarded wrapper:

```bash
sudo ark-install-external /dev/sdX
```

The wrapper:

- requires a whole-disk block device;
- refuses a mounted target or mounted child partition;
- requires the device to identify as USB, Thunderbolt, removable, or hot-pluggable;
- displays model, serial, size, transport, removable, and hotplug attributes;
- requires the exact phrase `ERASE /dev/sdX` before destruction;
- re-checks mounted state immediately before delegating to `ark-install`.

On the canonical `release/native-ark-v0.1` image before the wrapper is included, use the existing installer only after manually performing the identity check above:

```bash
sudo ark-install /dev/sdX
```

Prefer its interactive confirmation. Use `--confirm` only for controlled automation where target identity has already been independently verified.

The canonical installer creates:

- 512 MiB FAT32 EFI System Partition;
- remaining space as Btrfs;
- `@ark`, `@home`, `@log`, and `@snapshots` subvolumes;
- systemd-boot;
- `/etc/fstab` using filesystem UUIDs.

## 8. First external boot

After installation finishes:

```bash
sudo umount -R /mnt/arkinstall
sudo poweroff
```

Remove the installer USB. Leave the new ARKlinux external target attached. Boot the Yoga and select the external drive from the firmware boot menu.

Confirm the installed system before doing anything destructive:

```bash
findmnt /
findmnt /ark || true
lsblk -o NAME,PATH,SIZE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
cat /etc/os-release
systemctl --failed
```

The root mount should use `subvol=@ark`. The active A.R.K. tree must use `/ark`; `/opt/ark` must not be the active runtime root.

## 9. Bring ARK_GENESIS onto the installed system

After networking and GitHub authentication are intentionally configured:

```bash
cd ~
gh auth login
gh repo clone Superman08091992/ARK_GENESIS
cd ARK_GENESIS
git fetch --all --tags --prune
git switch feature/tradeanalyzer-risk-kernel-v2
```

For a reproducible deployment, prefer building/installing the repository's ARK packages from a reviewed commit rather than manually copying individual runtime files into `/ark`.

Record at minimum:

```bash
git rev-parse HEAD
git status --short
uname -a
lsblk -o NAME,PATH,SIZE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Store those values with the test evidence so the installed image, target disk, and A.R.K. runtime revision can be reconstructed later.

## 10. Safety invariants

- Never select a target solely by `/dev/sdX` name.
- Never install without checking model/serial/size.
- Never overwrite the only copy of repository or evidence data.
- Never treat a successful ISO write as proof that installation or reboot works.
- Do not install to the Yoga internal drive until the external-drive boot and runtime validation are complete.
- Preserve the exact image checksum and Git commit used for every hardware test.
