# ARKlinux Native Desktop v0.1

This is the first ARKlinux-owned graphical desktop layer. It deliberately keeps Labwc as the proven Wayland compositor while replacing the temporary Waybar/automatic-Foot scaffold with ARKlinux-native GTK4 shell surfaces.

## Navigation model

The interaction model is lightweight and modular like XFCE with Windows 7-style navigation concepts, without copying Microsoft artwork or branding:

- persistent desktop background
- ARKlinux-specific SVG icon set
- bottom navigation/task bar
- ARK/start button
- program/settings search field
- popup launcher window
- Files, Browser, Terminal and Settings launchers
- A.R.K. service state and clock
- Settings window with System, Hardware, Network, Audio and Appearance sections

## Operating-system authority

The visible desktop runs in the logged-in graphical session. Privileged actions are delegated to `ark-desktop-rootd.service` over `/run/ark-desktop/root.sock`.

The broker runs as UID 0 and accepts requests only from local processes with wheel-group membership. It is deliberately not a root shell. The protocol exposes only named, validated capabilities: approved service start/stop/restart, bounded service state and journal reads, specific `/run/ark` state files, hostname changes, Wi-Fi radio control, udev rescan, reboot, and poweroff. Arbitrary command execution, arbitrary root file reads, and arbitrary root file writes are rejected. Requests are recorded in `/var/log/ark-desktop/rootd.log`.

The initial GTK desktop still emits three legacy `exec`-shaped requests for hostname, Wi-Fi, and udev rescan. Protocol v2 treats those only as a compatibility encoding: `ark-rootd` exact-matches them to the corresponding named capability and rejects every other argv. New code must use named operations directly.

This boundary follows the ARKlinux rule that operator authority is explicit but privileged execution remains attributable and structurally bounded. Adding a new graphical privilege requires adding and validating a new protocol operation; it does not expand a generic shell escape hatch.

## Current graphical controls

The first implementation exposes:

- hostname changes
- A.R.K./NetworkManager/nftables/SSH service state and restart controls
- reboot and shutdown
- CPU information
- block-device information
- PCI devices
- USB devices
- hardware sensors
- udev device rescan
- Wi-Fi radio control
- network-device state
- PipeWire output volume

## Browser boundary

Firefox is included as the initial conventional browser. It is not the future ARK Browser. Browser processes are untrusted relative to the privileged desktop broker. Remote web content must never be converted directly into a root-broker request, and future browser/A.R.K. integration must pass through the normal A.R.K. authority, evidence, policy, and execution path.

## Next increments

- real running-window/task tracking in the bottom bar
- notification center/system tray
- removable-device controls
- display and GPU controls
- storage management
- network connection picker
- Bluetooth controls
- background/theme chooser
- richer file search
- recovery and snapshot UI
- ARK Browser with Kyle navigation and Joey analysis
- remove the three protocol-v1 compatibility request shapes after the GTK callers are migrated
- later 3D avatars/world surfaces
