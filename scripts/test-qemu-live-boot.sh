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
summary="${out}/qemu-live-summary.txt"
mkdir -p "$out"
: > "$log"

boot_marker() {
  grep -Eq 'ARKLinux v1\.0\.1|Reached target .*Multi-User|ARKLinux login:' "$log"
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
  {
    echo 'test=qemu-live-boot'
    echo 'status=pass'
    echo "qemu_exit=${qemu_rc}"
    echo "iso=${iso}"
  } | tee "$summary"
  exit 0
fi

{
  echo 'test=qemu-live-boot'
  echo 'status=fail'
  echo "qemu_exit=${qemu_rc}"
  echo "iso=${iso}"
  echo 'reason=no accepted boot marker in serial console'
} | tee "$summary" >&2
tail -n 200 "$log" >&2
exit 1
