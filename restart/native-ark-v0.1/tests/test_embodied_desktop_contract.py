from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


NATIVE_ROOT = Path(__file__).resolve().parents[1]
BROKER_PATH = NATIVE_ROOT / "rootfs/usr/lib/ark-desktop/ui_broker.py"
SPEC = importlib.util.spec_from_file_location("ark_ui_broker", BROKER_PATH)
assert SPEC and SPEC.loader
BROKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BROKER
SPEC.loader.exec_module(BROKER)


def routine_plan(**updates: object) -> dict[str, object]:
    plan: dict[str, object] = {
        "planId": "nav-test-1",
        "utterance": "open YouTube",
        "action": "open_url",
        "url": "https://www.youtube.com/",
        "routine": True,
        "confidence": 0.99,
        "requiresApproval": False,
        "source": "deterministic-navigation",
    }
    plan.update(updates)
    return plan


class BrokerTests(unittest.TestCase):
    def test_permit_is_one_use_and_ledger_is_hash_chained(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            ledger_path = Path(directory) / "desktop.jsonl"
            state = BROKER.BrokerState(BROKER.EvidenceLedger(ledger_path))
            authorization = state.authorize(routine_plan(), {})
            completion = state.complete(
                "nav-test-1", authorization["permit"], "YouTube opened."
            )
            self.assertTrue(completion["ok"])
            with self.assertRaises(BROKER.BrokerError):
                state.complete(
                    "nav-test-1", authorization["permit"], "replayed"
                )
            verified = BROKER.EvidenceLedger(ledger_path)
            self.assertEqual(verified.sequence, 2)
            self.assertNotEqual(verified.tip, BROKER.ZERO_HASH)
            records = [json.loads(line) for line in ledger_path.read_text().splitlines()]
            self.assertEqual([record["event"] for record in records], ["authorized", "completed"])
            self.assertNotIn("utterance", records[0])
            self.assertNotIn("message", records[1])

    def test_nonroutine_and_conversation_plans_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = BROKER.BrokerState(
                BROKER.EvidenceLedger(Path(directory) / "desktop.jsonl")
            )
            for plan in (
                routine_plan(action="conversation"),
                routine_plan(routine=False),
                routine_plan(requiresApproval=True),
                routine_plan(source="ark-runtime"),
                routine_plan(confidence=float("nan")),
            ):
                with self.assertRaises(BROKER.BrokerError):
                    state.authorize(plan, {})


class ImageContractTests(unittest.TestCase):
    def test_desktop_is_a_pinned_critical_image_component(self) -> None:
        build = (NATIVE_ROOT / "build/build-image.sh").read_text()
        packages = (NATIVE_ROOT / "config/packages.x86_64").read_text().splitlines()
        target_dropin = (
            NATIVE_ROOT
            / "rootfs/etc/systemd/system/ark.target.d/20-critical-desktop.conf"
        ).read_text()
        self.assertIn("ARKLINUX_SHELL_COMMIT", build)
        self.assertIn("ARK_SHELL_OVERLAY", build)
        self.assertIn("ark-desktop-core.target", build)
        self.assertIn("Requires=ark-desktop-core.target", target_dropin)
        self.assertIn("nodejs-lts-krypton", packages)
        self.assertIn("electron", packages)


if __name__ == "__main__":
    unittest.main()
