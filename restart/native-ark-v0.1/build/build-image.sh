#!/usr/bin/env bash
set -euo pipefail

# Run the complete assembler away from the workstation's live mount, PID, and
# /run namespaces. arch-chroot may bind its caller's /run into the guest, so the
# caller must expose only this build-private tmpfs—not host desktop, D-Bus,
# systemd, or GnuPG sockets.
[[ ${EUID:-$(id -u)} -eq 0 ]] || {
  echo "ERROR: build-image.sh must run as root" >&2
  exit 1
}
if [[ "${ARKLINUX_PRIVATE_BUILD_NAMESPACE:-0}" != "1" ]]; then
  exec unshare --mount --pid --fork --mount-proc --kill-child=SIGKILL \
    /usr/bin/env ARKLINUX_PRIVATE_BUILD_NAMESPACE=1 SYSTEMD_OFFLINE=1 \
    /usr/bin/bash "$0" "$@"
fi

mount --make-rprivate /
RESOLV_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
RESOLV_COPY="$(mktemp /tmp/arklinux-resolv.XXXXXX)"
if [[ -r /etc/resolv.conf ]]; then
  cp --dereference /etc/resolv.conf "$RESOLV_COPY"
else
  : > "$RESOLV_COPY"
fi
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run
mkdir -p /run/lock
if [[ "$RESOLV_TARGET" == /run/* ]]; then
  mkdir -p "$(dirname "$RESOLV_TARGET")"
  install -m 0644 "$RESOLV_COPY" "$RESOLV_TARGET"
fi
rm -f "$RESOLV_COPY"
unset DBUS_SESSION_BUS_ADDRESS DBUS_SYSTEM_BUS_ADDRESS DISPLAY WAYLAND_DISPLAY
unset XAUTHORITY XDG_RUNTIME_DIR PULSE_SERVER SSH_AUTH_SOCK GPG_AGENT_INFO
export SYSTEMD_OFFLINE=1
RELROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARK_GENESIS_LOCK="$RELROOT/config/ark-genesis.lock"
[[ -s "$ARK_GENESIS_LOCK" ]] || { echo "ERROR: missing ARK_GENESIS lock: $ARK_GENESIS_LOCK" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ARK_GENESIS_LOCK"
[[ "${ARK_GENESIS_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: invalid ARK_GENESIS_COMMIT in $ARK_GENESIS_LOCK" >&2; exit 1; }
ARKLINUX_SHELL_LOCK="$RELROOT/config/arklinux-shell.lock"
[[ -s "$ARKLINUX_SHELL_LOCK" ]] || { echo "ERROR: missing ARKlinux Shell lock: $ARKLINUX_SHELL_LOCK" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ARKLINUX_SHELL_LOCK"
[[ "${ARKLINUX_SHELL_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: invalid ARKLINUX_SHELL_COMMIT in $ARKLINUX_SHELL_LOCK" >&2; exit 1; }
OUT="${ARKLINUX_OUT:-$RELROOT/out}"
WORK="${ARKLINUX_WORK:-$RELROOT/.work}"
IMG="$OUT/arklinux-native-v0.1-x86_64.raw"
COMPRESSED="$IMG.zst"
OVERLAY="${ARK_RUNTIME_OVERLAY:-/ark-runtime-overlay/ark-runtime-overlay.tar.zst}"
SHELL_OVERLAY="${ARK_SHELL_OVERLAY:-/ark-shell-overlay/arklinux-shell-overlay.tar.zst}"
SIZE_GIB="${ARKLINUX_IMAGE_SIZE_GIB:-24}"
SWAP_GIB="${ARKLINUX_SWAP_GIB:-4}"
KERNEL_IMAGE=/vmlinuz-linux-lts
INITRAMFS_IMAGE=/initramfs-linux-lts.img
INITRAMFS_FALLBACK=/initramfs-linux-lts-fallback.img
MNT="$WORK/mnt"
LOCK_FILE="${WORK}.lock"
LOOP=""
ESP_DEV=""
ROOT_DEV=""
KPARTX_ACTIVE=0

stage(){ printf '\n==> %s\n' "$*"; }

teardown_build_state(){
  local tracked_loop="${LOOP:-}" associated_loops="" failed=0
  mountpoint -q "$MNT/boot" && umount "$MNT/boot" || true
  while mountpoint -q "$MNT"; do umount -R "$MNT" 2>/dev/null || break; done
  if [[ "$KPARTX_ACTIVE" == "1" && -n "$tracked_loop" ]]; then
    kpartx -d "$tracked_loop" 2>/dev/null || true
  fi
  if [[ -n "$tracked_loop" ]] && losetup "$tracked_loop" >/dev/null 2>&1; then
    losetup -d "$tracked_loop" 2>/dev/null || true
  fi
  findmnt -rnR -M "$MNT" >/dev/null 2>&1 && failed=1
  associated_loops="$(losetup --list --noheadings --raw --output NAME --associated "$IMG" 2>/dev/null || true)"
  [[ -n "$associated_loops" ]] && failed=1
  if [[ -n "$tracked_loop" ]] && losetup "$tracked_loop" >/dev/null 2>&1; then
    failed=1
  fi
  return "$failed"
}

cleanup(){
  local rc=$?
  trap - EXIT
  teardown_build_state >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT

clear_stale_build_state(){
  local stale_loop
  if findmnt -rnR -M "$MNT" >/dev/null 2>&1; then
    stage "remove stale build mounts"
    if ! umount -R "$MNT"; then
      echo "ERROR: stale build mount is busy: $MNT" >&2
      findmnt -R -M "$MNT" >&2 || true
      return 1
    fi
  fi
  while IFS= read -r stale_loop; do
    [[ -n "$stale_loop" ]] || continue
    command -v kpartx >/dev/null 2>&1 && kpartx -d "$stale_loop" 2>/dev/null || true
    losetup -d "$stale_loop"
  done < <(losetup --list --noheadings --raw --output NAME --associated "$IMG" 2>/dev/null || true)
  if findmnt -rn -M "$MNT" >/dev/null 2>&1; then
    echo "ERROR: stale build mount remains after cleanup: $MNT" >&2
    findmnt -R -M "$MNT" >&2 || true
    return 1
  fi
}

resolve_partitions(){
  local base
  base="$(basename "$LOOP")"
  partx -u "$LOOP" 2>/dev/null || partx -a "$LOOP" 2>/dev/null || true
  sleep 1
  if [[ -b "${LOOP}p1" && -b "${LOOP}p2" ]]; then
    ESP_DEV="${LOOP}p1"
    ROOT_DEV="${LOOP}p2"
    return 0
  fi
  command -v kpartx >/dev/null 2>&1 || { echo "ERROR: loop partition nodes absent and kpartx is unavailable" >&2; return 1; }
  kpartx -av "$LOOP"
  KPARTX_ACTIVE=1
  ESP_DEV="/dev/mapper/${base}p1"
  ROOT_DEV="/dev/mapper/${base}p2"
  for _ in {1..20}; do
    [[ -b "$ESP_DEV" && -b "$ROOT_DEV" ]] && return 0
    sleep 0.25
  done
  echo "ERROR: partition devices unavailable after partx/kpartx: $ESP_DEV $ROOT_DEV" >&2
  ls -l /dev/mapper /dev/${base}* 2>/dev/null || true
  return 1
}

apply_subvolume_mount_contract(){
  local subvol mp opts owner group mode cls actual expected
  while IFS=$'\t' read -r subvol mp opts owner group mode cls; do
    [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue
    arch-chroot "$MNT" chown "$owner:$group" "$mp"
    arch-chroot "$MNT" chmod "$mode" "$mp"
    actual="$(arch-chroot "$MNT" stat -c '%U:%G:%a' "$mp")"
    expected="$owner:$group:${mode#0}"
    [[ "$actual" == "$expected" ]] || {
      echo "ERROR: subvolume mount contract mismatch at $mp: expected=$expected actual=$actual" >&2
      return 1
    }
  done < "$RELROOT/config/subvolumes.tsv"
}

apply_persistent_ark_layout(){
  # Persistent state belongs to the Btrfs/image layer, not tmpfiles. This is
  # deliberately separate from /run/ark, which is volatile and recreated by
  # systemd-tmpfiles at normal boot.
  arch-chroot "$MNT" install -d -m 0755 -o root -g root /ark
  arch-chroot "$MNT" install -d -m 0770 -o arkd -g ark-state /ark/memory /ark/evidence /ark/state /ark/checkpoints /ark/quarantine /ark/storage /ark/logs /ark/bus
  arch-chroot "$MNT" install -d -m 0770 -o ark-kj -g ark-state /ark/kj
  arch-chroot "$MNT" install -d -m 0750 -o root -g ark-state /ark/graveyard /ark/models /ark/config
  arch-chroot "$MNT" usermod -a -G ark-state ollama
  arch-chroot "$MNT" install -d -m 0750 -o ollama -g ollama /ark/models/ollama
  arch-chroot "$MNT" install -d -m 0770 -o ark-trading -g ark-state /ark/trading
  arch-chroot "$MNT" install -d -m 0711 -o root -g root /ark/agents
  arch-chroot "$MNT" install -d -m 0755 -o root -g root /ark/agent-public-keys
  arch-chroot "$MNT" install -d -m 0700 -o root -g root /var/lib/ark/batch-executor /var/lib/ark/batch-executor/claims
  local role
  for role in kyle aletheia joey hrm kenny; do
    arch-chroot "$MNT" install -d -m 0750 -o "ark-$role" -g ark-agent-audit "/ark/agents/$role"
    arch-chroot "$MNT" install -d -m 0750 -o "ark-$role" -g ark-agent-audit "/ark/agents/$role/workspace" "/ark/agents/$role/artifacts" "/ark/agents/$role/proposals"
    arch-chroot "$MNT" install -d -m 2750 -o "ark-$role" -g ark-agent-audit "/ark/agents/$role/ledger"
    arch-chroot "$MNT" install -d -m 0755 -o "ark-$role" -g root "/ark/agent-public-keys/$role"
  done
  arch-chroot "$MNT" install -d -m 0750 -o root -g ark-state /etc/ark /etc/ark/trading
  arch-chroot "$MNT" install -d -m 0770 -o arkd -g ark-state /var/lib/ark
  arch-chroot "$MNT" install -d -m 0770 -o arkd -g ark-state /var/log/ark
  arch-chroot "$MNT" install -d -m 0750 -o ark-desktop -g ark-state /var/lib/ark/desktop
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: build-image.sh must run as root" >&2; exit 1; }
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "ERROR: another ARKlinux image build owns: $LOCK_FILE" >&2; exit 1; }
[[ -f "$OVERLAY" ]] || { echo "ERROR: private A.R.K. overlay missing: $OVERLAY" >&2; exit 1; }
[[ -f "$SHELL_OVERLAY" ]] || { echo "ERROR: critical ARKlinux Shell overlay missing: $SHELL_OVERLAY" >&2; exit 1; }
stage "prepare raw disk"
clear_stale_build_state
rm -rf "$WORK"; mkdir -p "$OUT" "$MNT"; rm -f "$IMG" "$COMPRESSED"
truncate -s "${SIZE_GIB}G" "$IMG"
sgdisk --zap-all "$IMG"
sgdisk -n 1:1MiB:+1GiB -t 1:ef00 -c 1:ARKESP "$IMG"
sgdisk -n 2:0:0 -t 2:8300 -c 2:ARKROOT "$IMG"
LOOP="$(losetup --find --show --partscan "$IMG")"
resolve_partitions
printf 'Partition map: loop=%s esp=%s root=%s\n' "$LOOP" "$ESP_DEV" "$ROOT_DEV"

stage "format and create native Btrfs topology"
mkfs.fat -F32 -n ARKESP "$ESP_DEV"
mkfs.btrfs -f -L ARKROOT "$ROOT_DEV"
mount "$ROOT_DEV" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue; btrfs subvolume create "$MNT/$subvol"; done < "$RELROOT/config/subvolumes.tsv"
umount "$MNT"
mount -o noatime,compress=zstd:3,subvol=@ark "$ROOT_DEV" "$MNT"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* || "$mp" == "/" ]] && continue; mkdir -p "$MNT$mp"; mount -o "subvol=$subvol,$opts" "$ROOT_DEV" "$MNT$mp"; done < "$RELROOT/config/subvolumes.tsv"
mkdir -p "$MNT/boot"; mount "$ESP_DEV" "$MNT/boot"

stage "install Arch package set"
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$RELROOT/config/packages.x86_64"); pacstrap -K "$MNT" "${PKGS[@]}"

stage "install ARKlinux rootfs, private A.R.K. overlay, and embodied desktop"
# Host checkout ownership must never become guest filesystem ownership.
cp -a --no-preserve=ownership "$RELROOT/rootfs/." "$MNT/"
tar --zstd --no-same-owner -xf "$OVERLAY" -C "$MNT"
tar --zstd --no-same-owner -xf "$SHELL_OVERLAY" -C "$MNT"
[[ -s "$MNT/etc/ark/ARK_GENESIS_COMMIT" ]] || { echo "ERROR: runtime overlay has no ARK_GENESIS_COMMIT provenance" >&2; exit 1; }
OBSERVED_ARK_GENESIS_COMMIT="$(tr -d '[:space:]' < "$MNT/etc/ark/ARK_GENESIS_COMMIT")"
[[ "$OBSERVED_ARK_GENESIS_COMMIT" == "$ARK_GENESIS_COMMIT" ]] || {
  echo "ERROR: runtime overlay commit $OBSERVED_ARK_GENESIS_COMMIT does not match locked $ARK_GENESIS_COMMIT" >&2
  exit 1
}
[[ -s "$MNT/etc/ark/ARKLINUX_SHELL_COMMIT" ]] || { echo "ERROR: shell overlay has no ARKLINUX_SHELL_COMMIT provenance" >&2; exit 1; }
OBSERVED_ARKLINUX_SHELL_COMMIT="$(tr -d '[:space:]' < "$MNT/etc/ark/ARKLINUX_SHELL_COMMIT")"
[[ "$OBSERVED_ARKLINUX_SHELL_COMMIT" == "$ARKLINUX_SHELL_COMMIT" ]] || {
  echo "ERROR: shell overlay commit $OBSERVED_ARKLINUX_SHELL_COMMIT does not match locked $ARKLINUX_SHELL_COMMIT" >&2
  exit 1
}
chown root:root "$MNT" "$MNT/etc" "$MNT/usr" "$MNT/usr/lib" "$MNT/opt" "$MNT/ark"
chmod 0755 "$MNT" "$MNT/etc" "$MNT/usr" "$MNT/usr/lib" "$MNT/opt" "$MNT/ark"
chmod 0755 "$MNT/usr/local/bin/ark-session" "$MNT/usr/local/bin/ark-bootstrap-ai" "$MNT/usr/local/sbin/ark-firstboot" "$MNT/usr/local/sbin/ark-embedding-model" "$MNT/usr/local/sbin/ark-model-pull" "$MNT/usr/local/sbin/ark-boot-proof" "$MNT/usr/local/sbin/ark-gpu-detect" "$MNT/usr/local/sbin/ark-gpu-install" "$MNT/usr/local/sbin/ark-display-preflight" "$MNT/usr/lib/ark-display/adapter.py"
chmod 0755 "$MNT/usr/local/bin/ark-embodied-desktop" "$MNT/usr/local/sbin/ark-desktop-ready" "$MNT/usr/lib/ark-desktop/ui_broker.py"
printf 'ARKlinux\n' > "$MNT/etc/hostname"; printf 'LANG=en_US.UTF-8\n' > "$MNT/etc/locale.conf"; sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$MNT/etc/locale.gen"; ln -sf /usr/share/zoneinfo/America/Los_Angeles "$MNT/etc/localtime"

stage "validate root filesystem trust boundary"
for path in / /etc /usr /usr/lib /opt /ark; do
  [[ "$(stat -c '%u:%g' "$MNT$path")" == "0:0" ]] || {
    echo "ERROR: guest system path is not root-owned: $path ($(stat -c '%u:%g' "$MNT$path"))" >&2
    exit 1
  }
done
[[ "$(stat -c '%a' "$MNT")" == "755" ]] || { echo "ERROR: guest / must have mode 0755" >&2; exit 1; }
if find "$MNT/etc" "$MNT/usr" "$MNT/opt" "$MNT/ark" -uid 1000 -print -quit | grep -q .; then
  echo "ERROR: host/operator UID 1000 leaked into guest system paths" >&2
  find "$MNT/etc" "$MNT/usr" "$MNT/opt" "$MNT/ark" -uid 1000 -print | head -50 >&2
  exit 1
fi

stage "validate package manager recovery contract"
for path in /etc/pacman.conf /etc/pacman.d/mirrorlist; do
  [[ -s "$MNT$path" ]] || {
    echo "ERROR: release image is missing package manager configuration: $path" >&2
    exit 1
  }
done
for path in /usr/bin/pacman /usr/bin/pacman-conf /usr/bin/pacman-key; do
  [[ -x "$MNT$path" ]] || {
    echo "ERROR: release image is missing package manager command: $path" >&2
    exit 1
  }
done
arch-chroot "$MNT" /bin/bash -lc '
  test -d /var/lib/pacman/local
  find /var/lib/pacman/local -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q .
  pacman -Q pacman archlinux-keyring >/dev/null
  repo_list="$(pacman-conf --repo-list)"
  grep -qx core <<<"$repo_list"
  grep -qx extra <<<"$repo_list"
'
# Package presence is not sufficient: initialize the image-local trust root,
# import Arch's packaged keys and owner-trust values, then calculate the trust
# database that Pacman will use after installation.
arch-chroot "$MNT" pacman-key --init
arch-chroot "$MNT" pacman-key --populate archlinux
arch-chroot "$MNT" pacman-key --updatedb
# pacman-key may leave its image-local gpg-agent alive. Stop that exact agent
# before final unmount so it cannot retain the guest Btrfs filesystem.
arch-chroot "$MNT" gpgconf --homedir /etc/pacman.d/gnupg --kill all || true

stage "generate locale"
arch-chroot "$MNT" locale-gen

stage "apply A.R.K. system users"
arch-chroot "$MNT" systemd-sysusers /usr/lib/sysusers.d/ark-native.conf /usr/lib/sysusers.d/ark-desktop.conf
arch-chroot "$MNT" getent group ark-agent-audit >/dev/null || { echo "ERROR: sysusers did not create ark-agent-audit" >&2; exit 1; }

stage "apply native Btrfs mount ownership contract"
apply_subvolume_mount_contract

stage "apply persistent A.R.K. Btrfs layout"
apply_persistent_ark_layout

stage "validate volatile tmpfiles contract transactionally"
# Use tmpfiles' alternate-root mode so this check cannot bind or alter the
# build host's live /run. Remove the test tree so boot must recreate it on tmpfs.
systemd-tmpfiles --root="$MNT" --create ark-native.conf
chroot "$MNT" /bin/bash -lc '
  test "$(stat -c "%U:%G:%a" /run/ark)" = root:root:755
  test "$(stat -c "%U:%G:%a" /run/ark/agents)" = root:root:755
  test "$(stat -c "%U:%G:%a" /run/ark/agents/kyle)" = root:ark-kyle-ipc:770
  test "$(stat -c "%U:%G:%a" /run/ark/agents/aletheia)" = root:ark-aletheia-ipc:770
  test "$(stat -c "%U:%G:%a" /run/ark/agents/joey)" = root:ark-joey-ipc:770
  test "$(stat -c "%U:%G:%a" /run/ark/agents/hrm)" = root:ark-hrm-ipc:770
  test "$(stat -c "%U:%G:%a" /run/ark/agents/kenny)" = root:ark-kenny-ipc:770
  test "$(stat -c "%U:%G:%a" /run/ark/kj)" = ark-kj:ark-kj-ipc:770
  test "$(stat -c "%U:%G:%a" /ark/agents)" = root:root:711
  test "$(stat -c "%U:%G:%a" /ark/agent-public-keys)" = root:root:755
  test "$(stat -c "%U:%G:%a" /ark/models)" = root:ark-state:750
  test "$(stat -c "%U:%G:%a" /ark/models/ollama)" = ollama:ollama:750
  id -nG ollama | tr " " "\n" | grep -qx ark-state
  test "$(stat -c "%U:%G:%a" /var/lib/ark/batch-executor/claims)" = root:root:700
  for role in kyle aletheia joey hrm kenny; do
    test "$(stat -c "%U:%G:%a" "/ark/agents/$role")" = "ark-$role:ark-agent-audit:750"
    test "$(stat -c "%U:%G:%a" "/ark/agents/$role/ledger")" = "ark-$role:ark-agent-audit:2750"
    test "$(stat -c "%U:%G:%a" "/ark/agent-public-keys/$role")" = "ark-$role:root:755"
  done
'
rm -rf "$MNT/run/ark"
[[ ! -e "$MNT/run/ark" ]] || { echo "ERROR: volatile /run/ark leaked into release image" >&2; exit 1; }

stage "validate forward-only namespace"
[[ ! -e "$MNT/opt/ark" && ! -L "$MNT/opt/ark" ]] || {
  echo "ERROR: obsolete /opt/ark path present in new image" >&2
  exit 1
}

stage "create operator account"
arch-chroot "$MNT" useradd -m -G wheel,audio,video,input,storage -s /bin/bash operator || true
arch-chroot "$MNT" passwd -l operator || true
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$MNT/etc/sudoers.d/10-wheel"; chmod 0440 "$MNT/etc/sudoers.d/10-wheel"

stage "write fstab and swapfile"
ROOTUUID="$(blkid -s UUID -o value "$ROOT_DEV")"; ESPUUID="$(blkid -s UUID -o value "$ESP_DEV")"; : > "$MNT/etc/fstab"
while IFS=$'\t' read -r subvol mp opts owner group mode cls; do [[ -z "${subvol:-}" || "$subvol" == \#* ]] && continue; printf 'UUID=%s\t%s\tbtrfs\tsubvol=%s,%s\t0 0\n' "$ROOTUUID" "$mp" "$subvol" "$opts" >> "$MNT/etc/fstab"; done < "$RELROOT/config/subvolumes.tsv"
printf 'UUID=%s\t/boot\tvfat\tumask=0077\t0 2\n' "$ESPUUID" >> "$MNT/etc/fstab"
arch-chroot "$MNT" btrfs filesystem mkswapfile --size "${SWAP_GIB}G" /swap/swapfile
printf '/swap/swapfile none swap defaults 0 0\n' >> "$MNT/etc/fstab"

stage "install systemd-boot"
arch-chroot "$MNT" bootctl --path=/boot install --no-variables; mkdir -p "$MNT/boot/loader/entries"
cat > "$MNT/boot/loader/loader.conf" <<EOF
default arklinux.conf
timeout 4
console-mode max
editor no
EOF
cat > "$MNT/boot/loader/entries/arklinux.conf" <<EOF
title ARKlinux Native v0.1
linux $KERNEL_IMAGE
initrd $INITRAMFS_IMAGE
options root=UUID=$ROOTUUID rootflags=subvol=@ark rw quiet audit=1 console=tty0 console=ttyS0,115200n8
EOF
cat > "$MNT/boot/loader/entries/arklinux-fallback.conf" <<EOF
title ARKlinux Native v0.1 (fallback)
linux $KERNEL_IMAGE
initrd $INITRAMFS_FALLBACK
options root=UUID=$ROOTUUID rootflags=subvol=@ark rw audit=1 console=tty0 console=ttyS0,115200n8
EOF

stage "regenerate portable initramfs"
# A release image must not inherit the build host's autodetect whitelist.
# Current Arch kernel packages may ship a default-only preset, so generate the
# portable image explicitly instead of assuming a vendor fallback preset exists.
arch-chroot "$MNT" mkinitcpio \
  -k "/boot$KERNEL_IMAGE" \
  -g "/boot$INITRAMFS_FALLBACK" \
  -S autodetect
[[ -s "$MNT/boot${INITRAMFS_FALLBACK}" ]] || {
  echo "ERROR: portable initramfs generation failed: /boot$INITRAMFS_FALLBACK" >&2
  exit 1
}
# Use the complete module set for first boot. Normal kernel upgrades on the
# installed workstation regenerate the default image against the real hardware.
cp "$MNT/boot${INITRAMFS_FALLBACK}" "$MNT/boot${INITRAMFS_IMAGE}"
arch-chroot "$MNT" /bin/bash -lc \
  "lsinitcpio '/boot$INITRAMFS_IMAGE' | grep -Eq '/nouveau\\.ko(\\.(gz|xz|zst))?$'"

stage "enable native services"
systemctl --root="$MNT" enable NetworkManager.service nftables.service chronyd.service greetd.service ollama.service ark-embedding-model.service ark-firstboot.service ark.target ark-desktop-core.target ark-ui-broker.service ark-shell-server.service ark-display-adapter.service ark-boot-proof.service ark-gpu-report.service ark-display-preflight.service
systemctl --root="$MNT" --global enable ark-embodied-desktop.service
# Keep ttyS0 as a write-only CI/emergency console without letting the generated
# serial getty restart forever on workstations that have no usable serial port.
systemctl --root="$MNT" mask serial-getty@ttyS0.service
systemctl --root="$MNT" set-default graphical.target

stage "validate native A.R.K. contract"
arch-chroot "$MNT" /bin/bash -lc 'test "$(stat -c "%U:%G:%a" /)" = root:root:755 && test "$(stat -c "%U:%G" /etc)" = root:root && test "$(stat -c "%U:%G" /usr)" = root:root && test "$(stat -c "%U:%G" /usr/lib)" = root:root'
arch-chroot "$MNT" /bin/bash -lc 'test -d /ark/runtime && test -f /ark/pair_mvp/pipeline.py && test -f /ark/pair_mvp/alatheia.py && test -x /usr/bin/ark-agentic-model-proof && test -f /etc/ark/ARK_GENESIS_COMMIT && test -f /etc/ark/ALATHEIA_COMMIT && ! test -e /opt/ark && ! test -L /opt/ark'
arch-chroot "$MNT" /bin/bash -lc 'test -x /usr/local/sbin/ark-model-pull && test -r /usr/share/ark/model-catalog.json && test -f /etc/systemd/system/ollama.service.d/10-ark-model-store.conf && grep -q "OLLAMA_MODELS=/ark/models/ollama" /etc/systemd/system/ollama.service.d/10-ark-model-store.conf'
arch-chroot "$MNT" /bin/bash -lc 'test "$(stat -c "%U:%G:%a" /ark/models/ollama)" = ollama:ollama:750 && id -nG ollama | tr " " "\n" | grep -qx ark-state'
arch-chroot "$MNT" /bin/bash -lc 'for path in /ark/logs /ark/bus /var/log/ark; do test -d "$path" && test "$(stat -c "%U:%G:%a" "$path")" = arkd:ark-state:770 || exit 1; done'
arch-chroot "$MNT" /bin/bash -lc 'for role in kyle aletheia joey hrm kenny; do mountpoint -q "/ark/agents/$role" && test "$(stat -c "%U:%G:%a" "/ark/agents/$role")" = "ark-$role:ark-agent-audit:750" || exit 1; done'
arch-chroot "$MNT" /bin/bash -lc 'test -f /usr/lib/systemd/system/arkd.service && test -f /etc/systemd/system/ark-embedding-model.service && test -f /usr/lib/systemd/system/ark-kj.service && test -f /usr/lib/systemd/system/ark-agent@.service && test -f /usr/lib/systemd/system/ark-batch-executor.socket && test -f /usr/lib/systemd/system/ark-batch-executor.service'
arch-chroot "$MNT" /bin/bash -lc 'test -s /usr/lib/arklinux-shell/dist/index.html && test -s /usr/lib/arklinux-shell/build/server.cjs && test -s /usr/lib/arklinux-shell/electron/main.cjs && test -x /usr/lib/ark-desktop/ui_broker.py && test -x /usr/local/bin/ark-embodied-desktop && test -x /usr/local/sbin/ark-desktop-ready && test -f /etc/ark/ARKLINUX_SHELL_COMMIT'
arch-chroot "$MNT" /bin/bash -lc 'test -f /etc/systemd/system/ark-desktop-core.target && test -f /etc/systemd/system/ark-ui-broker.service && test -f /etc/systemd/system/ark-shell-server.service && test -f /etc/systemd/system/ark.target.d/20-critical-desktop.conf && test -f /etc/systemd/user/ark-embodied-desktop.service'
arch-chroot "$MNT" /bin/bash -lc 'systemd-analyze verify /usr/lib/systemd/system/ollama.service /usr/lib/systemd/system/arkd.service /usr/lib/systemd/system/ark-kj.service /usr/lib/systemd/system/ark-agent@.service /usr/lib/systemd/system/ark-batch-executor.socket /usr/lib/systemd/system/ark-batch-executor.service /usr/lib/systemd/system/ark-local-api.service /etc/systemd/system/ark-desktop-core.target /etc/systemd/system/ark-ui-broker.service /etc/systemd/system/ark-shell-server.service /etc/systemd/user/ark-embodied-desktop.service /etc/systemd/system/ark-display-adapter.service /etc/systemd/system/ark-embedding-model.service /etc/systemd/system/ark-firstboot.service /etc/systemd/system/ark-boot-proof.service /etc/systemd/system/ark-gpu-report.service /etc/systemd/system/ark-display-preflight.service'
arch-chroot "$MNT" /bin/bash -lc 'test -f /etc/pam.d/greetd && grep -q "pam_env.so conffile=/etc/greetd/greetd-pam-env.conf" /etc/pam.d/greetd && test -f /etc/systemd/system/greetd.service.d/10-arklinux-vt.conf'
arch-chroot "$MNT" /bin/bash -lc 'grep -q "^OnFailure=getty@tty1.service$" /etc/systemd/system/ark-display-preflight.service && test "$(readlink /etc/systemd/system/serial-getty@ttyS0.service)" = /dev/null'
arch-chroot "$MNT" /bin/bash -lc 'pacman -Q linux-lts linux-lts-headers mesa libdrm plasma-pa xdg-desktop-portal-kde rtkit python-cryptography nodejs-lts-krypton electron >/dev/null'

stage "collect image evidence"
mkdir -p "$OUT/evidence"; cp "$RELROOT/config/subvolumes.tsv" "$OUT/evidence/subvolumes.tsv"; cp "$RELROOT/config/packages.x86_64" "$OUT/evidence/packages.requested"; cp "$RELROOT/config/dependencies.md" "$OUT/evidence/dependencies.md"; cp "$MNT/etc/fstab" "$OUT/evidence/fstab"; pacman --root "$MNT" --config /etc/pacman.conf -Q > "$OUT/evidence/packages.installed"; btrfs subvolume list "$MNT" > "$OUT/evidence/btrfs-subvolumes.txt"; findmnt -R "$MNT" > "$OUT/evidence/mount-tree.txt"; cp "$MNT/etc/ark/ARK_GENESIS_COMMIT" "$OUT/evidence/ARK_GENESIS_COMMIT"; cp "$MNT/etc/ark/ALATHEIA_COMMIT" "$OUT/evidence/ALATHEIA_COMMIT"; sha256sum "$OVERLAY" > "$OUT/evidence/ARK_RUNTIME_OVERLAY_SHA256"
cp "$MNT/etc/ark/ARKLINUX_SHELL_COMMIT" "$OUT/evidence/ARKLINUX_SHELL_COMMIT"; sha256sum "$SHELL_OVERLAY" > "$OUT/evidence/ARKLINUX_SHELL_OVERLAY_SHA256"
cp "$ARK_GENESIS_LOCK" "$OUT/evidence/ark-genesis.lock"
cp "$ARKLINUX_SHELL_LOCK" "$OUT/evidence/arklinux-shell.lock"

stage "finalize and compress image"
sync
if ! teardown_build_state; then
  echo "ERROR: refusing to finalize while the guest filesystem remains mounted or its loop remains attached" >&2
  findmnt -R -M "$MNT" >&2 || true
  losetup --list --output NAME,BACK-FILE --associated "$IMG" >&2 || true
  [[ -n "$LOOP" ]] && losetup "$LOOP" >&2 || true
  exit 1
fi
trap - EXIT
LOOP=""
KPARTX_ACTIVE=0
(cd "$OUT" && sha256sum "$(basename "$IMG")" > RAW-SHA256SUMS)
zstd -19 -T0 --rm "$IMG" -o "$COMPRESSED"
(cd "$OUT" && sha256sum "$(basename "$COMPRESSED")" > SHA256SUMS)
printf 'ARKlinux native release image: %s\n' "$COMPRESSED"
