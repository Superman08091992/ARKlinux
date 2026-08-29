#!/usr/bin/env python3
"""ARKlinux-owned hardware observation process.

Canonical A.R.K. agent roles are supplied by the private ark-runtime package.
This module deliberately does not emulate Kyle, Aletheia, Joey, HRM, Kenny,
an A.R.K. event bus, or a coordinator with heartbeat placeholders.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import signal
import time
from pathlib import Path

RUN = Path("/run/arklinux")
PROCESSES = RUN / "processes"
STOP = False


def stop(*_args) -> None:
    global STOP
    STOP = True


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def snapshot() -> dict:
    return {
        "net": sorted(Path(p).name for p in glob.glob("/sys/class/net/*")),
        "drm": sorted(Path(p).name for p in glob.glob("/sys/class/drm/*")),
        "sound": sorted(Path(p).name for p in glob.glob("/sys/class/sound/*")),
        "block": sorted(Path(p).name for p in glob.glob("/sys/class/block/*")),
        "gpio": sorted(Path(p).name for p in glob.glob("/dev/gpiochip*")),
        "i2c": sorted(Path(p).name for p in glob.glob("/dev/i2c-*")),
    }


def hardwared() -> None:
    while not STOP:
        now = time.monotonic_ns()
        inventory = snapshot()
        atomic_json(RUN / "hardware.json", {"observed_monotonic_ns": now, "inventory": inventory})
        atomic_json(
            PROCESSES / "hardwared.json",
            {
                "role": "arklinux-hardware-observer",
                "pid": os.getpid(),
                "uid": os.getuid(),
                "gid": os.getgid(),
                "monotonic_ns": now,
                "state": "ready",
                "inventory": "/run/arklinux/hardware.json",
            },
        )
        time.sleep(5)
    try:
        (PROCESSES / "hardwared.json").unlink()
    except FileNotFoundError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", choices=("hardwared",), default="hardwared")
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    RUN.mkdir(parents=True, exist_ok=True)
    PROCESSES.mkdir(parents=True, exist_ok=True)
    if args.role == "hardwared":
        hardwared()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
