from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_agent_subvolumes_are_role_owned_and_separate():
    text = (ROOT / "config" / "subvolumes.tsv").read_text(encoding="utf-8")
    for role in ("kyle", "aletheia", "joey", "hrm", "kenny"):
        assert f"@agent-{role}\t/ark/agents/{role}" in text
        assert f"\tark-{role}\tark-agent-audit\t0750\tagent-state" in text


def test_build_creates_setgid_audit_ledgers():
    build = (ROOT / "build" / "build-image.sh").read_text(encoding="utf-8")
    assert '"/ark/agents/$role/ledger"' in build
    assert "getent group ark-agent-audit" in build
    assert "python-cryptography" in (ROOT / "config" / "packages.x86_64").read_text(encoding="utf-8")


def test_boot_proof_requires_keys_and_ledger_permissions():
    proof = (ROOT / "rootfs" / "usr" / "local" / "sbin" / "ark-boot-proof").read_text(
        encoding="utf-8"
    )
    assert "missing_agent_private_key" in proof
    assert "invalid_agent_ledger" in proof
    assert "ark-agent-audit:2750" in proof
    assert '"/ark/agent-public-keys/$role/signing-key.json"' in proof
    assert "ark-batch-executor.socket" in proof
    assert "invalid_batch_claim_store" in proof


def test_image_is_pinned_to_agentic_runtime_commit():
    lock = (ROOT / "config" / "ark-genesis.lock").read_text(encoding="utf-8")
    assert "ARK_GENESIS_COMMIT=880757d5b937d27bfdae4bd5141000f5bff53f1f" in lock
    build = (ROOT / "build" / "build-image.sh").read_text(encoding="utf-8")
    assert "runtime overlay commit" in build
    assert "test -x /usr/bin/ark-agentic-model-proof" in build
    assert 'cp "$ARK_GENESIS_LOCK" "$OUT/evidence/ark-genesis.lock"' in build
