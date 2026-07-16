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

set +e
timeout --signal=TERM 240 qemu-system-x86_64 \
  -machine pc,accel=tcg \
  -cpu max \
  -m 2048 \
  -smp 2 \
  -boot d \
  -cdrom "$iso" \
  -display none \
  -serial "file:${log}" \
  -monitor none \
  -no-reboot
qemu_rc=$?
set -e

if grep -Eq 'Welcome to ARKLinux|Reached target .*Multi-User|ARKLinux login:' "$log"; then
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

