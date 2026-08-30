from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_native_desktop_files_exist():
    required = [
        ROOT / "rootfs/usr/lib/ark-desktop/ark-desktop.py",
        ROOT / "rootfs/usr/lib/ark-desktop/ark-shell.py",
        ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py",
        ROOT / "rootfs/usr/lib/ark-desktop/ark-agentctl.py",
        ROOT / "rootfs/usr/local/bin/ark-desktop-start",
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
    packages = {
        line.strip()
        for line in (ROOT / "config/packages.x86_64").read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    for package in {"gtk4", "gtk4-layer-shell", "python-gobject", "thunar", "firefox"}:
        assert package in packages
    assert "waybar" not in packages
    assert "wofi" not in packages


def test_labwc_starts_ark_desktop_only():
    autostart = (ROOT / "rootfs/etc/skel/.config/labwc/autostart").read_text()
    assert "ark-desktop-start" in autostart
    assert "waybar" not in autostart
    assert "foot &" not in autostart


def test_layer_shell_is_preloaded_before_gtk_imports():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-shell.py").read_text()
    assert 'CDLL("libgtk4-layer-shell.so")' in source
    assert source.index('CDLL("libgtk4-layer-shell.so")') < source.index("SPEC =")


def test_existing_operator_session_is_updated_by_patcher():
    source = (ROOT / "scripts/patch-desktop-image.sh").read_text()
    assert "/home/operator/.config/labwc/autostart" in source
    assert "pre-ark-desktop" in source


def test_root_broker_is_local_and_peer_authenticated():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py").read_text()
    assert "socket.AF_UNIX" in source
    assert "/run/ark-desktop/root.sock" in source
    assert "SO_PEERCRED" in source
    assert "WHEEL_GID" in source


def test_root_broker_has_no_general_root_shell_or_file_api():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py").read_text()
    assert 'return run(req.get("argv")' not in source
    assert 'if op == "read_file"' not in source
    assert 'if op == "write_file"' not in source
    assert "arbitrary argv execution is not exposed" in source
    assert "named_exec_compat" in source
    for operation in (
        'op == "runtime_read"',
        'op == "unit_state"',
        'op == "journal"',
        'op == "service"',
        'op == "set_hostname"',
        'op == "wifi_radio"',
        'op == "hardware_rescan"',
        'op == "power"',
    ):
        assert operation in source


def test_root_broker_separates_host_telemetry_from_ark_runtime_state():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-rootd.py").read_text()
    assert '"/run/arklinux/hardware.json"' in source
    assert '"/run/ark/hardware.json"' not in source
    assert "PROCESS_FILE_RE" not in source


def test_root_broker_service_is_hardened():
    service = (ROOT / "rootfs/etc/systemd/system/ark-desktop-rootd.service").read_text()
    assert "User=root" in service
    assert "NoNewPrivileges=yes" in service
    assert "ProtectSystem=strict" in service
    assert "ProtectHome=read-only" in service
    assert "RestrictAddressFamilies=AF_UNIX AF_NETLINK" in service
    assert "ReadWritePaths=/run/ark-desktop /var/log/ark-desktop" in service


def test_native_panel_surfaces_outcome_provenance_without_guessing():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-desktop.py").read_text()
    for term in (
        "RUNTIME_URL",
        'runtime_get("/status"',
        "classification",
        "evidence_level",
        "blocker_demonstrated",
        "user_action_required",
        "premature_stop",
        "reasoning_failure",
        "unknown_internal",
        "Cause not inferred",
    ):
        assert term in source
    assert "ark-runtime-api.service" in source
    assert "ark-trading.service" in source


def test_operator_console_surfaces_terminal_outcome_provenance():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-agentctl.py").read_text()
    for term in (
        "Last terminal outcome",
        "blocker_demonstrated",
        "evidence_level",
        "premature_stop",
        "unknown_internal",
        "provider_reported",
        "USER ACTION",
    ):
        assert term in source
    assert "/run/arklinux/hardware.json" in source
    assert "/run/ark/hardware.json" not in source


def test_agent_console_uses_named_broker_operations():
    source = (ROOT / "rootfs/usr/lib/ark-desktop/ark-agentctl.py").read_text()
    assert '"op": "unit_state"' in source
    assert '"op": "journal"' in source
    assert '"op": "runtime_read"' in source
    assert '"op": "exec"' not in source
    assert '"op": "read_file"' not in source


def test_desktop_python_parses():
    for rel in (
        "rootfs/usr/lib/ark-desktop/ark-desktop.py",
        "rootfs/usr/lib/ark-desktop/ark-shell.py",
        "rootfs/usr/lib/ark-desktop/ark-rootd.py",
        "rootfs/usr/lib/ark-desktop/ark-agentctl.py",
    ):
        path = ROOT / rel
        compile(path.read_text(), path.name, "exec")
