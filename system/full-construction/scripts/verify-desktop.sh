#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }

required=(
  rootfs/usr/lib/ark-desktop/ark-desktop.py
  rootfs/usr/lib/ark-desktop/ark-rootd.py
  rootfs/usr/lib/ark-desktop/ark-shell.py
  rootfs/usr/local/bin/ark-desktop-start
  rootfs/etc/systemd/system/ark-desktop-rootd.service
  rootfs/etc/systemd/system/greetd.service.d/ark-desktop.conf
  rootfs/usr/share/ark-desktop/icons/ark.svg
  rootfs/usr/share/ark-desktop/icons/computer.svg
  rootfs/usr/share/ark-desktop/icons/files.svg
  rootfs/usr/share/ark-desktop/icons/browser.svg
  rootfs/usr/share/ark-desktop/icons/terminal.svg
  rootfs/usr/share/ark-desktop/icons/settings.svg
)

for rel in "${required[@]}"; do
  [[ -f "$ROOT/$rel" ]] || fail "missing $rel"
done
[[ "$FAIL" -eq 0 ]] && pass "desktop files present"

python -m py_compile \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-desktop.py" \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-rootd.py" \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-shell.py" \
  && pass "desktop Python syntax" || fail "desktop Python syntax"

PKGS="$ROOT/config/packages.x86_64"
for pkg in gtk4 gtk4-layer-shell python-gobject thunar firefox; do
  grep -qxF "$pkg" "$PKGS" || fail "package missing: $pkg"
done
for pkg in waybar wofi; do
  if grep -qxF "$pkg" "$PKGS"; then
    fail "obsolete scaffold package still declared: $pkg"
  fi
done
[[ "$FAIL" -eq 0 ]] && pass "desktop package declarations"

AUTO="$ROOT/rootfs/etc/skel/.config/labwc/autostart"
grep -q 'ark-desktop-start' "$AUTO" \
  && pass "Labwc starts ARK desktop session" || fail "Labwc does not start ARK desktop session"
if grep -Eq 'waybar|(^|[[:space:]])foot[[:space:]]*&' "$AUTO"; then
  fail "temporary Waybar/Foot scaffold still autostarts"
else
  pass "temporary desktop scaffold removed"
fi

STARTER="$ROOT/rootfs/usr/local/bin/ark-desktop-start"
grep -q 'ark-desktop/session.log' "$STARTER" \
  && pass "desktop startup logging enabled" || fail "desktop startup logging missing"

SHELL="$ROOT/rootfs/usr/lib/ark-desktop/ark-shell.py"
grep -q 'CDLL("libgtk4-layer-shell.so")' "$SHELL" \
  && pass "GTK4 Layer Shell preloaded" || fail "GTK4 Layer Shell preload missing"

PATCHER="$ROOT/scripts/patch-desktop-image.sh"
grep -q '/home/operator/.config/labwc/autostart' "$PATCHER" \
  && pass "existing operator session is patched" || fail "operator Labwc session patch missing"

ROOTD="$ROOT/rootfs/usr/lib/ark-desktop/ark-rootd.py"
grep -q 'socket.AF_UNIX' "$ROOTD" || fail "root broker is not Unix-socket based"
grep -q '/run/ark-desktop/root.sock' "$ROOTD" || fail "root broker socket path missing"
grep -q 'SO_PEERCRED' "$ROOTD" || fail "root broker peer credential check missing"
grep -q 'WHEEL_GID' "$ROOTD" || fail "root broker wheel authorization missing"
[[ "$FAIL" -eq 0 ]] && pass "local privileged broker structure"

SERVICE="$ROOT/rootfs/etc/systemd/system/ark-desktop-rootd.service"
grep -q '^User=root$' "$SERVICE" \
  && pass "root broker runs as root" || fail "root broker service is not root"

DROPIN="$ROOT/rootfs/etc/systemd/system/greetd.service.d/ark-desktop.conf"
grep -q 'ark-desktop-rootd.service' "$DROPIN" \
  && pass "graphical login requires root broker" || fail "greetd/root broker dependency missing"

if [[ "$FAIL" -ne 0 ]]; then
  echo "ARKlinux desktop static verification: FAIL" >&2
  exit 1
fi

echo "ARKlinux desktop static verification: PASS"
