#!/usr/bin/env bash
# ARKLinux Docker build entrypoint
# Runs inside the arklinux-builder container.
# Source is mounted at /src; output ISO is written to /out.

set -euo pipefail

SRC="/src"
OUT="${ARK_OUTPUT_DIR:-/out}"
WORK="/tmp/arkwork"

mkdir -p "$OUT" "$WORK"

echo "[build] ARKLinux ISO builder"
echo "[build] Profile:  $SRC/archiso"
echo "[build] Output:   $OUT"
echo "[build] Snapshot: $(grep 'archive.archlinux.org' /etc/pacman.conf | head -1)"

# Stamp BUILD_ID
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)-local}"
sed -i "s|@BUILD_ID@|${BUILD_ID}|g" "$SRC/archiso/airootfs/etc/os-release" || true

# Run mkarchiso
mkarchiso -v -w "$WORK" -o "$OUT" "$SRC/archiso/"

# Record package lock
arch-chroot "$WORK/airootfs" pacman -Q 2>/dev/null | sort > "$OUT/packages.lock" || true

# Checksums
cd "$OUT"
ISO=$(ls *.iso | head -1)
sha256sum "$ISO" > SHA256SUMS
echo "[build] Done: $ISO"
echo "[build] SHA256: $(cat SHA256SUMS)"
