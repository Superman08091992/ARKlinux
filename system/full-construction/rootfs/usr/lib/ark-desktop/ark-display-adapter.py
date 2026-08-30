#!/usr/bin/env python3
"""ARKlinux display adapter.

This process is the read-only boundary between low-level ARKlinux/A.R.K. state
and the graphical desktop. It normalizes state into display-safe view models.
The display never talks directly to Kyle/Aletheia/Joey/HRM/Kenny, and this
adapter cannot execute commands or mint authority.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SOCKET_PATH = Path(os.environ.get("ARK_DISPLAY_ADAPTER_SOCKET", "/run/ark-display/state.sock"))
STATUS_URL = os.environ.get("ARK_STATUS_URL", "http://127.0.0.1:8081")
MAX_REQUEST = 16 * 1024
MAX_RESPONSE = 1024 * 1024


def _http_json(path: str, timeout: float = 2.0) -> dict[str, Any]:
    req = urllib.request.Request(STATUS_URL + path, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        value = json.loads(response.read().decode("utf-8"))
    return value if isinstance(value, dict) else {}


def _systemctl_state(unit: str) -> str:
    try:
        result = subprocess.run(
            ["systemctl", "is-active", unit],
            text=True,
            capture_output=True,
            timeout=2,
            check=False,
        )
        return (result.stdout.strip() or "inactive")[:64]
    except Exception:
        return "unknown"


def _runtime_view() -> dict[str, Any]:
    try:
        status = _http_json("/status")
        health = status.get("health") or {}
        outcomes = status.get("outcomes") or {}
        outcome = outcomes.get("last_outcome") or {}
        return {
            "available": True,
            "ready": bool(health.get("ready", health.get("alive", False))),
            "outcome": {
                "classification": str(outcome.get("classification") or "none"),
                "evidence_level": str(outcome.get("evidence_level") or "none"),
                "blocker_demonstrated": bool(outcome.get("blocker_demonstrated", False)),
                "user_action_required": bool(outcome.get("user_action_required", False)),
                "user_action": str(outcome.get("user_action") or ""),
                "summary": str(outcome.get("summary") or "No terminal outcome recorded yet."),
            },
        }
    except Exception as exc:
        return {
            "available": False,
            "ready": False,
            "outcome": {
                "classification": "unknown_internal",
                "evidence_level": "observed",
                "blocker_demonstrated": True,
                "user_action_required": False,
                "user_action": "",
                "summary": f"Display adapter cannot read runtime status: {type(exc).__name__}: {exc}",
            },
        }


def _system_view() -> dict[str, Any]:
    units = (
        "ark.target",
        "arkd.service",
        "ark-agent@kyle.service",
        "ark-agent@aletheia.service",
        "ark-agent@joey.service",
        "ark-agent@hrm.service",
        "ark-agent@kenny.service",
        "ark-local-api.service",
        "ark-trading.service",
        "ark-hardwared.service",
        "NetworkManager.service",
        "nftables.service",
    )
    return {"services": {unit: _systemctl_state(unit) for unit in units}}


def snapshot() -> dict[str, Any]:
    return {
        "ok": True,
        "adapter": "ark-display-adapter",
        "read_only": True,
        "authority": "none",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "runtime": _runtime_view(),
        "system": _system_view(),
    }


def handle(request: dict[str, Any]) -> dict[str, Any]:
    op = str(request.get("op") or "snapshot")
    if op == "snapshot":
        return snapshot()
    if op == "ping":
        return {"ok": True, "adapter": "ark-display-adapter", "read_only": True}
    return {"ok": False, "error": "unsupported_operation", "detail": op}


def serve() -> None:
    SOCKET_PATH.parent.mkdir(parents=True, exist_ok=True)
    SOCKET_PATH.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(SOCKET_PATH))
    os.chmod(SOCKET_PATH, 0o666)
    server.listen(16)
    try:
        while True:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(5.0)
                data = b""
                try:
                    while b"\n" not in data and len(data) <= MAX_REQUEST:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    if len(data) > MAX_REQUEST:
                        raise ValueError("request_too_large")
                    request = json.loads((data.split(b"\n", 1)[0] or b"{}").decode("utf-8"))
                    if not isinstance(request, dict):
                        raise ValueError("request_must_be_object")
                    response = handle(request)
                except Exception as exc:
                    response = {"ok": False, "error": type(exc).__name__, "detail": str(exc)}
                encoded = json.dumps(response, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"
                conn.sendall(encoded[:MAX_RESPONSE])
    finally:
        server.close()
        SOCKET_PATH.unlink(missing_ok=True)


if __name__ == "__main__":
    serve()
