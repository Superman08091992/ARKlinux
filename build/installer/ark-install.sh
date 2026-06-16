#!/usr/bin/env bash
# Repository-side entry point for the canonical ARKlinux installer.
# The authoritative installer is shipped in the archiso profile.

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CANONICAL_INSTALLER="${REPOSITORY_ROOT}/archiso/airootfs/usr/local/bin/ark-install"

if [[ ! -x "$CANONICAL_INSTALLER" ]]; then
  printf 'ARKlinux installer is missing or not executable: %s\n' "$CANONICAL_INSTALLER" >&2
  exit 1
fi

exec "$CANONICAL_INSTALLER" "$@"
