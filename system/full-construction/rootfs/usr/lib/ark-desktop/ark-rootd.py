#!/usr/bin/env python3
"""Narrow privileged broker for the ARKlinux desktop.

This service is intentionally *not* a root shell. The graphical session may
request only explicit, validated operations. The temporary ``exec`` operation
exists only as a compatibility shim for three existing GTK settings calls and
maps them to the same named operations; arbitrary argv execution is rejected.
"""
from __future__ import annotations

import grp
import json
import logging
import os
import re
import socket
import struct
import subprocess
from pathlib import Path
from typing import Any

SOCKET_PATH = Path("/run/ark-desktop/root.sock")
LOG_DIR = Path("/var/log/ark-desktop")
LOG_PATH = LOG_DIR / "rootd.log"
WHEEL_GID = grp.getgrnam("wheel").gr_gid
MAX_REQUEST = 64 * 1024

ARK_UNITS = {
    "ark.target",
    "ark-runtime-api.service",
    "ark-local-api.service",
    "ark-trading.service",
    "ark-hardwared.service",
}
SYSTEM_UNITS = {"NetworkManager.service", "nftables.service", "sshd.service"}
ALLOWED_UNITS = ARK_UNITS | SYSTEM_UNITS
SERVICE_ACTIONS = {"start", "stop", "restart"}
STATIC_RUNTIME_FILES = {
    "/run/arklinux/hardware.json",
}
HOSTNAME_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,61}[A-Za-z0-9])?$")

