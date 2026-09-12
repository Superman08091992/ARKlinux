import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AgentFilesystemContractTests(unittest.TestCase):
    def test_agent_subvolumes_are_role_owned_and_separate(self) -> None:
        text = (ROOT / "config" / "subvolumes.tsv").read_text(encoding="utf-8")
        for role in ("kyle", "aletheia", "joey", "hrm", "kenny"):
            self.assertIn(f"@agent-{role}\t/ark/agents/{role}", text)
            self.assertIn(f"\tark-{role}\tark-agent-audit\t0750\tagent-state", text)

    def test_build_creates_setgid_audit_ledgers(self) -> None:
        build = (ROOT / "build" / "build-image.sh").read_text(encoding="utf-8")
        self.assertIn('"/ark/agents/$role/ledger"', build)
        self.assertIn("getent group ark-agent-audit", build)
        packages = (ROOT / "config" / "packages.x86_64").read_text(encoding="utf-8")
        self.assertIn("python-cryptography", packages)

    def test_boot_proof_requires_keys_and_ledger_permissions(self) -> None:
        proof = (
            ROOT / "rootfs" / "usr" / "local" / "sbin" / "ark-boot-proof"
        ).read_text(encoding="utf-8")
        self.assertIn("missing_agent_private_key", proof)
        self.assertIn("invalid_agent_ledger", proof)
        self.assertIn("ark-agent-audit:2750", proof)
        self.assertIn('"/ark/agent-public-keys/$role/signing-key.json"', proof)
        self.assertIn("ark-batch-executor.socket", proof)
        self.assertIn("invalid_batch_claim_store", proof)

    def test_image_is_pinned_to_agentic_runtime_commit(self) -> None:
        lock = (ROOT / "config" / "ark-genesis.lock").read_text(encoding="utf-8")
        self.assertIn(
            "ARK_GENESIS_COMMIT=2a125608e22c1a3104f88142345b10b23df0a706",
            lock,
        )
        build = (ROOT / "build" / "build-image.sh").read_text(encoding="utf-8")
        self.assertIn("runtime overlay commit", build)
        self.assertIn("test -x /usr/bin/ark-agentic-model-proof", build)
        self.assertIn(
            'cp "$ARK_GENESIS_LOCK" "$OUT/evidence/ark-genesis.lock"',
            build,
        )


if __name__ == "__main__":
    unittest.main()
