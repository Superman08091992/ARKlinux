#!/usr/bin/env bash
# ARKLinux Docker build entrypoint
# Runs inside the arklinux-builder container.
# Source is mounted at /src; output ISO is written to /out.

set -euo pipefail

SRC="/src"
OUT="${ARK_OUTPUT_DIR:-/out}"
WORK="$(mktemp -d /tmp/arkwork.XXXXXX)"
PROFILE="${WORK}/profile"
trap 'umount -R "${WORK}" 2>/dev/null || true; rm -rf "${WORK}"' EXIT

mkdir -p "$OUT" "$PROFILE"

echo "[build] ARKLinux ISO builder"
echo "[build] Profile:  $PROFILE (copy of $SRC/archiso)"
echo "[build] Output:   $OUT"
echo "[build] Snapshot: $(grep 'archive.archlinux.org' /etc/pacman.conf | head -1)"

# Build from a private copy so the source checkout may be mounted read-only.
cp -a "$SRC/archiso/." "$PROFILE/"

# Stamp BUILD_ID only in the build copy.
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)-local}"
sed -i "s|@BUILD_ID@|${BUILD_ID}|g" "$PROFILE/airootfs/etc/os-release"

# Run mkarchiso
mkarchiso -v -w "$WORK/work" -o "$OUT" "$PROFILE"

# Checksums
cd "$OUT"
ISO=$(ls *.iso | head -1)
sha256sum "$ISO" > SHA256SUMS
echo "[build] Done: $ISO"
echo "[build] SHA256: $(cat SHA256SUMS)"
