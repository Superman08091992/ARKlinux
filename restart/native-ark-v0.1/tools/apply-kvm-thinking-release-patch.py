from __future__ import annotations

import re
import sys
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


if len(sys.argv) != 2 or not re.fullmatch(r"[0-9a-f]{40}", sys.argv[1]):
    raise SystemExit("usage: apply-kvm-thinking-release-patch.py <ARK_GENESIS_COMMIT>")
new_genesis = sys.argv[1]
root = Path("restart/native-ark-v0.1")
lock_path = root / "config/ark-genesis.lock"
lock = lock_path.read_text(encoding="utf-8")
match = re.search(r"^ARK_GENESIS_COMMIT=([0-9a-f]{40})$", lock, flags=re.MULTILINE)
if not match:
    raise SystemExit("current ARK_GENESIS_COMMIT not found")
old_genesis = match.group(1)

for path in root.rglob("*"):
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if old_genesis in text:
        path.write_text(text.replace(old_genesis, new_genesis), encoding="utf-8")

qemu = root / "build/qemu-proof.sh"
s = qemu.read_text(encoding="utf-8")
old = '''set +e
QEMU_TIMEOUT_SECONDS="${ARK_QEMU_TIMEOUT_SECONDS:-3600}"
setsid timeout --signal=TERM --kill-after=10s "$QEMU_TIMEOUT_SECONDS" qemu-system-x86_64 \\
  -machine q35,accel=tcg \\
  -cpu max -smp "${ARK_QEMU_CPUS:-4}" -m "${ARK_QEMU_MEMORY_MIB:-6144}" \\
'''
new = '''QEMU_ACCEL="${ARK_QEMU_ACCEL:-auto}"
case "$QEMU_ACCEL" in
  auto)
    if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
      QEMU_ACCEL=kvm
    else
      QEMU_ACCEL=tcg
    fi
    ;;
  kvm)
    [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] || {
      echo "ERROR: ARK_QEMU_ACCEL=kvm requested but /dev/kvm is unavailable" >&2
      exit 1
    }
    ;;
  tcg) ;;
  *)
    echo "ERROR: unsupported ARK_QEMU_ACCEL=$QEMU_ACCEL (expected auto, kvm, or tcg)" >&2
    exit 1
    ;;
esac
if [[ "$QEMU_ACCEL" == "kvm" ]]; then
  QEMU_CPU="${ARK_QEMU_CPU:-host}"
else
  QEMU_CPU="${ARK_QEMU_CPU:-max}"
fi
printf 'ARK_QEMU_ACCELERATOR=%s cpu=%s\\n' "$QEMU_ACCEL" "$QEMU_CPU"

set +e
QEMU_TIMEOUT_SECONDS="${ARK_QEMU_TIMEOUT_SECONDS:-3600}"
setsid timeout --signal=TERM --kill-after=10s "$QEMU_TIMEOUT_SECONDS" qemu-system-x86_64 \\
  -machine "q35,accel=$QEMU_ACCEL" \\
  -cpu "$QEMU_CPU" -smp "${ARK_QEMU_CPUS:-4}" -m "${ARK_QEMU_MEMORY_MIB:-6144}" \\
'''
s = replace_once(s, old, new, "QEMU accelerator block")
s = replace_once(
    s,
    "printf 'ARK_QEMU_EXCLUSIVE_RUN_PROBE=PASS scope=outdir\\n' >> \"$PROOF_TMP\"\n",
    "printf 'ARK_QEMU_ACCELERATOR=%s cpu=%s\\n' \"$QEMU_ACCEL\" \"$QEMU_CPU\" >> \"$PROOF_TMP\"\n"
    "printf 'ARK_QEMU_EXCLUSIVE_RUN_PROBE=PASS scope=outdir\\n' >> \"$PROOF_TMP\"\n",
    "QEMU accelerator evidence",
)
qemu.write_text(s, encoding="utf-8")

(root / "rootfs/etc/systemd/system/arkd.service.d/20-slow-hardware-timeout.conf").write_text(
    "[Service]\nEnvironment=ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=330\n",
    encoding="utf-8",
)
(root / "config/slow-hardware-timeout.lock").write_text(
    "# Slow-hardware release proof timing contract.\n"
    "ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=330\n"
    "ARK_BOOT_PROOF_HTTP_TIMEOUT_SECONDS=360\n",
    encoding="utf-8",
)

wrapper = root / "rootfs/usr/local/sbin/ark-boot-proof-slow-hardware"
w = wrapper.read_text(encoding="utf-8")
w = replace_once(
    w,
    "# 30-second HTTP caller permits. Transform only request_json defaults from\n# 30 seconds to 300 seconds for this boot-proof invocation.\n",
    "# 30-second HTTP caller permits. Transform only request_json defaults from\n# 30 seconds to 360 seconds for this boot-proof invocation.\n",
    "boot proof wrapper comment",
)
w = replace_once(
    w,
    "'s/def request_json(path, payload=None, timeout=30,/def request_json(path, payload=None, timeout=300,/g'",
    "'s/def request_json(path, payload=None, timeout=30,/def request_json(path, payload=None, timeout=360,/g'",
    "boot proof HTTP timeout",
)
wrapper.write_text(w, encoding="utf-8")

test = root / "tests/test_slow_hardware_timeout_contract.py"
t = test.read_text(encoding="utf-8")
t = t.replace("five_minutes", "six_minutes")
t = t.replace("five_minute", "five_and_a_half_minute")
t = t.replace('self.assertIn("timeout=300", wrapper)', 'self.assertIn("timeout=360", wrapper)')
t = t.replace('self.assertIn("ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=300", dropin)', 'self.assertIn("ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=330", dropin)')
test.write_text(t, encoding="utf-8")

test = root / "tests/test_slow_hardware_timeout_lock.py"
t = test.read_text(encoding="utf-8")
t = t.replace("ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=300", "ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=330")
t = t.replace("ARK_BOOT_PROOF_HTTP_TIMEOUT_SECONDS=300", "ARK_BOOT_PROOF_HTTP_TIMEOUT_SECONDS=360")
test.write_text(t, encoding="utf-8")

(root / "tests/test_qemu_accelerator_contract.py").write_text(
    '''from pathlib import Path\nimport unittest\n\n\nROOT = Path(__file__).resolve().parents[1]\n\n\nclass QemuAcceleratorContractTests(unittest.TestCase):\n    def test_qemu_prefers_kvm_and_falls_back_to_tcg(self):\n        script = (ROOT / "build/qemu-proof.sh").read_text()\n        self.assertIn('QEMU_ACCEL="${ARK_QEMU_ACCEL:-auto}"', script)\n        self.assertIn('QEMU_ACCEL=kvm', script)\n        self.assertIn('QEMU_ACCEL=tcg', script)\n        self.assertIn('-machine "q35,accel=$QEMU_ACCEL"', script)\n        self.assertIn('QEMU_CPU="${ARK_QEMU_CPU:-host}"', script)\n        self.assertIn('QEMU_CPU="${ARK_QEMU_CPU:-max}"', script)\n        self.assertIn('ARK_QEMU_ACCELERATOR=%s cpu=%s', script)\n\n\nif __name__ == "__main__":\n    unittest.main()\n''',
    encoding="utf-8",
)

print(f"ARKLINUX_RELEASE_PATCH=PASS old_ark_genesis={old_genesis} new_ark_genesis={new_genesis}")
