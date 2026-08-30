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
ESP_DEV=""
ROOT_DEV=""
KPARTX_ACTIVE=0

stage(){ printf '\n==> %s\n' "$*"; }

cleanup(){
  set +e
  mountpoint -q "$MNT/boot" && umount "$MNT/boot"
  while mountpoint -q "$MNT"; do umount -R "$MNT" 2>/dev/null || break; done
  if [[ "$KPARTX_ACTIVE" == "1" && -n "$LOOP" ]]; then kpartx -d "$LOOP" 2>/dev/null || true; fi
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

resolve_partitions(){
  local base
  base="$(basename "$LOOP")"
  partx -u "$LOOP" 2>/dev/null || partx -a "$LOOP" 2>/dev/null || true
  sleep 1
  if [[ -b "${LOOP}p1" && -b "${LOOP}p2" ]]; then
    ESP_DEV="${LOOP}p1"
    ROOT_DEV="${LOOP}p2"
    return 0
  fi
  command -v kpartx >/dev/null 2>&1 || { echo "ERROR: loop partition nodes absent and kpartx is unavailable" >&2; return 1; }
  kpartx -av "$LOOP"
  KPARTX_ACTIVE=1
  ESP_DEV="/dev/mapper/${base}p1"
  ROOT_DEV="/dev/mapper/${base}p2"
  for _ in {1..20}; do
    [[ -b "$ESP_DEV" && -b "$ROOT_DEV" ]] && return 0
    sleep 0.25
  done
  echo "ERROR: partition devices unavailable after partx/kpartx: $ESP_DEV $ROOT_DEV" >&2
  ls -l /dev/mapper /dev/${base}* 2>/dev/null || true
  return 1
}

apply_persistent_ark_layout(){
  # Persistent state belongs to the Btrfs/image layer, not tmpfiles. This is
  # deliberately separate from /run/ark, which is volatile and recreated by
  # systemd-tmpfiles at normal boot.
  arch-chroot "$MNT" install -d -m 0755 -o root -g root /ark
  arch-chroot "$MNT" install -d -m 0770 -o arkd -g ark-state /ark/memory /ark/evidence /ark/state /ark/checkpoints /ark/quarantine /ark/storage /ark/logs
  arch-chroot "$MNT" install -d -m 0770 -o ark-kj -g ark-state /ark/kj
  arch-chroot "$MNT" install -d -m 0750 -o root -g ark-state /ark/graveyard /ark/models /ark/config
  arch-chroot "$MNT" install -d -m 0770 -o ark-trading -g ark-state /ark/trading
  arch-chroot "$MNT" install -d -m 0750 -o root -g ark-state /etc/ark /etc/ark/trading
  arch-chroot "$MNT" install -d -m 0770 -o arkd -g ark-state /var/lib/ark
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: build-image.sh must run as root" >&2; exit 1; }
[[ -f "$OVERLAY" ]] || { echo "ERROR: private A.R.K. overlay missing: $OVERLAY" >&2; exit 1; }
stage "prepare raw disk"
rm -rf "$WORK"; mkdir -p "$OUT" "$MNT"; rm -f "$IMG" "$COMPRESSED"
truncate -s "${SIZE_GIB}G" "$IMG"
sgdisk --zap-all "$IMG"
sgdisk -n 1:1MiB:+1GiB -t 1:ef00 -c 1:ARKESP "$IMG"
sgdisk -n 2:0:0 -t 2:8300 -c 2:ARKROOT "$IMG"
LOOP="$(losetup --find --show --partscan "$IMG")"
resolve_partitions
printf 'Partition map: loop=%s esp=%s root=%s\n' "$LOOP" "$ESP_DEV" "$ROOT_DEV"

stage "format and create native Btrfs topology"
mkfs.fat -F32 -n ARKESP "$ESP_DEV"
mkfs.btrfs -f -L ARKROOT "$ROOT_DEV"
mount "$ROOT_DEV" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue; btrfs subvolume create "$MNT/$subvol"; done < "$RELROOT/config/subvolumes.tsv"
umount "$MNT"
mount -o noatime,compress=zstd:3,subvol=@ark "$ROOT_DEV" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* || "$mp" == "/" ]] && continue; mkdir -p "$MNT$mp"; mount -o "subvol=$subvol,$opts" "$ROOT_DEV" "$MNT$mp"; done < "$RELROOT/config/subvolumes.tsv"
mkdir -p "$MNT/boot"; mount "$ESP_DEV" "$MNT/boot"

stage "install Arch package set"
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$RELROOT/config/packages.x86_64"); pacstrap -K "$MNT" "${PKGS[@]}"

stage "install ARKlinux rootfs and private A.R.K. overlay"
cp -a "$RELROOT/rootfs/." "$MNT/"; tar --zstd -xf "$OVERLAY" -C "$MNT"
chmod 0755 "$MNT/usr/local/bin/ark-session" "$MNT/usr/local/bin/ark-bootstrap-ai" "$MNT/usr/local/sbin/ark-firstboot" "$MNT/usr/local/sbin/ark-embedding-model" "$MNT/usr/local/sbin/ark-boot-proof" "$MNT/usr/lib/ark-display/adapter.py"
printf 'ARKlinux\n' > "$MNT/etc/hostname"; printf 'LANG=en_US.UTF-8\n' > "$MNT/etc/locale.conf"; sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$MNT/etc/locale.gen"; ln -sf /usr/share/zoneinfo/America/Los_Angeles "$MNT/etc/localtime"

