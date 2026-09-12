#!/usr/bin/env bash
set -euo pipefail
umask 0077
IMAGE_ZST_INPUT="${1:?usage: qemu-proof.sh arklinux-native-v0.1-x86_64.raw.zst}"
IMAGE_ZST="$(realpath -m "$IMAGE_ZST_INPUT")"
OUTDIR="$(realpath -m "${2:-$(dirname "$IMAGE_ZST")/qemu-proof}")"
mkdir -p "$(dirname "$OUTDIR")"
QEMU_LOCK="$OUTDIR.lock"
exec {QEMU_LOCK_FD}> "$QEMU_LOCK"
if ! flock -n "$QEMU_LOCK_FD"; then
  echo "ERROR: QEMU proof already active for $OUTDIR" >&2
  exit 1
fi
mkdir -p "$OUTDIR"
rm -f -- "$OUTDIR/proof.txt" "$OUTDIR/agent-identities.txt"
chmod 0700 "$OUTDIR"
RAW="$OUTDIR/arklinux-qemu.raw"
LOG="$OUTDIR/serial.log"
REUSE_RAW="${ARK_QEMU_REUSE_RAW:-0}"
RETAIN_FAILED_RAW="${ARK_QEMU_RETAIN_FAILED_RAW:-0}"
QEMU_RUNNER_PID=""
[[ "$REUSE_RAW" == "0" ]] || {
  echo "ERROR: mutable QEMU raw reuse is incompatible with release-image proof" >&2
  exit 1
}

terminate_qemu_group(){
  local group_pid="$1"
  if ! kill -0 -- "-$group_pid" 2>/dev/null; then
    return 0
  fi
  kill -TERM -- "-$group_pid" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 -- "-$group_pid" 2>/dev/null || return 0
    sleep 0.2
  done
  kill -KILL -- "-$group_pid" 2>/dev/null || true
  for _ in {1..10}; do
    kill -0 -- "-$group_pid" 2>/dev/null || return 0
    sleep 0.2
  done
  return 1
}

wait_qemu_group_ready(){
  local runner_pid="$1"
  for _ in {1..100}; do
    kill -0 -- "-$runner_pid" 2>/dev/null && return 0
    kill -0 "$runner_pid" 2>/dev/null || return 1
    sleep 0.05
  done
  return 1
}

cleanup_qemu_raw(){
  local rc=$?
  local qemu_stopped=1
  trap - EXIT INT TERM HUP
  if [[ -n "${QEMU_RUNNER_PID:-}" ]]; then
    if terminate_qemu_group "$QEMU_RUNNER_PID"; then
      wait "$QEMU_RUNNER_PID" 2>/dev/null || true
    else
      qemu_stopped=0
      rc=1
      printf 'ERROR: QEMU process group did not stop; retaining its mutable disk\n' >&2
    fi
  fi
  if [[ -f "$RAW" ]]; then
    if [[ "$qemu_stopped" != "1" ]]; then
      chmod 0600 "$RAW"
      printf 'WARNING: retained active QEMU disk for safe recovery: %s\n' "$RAW" >&2
    elif [[ "$rc" -ne 0 && "$RETAIN_FAILED_RAW" == "1" ]]; then
      chmod 0600 "$RAW"
      printf 'WARNING: retained failed QEMU disk contains sensitive first-boot state: %s\n' "$RAW" >&2
    else
      rm -f -- "$RAW"
    fi
  fi
  exit "$rc"
}
trap cleanup_qemu_raw EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

