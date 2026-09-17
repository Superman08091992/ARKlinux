#!/usr/bin/env python3
"""One-time source edit for the native trading image; no image/host execution."""
from pathlib import Path
import hashlib

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'restart/native-ark-v0.1/build/build-image.sh'
MARKER=ROOT/'integration/trading-image.applied'
if MARKER.exists():
    if MARKER.read_text().strip()!='trading-native-image-v1':raise SystemExit('Unexpected application marker')
    raise SystemExit(0)
raw=BUILD.read_bytes()
blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
if blob!='8b70d96209e90538d287fd8e0827ecf20acf711c':
    raise SystemExit('Assembler changed; refusing to overwrite another revision')
text=raw.decode()
old='''validate_guest_contract(){
  local label="$1" check="$2"
  if ! arch-chroot "$MNT" /bin/bash -c "$check"; then
    echo "ERROR: native A.R.K. contract failed: $label" >&2
    return 1
  fi
}'''
new='''validate_guest_contract(){
  local label="$1" check="$2" contract_log
  [[ "$label" =~ ^[a-z0-9_]+$ ]] || { echo "ERROR: invalid contract label" >&2; return 1; }
  mkdir -p "$OUT/evidence/contracts"
  contract_log="$OUT/evidence/contracts/$label.log"
  # Force stderr into the build transcript even when systemd detects a journal
  # socket. Fail on the first failed assertion, not just the last shell command.
  if arch-chroot "$MNT" /usr/bin/env SYSTEMD_LOG_TARGET=console \\
       SYSTEMD_LOG_LEVEL=info SYSTEMD_COLORS=0 \\
       /bin/bash -euo pipefail -c "$check" 2>&1 | tee "$contract_log"; then
    printf 'ARK_GUEST_CONTRACT=PASS name=%s\\n' "$label"
  else
    printf 'ERROR: native A.R.K. contract failed: %s (details: %s)\\n' "$label" "$contract_log" >&2
    return 1
  fi
}'''
if text.count(old)!=1:raise SystemExit('Validation function mismatch')
text=text.replace(old,new,1)
lines=[line for line in text.splitlines() if line.startswith('validate_guest_contract systemd_units ')]
if len(lines)!=1:raise SystemExit('System-unit gate mismatch')
line=lines[0]
changed=line.replace('systemd-analyze verify','systemd-analyze --man=no verify',1)
changed=changed.replace(' /etc/systemd/user/ark-embodied-desktop.service','',1)
changed=changed.replace('/usr/lib/systemd/system/ark-agent@.service', ' '.join('ark-agent@'+role+'.service' for role in ('kyle','aletheia','joey','hrm','kenny')),1)
changed=changed[:-1]+' /usr/lib/systemd/system/ark-tradeanalyzer.service /usr/lib/systemd/system/ark-tradeanalyzer-feed.service /usr/lib/systemd/system/ark-webull-executor.service'+"'"
user='''
validate_guest_contract systemd_user_units '
  runtime="$(mktemp -d /run/ark-user-verify.XXXXXXXX)"
  export XDG_RUNTIME_DIR="$runtime"
  export SYSTEMD_UNIT_PATH=/etc/systemd/user:/usr/local/lib/systemd/user:/usr/lib/systemd/user
  systemd-analyze --user --man=no verify /etc/systemd/user/ark-embodied-desktop.service
'
validate_guest_contract tradeanalyzer_boot_click '
  test -s /ark/runtime/modules/tradeanalyzer/workstation/integrated.py
  test -s /ark/runtime/modules/tradeanalyzer/workstation/broker.py
  test -x /usr/local/bin/ark-trading-open
  test -s /usr/share/applications/ark-tradeanalyzer.desktop
  test -s /usr/lib/arklinux-shell/electron/trading.cjs
  test -s /usr/lib/arklinux-shell/electron/trading-preload.cjs
  test -s /etc/systemd/system/ark-agent@kenny.service.d/30-webull-adapter.conf
  test "$(readlink /etc/systemd/system/multi-user.target.wants/ark-tradeanalyzer.service)" = /usr/lib/systemd/system/ark-tradeanalyzer.service
'
validate_guest_contract kernel_series '
  kernel="$(pacman -Q linux-lts | cut -d " " -f 2)"
  headers="$(pacman -Q linux-lts-headers | cut -d " " -f 2)"
  [[ "$kernel" == 6.18.* && "$headers" == "$kernel" ]]
'
'''
text=text.replace(line,changed+user,1)
BOOT=ROOT/'restart/native-ark-v0.1/rootfs/usr/local/sbin/ark-boot-proof'
boot_raw=BOOT.read_bytes()
if hashlib.sha1(b'blob '+str(len(boot_raw)).encode()+b'\0'+boot_raw).hexdigest()!='16a7c09e5f785f332e8db1100aa4003c30560119':
    raise SystemExit('Boot proof changed; refusing to overwrite it')
boot=boot_raw.decode()
anchor='AUDIT_STATUS_END="$(capture_audit_status end)"'
if boot.count(anchor)!=1:raise SystemExit('Boot proof anchor mismatch')
boot=boot.replace(anchor,"/usr/local/sbin/ark-trading-boot-proof || fail 'trading_background_probe_failed'\n\n"+anchor,1)
QEMU=ROOT/'restart/native-ark-v0.1/build/qemu-proof.sh'
qemu=QEMU.read_text()
anchor=r'ARK_AUDIT_INTEGRITY_PROBE=PASS\|ARK_NATIVE_BOOT_PROOF=PASS'
if qemu.count(anchor)!=1:raise SystemExit('QEMU evidence capture anchor mismatch')
qemu=qemu.replace(anchor,r'ARK_TRADING_BACKGROUND_PROBE=PASS\|'+anchor,1)
BUILD.write_text(text)
BOOT.write_text(boot)
QEMU.write_text(qemu)
MARKER.write_text('trading-native-image-v1\n')
print('NATIVE_IMAGE_SOURCE_PATCH=PASS system_and_user_managers=separate diagnostics=retained')
