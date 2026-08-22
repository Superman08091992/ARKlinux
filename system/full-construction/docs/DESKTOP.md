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
- ARK service state and clock
- Settings window with System, Hardware, Network, Audio and Appearance sections

## Operating-system authority

The visible desktop runs in the logged-in graphical session. Privileged actions are delegated to `ark-desktop-rootd.service` over `/run/ark-desktop/root.sock`.

The broker runs as UID 0 and accepts requests only from local processes with wheel-group membership. It supports an unrestricted argv execution operation as the backend override mechanism, plus explicit service, power, file-read and file-write operations. Requests are written to `/var/log/ark-desktop-rootd.log`.

There is intentionally no general command-entry terminal embedded in the desktop UI. The graphical settings and control surfaces invoke the privileged backend directly.

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

The backend can perform additional root operations as later settings panels are added.

## Browser boundary

Firefox is included as the initial conventional browser. It is not the future ARK Browser. Before browser content receives deep A.R.K. integration, browser processes should be isolated from the desktop root-control channel in a separate sandbox/security domain. Remote web content must never be treated as a trusted desktop-control request.

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
- later 3D avatars/world surfaces
