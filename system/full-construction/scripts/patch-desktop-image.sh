#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMG="${1:-}"
DEST_IMG="${2:-$ROOT/out/arklinux-x86_64.raw}"
SNAP="${ARKLINUX_ARCH_SNAPSHOT:-2026/08/20}"
WORK="$ROOT/.work/desktop-patch"
MNT="$WORK/mnt"
LOOP=""

if [[ -z "$SOURCE_IMG" ]]; then
  echo "usage: $0 /path/to/proven/arklinux-x86_64.raw [destination.raw]" >&2
  exit 2
fi

SOURCE_IMG="$(readlink -f "$SOURCE_IMG")"
mkdir -p "$(dirname "$DEST_IMG")"
DEST_IMG="$(readlink -m "$DEST_IMG")"

[[ -f "$SOURCE_IMG" ]] || { echo "ERROR: source image not found: $SOURCE_IMG" >&2; exit 1; }
[[ "$SOURCE_IMG" != "$DEST_IMG" ]] || { echo "ERROR: source and destination must differ" >&2; exit 1; }

cleanup(){
  set +e
  mountpoint -q "$MNT/boot" && umount "$MNT/boot"
  while mountpoint -q "$MNT"; do umount -R "$MNT" 2>/dev/null || break; done
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

rm -rf "$WORK"
mkdir -p "$WORK" "$MNT"
rm -f "$DEST_IMG"

printf 'Copying proven image:\n  %s\n->%s\n' "$SOURCE_IMG" "$DEST_IMG"
cp --reflink=auto --sparse=always "$SOURCE_IMG" "$DEST_IMG"

LOOP="$(losetup --find --show --partscan "$DEST_IMG")"
mount -o noatime,compress=zstd:3,subvol=@ "${LOOP}p2" "$MNT"
mkdir -p "$MNT/boot"
mount "${LOOP}p1" "$MNT/boot"

[[ -f "$MNT/etc/os-release" ]] || { echo "ERROR: copied image does not contain ARKlinux rootfs" >&2; exit 1; }
grep -q '^ID=arklinux$' "$MNT/etc/os-release" || { echo "ERROR: destination is not an ARKlinux image" >&2; exit 1; }
[[ -f "$MNT/boot/arklinux-kernel" ]] || { echo "ERROR: ARKlinux kernel missing from copied image" >&2; exit 1; }

# Install only desktop dependencies against the same pinned userspace snapshot
# used by the proven construction image. This avoids an unrelated rolling upgrade.
cat > "$MNT/etc/pacman.d/arklinux-desktop-mirrorlist" <<EOF
Server = https://archive.archlinux.org/repos/${SNAP}/\$repo/os/\$arch
EOF
cp "$MNT/etc/pacman.conf" "$WORK/pacman-desktop.conf"
sed -i 's|^Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/arklinux-desktop-mirrorlist|' "$WORK/pacman-desktop.conf"
cp "$WORK/pacman-desktop.conf" "$MNT/tmp/arklinux-desktop-pacman.conf"

DESKTOP_PKGS=(gtk4 gtk4-layer-shell python-gobject thunar firefox)
arch-chroot "$MNT" pacman -Syy --noconfirm --config /tmp/arklinux-desktop-pacman.conf
arch-chroot "$MNT" pacman -S --needed --noconfirm --config /tmp/arklinux-desktop-pacman.conf "${DESKTOP_PKGS[@]}"
rm -f "$MNT/tmp/arklinux-desktop-pacman.conf" "$MNT/etc/pacman.d/arklinux-desktop-mirrorlist"

# Overlay ARKlinux-owned desktop/session files. The overlay does not contain
# persistent /ark state and therefore does not replace Btrfs state subvolumes.
cp -a "$ROOT/rootfs/." "$MNT/"

# Ensure the installed operator can reach the local privileged broker.
arch-chroot "$MNT" usermod -aG wheel operator

# Verify service and Python syntax inside the image before detaching it.
arch-chroot "$MNT" systemd-analyze verify \
  /etc/systemd/system/ark-desktop-rootd.service \
  /etc/systemd/system/greetd.service
arch-chroot "$MNT" python -m py_compile \
  /usr/lib/ark-desktop/ark-desktop.py \
  /usr/lib/ark-desktop/ark-rootd.py \
  /usr/lib/ark-desktop/ark-shell.py

sync
cleanup
LOOP=""

sha256sum "$DEST_IMG" > "$ROOT/out/arklinux-desktop-SHA256SUMS"
printf 'ARKlinux desktop test image patched: %s\n' "$DEST_IMG"
printf 'Original proven image preserved: %s\n' "$SOURCE_IMG"
