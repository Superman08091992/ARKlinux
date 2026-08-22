#!/usr/bin/env python3
import grp
import json
import logging
import os
import socket
import struct
import subprocess
from pathlib import Path

SOCKET_PATH = Path("/run/ark-desktop/root.sock")
LOG_PATH = "/var/log/ark-desktop-rootd.log"
WHEEL_GID = grp.getgrnam("wheel").gr_gid

logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)


def peer_allowed(conn):
    pid, uid, gid = struct.unpack(
        "3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
    )
    if uid == 0:
        return True, pid, uid
    try:
        text = Path(f"/proc/{pid}/status").read_text()
        groups = []
        for line in text.splitlines():
            if line.startswith("Groups:"):
                groups = [int(x) for x in line.split()[1:]]
                break
        return WHEEL_GID in groups, pid, uid
    except Exception:
        return False, pid, uid


def run(argv, timeout=60):
    if not isinstance(argv, list) or not argv or not all(isinstance(x, str) for x in argv):
        raise ValueError("argv must be a non-empty string array")
    cp = subprocess.run(
        argv,
        text=True,
        capture_output=True,
        timeout=max(1, min(int(timeout), 300)),
        env={
            "PATH": "/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin",
            "LANG": "C.UTF-8",
        },
    )
    return {"returncode": cp.returncode, "stdout": cp.stdout, "stderr": cp.stderr}


def dispatch(req):
    op = req.get("op")
    if op == "exec":
        return run(req.get("argv"), req.get("timeout", 60))
    if op == "read_file":
        return {"content": Path(req["path"]).read_text(errors="replace")}
    if op == "write_file":
        path = Path(req["path"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(req.get("content", ""))
        os.chmod(path, int(str(req.get("mode", "0644")), 8))
        return {"ok": True}
    if op == "service":
        action = req["action"]
        unit = req["unit"]
        if action not in {"start", "stop", "restart", "enable", "disable", "mask", "unmask"}:
            raise ValueError("unsupported service action")
        return run(["systemctl", action, unit], 120)
    if op == "power":
        action = req["action"]
        if action == "reboot":
            return run(["systemctl", "reboot"], 10)
        if action == "poweroff":
            return run(["systemctl", "poweroff"], 10)
        raise ValueError("unsupported power action")
    if op == "ping":
        return {"ok": True, "uid": 0}
    raise ValueError("unknown operation")


def handle(conn):
    allowed, pid, uid = peer_allowed(conn)
    if not allowed:
        conn.sendall(b'{"ok":false,"error":"not authorized"}\n')
        logging.warning("denied pid=%s uid=%s", pid, uid)
        return
    data = b""
    while b"\n" not in data and len(data) < 1024 * 1024:
        chunk = conn.recv(65536)
        if not chunk:
            break
        data += chunk
    try:
        req = json.loads(data.split(b"\n", 1)[0].decode("utf-8"))
        logging.info("request pid=%s uid=%s op=%s", pid, uid, req.get("op"))
        payload = {"ok": True, "result": dispatch(req)}
    except Exception as exc:
        logging.exception("request failed pid=%s uid=%s", pid, uid)
        payload = {"ok": False, "error": str(exc)}
    conn.sendall((json.dumps(payload) + "\n").encode("utf-8"))


def main():
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
    logging.info("ARKlinux root broker listening on %s", SOCKET_PATH)
    while True:
        conn, _ = server.accept()
        with conn:
            handle(conn)


if __name__ == "__main__":
    main()
