#!/usr/bin/env bash
set -euo pipefail
RELROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ARKLINUX_OUT:-$RELROOT/out}"
WORK="${ARKLINUX_WORK:-$RELROOT/.work}"
IMG="$OUT/arklinux-native-v0.1-x86_64.raw"
COMPRESSED="$IMG.zst"
OVERLAY="${ARK_RUNTIME_OVERLAY:-/ark-runtime-overlay/ark-runtime-overlay.tar.zst}"
SIZE_GIB="${ARKLINUX_IMAGE_SIZE_GIB:-24}"
SWAP_GIB="${ARKLINUX_SWAP_GIB:-4}"
MNT="$WORK/mnt"
LOOP=""
cleanup(){ set +e; mountpoint -q "$MNT/boot" && umount "$MNT/boot"; while mountpoint -q "$MNT"; do umount -R "$MNT" 2>/dev/null || break; done; [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: build-image.sh must run as root" >&2; exit 1; }
[[ -f "$OVERLAY" ]] || { echo "ERROR: private A.R.K. overlay missing: $OVERLAY" >&2; exit 1; }
rm -rf "$WORK"; mkdir -p "$OUT" "$MNT"; rm -f "$IMG" "$COMPRESSED"
truncate -s "${SIZE_GIB}G" "$IMG"
sgdisk --zap-all "$IMG"; sgdisk -n 1:1MiB:+1GiB -t 1:ef00 -c 1:ARKESP "$IMG"; sgdisk -n 2:0:0 -t 2:8300 -c 2:ARKROOT "$IMG"
LOOP="$(losetup --find --show --partscan "$IMG")"
mkfs.fat -F32 -n ARKESP "${LOOP}p1"; mkfs.btrfs -f -L ARKROOT "${LOOP}p2"; mount "${LOOP}p2" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue; btrfs subvolume create "$MNT/$subvol"; done < "$RELROOT/config/subvolumes.tsv"
umount "$MNT"
mount -o noatime,compress=zstd:3,subvol=@ark "${LOOP}p2" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* || "$mp" == "/" ]] && continue; mkdir -p "$MNT$mp"; mount -o "subvol=$subvol,$opts" "${LOOP}p2" "$MNT$mp"; done < "$RELROOT/config/subvolumes.tsv"
mkdir -p "$MNT/boot"; mount "${LOOP}p1" "$MNT/boot"
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$RELROOT/config/packages.x86_64"); pacstrap -K "$MNT" "${PKGS[@]}"
cp -a "$RELROOT/rootfs/." "$MNT/"; tar --zstd -xf "$OVERLAY" -C "$MNT"
chmod 0755 "$MNT/usr/local/bin/ark-session" "$MNT/usr/local/bin/ark-bootstrap-ai" "$MNT/usr/local/sbin/ark-firstboot" "$MNT/usr/local/sbin/ark-boot-proof" "$MNT/usr/lib/ark-display/adapter.py"
printf 'ARKlinux\n' > "$MNT/etc/hostname"; printf 'LANG=en_US.UTF-8\n' > "$MNT/etc/locale.conf"; sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$MNT/etc/locale.gen"; ln -sf /usr/share/zoneinfo/America/Los_Angeles "$MNT/etc/localtime"; arch-chroot "$MNT" locale-gen
arch-chroot "$MNT" systemd-sysusers; arch-chroot "$MNT" systemd-tmpfiles --create; mkdir -p "$MNT/var/lib/ark"
arch-chroot "$MNT" useradd -m -G wheel,audio,video,input,storage -s /bin/bash operator || true; arch-chroot "$MNT" passwd -l operator || true
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$MNT/etc/sudoers.d/10-wheel"; chmod 0440 "$MNT/etc/sudoers.d/10-wheel"
ROOTUUID="$(blkid -s UUID -o value "${LOOP}p2")"; ESPUUID="$(blkid -s UUID -o value "${LOOP}p1")"; : > "$MNT/etc/fstab"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue; printf 'UUID=%s\t%s\tbtrfs\tsubvol=%s,%s\t0 0\n' "$ROOTUUID" "$mp" "$subvol" "$opts" >> "$MNT/etc/fstab"; done < "$RELROOT/config/subvolumes.tsv"
printf 'UUID=%s\t/boot\tvfat\tumask=0077\t0 2\n' "$ESPUUID" >> "$MNT/etc/fstab"
arch-chroot "$MNT" btrfs filesystem mkswapfile --size "${SWAP_GIB}G" /swap/swapfile; printf '/swap/swapfile none swap defaults 0 0\n' >> "$MNT/etc/fstab"
arch-chroot "$MNT" bootctl --path=/boot install --no-variables; mkdir -p "$MNT/boot/loader/entries"
cat > "$MNT/boot/loader/loader.conf" <<EOF
default arklinux.conf
timeout 4
console-mode max
editor no
EOF
cat > "$MNT/boot/loader/entries/arklinux.conf" <<EOF
title ARKlinux Native v0.1
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=UUID=$ROOTUUID rootflags=subvol=@ark rw quiet audit=1 console=tty0 console=ttyS0,115200n8
EOF
cat > "$MNT/boot/loader/entries/arklinux-fallback.conf" <<EOF
title ARKlinux Native v0.1 (fallback)
linux /vmlinuz-linux
initrd /initramfs-linux-fallback.img
options root=UUID=$ROOTUUID rootflags=subvol=@ark rw audit=1 console=tty0 console=ttyS0,115200n8
EOF
arch-chroot "$MNT" mkinitcpio -P
arch-chroot "$MNT" systemctl enable NetworkManager.service nftables.service chronyd.service greetd.service ark-firstboot.service ark.target ark-display-adapter.service ark-boot-proof.service
arch-chroot "$MNT" systemctl set-default graphical.target
arch-chroot "$MNT" /bin/bash -lc 'test -d /ark/runtime && test -L /opt/ark && test "$(readlink /opt/ark)" = /ark'
arch-chroot "$MNT" /bin/bash -lc 'test -f /usr/lib/systemd/system/arkd.service && test -f /usr/lib/systemd/system/ark-kj.service && test -f /usr/lib/systemd/system/ark-agent@.service'
arch-chroot "$MNT" /bin/bash -lc 'systemd-analyze verify /usr/lib/systemd/system/arkd.service /usr/lib/systemd/system/ark-kj.service /usr/lib/systemd/system/ark-agent@.service /usr/lib/systemd/system/ark-local-api.service /etc/systemd/system/ark-display-adapter.service /etc/systemd/system/ark-firstboot.service /etc/systemd/system/ark-boot-proof.service'
mkdir -p "$OUT/evidence"; cp "$RELROOT/config/subvolumes.tsv" "$OUT/evidence/subvolumes.tsv"; cp "$RELROOT/config/packages.x86_64" "$OUT/evidence/packages.requested"; cp "$RELROOT/config/dependencies.md" "$OUT/evidence/dependencies.md"; cp "$MNT/etc/fstab" "$OUT/evidence/fstab"; arch-chroot "$MNT" pacman -Q > "$OUT/evidence/packages.installed"; btrfs subvolume list "$MNT" > "$OUT/evidence/btrfs-subvolumes.txt"; findmnt -R "$MNT" > "$OUT/evidence/mount-tree.txt"; cp "$MNT/etc/ark/ARK_GENESIS_COMMIT" "$OUT/evidence/ARK_GENESIS_COMMIT"
sync; cleanup; LOOP=""; sha256sum "$IMG" > "$OUT/RAW-SHA256SUMS"; zstd -19 -T0 --rm "$IMG" -o "$COMPRESSED"; sha256sum "$COMPRESSED" > "$OUT/SHA256SUMS"; printf 'ARKlinux native release image: %s\n' "$COMPRESSED"
