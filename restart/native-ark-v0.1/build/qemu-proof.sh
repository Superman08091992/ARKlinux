#!/usr/bin/env bash
set -euo pipefail
umask 0077
IMAGE_ZST="${1:?usage: qemu-proof.sh arklinux-native-v0.1-x86_64.raw.zst}"
OUTDIR="${2:-$(dirname "$IMAGE_ZST")/qemu-proof}"
mkdir -p "$OUTDIR"
chmod 0700 "$OUTDIR"
RAW="$OUTDIR/arklinux-qemu.raw"
LOG="$OUTDIR/serial.log"
REUSE_RAW="${ARK_QEMU_REUSE_RAW:-0}"
RETAIN_FAILED_RAW="${ARK_QEMU_RETAIN_FAILED_RAW:-0}"
[[ "$REUSE_RAW" == "0" ]] || {
  echo "ERROR: mutable QEMU raw reuse is incompatible with release-image proof" >&2
  exit 1
}

cleanup_qemu_raw(){
  local rc=$?
  trap - EXIT
  if [[ -f "$RAW" ]]; then
    if [[ "$rc" -ne 0 && "$RETAIN_FAILED_RAW" == "1" ]]; then
      chmod 0600 "$RAW"
      printf 'WARNING: retained failed QEMU disk contains sensitive first-boot state: %s\n' "$RAW" >&2
    else
      rm -f -- "$RAW"
    fi
  fi
  exit "$rc"
}
trap cleanup_qemu_raw EXIT

rm -f "$LOG" "$RAW"
zstd -d --sparse "$IMAGE_ZST" -o "$RAW"
chmod 0600 "$RAW"

CODE="$(find /usr/share/edk2 -type f \( -name 'OVMF_CODE.4m.fd' -o -name 'OVMF_CODE.fd' \) | head -1)"
VARS_SRC="$(find /usr/share/edk2 -type f \( -name 'OVMF_VARS.4m.fd' -o -name 'OVMF_VARS.fd' \) | head -1)"
[[ -n "$CODE" && -n "$VARS_SRC" ]] || { echo 'ERROR: OVMF firmware not found' >&2; exit 1; }
VARS="$OUTDIR/OVMF_VARS.fd"
cp "$VARS_SRC" "$VARS"

set +e
QEMU_TIMEOUT_SECONDS="${ARK_QEMU_TIMEOUT_SECONDS:-3600}"
setsid timeout "$QEMU_TIMEOUT_SECONDS" qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -cpu max -smp "${ARK_QEMU_CPUS:-4}" -m "${ARK_QEMU_MEMORY_MIB:-6144}" \
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

grep 'ARK_SOURCE_PROVENANCE_PROBE=PASS\|ARK_AGENT_IDENTITY_PROBE=PASS\|ARK_STATUS_PROBE=PASS\|ARK_INGESTION_PREVERIFICATION_PROBE=PASS\|ARK_INGESTION_DEDUPLICATION_PROBE=PASS\|ARK_ALATHEIA_REJECTION_PROBE=PASS\|ARK_GRAVEYARD_REJECTION_PROBE=PASS\|ARK_ALATHEIA_VERIFICATION_PROBE=PASS\|ARK_INGESTION_PROBE=PASS\|ARK_INGESTION_PERSISTENCE_PROBE=PASS\|ARK_GRAVEYARD_UNVERIFIED_REJECTION_PROBE=PASS\|ARK_GRAVEYARD_ADMISSION_PROBE=PASS\|ARK_GRAVEYARD_TAMPER_REJECTION_PROBE=PASS\|ARK_REAL_EMBEDDING_PROBE=PASS\|ARK_EVIDENCE_CONTINUITY_PROBE=PASS\|ARK_NATIVE_BOOT_PROOF=PASS' "$LOG" > "$OUTDIR/proof.txt"
printf 'qemu_exit=%s\n' "$RC" >> "$OUTDIR/proof.txt"
printf 'QEMU native boot proof passed.\n'
rm -f -- "$RAW"

