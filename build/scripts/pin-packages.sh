#!/usr/bin/env bash
# build/scripts/pin-packages.sh — regenerate packages.lock against an Arch snapshot
# Usage: ./build/scripts/pin-packages.sh [YYYY/MM/DD]
# Example: ./build/scripts/pin-packages.sh 2026/02/01

set -euo pipefail

SNAPSHOT="${1:-2026/02/01}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${SCRIPT_DIR}/../../build/lock/packages.lock"
PACKAGES_FILE="${SCRIPT_DIR}/../../archiso/packages.x86_64"

echo "[pin-packages] Resolving package versions for Arch snapshot: ${SNAPSHOT}"
echo "[pin-packages] Package list: ${PACKAGES_FILE}"

mapfile -t PACKAGES < <(grep -Ev '^\s*(#|$)' "${PACKAGES_FILE}")

if command -v pacman >/dev/null 2>&1; then
  echo "[pin-packages] pacman detected; resolving directly"
  pacman -Sy --noconfirm >/dev/null
  pacman -Si "${PACKAGES[@]}" | awk '/^Name\s*:|^Version\s*:/{print $3}' \
    | paste - - \
    | sort > "${LOCK_FILE}"
elif command -v docker >/dev/null 2>&1; then
  echo "[pin-packages] docker detected; resolving in Arch container"
  docker run --rm \
    -v "${PACKAGES_FILE}:/work/packages.x86_64:ro" \
    -v "${SCRIPT_DIR}/../../:/out" \
    -e ARCH_SNAPSHOT="${SNAPSHOT}" \
    archlinux:base-devel \
    bash -lc '
      set -euo pipefail
      cat > /etc/pacman.d/mirrorlist << EOF
Server = https://archive.archlinux.org/repos/${ARCH_SNAPSHOT}/$repo/os/$arch
EOF
      mapfile -t PKGS < <(grep -Ev "^\s*(#|$)" /work/packages.x86_64)
      pacman -Sy --noconfirm >/dev/null
      pacman -Si "${PKGS[@]}" | awk "/^Name\s*:|^Version\s*:/{print \$3}" | paste - - | sort > /out/build/lock/packages.lock
    '
else
  echo "[pin-packages] ERROR: neither pacman nor docker is available" >&2
  exit 127
fi

echo "[pin-packages] Lock file written: ${LOCK_FILE}"
echo "[pin-packages] $(wc -l < "${LOCK_FILE}") packages pinned"
head -20 "${LOCK_FILE}"
