#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DETECTOR = ROOT / "rootfs/usr/local/sbin/ark-gpu-detect"


class GpuDetectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "bus/pci/devices").mkdir(parents=True)
        self.lspci = self.root / "lspci.txt"
        self.lspci.write_text("", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def add_gpu(self, slot, vendor, device, driver, name, boot=False):
        path = self.root / "bus/pci/devices" / slot
        path.mkdir()
        (path / "class").write_text("0x030000\n", encoding="ascii")
        (path / "vendor").write_text(f"0x{vendor}\n", encoding="ascii")
        (path / "device").write_text(f"0x{device}\n", encoding="ascii")
        (path / "boot_vga").write_text("1\n" if boot else "0\n", encoding="ascii")
        if driver:
            (path / "driver").symlink_to(f"../../../drivers/{driver}")
        with self.lspci.open("a", encoding="utf-8") as handle:
            handle.write(f"{slot} {name} [{vendor}:{device}]\n")

    def run_detector(self, *arguments):
        env = os.environ.copy()
        env["ARK_GPU_SYSFS_ROOT"] = str(self.root)
        env["ARK_GPU_LSPCI_FILE"] = str(self.lspci)
        return subprocess.run(
            [str(DETECTOR), *arguments],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_target_dual_pascal_selects_r580(self):
        self.add_gpu("0000:15:00.0", "10de", "1d01", "nouveau", "NVIDIA GP108 GeForce GT 1030", True)
        self.add_gpu("0000:21:00.0", "10de", "1c31", "nouveau", "NVIDIA GP106GL Quadro P2200")
        result = self.run_detector()
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["recommended_profile"], "nvidia-pascal")
        self.assertEqual(value["status"], "attention")
        self.assertEqual({item["architecture"] for item in value["devices"]}, {"pascal"})

    def test_pascal_is_ready_only_on_proprietary_driver(self):
        self.add_gpu("0000:21:00.0", "10de", "1c31", "nvidia", "NVIDIA GP106GL Quadro P2200", True)
        result = self.run_detector("--verify")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unknown_nvidia_refuses_automatic_choice(self):
        self.add_gpu("0000:01:00.0", "10de", "9999", "nouveau", "NVIDIA unknown", True)
        result = self.run_detector("--profile")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "manual")

    def test_non_nvidia_retains_system_default(self):
        self.add_gpu("0000:01:00.0", "1002", "9999", "amdgpu", "AMD display", True)
        result = self.run_detector("--profile")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "system-default")

    def test_installer_auto_dry_run_uses_detected_profile(self):
        self.add_gpu("0000:15:00.0", "10de", "1d01", "nouveau", "NVIDIA GP108 GeForce GT 1030", True)
        env = os.environ.copy()
        env["ARK_GPU_DETECTOR"] = str(DETECTOR)
        env["ARK_GPU_SYSFS_ROOT"] = str(self.root)
        env["ARK_GPU_LSPCI_FILE"] = str(self.lspci)
        installer = ROOT / "rootfs/usr/local/sbin/ark-gpu-install"
        result = subprocess.run(
            [str(installer), "auto", "--dry-run"],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "ARK_GPU_PROFILE=nvidia-pascal")


if __name__ == "__main__":
    unittest.main()
