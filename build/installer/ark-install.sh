#!/bin/bash
# ARKLinux Installer - Individual Operator Edition
# Installs ARKLinux with BTRFS subvolumes and systemd-boot

set -e
DISK="${1:-/dev/sda}"
echo "=== ARKLinux v1.0-final Installer ==="
echo "Target: $DISK"
echo ""

# Partition layout
echo "Creating partitions on $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart root 513MiB 100%

# Format
mkfs.fat -F 32 "${DISK}1"
mkfs.btrfs -L arklinux "${DISK}2"

# Mount and create BTRFS subvolumes
mount "${DISK}2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@opt_ark
umount /mnt

# Remount with subvolumes
mount -o subvol=@,compress=zstd,noatime "${DISK}2" /mnt
mkdir -p /mnt/{home,var/log,.snapshots,boot/efi,opt/ark}
mount -o subvol=@home,compress=zstd "${DISK}2" /mnt/home
mount -o subvol=@log,compress=zstd "${DISK}2" /mnt/var/log
mount -o subvol=@snapshots "${DISK}2" /mnt/.snapshots
mount -o subvol=@opt_ark,compress=zstd,noatime "${DISK}2" /mnt/opt/ark
mount "${DISK}1" /mnt/boot/efi

echo "=== Installing ARKLinux... ==="
# (In live environment, rsync from squashfs root)
rsync -aAX --exclude={/proc,/sys,/dev,/tmp,/run,/mnt} / /mnt/

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Install systemd-boot
bootctl --path=/mnt/boot/efi install

# Write boot entry
mkdir -p /mnt/boot/efi/loader/entries
cat > /mnt/boot/efi/loader/loader.conf << 'LOADER'
default arklinux
timeout 3
console-mode auto
editor no
LOADER

PARTUUID=$(blkid -s PARTUUID -o value "${DISK}2")
cat > /mnt/boot/efi/loader/entries/arklinux.conf << ENTRY
title   ARKLinux v1.0-final (Individual Operator Edition)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$PARTUUID rootflags=subvol=@ rw quiet loglevel=3 audit=1
ENTRY

echo ""
echo "=== ARKLinux installation complete! ==="
echo "Reboot and remove installation media."
