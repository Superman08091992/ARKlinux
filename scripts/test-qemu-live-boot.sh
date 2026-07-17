#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 path/to/arklinux.iso" >&2; exit 2; }
iso="$(realpath "$1")"
[[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null || {
  echo 'dependency blocker: qemu-system-x86_64 is required' >&2
  exit 2
}

out="${ARK_TEST_OUTPUT_DIR:-$(dirname "$iso")/test-results}"
log="${out}/qemu-live-console.log"
summary="${out}/qemu-live-boot-summary.json"
mkdir -p "$out"
: > "$log"

boot_marker() {
  grep -Eq 'ARKLinux v1\.0\.1|Reached target .*Multi-User|ARKLinux login:' "$log"
}

write_summary() {
  local status="$1"
  local reason="${2:-}"
  python3 - "$summary" "$status" "$qemu_rc" "$iso" "$reason" <<'PY'
import json
import sys

path, status, qemu_exit, iso, reason = sys.argv[1:]
record = {
    "test": "qemu-live-boot",
    "status": status,
    "qemu_exit": int(qemu_exit),
    "iso": iso,
    "real_execution": False,
}
if reason:
    record["reason"] = reason
with open(path, "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu max \
  -m 2048 \
  -smp 2 \
  -boot d \
  -cdrom "$iso" \
  -display none \
  -serial "file:${log}" \
  -monitor none \
  -no-reboot &
qemu_pid=$!
trap 'kill "$qemu_pid" 2>/dev/null || true' EXIT

qemu_rc=124
for _ in $(seq 1 240); do
  if boot_marker; then
    qemu_rc=0
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    set +e
    wait "$qemu_pid"
    qemu_rc=$?
    set -e
    break
  fi
  sleep 1
done
kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true
trap - EXIT

if boot_marker; then
  write_summary pass
  cat "$summary"
  exit 0
fi

write_summary fail 'no accepted boot marker in serial console'
cat "$summary" >&2
tail -n 200 "$log" >&2
exit 1
