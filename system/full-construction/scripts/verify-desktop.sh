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
  rootfs/usr/lib/ark-desktop/ark-agentctl.py
  rootfs/usr/local/bin/ark-desktop-start
  rootfs/etc/systemd/system/ark-desktop-rootd.service
  rootfs/etc/systemd/system/greetd.service.d/ark-desktop.conf
  rootfs/usr/share/applications/ark-agents.desktop
  rootfs/usr/share/ark-desktop/icons/ark.svg
  rootfs/usr/share/ark-desktop/icons/computer.svg
  rootfs/usr/share/ark-desktop/icons/files.svg
  rootfs/usr/share/ark-desktop/icons/browser.svg
  rootfs/usr/share/ark-desktop/icons/terminal.svg
  rootfs/usr/share/ark-desktop/icons/settings.svg
  rootfs/usr/share/ark-desktop/icons/agents.svg
)

for rel in "${required[@]}"; do
  [[ -f "$ROOT/$rel" ]] || fail "missing $rel"
done
[[ "$FAIL" -eq 0 ]] && pass "desktop files present"

python -m py_compile \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-desktop.py" \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-rootd.py" \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-shell.py" \
  "$ROOT/rootfs/usr/lib/ark-desktop/ark-agentctl.py" \
  && pass "desktop Python syntax" || fail "desktop Python syntax"

PKGS="$ROOT/config/packages.x86_64"
for pkg in gtk4 gtk4-layer-shell python-gobject thunar firefox; do
  grep -qxF "$pkg" "$PKGS" || fail "package missing: $pkg"
done
for pkg in waybar wofi; do
  grep -qxF "$pkg" "$PKGS" && fail "obsolete scaffold package still declared: $pkg"
done
[[ "$FAIL" -eq 0 ]] && pass "desktop package declarations"

AUTO="$ROOT/rootfs/etc/skel/.config/labwc/autostart"
grep -q 'ark-desktop-start' "$AUTO" && pass "Labwc starts ARK desktop session" || fail "Labwc does not start ARK desktop session"
if grep -Eq 'waybar|(^|[[:space:]])foot[[:space:]]*&' "$AUTO"; then
  fail "temporary Waybar/Foot scaffold still autostarts"
else
  pass "temporary desktop scaffold removed"
fi

STARTER="$ROOT/rootfs/usr/local/bin/ark-desktop-start"
if grep -q 'STATE_DIR=.*ark-desktop' "$STARTER" && grep -q 'session.log' "$STARTER"; then
  pass "desktop startup logging enabled"
else
  fail "desktop startup logging missing"
fi

SHELL="$ROOT/rootfs/usr/lib/ark-desktop/ark-shell.py"
grep -q 'CDLL("libgtk4-layer-shell.so")' "$SHELL" && pass "GTK4 Layer Shell preloaded" || fail "GTK4 Layer Shell preload missing"

PATCHER="$ROOT/scripts/patch-desktop-image.sh"
grep -q '/home/operator/.config/labwc/autostart' "$PATCHER" && pass "existing operator session is patched" || fail "operator Labwc session patch missing"

ROOTD="$ROOT/rootfs/usr/lib/ark-desktop/ark-rootd.py"
grep -q 'socket.AF_UNIX' "$ROOTD" || fail "root broker is not Unix-socket based"
grep -q '/run/ark-desktop/root.sock' "$ROOTD" || fail "root broker socket path missing"
grep -q 'SO_PEERCRED' "$ROOTD" || fail "root broker peer credential check missing"
grep -q 'WHEEL_GID' "$ROOTD" || fail "root broker wheel authorization missing"
if grep -q 'return run(req.get("argv")' "$ROOTD"; then
  fail "unrestricted argv execution returned to root broker"
fi
if grep -q 'if op == "read_file"' "$ROOTD" || grep -q 'if op == "write_file"' "$ROOTD"; then
  fail "arbitrary privileged file API returned to root broker"
