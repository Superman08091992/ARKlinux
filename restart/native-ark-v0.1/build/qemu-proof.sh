#!/usr/bin/env bash
set -euo pipefail
IMAGE_ZST="${1:?usage: qemu-proof.sh arklinux-native-v0.1-x86_64.raw.zst}"
OUTDIR="${2:-$(dirname "$IMAGE_ZST")/qemu-proof}"
mkdir -p "$OUTDIR"
RAW="$OUTDIR/arklinux-qemu.raw"
LOG="$OUTDIR/serial.log"
rm -f "$RAW" "$LOG"
zstd -d --sparse "$IMAGE_ZST" -o "$RAW"

CODE="$(find /usr/share/edk2 -type f \( -name 'OVMF_CODE.4m.fd' -o -name 'OVMF_CODE.fd' \) | head -1)"
VARS_SRC="$(find /usr/share/edk2 -type f \( -name 'OVMF_VARS.4m.fd' -o -name 'OVMF_VARS.fd' \) | head -1)"
[[ -n "$CODE" && -n "$VARS_SRC" ]] || { echo 'ERROR: OVMF firmware not found' >&2; exit 1; }
VARS="$OUTDIR/OVMF_VARS.fd"
cp "$VARS_SRC" "$VARS"

set +e
setsid timeout 600 qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -cpu max -smp 2 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$RAW",format=raw,if=virtio,cache=unsafe \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -monitor none -serial stdio -no-reboot > >(tee "$LOG") 2>&1 &
QEMU_RUNNER_PID=$!
STOPPED_ON_MARKER=0
while kill -0 "$QEMU_RUNNER_PID" 2>/dev/null; do
  if grep -q 'ARK_NATIVE_BOOT_PROOF=PASS\|ARK_NATIVE_BOOT_PROOF=FAIL' "$LOG" 2>/dev/null; then
    STOPPED_ON_MARKER=1
    kill -TERM -- "-$QEMU_RUNNER_PID" 2>/dev/null || true
    break
  fi
  sleep 1
done
wait "$QEMU_RUNNER_PID"
RC=$?
if [[ "$STOPPED_ON_MARKER" == "1" ]] && grep -q 'ARK_NATIVE_BOOT_PROOF=PASS' "$LOG"; then
  RC=0
fi
set -e

if ! grep -q 'ARK_NATIVE_BOOT_PROOF=PASS' "$LOG"; then
  echo "ERROR: QEMU boot did not produce ARK_NATIVE_BOOT_PROOF=PASS (qemu rc=$RC)" >&2
  tail -200 "$LOG" >&2
  exit 1
fi

grep 'ARK_STATUS_PROBE=PASS\|ARK_REAL_EMBEDDING_PROBE=PASS\|ARK_NATIVE_BOOT_PROOF=PASS' "$LOG" > "$OUTDIR/proof.txt"
printf 'qemu_exit=%s\n' "$RC" >> "$OUTDIR/proof.txt"
printf 'QEMU native boot proof passed.\n'
rm -f "$RAW"