stage "generate locale"
arch-chroot "$MNT" locale-gen

stage "apply A.R.K. system users"
arch-chroot "$MNT" systemd-sysusers /usr/lib/sysusers.d/ark-native.conf

stage "apply persistent A.R.K. Btrfs layout"
apply_persistent_ark_layout

stage "validate volatile tmpfiles contract without creating it"
# ark-native.conf now contains only /run/ark runtime paths. Validate syntax at
# image-build time, but do not create volatile state inside the build chroot.
arch-chroot "$MNT" systemd-tmpfiles --create --dry-run /usr/lib/tmpfiles.d/ark-native.conf

stage "validate compatibility namespace"
[[ -L "$MNT/opt/ark" ]] || { echo "ERROR: /opt/ark compatibility symlink missing" >&2; exit 1; }
[[ "$(readlink "$MNT/opt/ark")" == "/ark" ]] || { echo "ERROR: /opt/ark must resolve to /ark" >&2; exit 1; }

stage "create operator account"
arch-chroot "$MNT" useradd -m -G wheel,audio,video,input,storage -s /bin/bash operator || true
arch-chroot "$MNT" passwd -l operator || true
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$MNT/etc/sudoers.d/10-wheel"; chmod 0440 "$MNT/etc/sudoers.d/10-wheel"

stage "write fstab and swapfile"
ROOTUUID="$(blkid -s UUID -o value "$ROOT_DEV")"; ESPUUID="$(blkid -s UUID -o value "$ESP_DEV")"; : > "$MNT/etc/fstab"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue; printf 'UUID=%s\t%s\tbtrfs\tsubvol=%s,%s\t0 0\n' "$ROOTUUID" "$mp" "$subvol" "$opts" >> "$MNT/etc/fstab"; done < "$RELROOT/config/subvolumes.tsv"
printf 'UUID=%s\t/boot\tvfat\tumask=0077\t0 2\n' "$ESPUUID" >> "$MNT/etc/fstab"
arch-chroot "$MNT" btrfs filesystem mkswapfile --size "${SWAP_GIB}G" /swap/swapfile
printf '/swap/swapfile none swap defaults 0 0\n' >> "$MNT/etc/fstab"

stage "install systemd-boot"
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

stage "regenerate initramfs"
arch-chroot "$MNT" mkinitcpio -P

stage "enable native services"
arch-chroot "$MNT" systemctl enable NetworkManager.service nftables.service chronyd.service greetd.service ollama.service ark-embedding-model.service ark-firstboot.service ark.target ark-display-adapter.service ark-boot-proof.service
arch-chroot "$MNT" systemctl set-default graphical.target

stage "validate native A.R.K. contract"
arch-chroot "$MNT" /bin/bash -lc 'test -d /ark/runtime && test -L /opt/ark && test "$(readlink /opt/ark)" = /ark'
arch-chroot "$MNT" /bin/bash -lc 'test -f /usr/lib/systemd/system/arkd.service && test -f /etc/systemd/system/ark-embedding-model.service && test -f /usr/lib/systemd/system/ark-kj.service && test -f /usr/lib/systemd/system/ark-agent@.service'
arch-chroot "$MNT" /bin/bash -lc 'systemd-analyze verify /usr/lib/systemd/system/arkd.service /usr/lib/systemd/system/ark-kj.service /usr/lib/systemd/system/ark-agent@.service /usr/lib/systemd/system/ark-local-api.service /etc/systemd/system/ark-display-adapter.service /etc/systemd/system/ark-embedding-model.service /etc/systemd/system/ark-firstboot.service /etc/systemd/system/ark-boot-proof.service'

stage "collect image evidence"
mkdir -p "$OUT/evidence"; cp "$RELROOT/config/subvolumes.tsv" "$OUT/evidence/subvolumes.tsv"; cp "$RELROOT/config/packages.x86_64" "$OUT/evidence/packages.requested"; cp "$RELROOT/config/dependencies.md" "$OUT/evidence/dependencies.md"; cp "$MNT/etc/fstab" "$OUT/evidence/fstab"; pacman --root "$MNT" --dbpath "$MNT/var/lib/pacman" --config /etc/pacman.conf -Q > "$OUT/evidence/packages.installed"; btrfs subvolume list "$MNT" > "$OUT/evidence/btrfs-subvolumes.txt"; findmnt -R "$MNT" > "$OUT/evidence/mount-tree.txt"; cp "$MNT/etc/ark/ARK_GENESIS_COMMIT" "$OUT/evidence/ARK_GENESIS_COMMIT"

stage "finalize and compress image"
sync; cleanup; LOOP=""; KPARTX_ACTIVE=0; (cd "$OUT" && sha256sum "$(basename "$IMG")" > RAW-SHA256SUMS); zstd -19 -T0 --rm "$IMG" -o "$COMPRESSED"; (cd "$OUT" && sha256sum "$(basename "$COMPRESSED")" > SHA256SUMS); printf 'ARKlinux native release image: %s\n' "$COMPRESSED"
