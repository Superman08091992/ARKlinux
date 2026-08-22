#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python "$ROOT/tests/test_topology.py"
for f in "$ROOT"/build/*.sh "$ROOT"/kernel/*.sh "$ROOT"/scripts/*.sh; do bash -n "$f"; done
python -m py_compile "$ROOT/rootfs/usr/lib/ark/ark_native.py"
echo 'ARKlinux construction static verification: PASS'