fi
grep -q 'named_exec_compat' "$ROOTD" || fail "bounded legacy request mapper missing"
grep -q 'arbitrary argv execution is not exposed' "$ROOTD" || fail "root broker does not explicitly reject arbitrary argv"
for op in runtime_read unit_state journal service set_hostname wifi_radio hardware_rescan power; do
  grep -q "op == \"$op\"" "$ROOTD" || fail "named root operation missing: $op"
done
for unit in ark-runtime-api.service ark-local-api.service ark-trading.service ark-hardwared.service; do
  grep -q "\"$unit\"" "$ROOTD" || fail "canonical unit not broker-allowlisted: $unit"
done
for fake in ark-kyle.service ark-joey.service ark-hrm.service ark-kenny.service; do
  grep -q "\"$fake\"" "$ROOTD" && fail "heartbeat agent still exposed by broker: $fake"
done
grep -qF '"/run/arklinux/hardware.json"' "$ROOTD" || fail "ARKlinux hardware telemetry path missing"
if grep -qF '"/run/ark/hardware.json"' "$ROOTD"; then
  fail "ARKlinux hardware telemetry still collides with A.R.K. /run state"
fi
[[ "$FAIL" -eq 0 ]] && pass "local constrained privilege broker structure"

SERVICE="$ROOT/rootfs/etc/systemd/system/ark-desktop-rootd.service"
grep -q '^User=root$' "$SERVICE" || fail "root broker service is not root"
for rule in 'NoNewPrivileges=yes' 'ProtectSystem=strict' 'ProtectHome=read-only' 'RestrictAddressFamilies=AF_UNIX AF_NETLINK'; do
  grep -q "^${rule}$" "$SERVICE" || fail "root broker hardening missing: $rule"
done
[[ "$FAIL" -eq 0 ]] && pass "root broker systemd hardening"

DROPIN="$ROOT/rootfs/etc/systemd/system/greetd.service.d/ark-desktop.conf"
grep -q 'ark-desktop-rootd.service' "$DROPIN" && pass "graphical login requires root broker" || fail "greetd/root broker dependency missing"

AGENTCTL="$ROOT/rootfs/usr/lib/ark-desktop/ark-agentctl.py"
AGENTAPP="$ROOT/rootfs/usr/share/applications/ark-agents.desktop"
for required_text in \
  'http://127.0.0.1:18080' \
  '"/health"' \
  '"/status"' \
  '"/contract"' \
  '"/bus/events"' \
  'ark-runtime-api.service' \
  'ark-trading.service' \
  'logical stages, not fake per-agent daemons' \
  'Last terminal outcome' \
  'blocker_demonstrated' \
  'evidence_level' \
  'premature_stop' \
  'unknown_internal' \
  'provider_reported' \
  'USER ACTION' \
  '/run/arklinux/hardware.json'; do
  grep -qF "$required_text" "$AGENTCTL" || fail "canonical runtime console missing: $required_text"
done
for fake in ark-kyle.service ark-joey.service ark-hrm.service ark-kenny.service; do
  grep -q "$fake" "$AGENTCTL" && fail "agent console still models heartbeat daemon: $fake"
done
if grep -q '"op": "exec"' "$AGENTCTL" || grep -q '"op": "read_file"' "$AGENTCTL"; then
  fail "runtime console still depends on generic privileged operations"
fi
if grep -qF '/run/ark/hardware.json' "$AGENTCTL"; then
  fail "runtime console still reads ARKlinux host telemetry from A.R.K. runtime state"
fi
if grep -q 'Name=A.R.K. Agent Console' "$AGENTAPP" && grep -q '/usr/lib/ark-desktop/ark-agentctl.py' "$AGENTAPP"; then
  pass "A.R.K. runtime console registered in launcher"
else
  fail "A.R.K. runtime console launcher missing"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "ARKlinux desktop static verification: FAIL" >&2
  exit 1
fi

echo "ARKlinux desktop static verification: PASS"
