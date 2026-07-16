#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${root}/archiso"

required=(
  profiledef.sh
  pacman.conf
  packages.x86_64
  airootfs/etc/os-release
  airootfs/etc/mkinitcpio.conf
  airootfs/etc/nftables.conf
  airootfs/usr/local/bin/ark-install
  syslinux/syslinux.cfg
)

for path in "${required[@]}"; do
  [[ -s "${profile}/${path}" ]] || {
    echo "missing required profile file: ${profile}/${path}" >&2
    exit 1
  }
done

grep -Fq 'archive.archlinux.org/repos/2026/02/01/' "${profile}/pacman.conf"
grep -Fq 'archisolabel=ARKLINUX_1_0' "${profile}/syslinux/syslinux.cfg"
grep -Fq 'console=ttyS0,115200n8' "${profile}/syslinux/syslinux.cfg"

# The default workflow must not invoke the destructive installer.
if grep -R --line-number --fixed-strings 'ark-install /dev/' \
  "${root}/.github/workflows" "${root}/scripts/build-iso.sh" \
  "${root}/scripts/test-qemu-live-boot.sh" 2>/dev/null; then
  echo 'unsafe installer invocation found in default workflow' >&2
  exit 1
fi

echo 'ISO profile validation: PASS'
