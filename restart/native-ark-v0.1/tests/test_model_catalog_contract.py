#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "rootfs/usr/share/ark/model-catalog.json"
PULL_SCRIPT = ROOT / "rootfs/usr/local/sbin/ark-model-pull"
STORE_DROPIN = ROOT / "rootfs/etc/systemd/system/ollama.service.d/10-ark-model-store.conf"
RELEASE_MODELS_LOCK = ROOT / "config/release-models.lock"
BUILD_SCRIPT = ROOT / "build/build-image.sh"


class ModelCatalogContractTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))

    def test_current_hardware_bundle_is_available_but_paused(self):
        expected = {
            "qwen3.5:4b-q4_K_M",
            "qwen3:4b",
            "gemma3:4b",
            "qwen3.5:2b-q4_K_M",
            "deepseek-r1:1.5b",
        }
        models = {item["name"]: item for item in self.catalog["models"]}
        self.assertEqual(set(models), expected)
        for model in models.values():
            self.assertEqual(model["bundle"], "current-hardware")
            self.assertTrue(model["pull_by_default"])
            self.assertEqual(model["route_state"], "available")
            self.assertEqual(model["runtime_state"], "paused")
            self.assertEqual(model["activation"], "on_demand")
            self.assertFalse(model["preload"])
            self.assertEqual(model["keep_alive"], 0)

    def test_every_route_references_a_cataloged_model(self):
        names = {item["name"] for item in self.catalog["models"]}
        for role, route in self.catalog["routes"].items():
            self.assertIn(route["primary"], names, role)
            self.assertLessEqual(set(route["alternatives"]), names, role)
        self.assertEqual(self.catalog["routes"]["kyle"]["primary"], "qwen3.5:2b-q4_K_M")
        self.assertEqual(self.catalog["routes"]["aletheia"]["primary"], "qwen3.5:4b-q4_K_M")
        self.assertEqual(self.catalog["routes"]["joey"]["primary"], "qwen3:4b")

    def test_ollama_uses_dedicated_ark_model_store(self):
        self.assertEqual(self.catalog["storage_path"], "/ark/models/ollama")
        dropin = STORE_DROPIN.read_text(encoding="utf-8")
        self.assertIn("OLLAMA_MODELS=/ark/models/ollama", dropin)
        self.assertIn("OLLAMA_KEEP_ALIVE=0", dropin)
        build = (ROOT / "build/build-image.sh").read_text(encoding="utf-8")
        self.assertIn("usermod -a -G ark-state ollama", build)
        self.assertIn("-o ollama -g ollama /ark/models/ollama", build)

    def test_locked_release_models_are_seeded_into_image(self):
        expected_models = {
            "qwen3.5:2b-q4_K_M",
            "deepseek-r1:1.5b",
            "llava:latest",
            "tinyllama:latest",
        }

        records = {}
        for raw in RELEASE_MODELS_LOCK.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            model, digest = line.split("\t", 1)
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertNotIn(model, records)
            records[model] = digest

        self.assertEqual(set(records), expected_models)

        # Kyle's primary model must be physically present in the release set.
        self.assertIn(
            self.catalog["routes"]["kyle"]["primary"],
            records,
        )

        build = BUILD_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("seed_release_models(){", build)
        self.assertIn('done < "$lock_file"', build)
        self.assertIn("ARK_RELEASE_MODEL_SEEDED=PASS", build)
        self.assertIn("release_models_installed", build)

        # Every referenced blob is content-address verified before inclusion.
        self.assertIn(
            '[[ "$blob_sha" == "${digest#sha256:}" ]]',
            build,
        )

        # Guest ownership must use guest account resolution, not host numeric IDs.
        self.assertIn(
            'arch-chroot "$MNT" chown -R ollama:ollama /ark/models/ollama',
            build,
        )


    def test_pull_is_explicit_and_not_a_boot_download(self):
        script = PULL_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('ollama pull "$model"', script)
        self.assertIn('ollama stop "$model"', script)
        self.assertIn("model-inventory.json", script)
        build = (ROOT / "build/build-image.sh").read_text(encoding="utf-8")
        enable_line = next(
            line for line in build.splitlines()
            if "enable NetworkManager.service" in line
        )
        self.assertNotIn("ark-model-pull", enable_line)
        result = subprocess.run(["bash", "-n", str(PULL_SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
