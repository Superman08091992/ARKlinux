from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SlowHardwareTimeoutContractTests(unittest.TestCase):
    def test_boot_proof_wrapper_raises_default_http_budget_to_six_minutes(self):
        wrapper = (ROOT / "rootfs/usr/local/sbin/ark-boot-proof-slow-hardware").read_text()
        self.assertIn("timeout=30", wrapper)
        self.assertIn("timeout=360", wrapper)

    def test_boot_proof_service_uses_slow_hardware_wrapper(self):
        dropin = (ROOT / "rootfs/etc/systemd/system/ark-boot-proof.service.d/20-slow-hardware-timeout.conf").read_text()
        self.assertIn("ExecStart=/usr/bin/bash /usr/local/sbin/ark-boot-proof-slow-hardware", dropin)

    def test_runtime_router_allows_five_and_a_half_minute_agent_response(self):
        dropin = (ROOT / "rootfs/etc/systemd/system/arkd.service.d/20-slow-hardware-timeout.conf").read_text()
        self.assertIn("ARK_AGENT_RESPONSE_TIMEOUT_SECONDS=330", dropin)


if __name__ == "__main__":
    unittest.main()
