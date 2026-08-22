#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$ROOT/out/arklinux-x86_64.raw"

[[ -f "$IMG" ]] || {
    echo "missing image: $IMG" >&2
    exit 1
}

LOOP=""
M="$(mktemp -d)"

cleanup() {
    set +e
    mountpoint -q "$M/boot" && sudo umount "$M/boot"
    mountpoint -q "$M" && sudo umount "$M"
    [[ -n "$LOOP" ]] && sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$M/boot" 2>/dev/null || true
    rmdir "$M" 2>/dev/null || true
}

trap cleanup EXIT

LOOP="$(sudo losetup --read-only --find --show --partscan "$IMG")"

# ARKROOT
sudo mount -o ro,subvol=@ "${LOOP}p2" "$M"

# ARKESP
sudo mkdir -p "$M/boot"
sudo mount -o ro "${LOOP}p1" "$M/boot"

required=(
    boot/arklinux-kernel
    boot/initramfs-arklinux.img
    etc/os-release
    etc/mkinitcpio.d/arklinux.preset
    etc/systemd/system/ark.target
    usr/lib/ark/ark_native.py
)

for f in "${required[@]}"; do
    if sudo test -e "$M/$f"; then
        printf 'PASS  %s\n' "$f"
    else
        printf 'MISSING  %s\n' "$f" >&2
        exit 1
    fi
done

grep -q '^ID=arklinux$' "$M/etc/os-release" || {
    echo "root filesystem does not identify as ARKlinux" >&2
    exit 1
}

expected="$(
    grep -vE '^[[:space:]]*(#|$)' \
        "$ROOT/config/subvolumes.tsv" |
    wc -l
)"

actual="$(sudo btrfs subvolume list "$M" | wc -l)"

(( actual >= expected )) || {
    echo "subvolume count $actual < expected $expected" >&2
    exit 1
}

echo
echo "ARKlinux identity: PASS"
echo "ARKlinux boot partition: PASS"
echo "Btrfs topology: PASS ($actual subvolumes)"
echo "ARKlinux image structural verification: PASS"
