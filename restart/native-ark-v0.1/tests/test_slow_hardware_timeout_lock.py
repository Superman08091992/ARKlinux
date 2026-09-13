from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SlowHardwareTimeoutLockTests(unittest.TestCase):
    def test_timeout_lock_matches_runtime_dropins(self):
        lock = (ROOT / "config/slow-hardware-timeout.lock").read_text()
        self.assertIn("ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=300", lock)
        self.assertIn("ARK_BOOT_PROOF_HTTP_TIMEOUT_SECONDS=300", lock)


if __name__ == "__main__":
    unittest.main()
