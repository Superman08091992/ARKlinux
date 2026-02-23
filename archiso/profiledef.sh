#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are consumed by mkarchiso (external sourcer)
# ARKLinux archiso profile definition
# Pinned to Arch Linux 2026.02.01 snapshot — do not change without updating
# the mirror date in pacman.conf and re-running the package lock procedure.

iso_name="arklinux"
iso_label="ARKLINUX_1_0"
iso_publisher="ARKLinux Project <https://github.com/Superman08091992/ARKlinux>"
iso_application="ARKLinux Individual Operator Edition"
iso_version="1.0.1"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')

# File permissions inside airootfs that archiso will apply
# Format: [path]="owner:group:mode"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/opt/ark"]="973:973:750"
  ["/opt/ark/secrets"]="973:973:700"
  ["/opt/ark/id"]="973:973:700"
  ["/opt/ark/models"]="973:973:755"
  ["/opt/ark/logs"]="973:973:750"
  ["/opt/ark/quarantine"]="973:973:700"
  ["/opt/ark/aletheia"]="973:973:750"
  ["/opt/ark/aletheia/audit"]="973:973:750"
  ["/opt/ark/aletheia/manifests"]="973:973:750"
  ["/usr/local/bin/ark-install"]="0:0:755"
  ["/usr/local/bin/ark-verify-perms"]="0:0:755"
  ["/usr/local/bin/ark-core"]="0:0:755"
  ["/usr/local/bin/ark-watchdog"]="0:0:755"
)
