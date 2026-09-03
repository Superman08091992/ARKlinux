#!/usr/bin/env bash
set -euo pipefail

ROOT=/src
OUT="$ROOT/out"
WORK="$ROOT/.work/image"
IMG="$OUT/arklinux-x86_64.raw"
SWAP_GIB="${ARKLINUX_SWAP_GIB:-2}"
MNT="$WORK/mnt"
LOOP=""

cleanup(){
  set +e
  mountpoint -q "$MNT/boot" && umount "$MNT/boot"
  while mountpoint -q "$MNT"; do
    umount -R "$MNT" 2>/dev/null || break
  done
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
}

trap cleanup EXIT

[[ -f "$IMG" ]] || {
  echo "ERROR: existing raw image not found: $IMG" >&2
  exit 1
}

mkdir -p "$MNT"

LOOP="$(losetup --find --show --partscan "$IMG")"

mount -o noatime,compress=zstd:3,subvol=@ark "${LOOP}p2" "$MNT"

while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* || "$mp" == "/" ]] && continue
  mkdir -p "$MNT$mp"
  mount -o "subvol=$subvol,$opts" "${LOOP}p2" "$MNT$mp"
done < "$ROOT/config/subvolumes.tsv"

mkdir -p "$MNT/boot"
mount "${LOOP}p1" "$MNT/boot"

[[ -x "$MNT/usr/bin/pacman" ]] || {
  echo "ERROR: rootfs package installation did not complete" >&2
  exit 1
}

[[ -f "$MNT/boot/arklinux-kernel" ]] || {
  echo "ERROR: ARKlinux kernel is missing from existing image" >&2
  exit 1
}

[[ -f "$MNT/usr/lib/ark/ark_native.py" ]] || {
  echo "ERROR: ARKlinux rootfs copy is incomplete" >&2
  exit 1
}

install -Dm0644 /etc/pacman.conf "$MNT/etc/pacman.conf"
install -Dm0644 /etc/pacman.d/mirrorlist "$MNT/etc/pacman.d/mirrorlist"

echo "Existing image verified."
echo "Resuming ARKlinux construction after pacstrap."
# Keep rolling userspace updates from replacing the directly constructed ARKlinux kernel.
if ! grep -q 'arklinux-kernel-hold.conf' "$MNT/etc/pacman.conf"; then printf '\nInclude = /etc/pacman.d/arklinux-kernel-hold.conf\n' >> "$MNT/etc/pacman.conf"; fi
# Build identities before applying subvolume ownership.
install -Dm0644 "$ROOT/rootfs/etc/tmpfiles.d/ark.conf" "$MNT/etc/tmpfiles.d/ark.conf"

arch-chroot "$MNT" systemd-sysusers
arch-chroot "$MNT" systemd-tmpfiles --create --dry-run /etc/tmpfiles.d/ark.conf
# Apply declared mount ownership/mode.
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue
  arch-chroot "$MNT" chown "$owner:$group" "$mp"
  arch-chroot "$MNT" chmod "$mode" "$mp"
done < "$ROOT/config/subvolumes.tsv"
# Generate fstab from the authoritative topology.
ROOTUUID="$(blkid -s UUID -o value "${LOOP}p2")"
ESPUUID="$(blkid -s UUID -o value "${LOOP}p1")"
: > "$MNT/etc/fstab"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue
  printf 'UUID=%s\t%s\tbtrfs\tsubvol=%s,%s\t0 0\n' "$ROOTUUID" "$mp" "$subvol" "$opts" >> "$MNT/etc/fstab"
done < "$ROOT/config/subvolumes.tsv"
printf 'UUID=%s\t/boot\tvfat\tumask=0077\t0 2\n' "$ESPUUID" >> "$MNT/etc/fstab"
# Btrfs swapfile is created after @swap is mounted and excluded from CoW.
if [[ ! -e "$MNT/swap/swapfile" ]]; then
  arch-chroot "$MNT" btrfs filesystem mkswapfile --size "${SWAP_GIB}G" /swap/swapfile
fi
printf '/swap/swapfile none swap defaults 0 0\n' >> "$MNT/etc/fstab"
# Bootloader + initramfs.
arch-chroot "$MNT" bootctl --path=/boot install --no-variables
mkdir -p "$MNT/boot/loader/entries"
cat > "$MNT/boot/loader/loader.conf" <<EOF
default arklinux.conf
timeout 3
console-mode max
editor no
EOF
cat > "$MNT/boot/loader/entries/arklinux.conf" <<EOF
title ARKlinux
linux /arklinux-kernel
initrd /initramfs-arklinux.img
options root=UUID=$ROOTUUID rootflags=subvol=@ark rw quiet audit=1 console=tty0 console=ttyS0,115200n8
EOF
cat > "$MNT/boot/loader/entries/arklinux-rescue.conf" <<EOF
title ARKlinux Rescue
linux /arklinux-kernel
initrd /initramfs-arklinux-fallback.img
options root=UUID=$ROOTUUID rootflags=subvol=@ark rw systemd.unit=rescue.target audit=1 console=tty0 console=ttyS0,115200n8
EOF
arch-chroot "$MNT" mkinitcpio -p arklinux
# Basic machine identity and services.
echo arklinux > "$MNT/etc/hostname"
arch-chroot "$MNT" systemctl enable NetworkManager.service nftables.service greetd.service ark.target arklinux-snapshot.timer
# Give the operator an install-time account; password remains locked until explicitly set.
arch-chroot "$MNT" useradd -m -G wheel,audio,video,input,storage -s /bin/bash operator || true
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$MNT/etc/sudoers.d/10-wheel"
chmod 0440 "$MNT/etc/sudoers.d/10-wheel"
# Provenance + topology evidence.
mkdir -p "$OUT/evidence"
cp "$ROOT/config/subvolumes.tsv" "$OUT/evidence/subvolumes.tsv"
cp "$ROOT/config/processes.tsv" "$OUT/evidence/processes.tsv"
cp "$ROOT/kernel/source.lock" "$OUT/evidence/kernel-source.lock"
cp "$ROOT/out/kernel/SHA256SUMS" "$OUT/evidence/kernel-SHA256SUMS"
btrfs subvolume list "$MNT" > "$OUT/evidence/btrfs-subvolumes.txt"
findmnt -R "$MNT" > "$OUT/evidence/mount-tree.txt"
arch-chroot "$MNT" /bin/bash -lc 'systemd-analyze verify /etc/systemd/system/ark*.service /etc/systemd/system/ark*.target' 
sync
cleanup; LOOP=""
sha256sum "$IMG" > "$OUT/SHA256SUMS"
printf 'ARKlinux raw image constructed: %s\n' "$IMG"
