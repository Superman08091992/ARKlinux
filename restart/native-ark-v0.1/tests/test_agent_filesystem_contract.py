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
        self.assertIn("wait_agent_ready", proof)
        self.assertIn("agent_socket_responds", proof)
        self.assertIn("ARK_AGENT_SOCKET_PROBE=PASS", proof)
        self.assertIn("__ark_boot_readiness_probe__", proof)
        self.assertIn("ARK_AGENT_IDENTITY_PROBE=PASS", proof)
        self.assertIn("ARK_AGENT_IDENTITY_SET_PROBE=PASS roles=5 unique_key_ids=5", proof)
        self.assertIn("duplicate_agent_key_id", proof)
        self.assertIn("invalid_agent_private_directory", proof)
        self.assertIn("ARK_AGENT_CROSS_ROLE_ACCESS_PROBE=PASS", proof)
        self.assertIn("peer_private_key_readable", proof)
        self.assertIn("peer_ledger_unreadable", proof)
        self.assertIn("peer_ledger_writable", proof)
        self.assertIn("public record does not match private identity", proof)

        qemu_proof = (
            ROOT / "build" / "qemu-proof.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("trap cleanup_qemu_raw EXIT", qemu_proof)
        self.assertIn("mutable QEMU raw reuse is incompatible", qemu_proof)
        self.assertIn("ARK_QEMU_RETAIN_FAILED_RAW", qemu_proof)
        self.assertIn("wait_qemu_group_ready", qemu_proof)
        self.assertIn("QEMU process group was not established", qemu_proof)
        self.assertIn('kill -0 -- "-$runner_pid"', qemu_proof)
        self.assertIn('kill -0 -- "-$group_pid"', qemu_proof)
        self.assertIn('kill -TERM -- "-$group_pid"', qemu_proof)
        self.assertIn('kill -KILL -- "-$group_pid"', qemu_proof)
        self.assertIn('wait "$QEMU_RUNNER_PID"', qemu_proof)
        self.assertIn("retained active QEMU disk for safe recovery", qemu_proof)
        self.assertIn("ARK_AGENT_SOCKET_PROBE=PASS", qemu_proof)
        self.assertIn("identity marker set is not exact", qemu_proof)
        self.assertIn("identity marker set contains duplicate key IDs", qemu_proof)
        self.assertIn("guest identity-set marker is missing or duplicated", qemu_proof)
        self.assertIn("QEMU boot produced ARK_NATIVE_BOOT_PROOF=FAIL", qemu_proof)
        stale_invalidation = '"$OUTDIR/proof.txt" "$OUTDIR/agent-identities.txt"'
        self.assertIn(stale_invalidation, qemu_proof)
        self.assertLess(
            qemu_proof.index(stale_invalidation),
            qemu_proof.index('REUSE_RAW="${ARK_QEMU_REUSE_RAW:-0}"'),
        )
        self.assertIn('QEMU_LOCK="$OUTDIR.lock"', qemu_proof)
        self.assertIn('flock -n "$QEMU_LOCK_FD"', qemu_proof)
        self.assertLess(
            qemu_proof.index('flock -n "$QEMU_LOCK_FD"'),
            qemu_proof.index(stale_invalidation),
        )
        self.assertIn("IMAGE_SHA256_BEFORE", qemu_proof)
        self.assertIn("IMAGE_SHA256_AFTER", qemu_proof)
        self.assertIn('"$IMAGE_SHA256_AFTER" != "$IMAGE_SHA256_BEFORE"', qemu_proof)
        self.assertIn("ARK_QEMU_IMAGE_SHA256", qemu_proof)
        self.assertLess(
            qemu_proof.index("compressed image changed during QEMU proof"),
            qemu_proof.index('PROOF_TMP="$(mktemp'),
        )
        self.assertIn("ARK_QEMU_EXPECTED_IMAGE_SHA256", qemu_proof)
        self.assertIn("ARK_QEMU_EXCLUSIVE_RUN_PROBE=PASS", qemu_proof)
        self.assertIn('mv -f -- "$PROOF_TMP" "$OUTDIR/proof.txt"', qemu_proof)
        self.assertLess(
            qemu_proof.index('qemu_exit=%s\\n\' "$RC" >> "$PROOF_TMP"'),
            qemu_proof.index('mv -f -- "$PROOF_TMP" "$OUTDIR/proof.txt"'),
        )
        self.assertNotIn('>> "$OUTDIR/proof.txt"', qemu_proof)
        self.assertIn("refusing to derive proof", qemu_proof)
        self.assertLess(
            qemu_proof.index("refusing to derive proof"),
            qemu_proof.index('with proof_path.open("a", encoding="utf-8")'),
        )
        self.assertIn('proof.write("ARK_NATIVE_BOOT_PROOF=PASS\\n")', qemu_proof)
        self.assertIn("ARK_QEMU_IDENTITY_EVIDENCE=PASS", qemu_proof)
        self.assertNotIn(
            "printf 'ARK_AGENT_IDENTITY_SET_PROBE=PASS",
            qemu_proof,
        )
        self.assertIn("ARK_AGENT_CROSS_ROLE_ACCESS_PROBE=PASS", qemu_proof)

    def test_image_is_pinned_to_agentic_runtime_commit(self) -> None:
        lock = (ROOT / "config" / "ark-genesis.lock").read_text(encoding="utf-8")
        self.assertIn(
            "ARK_GENESIS_COMMIT=d3fbe917f142ef8d6c3c2e8fc4ceebfbfce277f3",
            lock,
        )
        build = (ROOT / "build" / "build-image.sh").read_text(encoding="utf-8")
        self.assertIn("runtime overlay commit", build)
        self.assertIn("test -x /usr/bin/ark-agentic-model-proof", build)
        self.assertIn(
            'cp "$ARK_GENESIS_LOCK" "$OUT/evidence/ark-genesis.lock"',
            build,
        )
        self.assertIn("no_baked_agent_private_material", build)
        self.assertIn('! test -e "$private" && ! test -L "$private"', build)
        self.assertIn("--kill-child=SIGTERM", build)
        self.assertNotIn("--kill-child=SIGKILL", build)


if __name__ == "__main__":
    unittest.main()
