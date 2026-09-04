#!/usr/bin/env bash
set -euo pipefail

ROOT=/src
OUT="$ROOT/out"
WORK="$ROOT/.work/image"
IMG="$OUT/arklinux-x86_64.raw"
SIZE_GIB="${ARKLINUX_IMAGE_SIZE_GIB:-12}"
SWAP_GIB="${ARKLINUX_SWAP_GIB:-2}"
SNAP="${ARKLINUX_ARCH_SNAPSHOT:-2026/08/20}"
ARK_REQUIRED="${ARK_GENESIS_REQUIRED:-0}"
ARK_PACKAGE_MOUNT=/ark-genesis-packages
ARK_LOCK="$ROOT/config/ark-genesis.lock"
MNT="$WORK/mnt"
LOOP=""
ARK_INTEGRATED=0

# shellcheck disable=SC1090
source "$ARK_LOCK"

cleanup(){
  set +e
  mountpoint -q "$MNT/boot" && umount "$MNT/boot"
  while mountpoint -q "$MNT"; do umount -R "$MNT" 2>/dev/null || break; done
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

verify_private_packages(){
  local dir="$1"
  [[ -f "$dir/ARK_GENESIS_COMMIT" ]] || { echo "ERROR: package set lacks ARK_GENESIS_COMMIT" >&2; return 1; }
  [[ -f "$dir/ARK_GENESIS_REPOSITORY" ]] || { echo "ERROR: package set lacks ARK_GENESIS_REPOSITORY" >&2; return 1; }
  [[ -f "$dir/SHA256SUMS" ]] || { echo "ERROR: package set lacks SHA256SUMS" >&2; return 1; }

  local observed_commit observed_repo
  observed_commit="$(tr -d '[:space:]' < "$dir/ARK_GENESIS_COMMIT")"
  observed_repo="$(tr -d '\r\n' < "$dir/ARK_GENESIS_REPOSITORY")"
  [[ "$observed_commit" == "$ARK_GENESIS_COMMIT" ]] || {
    echo "ERROR: A.R.K. package commit $observed_commit does not match lock $ARK_GENESIS_COMMIT" >&2
    return 1
  }
  [[ "$observed_repo" == "$ARK_GENESIS_REPOSITORY" ]] || {
    echo "ERROR: A.R.K. package repository $observed_repo does not match lock $ARK_GENESIS_REPOSITORY" >&2
    return 1
  }

  (cd "$dir" && sha256sum -c SHA256SUMS)
  for package in $ARK_GENESIS_PACKAGES; do
    local -a matches=()
    mapfile -t matches < <(find "$dir" -maxdepth 1 -type f -name "${package}-*.pkg.tar.*" ! -name '*.sig' -print | sort)
    [[ "${#matches[@]}" -eq 1 ]] || {
      echo "ERROR: expected exactly one verified package for $package, found ${#matches[@]}" >&2
      return 1
    }
  done
}

install_private_packages(){
  local dir="$1"
  verify_private_packages "$dir"
  local stage="$MNT/tmp/ark-genesis-packages"
  rm -rf "$stage"
  mkdir -p "$stage"
  cp "$dir"/*.pkg.tar.* "$stage/"

  mapfile -t package_names < <(find "$stage" -maxdepth 1 -type f -name '*.pkg.tar.*' -printf '/tmp/ark-genesis-packages/%f\n' | sort)
  [[ "${#package_names[@]}" -eq 3 ]] || {
    echo "ERROR: expected exactly three A.R.K. packages, found ${#package_names[@]}" >&2
    exit 1
  }
  arch-chroot "$MNT" pacman -U --noconfirm "${package_names[@]}"
  rm -rf "$stage"

  [[ -f "$MNT/usr/lib/systemd/system/ark-runtime-api.service" ]] || { echo "ERROR: ark-runtime-api.service not installed" >&2; exit 1; }
  [[ -f "$MNT/usr/lib/systemd/system/ark-local-api.service" ]] || { echo "ERROR: ark-local-api.service not installed" >&2; exit 1; }
  [[ -f "$MNT/usr/lib/systemd/system/ark-trading.service" ]] || { echo "ERROR: ark-trading.service not installed" >&2; exit 1; }
  [[ -d "$MNT/ark/runtime" ]] || { echo "ERROR: /ark/runtime not installed" >&2; exit 1; }

  install -d -m0750 "$MNT/etc/ark"
  printf '%s\n' "$ARK_GENESIS_COMMIT" > "$MNT/etc/ark/ARK_GENESIS_COMMIT"
  printf '%s\n' "$ARK_GENESIS_REPOSITORY" > "$MNT/etc/ark/ARK_GENESIS_REPOSITORY"
  ARK_INTEGRATED=1
}

rm -rf "$WORK"
mkdir -p "$OUT" "$MNT"
"$ROOT/kernel/build-kernel.sh"
rm -f "$IMG"
truncate -s "${SIZE_GIB}G" "$IMG"
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

# Mount root first, then every declared mutable/state subvolume in file order.
mount -o noatime,compress=zstd:3,subvol=@ark "${LOOP}p2" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* || "$mp" == "/" ]] && continue
  mkdir -p "$MNT$mp"
  mount -o "subvol=$subvol,$opts" "${LOOP}p2" "$MNT$mp"
done < "$ROOT/config/subvolumes.tsv"
mkdir -p "$MNT/boot"
mount "${LOOP}p1" "$MNT/boot"

# Pinned Arch userspace construction source. Arch is construction input, not ARKlinux identity.
cat >/etc/pacman.d/arklinux-build-mirrorlist <<EOF
Server = https://archive.archlinux.org/repos/${SNAP}/\$repo/os/\$arch
EOF
cp /etc/pacman.conf "$WORK/pacman.conf"
sed -i 's|^Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/arklinux-build-mirrorlist|' "$WORK/pacman.conf"
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT/config/packages.x86_64")
pacstrap -C "$WORK/pacman.conf" -K "$MNT" "${PKGS[@]}"

install -Dm0644 /etc/pacman.conf "$MNT/etc/pacman.conf"
install -Dm0644 /etc/pacman.d/mirrorlist "$MNT/etc/pacman.d/mirrorlist"

# ARKlinux kernel is constructed directly; no distribution kernel package owns it.
cp "$ROOT/out/kernel/arklinux-kernel" "$MNT/boot/arklinux-kernel"
KREL="$(cat "$ROOT/out/kernel/kernel-release")"
mkdir -p "$MNT/usr/lib/modules"
cp -a "$ROOT/out/kernel/modules/lib/modules/$KREL" "$MNT/usr/lib/modules/"

# Install ARKlinux-owned substrate/desktop files first.
cp -a "$ROOT/rootfs/." "$MNT/"

# Optionally install the private, provenance-locked canonical A.R.K. packages.
if [[ -d "$ARK_PACKAGE_MOUNT" ]]; then
  install_private_packages "$ARK_PACKAGE_MOUNT"
elif [[ "$ARK_REQUIRED" == "1" ]]; then
  echo "ERROR: integrated image requested but /ark-genesis-packages is not mounted" >&2
  exit 1
else
  echo "Building ARKlinux substrate-only image: no private A.R.K. package set supplied."
fi

# Keep rolling userspace updates from replacing the directly constructed ARKlinux kernel.
if ! grep -q 'arklinux-kernel-hold.conf' "$MNT/etc/pacman.conf"; then
  printf '\nInclude = /etc/pacman.d/arklinux-kernel-hold.conf\n' >> "$MNT/etc/pacman.conf"
fi

# Create both substrate and package-provided identities before applying tmpfiles.
arch-chroot "$MNT" systemd-sysusers

# Apply declared mount ownership/mode. ARK state subvolumes remain root-owned in
# substrate-only builds; the canonical ark-services tmpfiles contract assigns the
# `ark` runtime ownership when the private packages are installed.
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
  [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue
  arch-chroot "$MNT" chown "$owner:$group" "$mp"
  arch-chroot "$MNT" chmod "$mode" "$mp"
done < "$ROOT/config/subvolumes.tsv"
arch-chroot "$MNT" systemd-tmpfiles --create

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
if [[ "$ARK_INTEGRATED" == "1" ]]; then
  arch-chroot "$MNT" systemctl enable ark-runtime-api.service
  arch-chroot "$MNT" systemctl add-wants ark.target ark-runtime-api.service
  # ark-local-api is optional/read-only; ark-trading remains disabled until an
  # operator installs a mandate and brokerage credentials.
fi

# Give the operator an install-time account; password remains locked until explicitly set.
arch-chroot "$MNT" useradd -m -G wheel,audio,video,input,storage -s /bin/bash operator || true
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$MNT/etc/sudoers.d/10-wheel"
chmod 0440 "$MNT/etc/sudoers.d/10-wheel"

# Provenance + topology evidence.
mkdir -p "$OUT/evidence"
cp "$ROOT/config/subvolumes.tsv" "$OUT/evidence/subvolumes.tsv"
cp "$ROOT/config/processes.tsv" "$OUT/evidence/processes.tsv"
cp "$ROOT/config/ark-genesis.lock" "$OUT/evidence/ark-genesis.lock"
cp "$ROOT/kernel/source.lock" "$OUT/evidence/kernel-source.lock"
cp "$ROOT/out/kernel/SHA256SUMS" "$OUT/evidence/kernel-SHA256SUMS"
if [[ "$ARK_INTEGRATED" == "1" ]]; then
  cp "$ARK_PACKAGE_MOUNT/ARK_GENESIS_COMMIT" "$OUT/evidence/ARK_GENESIS_COMMIT"
  cp "$ARK_PACKAGE_MOUNT/ARK_GENESIS_REPOSITORY" "$OUT/evidence/ARK_GENESIS_REPOSITORY"
  cp "$ARK_PACKAGE_MOUNT/SHA256SUMS" "$OUT/evidence/ARK_GENESIS_PACKAGE_SHA256SUMS"
  [[ -f "$ARK_PACKAGE_MOUNT/MANIFEST" ]] && cp "$ARK_PACKAGE_MOUNT/MANIFEST" "$OUT/evidence/ARK_GENESIS_PACKAGE_MANIFEST"
  printf 'integrated\n' > "$OUT/evidence/ark-runtime-mode.txt"
else
  printf 'substrate-only\n' > "$OUT/evidence/ark-runtime-mode.txt"
fi
btrfs subvolume list "$MNT" > "$OUT/evidence/btrfs-subvolumes.txt"
findmnt -R "$MNT" > "$OUT/evidence/mount-tree.txt"
arch-chroot "$MNT" /bin/bash -lc 'systemd-analyze verify /etc/systemd/system/ark*.service /etc/systemd/system/ark*.target /usr/lib/systemd/system/ark*.service'

if [[ "$ARK_INTEGRATED" == "1" ]]; then
  arch-chroot "$MNT" /bin/bash -lc 'test -d /ark/runtime && test -f /etc/ark/ARK_GENESIS_COMMIT && ! test -e /opt/ark && ! test -L /opt/ark'
fi

sync
cleanup
LOOP=""
sha256sum "$IMG" > "$OUT/SHA256SUMS"
printf 'ARKlinux raw image constructed: %s\n' "$IMG"
printf 'A.R.K. integration mode: %s\n' "$([[ "$ARK_INTEGRATED" == "1" ]] && echo integrated || echo substrate-only)"
