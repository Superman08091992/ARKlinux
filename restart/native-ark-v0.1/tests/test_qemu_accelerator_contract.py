from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class QemuAcceleratorContractTests(unittest.TestCase):
    def test_qemu_prefers_kvm_and_falls_back_to_tcg(self):
        script = (ROOT / "build/qemu-proof.sh").read_text()
        self.assertIn('QEMU_ACCEL="${ARK_QEMU_ACCEL:-auto}"', script)
        self.assertIn("QEMU_ACCEL=kvm", script)
        self.assertIn("QEMU_ACCEL=tcg", script)
        self.assertIn('-machine "q35,accel=$QEMU_ACCEL"', script)
        self.assertIn('QEMU_CPU="${ARK_QEMU_CPU:-host}"', script)
        self.assertIn('QEMU_CPU="${ARK_QEMU_CPU:-max}"', script)
        self.assertIn("ARK_QEMU_ACCELERATOR=%s cpu=%s", script)

if __name__ == "__main__":
    unittest.main()
