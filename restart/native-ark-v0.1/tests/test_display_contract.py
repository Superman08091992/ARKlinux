from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


NATIVE_ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = NATIVE_ROOT / "rootfs/usr/local/sbin/ark-display-preflight"


class DisplayContractTests(unittest.TestCase):
    def test_release_uses_lts_kernel_and_complete_desktop_runtime(self) -> None:
        packages = {
            line.strip()
            for line in (NATIVE_ROOT / "config/packages.x86_64").read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        self.assertIn("linux-lts", packages)
        self.assertIn("linux-lts-headers", packages)
        self.assertIn("pacman", packages)
        self.assertIn("archlinux-keyring", packages)
        self.assertNotIn("linux", packages)
        self.assertNotIn("linux-headers", packages)
        for package in (
            "mesa",
            "libdrm",
            "plasma-pa",
            "xdg-desktop-portal",
            "xdg-desktop-portal-kde",
            "rtkit",
        ):
            self.assertIn(package, packages)

    def test_release_uses_portable_initramfs_for_first_boot(self) -> None:
        build = (NATIVE_ROOT / "build/build-image.sh").read_text()
        self.assertIn("KERNEL_IMAGE=/vmlinuz-linux-lts", build)
        self.assertIn("INITRAMFS_IMAGE=/initramfs-linux-lts.img", build)
        self.assertIn('cp "$MNT/boot${INITRAMFS_FALLBACK}"', build)
        self.assertIn("/nouveau\\\\.ko", build)

    def test_greetd_has_pre_pam_wayland_type_and_vt_exclusion(self) -> None:
        config = (NATIVE_ROOT / "rootfs/etc/greetd/config.toml").read_text()
        pam_env = (
            NATIVE_ROOT / "rootfs/etc/greetd/greetd-pam-env.conf"
        ).read_text()
        pam_stack = (NATIVE_ROOT / "rootfs/etc/pam.d/greetd").read_text()
        unit_dropin = (
            NATIVE_ROOT
            / "rootfs/etc/systemd/system/greetd.service.d/10-arklinux-vt.conf"
        ).read_text()
        preflight_unit = (
            NATIVE_ROOT
            / "rootfs/etc/systemd/system/ark-display-preflight.service"
        ).read_text()
        session = (NATIVE_ROOT / "rootfs/usr/local/bin/ark-session").read_text()
        self.assertNotIn("service =", config)
        self.assertIn("XDG_SESSION_TYPE DEFAULT=wayland OVERRIDE=wayland", pam_env)
        self.assertIn("pam_securetty.so", pam_stack)
        self.assertIn("pam_nologin.so", pam_stack)
        self.assertLess(pam_stack.index("pam_env.so"), pam_stack.index("session    include"))
        self.assertIn("Conflicts=getty@tty1.service", unit_dropin)
        self.assertIn("Requires=ark-display-preflight.service", unit_dropin)
        self.assertIn("OnFailure=getty@tty1.service", preflight_unit)
        self.assertIn("plasma-dbus-run-session-if-needed", session)

    def test_pascal_reinstall_repairs_module_configuration_before_return(self) -> None:
        installer = (
            NATIVE_ROOT / "rootfs/usr/local/sbin/ark-gpu-install"
        ).read_text()
        already_installed = installer.index(
            "Pinned NVIDIA R580 packages are already installed."
        )
        early_return = installer.index("return 0", already_installed)
        block = installer[already_installed:early_return]
        self.assertIn("configure_proprietary_modules", block)
        self.assertIn("refresh_initramfs", block)
        self.assertIn("verify_built_modules", block)

    def test_pascal_build_uses_one_unprivileged_git_identity(self) -> None:
        installer = (
            NATIVE_ROOT / "rootfs/usr/local/sbin/ark-gpu-install"
        ).read_text()
        ownership = installer.index('chown nobody:nobody "$build_root"')
        git_init = installer.index(
            'run_pascal_builder git -C "$source_dir" init -q'
        )
        makepkg = installer.index(
            'run_pascal_builder makepkg --cleanbuild --clean --force'
        )
        self.assertLess(ownership, git_init)
        self.assertLess(git_init, makepkg)
        self.assertIn('runuser -u nobody -- env', installer)
        self.assertNotIn('git config --global', installer)
        self.assertNotIn('\n  git -C "$source_dir"', installer)

    def test_ai_profile_switch_removes_incompatible_pascal_state_transactionally(self) -> None:
        bootstrap = (
            NATIVE_ROOT / "rootfs/usr/local/bin/ark-bootstrap-ai"
        ).read_text()
        self.assertIn("remove_system_packages cuda cudnn ollama-cuda", bootstrap)
        self.assertIn(
            "remove_venv_packages vllm triton nvidia-nccl-cu12", bootstrap
        )
        self.assertIn("$AI_VENV_ROOT/.ai-build.XXXXXX", bootstrap)
        self.assertIn("Previous AI environment retained for rollback", bootstrap)

    def test_offline_repair_has_identity_rollback_and_expansion_guards(self) -> None:
        repair = (
            NATIVE_ROOT / "tools/ark-repair-installed-display"
        ).read_text()
        for contract in (
            "refusing to repair the currently running root filesystem",
            "the root and EFI partitions are not on the same physical disk",
            "sgdisk --backup=",
            "--partition-guid=",
            "actual_uuid",
            "btrfs filesystem resize max",
            "ARK_DISPLAY_REPAIR=PASS",
            "systemctl mask serial-getty@ttyS0.service",
        ):
            self.assertIn(contract, repair)
        self.assertIn("if (( EXPAND_ROOT == 1 ))", repair)
        self.assertIn("aligned_last_sector", repair)
        self.assertIn("ensure_target_pacman_configuration", repair)
        self.assertIn("target-pacnew", repair)
        self.assertIn("PACMAN_CONFIG_SOURCE=repair-host", repair)
        self.assertIn("pacman-conf --repo-list", repair)
        self.assertIn("target pacman package database is missing or empty", repair)
        self.assertIn('pacman-key --init', repair)
        self.assertIn('pacman-key --populate archlinux', repair)
        self.assertIn('pacman-key --updatedb', repair)
        self.assertIn("pacman -Sy --noconfirm archlinux-keyring", repair)
        self.assertNotIn(
            "pacman -Sy --noconfirm --needed archlinux-keyring", repair
        )
        self.assertIn("--ignore linux --ignore linux-headers", repair)

    def test_image_build_rejects_unrepairable_package_manager_state(self) -> None:
        build = (NATIVE_ROOT / "build/build-image.sh").read_text()
        self.assertIn('stage "validate package manager recovery contract"', build)
        self.assertIn("/etc/pacman.conf /etc/pacman.d/mirrorlist", build)
        self.assertIn("/usr/bin/pacman /usr/bin/pacman-conf /usr/bin/pacman-key", build)
        self.assertIn("pacman -Q pacman archlinux-keyring", build)
        self.assertIn("pacman-conf --repo-list", build)
        self.assertIn('pacman-key --init', build)
        self.assertIn('pacman-key --populate archlinux', build)
        self.assertIn('pacman-key --updatedb', build)


class DisplayPreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.detector = self.bin / "detect"
        self.lsinitcpio = self.bin / "lsinitcpio"
        self.initramfs = self.root / "initramfs.img"
        self.initramfs.write_text("fixture")
        self.lsinitcpio.write_text(
            "#!/usr/bin/env bash\n"
            "echo usr/lib/modules/6.18.49-2-lts/kernel/drivers/gpu/drm/nouveau/nouveau.ko.zst\n"
        )
        self.lsinitcpio.chmod(self.lsinitcpio.stat().st_mode | stat.S_IXUSR)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_detector(self, driver: str) -> None:
        value = {
            "recommended_profile": "nvidia-pascal",
            "status": "ready" if driver == "nvidia" else "attention",
            "devices": [
                {"vendor_id": "10de", "device_id": "1d01", "driver": driver},
                {"vendor_id": "10de", "device_id": "1c31", "driver": driver},
            ],
        }
        self.detector.write_text(
            "#!/usr/bin/env bash\n"
            + "printf '%s\\n' "
            + repr(json.dumps(value))
            + "\n"
        )
        self.detector.chmod(self.detector.stat().st_mode | stat.S_IXUSR)

    def write_system_default_detector(self, driver: str | None) -> None:
        value = {
            "recommended_profile": "system-default",
            "status": "ready" if driver else "attention",
            "devices": [
                {"vendor_id": "1002", "device_id": "9999", "driver": driver}
            ],
        }
        self.detector.write_text(
            "#!/usr/bin/env bash\n"
            + "printf '%s\\n' "
            + repr(json.dumps(value))
            + "\n"
        )
        self.detector.chmod(self.detector.stat().st_mode | stat.S_IXUSR)

    def run_preflight(self, kernel: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:{env['PATH']}",
                "ARK_GPU_DETECTOR": str(self.detector),
                "ARK_DISPLAY_READY_MARKER": str(self.root / "ready"),
                "ARK_DISPLAY_REPORT_FILE": str(self.root / "report.json"),
                "ARK_RUNNING_KERNEL": kernel,
                "ARK_INITRAMFS_IMAGE": str(self.initramfs),
            }
        )
        return subprocess.run(
            [str(PREFLIGHT)],
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def test_nouveau_pascal_allowed_on_portable_lts_boot(self) -> None:
        self.write_detector("nouveau")
        result = self.run_preflight("6.18.49-2-lts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mode=nouveau-lts-display", result.stdout)
        self.assertTrue((self.root / "ready").is_file())

    def test_nouveau_pascal_blocks_unproven_mainline_kernel(self) -> None:
        self.write_detector("nouveau")
        result = self.run_preflight("7.2.3-arch1-2")
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((self.root / "report.json").read_text())
        self.assertEqual(report["reason"], "pascal_nouveau_requires_lts_kernel")
        self.assertFalse((self.root / "ready").exists())

    def test_proprietary_pascal_binding_is_graphically_ready(self) -> None:
        self.write_detector("nvidia")
        result = self.run_preflight("6.18.49-2-lts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mode=nvidia-proprietary", result.stdout)

    def test_unknown_nvidia_profile_blocks_graphical_startup(self) -> None:
        value = {
            "recommended_profile": "manual",
            "status": "attention",
            "devices": [
                {"vendor_id": "10de", "device_id": "9999", "driver": "nouveau"}
            ],
        }
        self.detector.write_text(
            "#!/usr/bin/env bash\n"
            + "printf '%s\\n' "
            + repr(json.dumps(value))
            + "\n"
        )
        self.detector.chmod(self.detector.stat().st_mode | stat.S_IXUSR)
        result = self.run_preflight("6.18.49-2-lts")
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((self.root / "report.json").read_text())
        self.assertEqual(report["reason"], "gpu_profile_requires_manual_selection")

    def test_unbound_system_default_blocks_graphical_startup(self) -> None:
        self.write_system_default_detector(None)
        result = self.run_preflight("6.18.49-2-lts")
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((self.root / "report.json").read_text())
        self.assertEqual(report["reason"], "gpu_driver_binding_incomplete")


if __name__ == "__main__":
    unittest.main()
