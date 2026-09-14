from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AuditIntegrityContractTests(unittest.TestCase):
    def test_image_starts_auditd_with_an_early_8192_record_backlog(self) -> None:
        build = (ROOT / "build/build-image.sh").read_text(encoding="utf-8")
        loader_lines = [
            line for line in build.splitlines() if line.startswith("options root=UUID=")
        ]
        self.assertEqual(len(loader_lines), 2)
        self.assertTrue(
            all("audit=1 audit_backlog_limit=8192" in line for line in loader_lines)
        )
        self.assertIn('enable NetworkManager.service auditd.service', build)
        self.assertIn("validate_guest_contract audit_integrity", build)
        self.assertIn("pacman -Q audit linux-lts", build)

        rules = (
            ROOT / "rootfs/etc/audit/rules.d/10-arklinux-backlog.rules"
        ).read_text(encoding="utf-8")
        self.assertEqual(rules, "-b 8192\n")

    def test_boot_proof_cannot_pass_after_audit_record_loss(self) -> None:
        proof = (
            ROOT / "rootfs/usr/local/sbin/ark-boot-proof"
        ).read_text(encoding="utf-8")
        self.assertIn("wait_active auditd.service", proof)
        self.assertIn("audit_records_already_lost", proof)
        self.assertIn("audit_records_lost_during_proof", proof)
        self.assertIn("auditd_restarted_during_proof", proof)
        self.assertIn("audit_backlog_too_small", proof)
        self.assertIn("ARK_AUDIT_INTEGRITY_PROBE=PASS", proof)
        self.assertLess(
            proof.index("ARK_AUDIT_INTEGRITY_PROBE=PASS"),
            proof.index("ARK_NATIVE_BOOT_PROOF=PASS"),
        )

    def test_boot_proof_is_ordered_after_and_requires_auditd(self) -> None:
        unit = (
            ROOT / "rootfs/etc/systemd/system/ark-boot-proof.service"
        ).read_text(encoding="utf-8")
        self.assertIn("After=auditd.service audit-rules.service ", unit)
        self.assertIn("Requires=auditd.service audit-rules.service ", unit)


if __name__ == "__main__":
    unittest.main()
