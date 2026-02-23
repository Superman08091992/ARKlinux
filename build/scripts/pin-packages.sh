#!/usr/bin/env bash
# build/scripts/pin-packages.sh — regenerate packages.lock against an Arch snapshot
# Usage: ./build/scripts/pin-packages.sh [YYYY/MM/DD]
# Example: ./build/scripts/pin-packages.sh 2026/02/01
#
# Requires: Docker (to spin up a clean archlinux container)

set -euo pipefail

SNAPSHOT="${1:-2026/02/01}"
LOCK_FILE="$(dirname "$0")/../../build/lock/packages.lock"
PACKAGES_FILE="$(dirname "$0")/../../archiso/packages.x86_64"

echo "[pin-packages] Resolving package versions for Arch snapshot: $SNAPSHOT"
echo "[pin-packages] Package list: $PACKAGES_FILE"

# Strip comments and blank lines from package list
PKGS=$(grep -v '^\s*#' "$PACKAGES_FILE" | grep -v '^\s*$' | tr '\n' ' ')

# Run in a clean archlinux container
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