rm -f -- "$LOG" "$RAW"
IMAGE_SHA256_BEFORE="$(sha256sum -- "$IMAGE_ZST")"
IMAGE_SHA256_BEFORE="${IMAGE_SHA256_BEFORE%% *}"
[[ "$IMAGE_SHA256_BEFORE" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not bind QEMU proof to a valid image digest" >&2
  exit 1
}
zstd -d --sparse "$IMAGE_ZST" -o "$RAW"
chmod 0600 "$RAW"

CODE="$(find /usr/share/edk2 -type f \( -name 'OVMF_CODE.4m.fd' -o -name 'OVMF_CODE.fd' \) | head -1)"
VARS_SRC="$(find /usr/share/edk2 -type f \( -name 'OVMF_VARS.4m.fd' -o -name 'OVMF_VARS.fd' \) | head -1)"
[[ -n "$CODE" && -n "$VARS_SRC" ]] || { echo 'ERROR: OVMF firmware not found' >&2; exit 1; }
VARS="$OUTDIR/OVMF_VARS.fd"
cp "$VARS_SRC" "$VARS"

set +e
QEMU_TIMEOUT_SECONDS="${ARK_QEMU_TIMEOUT_SECONDS:-3600}"
setsid timeout --signal=TERM --kill-after=10s "$QEMU_TIMEOUT_SECONDS" qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -cpu max -smp "${ARK_QEMU_CPUS:-4}" -m "${ARK_QEMU_MEMORY_MIB:-6144}" \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$RAW",format=raw,if=virtio,cache=unsafe \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -monitor none -serial stdio -no-reboot > >(tee "$LOG") 2>&1 &
QEMU_RUNNER_PID=$!
if ! wait_qemu_group_ready "$QEMU_RUNNER_PID"; then
  kill -TERM "$QEMU_RUNNER_PID" 2>/dev/null || true
  wait "$QEMU_RUNNER_PID" 2>/dev/null || true
  QEMU_RUNNER_PID=""
  echo "ERROR: QEMU process group was not established" >&2
  exit 1
fi
STOPPED_ON_MARKER=0
TERMINATION_FAILED=0
while kill -0 -- "-$QEMU_RUNNER_PID" 2>/dev/null; do
  if grep -q 'ARK_NATIVE_BOOT_PROOF=PASS\|ARK_NATIVE_BOOT_PROOF=FAIL' "$LOG" 2>/dev/null; then
    STOPPED_ON_MARKER=1
    if ! terminate_qemu_group "$QEMU_RUNNER_PID"; then
      TERMINATION_FAILED=1
    fi
    break
  fi
  sleep 1
done
if [[ "$TERMINATION_FAILED" == "1" ]]; then
  RC=1
else
  wait "$QEMU_RUNNER_PID"
  RC=$?
  if terminate_qemu_group "$QEMU_RUNNER_PID"; then
    QEMU_RUNNER_PID=""
  else
    TERMINATION_FAILED=1
    RC=1
  fi
fi
if [[ "$TERMINATION_FAILED" == "0" && "$STOPPED_ON_MARKER" == "1" ]] &&
   grep -q 'ARK_NATIVE_BOOT_PROOF=PASS' "$LOG"; then
  RC=0
fi
set -e

if [[ "$TERMINATION_FAILED" != "0" ]]; then
  echo "ERROR: QEMU process group teardown failed; refusing to derive proof" >&2
  tail -200 "$LOG" >&2
  exit 1
fi
if grep -q 'ARK_NATIVE_BOOT_PROOF=FAIL' "$LOG"; then
  echo "ERROR: QEMU boot produced ARK_NATIVE_BOOT_PROOF=FAIL (qemu rc=$RC)" >&2
  tail -200 "$LOG" >&2
  exit 1
fi
if ! grep -q 'ARK_NATIVE_BOOT_PROOF=PASS' "$LOG"; then
  echo "ERROR: QEMU boot did not produce ARK_NATIVE_BOOT_PROOF=PASS (qemu rc=$RC)" >&2
  tail -200 "$LOG" >&2
  exit 1
fi

if [[ "$RC" -ne 0 ]]; then
  echo "ERROR: QEMU exited unsuccessfully after proof collection (qemu rc=$RC)" >&2
  tail -200 "$LOG" >&2
  exit 1
fi

IMAGE_SHA256_AFTER="$(sha256sum -- "$IMAGE_ZST")"
IMAGE_SHA256_AFTER="${IMAGE_SHA256_AFTER%% *}"
if [[ "$IMAGE_SHA256_AFTER" != "$IMAGE_SHA256_BEFORE" ]]; then
  echo "ERROR: compressed image changed during QEMU proof; refusing evidence" >&2
  exit 1
fi

grep 'ARK_SOURCE_PROVENANCE_PROBE=PASS\|ARK_AGENT_SOCKET_PROBE=PASS\|ARK_AGENT_IDENTITY_PROBE=PASS\|ARK_AGENT_IDENTITY_SET_PROBE=PASS\|ARK_AGENT_CROSS_ROLE_ACCESS_PROBE=PASS\|ARK_STATUS_PROBE=PASS\|ARK_INGESTION_PREVERIFICATION_PROBE=PASS\|ARK_INGESTION_DEDUPLICATION_PROBE=PASS\|ARK_ALATHEIA_REJECTION_PROBE=PASS\|ARK_GRAVEYARD_REJECTION_PROBE=PASS\|ARK_ALATHEIA_VERIFICATION_PROBE=PASS\|ARK_INGESTION_PROBE=PASS\|ARK_INGESTION_PERSISTENCE_PROBE=PASS\|ARK_GRAVEYARD_UNVERIFIED_REJECTION_PROBE=PASS\|ARK_GRAVEYARD_ADMISSION_PROBE=PASS\|ARK_GRAVEYARD_TAMPER_REJECTION_PROBE=PASS\|ARK_REAL_EMBEDDING_PROBE=PASS\|ARK_EVIDENCE_CONTINUITY_PROBE=PASS\|ARK_NATIVE_BOOT_PROOF=PASS' "$LOG" > "$OUTDIR/proof.txt"
/usr/bin/python - "$OUTDIR/proof.txt" "$OUTDIR/agent-identities.txt" <<'PY'
import collections
import re
import sys
from pathlib import Path

proof_path = Path(sys.argv[1])
identity_path = Path(sys.argv[2])
text = proof_path.read_text(encoding="utf-8", errors="replace")
roles = ("kyle", "aletheia", "joey", "hrm", "kenny")
role_pattern = "|".join(roles)
identity_pattern = re.compile(
    rf"ARK_AGENT_IDENTITY_PROBE=PASS role=({role_pattern}) "
    r"key_id=(ed25519:[0-9a-f]{32})(?![0-9a-f])"
)
socket_pattern = re.compile(
    rf"ARK_AGENT_SOCKET_PROBE=PASS role=({role_pattern})(?![a-z])"
)
identities = identity_pattern.findall(text)
identity_counts = collections.Counter(role for role, _key_id in identities)
if identity_counts != collections.Counter({role: 1 for role in roles}):
    raise SystemExit(f"identity marker set is not exact: {dict(identity_counts)}")
key_ids = [key_id for _role, key_id in identities]
if len(set(key_ids)) != len(roles):
    raise SystemExit("identity marker set contains duplicate key IDs")
socket_counts = collections.Counter(socket_pattern.findall(text))
if socket_counts != collections.Counter({role: 1 for role in roles}):
    raise SystemExit(f"socket marker set is not exact: {dict(socket_counts)}")
if text.count("ARK_AGENT_IDENTITY_SET_PROBE=PASS roles=5 unique_key_ids=5") != 1:
    raise SystemExit("guest identity-set marker is missing or duplicated")
if text.count(
    "ARK_AGENT_CROSS_ROLE_ACCESS_PROBE=PASS "
    "private=isolated peer_ledgers=read_only pairs=20"
) != 1:
    raise SystemExit("guest cross-role access marker is missing or duplicated")
by_role = dict(identities)
identity_path.write_text(
    "".join(
        f"ARK_AGENT_IDENTITY_PROBE=PASS role={role} key_id={by_role[role]}\n"
        for role in roles
    ),
    encoding="utf-8",
)
qemu_identity_marker = (
    "ARK_QEMU_IDENTITY_EVIDENCE=PASS roles=5 unique_key_ids=5 sockets=5"
)
with proof_path.open("a", encoding="utf-8") as proof:
    # Preserve the prefixed serial evidence above, then add the canonical
    # verified markers consumed by DREAMER's release gate.
    proof.write(qemu_identity_marker + "\n")
    proof.write("ARK_NATIVE_BOOT_PROOF=PASS\n")
print(qemu_identity_marker)
PY
printf 'ARK_QEMU_IMAGE_SHA256=%s\n' "$IMAGE_SHA256_AFTER" >> "$OUTDIR/proof.txt"
printf 'qemu_exit=%s\n' "$RC" >> "$OUTDIR/proof.txt"
printf 'QEMU native boot proof passed.\n'
rm -f -- "$RAW"

