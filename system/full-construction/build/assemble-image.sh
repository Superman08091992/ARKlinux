#!/usr/bin/env bash
set -euo pipefail
ROOT=/src
OUT="$ROOT/out"
WORK="$ROOT/.work/image"
IMG="$OUT/arklinux-x86_64.raw"
SIZE_GIB="${ARKLINUX_IMAGE_SIZE_GIB:-12}"
SWAP_GIB="${ARKLINUX_SWAP_GIB:-2}"
SNAP="${ARKLINUX_ARCH_SNAPSHOT:-2026/08/20}"
MNT="$WORK/mnt"
LOOP=""
cleanup(){ set +e; mountpoint -q "$MNT/boot" && umount "$MNT/boot"; while mountpoint -q "$MNT"; do umount -R "$MNT" 2>/dev/null || break; done; [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
rm -rf "$WORK"; mkdir -p "$OUT" "$MNT"
"$ROOT/kernel/build-kernel.sh"
rm -f "$IMG"; truncate -s "${SIZE_GIB}G" "$IMG"
sgdisk --zap-all "$IMG"
sgdisk -n 1:1MiB:+1GiB -t 1:ef00 -c 1:ARKESP "$IMG"
sgdisk -n 2:0:0 -t 2:8300 -c 2:ARKROOT "$IMG"
LOOP="$(losetup --find --show --partscan "$IMG")"
mkfs.fat -F32 -n ARKESP "${LOOP}p1"
mkfs.btrfs -f -L ARKROOT "${LOOP}p2"
mount "${LOOP}p2" "$MNT"
# Create every declared subvolume exactly once.
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue
  btrfs subvolume create "$MNT/$subvol"
done < "$ROOT/config/subvolumes.tsv"
umount "$MNT"
# Mount root first.
mount -o noatime,compress=zstd:3,subvol=@ "${LOOP}p2" "$MNT"
# Mount every non-root subvolume.
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* || "$mp" == "/" ]] && continue
  mkdir -p "$MNT$mp"
  mount -o "subvol=$subvol,$opts" "${LOOP}p2" "$MNT$mp"
done < "$ROOT/config/subvolumes.tsv"
mkdir -p "$MNT/boot"; mount "${LOOP}p1" "$MNT/boot"
# Pinned Arch userspace construction source. ARKlinux does not run on Arch; Arch is only used to populate userspace.
cat >/etc/pacman.d/arklinux-build-mirrorlist <<EOF
Server = https://archive.archlinux.org/repos/${SNAP}/\$repo/os/\$arch
EOF
cp /etc/pacman.conf "$WORK/pacman.conf"
sed -i 's|^Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/arklinux-build-mirrorlist|' "$WORK/pacman.conf"
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT/config/packages.x86_64")
pacstrap -C "$WORK/pacman.conf" -K "$MNT" "${PKGS[@]}"
# Construction uses the pinned archive snapshot above.
# The installed ARKlinux system receives the normal runtime pacman configuration.
install -Dm0644 /etc/pacman.conf "$MNT/etc/pacman.conf"
install -Dm0644 /etc/pacman.d/mirrorlist "$MNT/etc/pacman.d/mirrorlist"
# Copy the direct ARKlinux kernel and module tree; no kernel package owns it.
cp "$ROOT/out/kernel/arklinux-kernel" "$MNT/boot/arklinux-kernel"
KREL="$(cat "$ROOT/out/kernel/kernel-release")"
mkdir -p "$MNT/usr/lib/modules"
cp -a "$ROOT/out/kernel/modules/lib/modules/$KREL" "$MNT/usr/lib/modules/"
# ARKlinux-owned configuration and native A.R.K. process scaffolding.
cp -a "$ROOT/rootfs/." "$MNT/"
# Keep rolling userspace updates from replacing the directly constructed ARKlinux kernel.
if ! grep -q 'arklinux-kernel-hold.conf' "$MNT/etc/pacman.conf"; then printf '\nInclude = /etc/pacman.d/arklinux-kernel-hold.conf\n' >> "$MNT/etc/pacman.conf"; fi
# Build identities before applying subvolume ownership.
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
arch-chroot "$MNT" btrfs filesystem mkswapfile --size "${SWAP_GIB}G" /swap/swapfile
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
options root=UUID=$ROOTUUID rootflags=subvol=@ rw quiet audit=1 console=tty0 console=ttyS0,115200n8
EOF
cat > "$MNT/boot/loader/entries/arklinux-rescue.conf" <<EOF
title ARKlinux Rescue
linux /arklinux-kernel
initrd /initramfs-arklinux-fallback.img
options root=UUID=$ROOTUUID rootflags=subvol=@ rw systemd.unit=rescue.target audit=1 console=tty0 console=ttyS0,115200n8
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
