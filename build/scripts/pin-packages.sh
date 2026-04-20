#!/usr/bin/env bash
# build/scripts/pin-packages.sh — regenerate packages.lock against an Arch snapshot
# Usage: ./build/scripts/pin-packages.sh [YYYY/MM/DD]
# Example: ./build/scripts/pin-packages.sh 2026/02/01
#
# Resolution order: pacman (preferred) -> docker (fallback) -> fail

set -euo pipefail

SNAPSHOT="${1:-2026/02/01}"
LOCK_FILE="$(dirname "$0")/../../build/lock/packages.lock"
PACKAGES_FILE="$(dirname "$0")/../../archiso/packages.x86_64"

echo "[pin-packages] Resolving package versions for Arch snapshot: $SNAPSHOT"
echo "[pin-packages] Package list: $PACKAGES_FILE"

# Strip comments and blank lines from package list
PKGS=$(grep -v '^\s*#' "$PACKAGES_FILE" | grep -v '^\s*$' | tr '\n' ' ')

# Method 1: Use pacman directly (preferred when already in Arch environment)
if command -v pacman >/dev/null 2>&1; then
  echo "[pin-packages] pacman detected; resolving directly"

  # Point pacman at snapshot mirror
  cat > /etc/pacman.d/mirrorlist << EOF
Server = https://archive.archlinux.org/repos/${SNAPSHOT}/\$repo/os/\$arch
EOF

  pacman -Sy --noconfirm 2>/dev/null
  pacman -S --print-format '%n %v' --noconfirm $PKGS 2>/dev/null | sort > "$LOCK_FILE"

  echo "[pin-packages] Lock file written: $LOCK_FILE"
  echo "[pin-packages] $(wc -l < "$LOCK_FILE") packages pinned"
  head -20 "$LOCK_FILE"
  exit 0
fi

# Method 2: Use Docker (fallback for non-Arch environments)
if command -v docker >/dev/null 2>&1; then
  echo "[pin-packages] docker detected; resolving in Arch container"

  docker run --rm \
    -e ARCH_SNAPSHOT="$SNAPSHOT" \
    archlinux:base \
    bash -c "
      # Configure snapshot mirror
      cat > /etc/pacman.conf << CONF
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
SigLevel = Required DatabaseOptional

[core]
Server = https://archive.archlinux.org/repos/${SNAPSHOT}/\\\$repo/os/\\\$arch

[extra]
Server = https://archive.archlinux.org/repos/${SNAPSHOT}/\\\$repo/os/\\\$arch
CONF
      pacman-key --init 2>/dev/null
      pacman-key --populate archlinux 2>/dev/null
      pacman -Sy --noconfirm 2>/dev/null
      pacman -S --print-format '%n %v' --noconfirm $PKGS 2>/dev/null | sort
    " > "$LOCK_FILE"

  echo "[pin-packages] Lock file written: $LOCK_FILE"
  echo "[pin-packages] $(wc -l < "$LOCK_FILE") packages pinned"
  head -20 "$LOCK_FILE"
  exit 0
fi

# Method 3: No suitable resolver found
echo "[pin-packages] ERROR: neither pacman nor docker is available" >&2
exit 127
