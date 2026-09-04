#!/usr/bin/env python3
import re
from pathlib import Path

R = Path(__file__).resolve().parents[1]


def rows(name, fields):
    out = []
    for line in (R / name).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        assert len(parts) == fields, (name, line, len(parts))
        out.append(parts)
    return out


subvolumes = rows("config/subvolumes.tsv", 7)
processes = rows("config/processes.tsv", 6)
subs = [row[0] for row in subvolumes]
mountpoints = [row[1] for row in subvolumes]

assert len(subs) == len(set(subs)), "duplicate subvolume"
assert len(mountpoints) == len(set(mountpoints)), "duplicate mountpoint"

required_os = {"@ark", "@home", "@root", "@var", "@log", "@pkg", "@swap", "@snapshots"}
assert required_os <= set(subs)

required_ark_state = {
    "@ark-bus",
    "@ark-evidence",
    "@ark-memory",
    "@ark-state",
    "@ark-checkpoints",
    "@ark-quarantine",
    "@ark-models",
    "@ark-storage",
    "@ark-artifacts",
    "@ark-datasets",
    "@ark-varlib",
    "@ark-backups",
}
assert required_ark_state <= set(subs)

for path in mountpoints:
    assert not path.startswith("/opt/ARK"), f"case-drift mount remains: {path}"
    assert not path.startswith("/opt/ark"), f"obsolete root mount remains: {path}"

# Package-owned code must never be hidden behind state subvolumes.
for forbidden in ("/ark/runtime", "/ark/graveyard", "/ark/ui", "/ark/docs"):
    assert forbidden not in mountpoints, f"package-owned code hidden by mount: {forbidden}"

for required in (
    "/ark/bus",
    "/ark/evidence",
    "/ark/memory",
    "/ark/state",
    "/ark/checkpoints",
    "/ark/quarantine",
    "/var/lib/ark",
):
    assert required in mountpoints

roles = {row[1] for row in processes}
assert roles == {"ark-runtime", "status-api", "trading", "hardwared"}

process_text = (R / "config/processes.tsv").read_text(encoding="utf-8")
for fake_service in ("ark-kyle.service", "ark-joey.service", "ark-hrm.service", "ark-kenny.service"):
    assert fake_service not in process_text

lock = (R / "config/ark-genesis.lock").read_text(encoding="utf-8")
assert "ARK_GENESIS_REPOSITORY=Superman08091992/ARK_GENESIS" in lock
match = re.search(r"^ARK_GENESIS_COMMIT=([0-9a-f]{40})$", lock, re.MULTILINE)
assert match, "ARK_GENESIS_COMMIT must pin one exact 40-hex commit"
assert match.group(1) != "0" * 40
assert 'ARK_GENESIS_PACKAGES="ark-runtime ark-services ark-ui"' in lock
assert "ARK_RUNTIME_ROOT=/ark" in lock

print(f"{len(subvolumes)} subvolumes; {len(processes)} truthful process definitions; A.R.K. pinned to {match.group(1)}: PASS")