LOG_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(filename=str(LOG_PATH), level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def peer_allowed(conn: socket.socket) -> tuple[bool, int, int]:
    pid, uid, _gid = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid == 0:
        return True, pid, uid
    try:
        groups: list[int] = []
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("Groups:"):
                groups = [int(value) for value in line.split()[1:]]
                break
        return WHEEL_GID in groups, pid, uid
    except (OSError, ValueError):
        return False, pid, uid


def run(argv: list[str], timeout: int = 30) -> dict[str, Any]:
    cp = subprocess.run(
        argv,
        text=True,
        capture_output=True,
        timeout=max(1, min(int(timeout), 120)),
        env={"PATH": "/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin", "LANG": "C.UTF-8"},
        check=False,
    )
    return {"returncode": cp.returncode, "stdout": cp.stdout[-256_000:], "stderr": cp.stderr[-64_000:]}


def require_unit(req: dict[str, Any]) -> str:
    unit = str(req.get("unit") or "")
    if unit not in ALLOWED_UNITS:
        raise ValueError("unit is not exposed by the desktop broker")
    return unit


def validate_hostname(value: Any) -> str:
    hostname = str(value or "").strip()
    if not HOSTNAME_RE.fullmatch(hostname) or ".." in hostname:
        raise ValueError("invalid hostname")
    return hostname


def runtime_read(path_text: str) -> dict[str, str]:
    path = str(path_text or "")
    if path not in STATIC_RUNTIME_FILES:
        raise ValueError("runtime path is not exposed by the desktop broker")
    target = Path(path)
    if target.is_symlink():
        raise ValueError("runtime broker will not follow symbolic links")
    return {"content": target.read_text(encoding="utf-8", errors="replace")}


def named_exec_compat(argv: Any) -> dict[str, Any]:
    """Compatibility for pre-protocol-v2 GTK calls; never a general exec."""
    if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
        raise ValueError("compat argv must be a string array")
    if argv == ["udevadm", "trigger", "--action=change"]:
        return run(["/usr/bin/udevadm", "trigger", "--action=change"], 30)
    if len(argv) == 3 and argv[:2] == ["hostnamectl", "set-hostname"]:
        return run(["/usr/bin/hostnamectl", "set-hostname", validate_hostname(argv[2])], 15)
    if len(argv) == 4 and argv[:3] == ["nmcli", "radio", "wifi"] and argv[3] in {"on", "off"}:
        return run(["/usr/bin/nmcli", "radio", "wifi", argv[3]], 15)
    raise ValueError("arbitrary argv execution is not exposed by the desktop broker")


def dispatch(req: dict[str, Any]) -> dict[str, Any]:
    op = str(req.get("op") or "")
    if op == "ping":
        return {"ok": True, "uid": 0, "protocol": 2}
    if op == "runtime_read":
        return runtime_read(str(req.get("path") or ""))
    if op == "unit_state":
        unit = require_unit(req)
        return run(["/usr/bin/systemctl", "show", unit, "--property=ActiveState", "--property=SubState", "--property=MainPID", "--no-pager"], 8)
    if op == "journal":
        unit = require_unit(req)
        count = max(1, min(int(req.get("count", 30)), 500))
        return run(["/usr/bin/journalctl", "-u", unit, "-n", str(count), "--no-pager", "--output=short-iso"], 20)
    if op == "service":
        unit = require_unit(req)
        action = str(req.get("action") or "")
        if action not in SERVICE_ACTIONS:
            raise ValueError("unsupported service action")
        return run(["/usr/bin/systemctl", action, unit], 120)
    if op == "set_hostname":
        return run(["/usr/bin/hostnamectl", "set-hostname", validate_hostname(req.get("hostname"))], 15)
    if op == "wifi_radio":
        enabled = req.get("enabled")
        if not isinstance(enabled, bool):
            raise ValueError("enabled must be boolean")
        return run(["/usr/bin/nmcli", "radio", "wifi", "on" if enabled else "off"], 15)
    if op == "hardware_rescan":
        return run(["/usr/bin/udevadm", "trigger", "--action=change"], 30)
    if op == "exec":
        return named_exec_compat(req.get("argv"))
    if op == "power":
        action = str(req.get("action") or "")
        if action not in {"reboot", "poweroff"}:
            raise ValueError("unsupported power action")
        return run(["/usr/bin/systemctl", action], 10)
    raise ValueError("unknown privileged desktop operation")


def handle(conn: socket.socket) -> None:
    allowed, pid, uid = peer_allowed(conn)
    if not allowed:
        conn.sendall(b'{"ok":false,"error":"not authorized"}\n')
        logging.warning("denied pid=%s uid=%s", pid, uid)
        return
    data = b""
    while b"\n" not in data and len(data) <= MAX_REQUEST:
        chunk = conn.recv(8192)
        if not chunk:
            break
        data += chunk
    if len(data) > MAX_REQUEST:
        conn.sendall(b'{"ok":false,"error":"request too large"}\n')
        logging.warning("oversize request pid=%s uid=%s", pid, uid)
        return
    try:
        req = json.loads(data.split(b"\n", 1)[0].decode("utf-8"))
        if not isinstance(req, dict):
            raise ValueError("request must be a JSON object")
        logging.info("request pid=%s uid=%s op=%s", pid, uid, req.get("op"))
        payload = {"ok": True, "result": dispatch(req)}
    except Exception as exc:
        logging.warning("request failed pid=%s uid=%s error=%s", pid, uid, exc)
        payload = {"ok": False, "error": str(exc)}
    conn.sendall((json.dumps(payload, sort_keys=True) + "\n").encode("utf-8"))


def main() -> None:
    SOCKET_PATH.parent.mkdir(parents=True, exist_ok=True)
    os.chown(SOCKET_PATH.parent, 0, WHEEL_GID)
    os.chmod(SOCKET_PATH.parent, 0o770)
    try:
        SOCKET_PATH.unlink()
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(SOCKET_PATH))
    os.chown(SOCKET_PATH, 0, WHEEL_GID)
    os.chmod(SOCKET_PATH, 0o660)
    server.listen(16)
    logging.info("ARKlinux constrained desktop broker listening on %s", SOCKET_PATH)
    while True:
        conn, _ = server.accept()
        with conn:
            handle(conn)


if __name__ == "__main__":
    main()
