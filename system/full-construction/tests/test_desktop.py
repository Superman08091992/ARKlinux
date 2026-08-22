from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_native_desktop_files_exist():
    required = [
        ROOT / "rootfs/usr/lib/ark-desktop/ark-desktop.py",
        ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py",
        ROOT / "rootfs/etc/systemd/system/ark-desktop-rootd.service",
        ROOT / "rootfs/etc/systemd/system/greetd.service.d/ark-desktop.conf",
        ROOT / "rootfs/usr/share/ark-desktop/icons/ark.svg",
        ROOT / "rootfs/usr/share/ark-desktop/icons/computer.svg",
        ROOT / "rootfs/usr/share/ark-desktop/icons/files.svg",
        ROOT / "rootfs/usr/share/ark-desktop/icons/browser.svg",
        ROOT / "rootfs/usr/share/ark-desktop/icons/terminal.svg",
        ROOT / "rootfs/usr/share/ark-desktop/icons/settings.svg",
    ]
    for path in required:
        assert path.is_file(), path


def test_desktop_packages_are_declared():
    packages = set(
        line.strip()
        for line in (ROOT / "config/packages.x86_64").read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    for package in {
        "gtk4",
        "gtk4-layer-shell",
        "python-gobject",
        "thunar",
        "firefox",
    }:
        assert package in packages
    assert "waybar" not in packages
    assert "wofi" not in packages


def test_labwc_starts_ark_desktop_only():
    autostart = (ROOT / "rootfs/etc/skel/.config/labwc/autostart").read_text()
    assert "/usr/lib/ark-desktop/ark-desktop.py" in autostart
    assert "waybar" not in autostart
    assert "foot &" not in autostart


def test_root_broker_is_local_unix_socket():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py").read_text()
    assert 'socket.AF_UNIX' in source
    assert '/run/ark-desktop/root.sock' in source
    assert 'SO_PEERCRED' in source
    assert 'WHEEL_GID' in source


def test_desktop_python_parses():
    compile(
        (ROOT / "rootfs/usr/lib/ark-desktop/ark-desktop.py").read_text(),
        "ark-desktop.py",
        "exec",
    )
    compile(
        (ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py").read_text(),
        "ark-rootd.py",
        "exec",
    )
