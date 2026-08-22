#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$ROOT/out/arklinux-x86_64.raw"
[[ -f "$IMG" ]] || { echo "missing $IMG" >&2; exit 1; }
CODE="$(find /usr/share/edk2 -type f \( -name 'OVMF_CODE*.fd' -o -name 'OVMF_CODE.fd' \) 2>/dev/null | head -1)"
VARS_SRC="$(find /usr/share/edk2 -type f \( -name 'OVMF_VARS*.fd' -o -name 'OVMF_VARS.fd' \) 2>/dev/null | head -1)"
[[ -n "$CODE" && -n "$VARS_SRC" ]] || { echo 'OVMF firmware not found' >&2; exit 1; }
VARS="$ROOT/out/OVMF_VARS.fd"; cp "$VARS_SRC" "$VARS"
ACCEL=tcg; CPU=max
if [[ -r /dev/kvm ]]; then ACCEL=kvm; CPU=host; fi
exec qemu-system-x86_64 -machine q35,accel="$ACCEL" -cpu "$CPU" -m 4096 -smp 4 \
 -drive if=pflash,format=raw,readonly=on,file="$CODE" \
 -drive if=pflash,format=raw,file="$VARS" \
 -drive if=virtio,format=raw,file="$IMG" \
 -device virtio-vga -display gtk -serial mon:stdio
