#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/source.lock"
OUT="${ARKLINUX_KERNEL_OUT:-$ROOT/out/kernel}"
WORK="${ARKLINUX_KERNEL_WORK:-$ROOT/.work/kernel}"
JOBS="${JOBS:-$(nproc)}"
mkdir -p "$OUT" "$WORK"
cd "$WORK"
fetch_verify(){ local url="$1" file="$2" hash="$3"; [[ -f "$file" ]] || curl -fL "$url" -o "$file"; echo "$hash  $file" | sha256sum -c -; }
fetch_verify "$KERNEL_URL" "linux-${KERNEL_VERSION}.tar.xz" "$KERNEL_SHA256"
fetch_verify "$ARCH_PATCH_URL" "linux-${KERNEL_VERSION}-arch.patch.zst" "$ARCH_PATCH_SHA256"
fetch_verify "$ARCH_CONFIG_URL" "arch-${KERNEL_VERSION}.config" "$ARCH_CONFIG_SHA256"
rm -rf "linux-${KERNEL_VERSION}"
tar -xf "linux-${KERNEL_VERSION}.tar.xz"
cd "linux-${KERNEL_VERSION}"
zstd -dc "../linux-${KERNEL_VERSION}-arch.patch.zst" | patch -Np1
# Keep Arch code/config changes but not the Arch runtime name.
find . -maxdepth 1 -type f -name "localversion*" -delete
cp "../arch-${KERNEL_VERSION}.config" .config
# The Arch config is the hardware/support baseline. ARKlinux changes only what it owns.
scripts/kconfig/merge_config.sh -m .config "$HERE/arklinux.config.fragment"
make olddefconfig
make -j"$JOBS" bzImage modules
KREL="$(make -s kernelrelease)"
rm -rf "$OUT/modules"
make modules_install INSTALL_MOD_PATH="$OUT/modules"
cp arch/x86/boot/bzImage "$OUT/arklinux-kernel"
cp System.map "$OUT/System.map-arklinux"
cp .config "$OUT/config-arklinux"
printf '%s\n' "$KREL" > "$OUT/kernel-release"
(
  cd "$OUT"
  sha256sum arklinux-kernel System.map-arklinux config-arklinux kernel-release > SHA256SUMS
)
printf 'ARKlinux kernel complete: %s\n' "$KREL"
