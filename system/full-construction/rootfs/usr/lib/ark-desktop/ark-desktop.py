#!/usr/bin/env python3
import json
import socket
import subprocess
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Gtk4LayerShell

APP_ID = "world.1true.arklinux.Desktop"
SOCKET_PATH = "/run/ark-desktop/root.sock"
RUNTIME_URL = "http://127.0.0.1:18080"
ASSET_DIR = Path("/usr/share/ark-desktop/icons")

CSS = r"""
window.ark-background {
  background: linear-gradient(145deg, #07111f 0%, #0b2440 42%, #123c5c 72%, #081421 100%);
}
.ark-brand { color: rgba(236,247,255,.92); font-size: 42px; font-weight: 700; }
.ark-subtitle { color: rgba(210,231,244,.70); font-size: 13px; }
.ark-panel {
  background: linear-gradient(to bottom, rgba(35,55,72,.97), rgba(12,23,35,.98));
  border-top: 1px solid rgba(173,217,244,.32);
}
.ark-start {
  background: linear-gradient(to bottom, #2c9a73, #146047);
  border-radius: 20px;
  min-width: 44px;
  min-height: 36px;
}
.ark-task {
  background: rgba(255,255,255,.07);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 6px;
  min-width: 42px;
  min-height: 36px;
}
.ark-search { border-radius: 7px; min-height: 34px; }
.ark-clock { color: #e9f4fb; padding-left: 12px; padding-right: 12px; }
.desktop-icon { background: transparent; border: 0; color: white; padding: 8px; }
.desktop-icon:hover { background: rgba(120,190,230,.16); border-radius: 8px; }
.launcher-title { font-size: 24px; font-weight: 700; }
.section-title { font-size: 17px; font-weight: 700; }
"""


def run(argv, timeout=8):
    try:
        return subprocess.run(argv, text=True, capture_output=True, timeout=timeout)
    except Exception as exc:
        class Result:
            returncode = 1
            stdout = ""
            stderr = str(exc)
        return Result()


def spawn(argv):
    try:
        subprocess.Popen(argv, start_new_session=True)
    except Exception:
        pass


def runtime_get(path, timeout=2):
    request = urllib.request.Request(RUNTIME_URL + path, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def root_call(payload, timeout=65):
    data = (json.dumps(payload) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(SOCKET_PATH)
        sock.sendall(data)
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    return json.loads(buf.split(b"\n", 1)[0].decode())


def icon_picture(name, size=28):
    pic = Gtk.Picture.new_for_filename(str(ASSET_DIR / f"{name}.svg"))
    pic.set_content_fit(Gtk.ContentFit.CONTAIN)
    pic.set_size_request(size, size)
    return pic


def layer_window(win, layer, *, top=False, bottom=False, left=False, right=False, exclusive=False):
    Gtk4LayerShell.init_for_window(win)
    Gtk4LayerShell.set_layer(win, layer)
    Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP, top)
    Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, bottom)
    Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT, left)
    Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT, right)
    Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.NONE)
    if exclusive:
        Gtk4LayerShell.auto_exclusive_zone_enable(win)


class ArkDesktop(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.background = None
        self.panel = None
        self.launcher = None
        self.settings = None
        self.apps = []
        self.hardware_text = None
        self.service_rows = {}

    def do_activate(self):
        self.install_css()
        self.apps = sorted(
            [a for a in Gio.AppInfo.get_all() if a.should_show() and a.get_display_name()],
            key=lambda a: a.get_display_name().lower(),
        )
        self.make_background()
        self.make_panel()

    def install_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def make_background(self):
        win = Gtk.ApplicationWindow(application=self)
        win.add_css_class("ark-background")
        win.set_title("ARKlinux Desktop")
        layer_window(win, Gtk4LayerShell.Layer.BACKGROUND, top=True, bottom=True, left=True, right=True)

        overlay = Gtk.Overlay()
        win.set_child(overlay)

        center = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        center.set_halign(Gtk.Align.CENTER)
        center.set_valign(Gtk.Align.CENTER)
        brand = Gtk.Label(label="ARKlinux")
        brand.add_css_class("ark-brand")
        subtitle = Gtk.Label(label="local • sovereign • operator controlled")
        subtitle.add_css_class("ark-subtitle")
        center.append(brand)
        center.append(subtitle)
        overlay.set_child(center)

        icons = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        icons.set_halign(Gtk.Align.START)
        icons.set_valign(Gtk.Align.START)
        icons.set_margin_top(28)
        icons.set_margin_start(22)
        for name, label, callback in (
            ("computer", "Computer", lambda *_: self.open_settings("Hardware")),
            ("files", "Files", lambda *_: spawn(["thunar"])),
            ("browser", "Browser", lambda *_: spawn(["firefox"])),
            ("settings", "Settings", lambda *_: self.open_settings()),
        ):
            icons.append(self.desktop_button(name, label, callback))
        overlay.add_overlay(icons)
        win.present()
        self.background = win

    def desktop_button(self, icon, label, callback):
        btn = Gtk.Button()
        btn.add_css_class("desktop-icon")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.append(icon_picture(icon, 48))
        box.append(Gtk.Label(label=label))
        btn.set_child(box)
        btn.connect("clicked", callback)
        return btn

    def make_panel(self):
        win = Gtk.ApplicationWindow(application=self)
        win.add_css_class("ark-panel")
        win.set_title("ARKlinux Navigation")
        layer_window(win, Gtk4LayerShell.Layer.TOP, bottom=True, left=True, right=True, exclusive=True)
        win.set_default_size(1200, 50)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for attr, value in (("top", 5), ("bottom", 5), ("start", 7), ("end", 7)):
            getattr(bar, f"set_margin_{attr}")(value)
        win.set_child(bar)

        start = Gtk.Button()
        start.add_css_class("ark-start")
        start.set_tooltip_text("ARK menu")
        start.set_child(icon_picture("ark", 26))
        start.connect("clicked", lambda *_: self.open_launcher())
        bar.append(start)

        search = Gtk.SearchEntry()
        search.add_css_class("ark-search")
        search.set_placeholder_text("Search programs and settings")
        search.set_size_request(330, -1)
        search.connect("activate", self.panel_search_activate)
        bar.append(search)

        for icon, tip, argv in (
            ("files", "Files", ["thunar"]),
            ("browser", "Browser", ["firefox"]),
            ("terminal", "Terminal", ["foot"]),
        ):
            btn = Gtk.Button()
            btn.add_css_class("ark-task")
            btn.set_tooltip_text(tip)
            btn.set_child(icon_picture(icon, 24))
            btn.connect("clicked", lambda _b, command=argv: spawn(command))
            bar.append(btn)

        settings = Gtk.Button()
        settings.add_css_class("ark-task")
        settings.set_tooltip_text("Settings")
        settings.set_child(icon_picture("settings", 24))
        settings.connect("clicked", lambda *_: self.open_settings())
        bar.append(settings)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        bar.append(spacer)
        status = Gtk.Label(label="ARK …")
        status.set_tooltip_text("A.R.K. runtime state has not been read yet")
        bar.append(status)
        clock = Gtk.Label()
        clock.add_css_class("ark-clock")
        bar.append(clock)

        def update_clock():
            clock.set_text(datetime.now().strftime("%a %b %-d   %-I:%M %p"))
            try:
                payload = runtime_get("/status", 2)
                health = payload.get("health") or {}
                outcomes = payload.get("outcomes") or {}
                outcome = outcomes.get("last_outcome") or {}
                classification = str(outcome.get("classification") or "none")
                evidence = str(outcome.get("evidence_level") or "none")
                blocker = bool(outcome.get("blocker_demonstrated"))
                user_action = bool(outcome.get("user_action_required"))
                ready = bool(health.get("ready", health.get("alive", False)))
                if classification in {"premature_stop", "reasoning_failure", "unknown_internal", "dependency_failure"}:
                    marker = "!"
                elif classification in {"technical_limit", "tool_unavailable", "context_degraded", "product_limit", "policy_intervention", "authority_denied", "input_invalid"}:
                    marker = "◐"
                else:
                    marker = "●" if ready else "○"
                status.set_text(f"ARK {marker}")
                summary = str(outcome.get("summary") or "No terminal outcome recorded yet.")
                action_text = str(outcome.get("user_action") or "none") if user_action else "none"
                status.set_tooltip_text(
                    "A.R.K. runtime: {}\nLast outcome: {}\nEvidence: {}\nBlocker demonstrated: {}\nUser action: {}\n{}".format(
                        "ready" if ready else "degraded",
                        classification,
                        evidence,
                        "yes" if blocker else "no",
                        action_text,
                        summary,
                    )
                )
            except Exception as exc:
                status.set_text("ARK ?")
                status.set_tooltip_text(f"A.R.K. status unavailable. Cause not inferred.\n{type(exc).__name__}: {exc}")
            return True

        update_clock()
        GLib.timeout_add_seconds(10, update_clock)
        win.present()
        self.panel = win

    def panel_search_activate(self, entry):
        text = entry.get_text().strip()
        self.open_launcher(text)
        entry.set_text("")

    def open_launcher(self, initial=""):
        if self.launcher is None:
            win = Gtk.ApplicationWindow(application=self)
            win.set_title("ARK")
            win.set_default_size(640, 560)
            root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            for attr in ("top", "bottom", "start", "end"):
                getattr(root, f"set_margin_{attr}")(16)
            win.set_child(root)
            title = Gtk.Label(label="ARK")
            title.set_halign(Gtk.Align.START)
            title.add_css_class("launcher-title")
            root.append(title)
            search = Gtk.SearchEntry()
            search.set_placeholder_text("Search programs and files")
            root.append(search)

            quick = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            for text, cb in (
                ("Settings", lambda *_: self.open_settings()),
                ("Hardware", lambda *_: self.open_settings("Hardware")),
                ("Restart", lambda *_: self.confirm_power("reboot")),
                ("Shut down", lambda *_: self.confirm_power("poweroff")),
            ):
                b = Gtk.Button(label=text)
                b.connect("clicked", cb)
                quick.append(b)
            root.append(quick)

            scroll = Gtk.ScrolledWindow()
            scroll.set_vexpand(True)
            app_list = Gtk.ListBox()
            app_list.set_selection_mode(Gtk.SelectionMode.NONE)
            scroll.set_child(app_list)
            root.append(scroll)
            win._ark_search = search
            win._ark_app_list = app_list
            search.connect("search-changed", lambda e: self.populate_apps(e.get_text()))
            self.launcher = win

        self.launcher._ark_search.set_text(initial)
        self.populate_apps(initial)
        self.launcher.present()
        self.launcher._ark_search.grab_focus()

    def populate_apps(self, query):
        box = self.launcher._ark_app_list
        child = box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt
        q = query.strip().lower()
        matches = []
        for app in self.apps:
            name = app.get_display_name()
            desc = app.get_description() or ""
            if not q or q in name.lower() or q in desc.lower():
                matches.append(app)
            if len(matches) >= 32:
                break
        for app in matches:
            row = Gtk.Button()
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
            name = Gtk.Label(label=app.get_display_name())
            name.set_halign(Gtk.Align.START)
            desc = Gtk.Label(label=app.get_description() or app.get_executable() or "")
            desc.set_halign(Gtk.Align.START)
            desc.add_css_class("dim-label")
            content.append(name)
            content.append(desc)
            row.set_child(content)
            row.connect("clicked", lambda _b, a=app: self.launch_app(a))
            box.append(row)

    def launch_app(self, app):
        try:
            app.launch([], None)
            self.launcher.hide()
        except Exception:
            pass

    def open_settings(self, page=None):
        if self.settings is None:
            self.settings = self.build_settings()
        if page:
            labels = ["System", "Hardware", "Network", "Audio", "Appearance"]
            if page in labels:
                self.settings._ark_notebook.set_current_page(labels.index(page))
        self.refresh_settings()
        self.settings.present()

    def build_settings(self):
        win = Gtk.ApplicationWindow(application=self)
        win.set_title("ARKlinux Settings")
        win.set_default_size(880, 620)
        notebook = Gtk.Notebook()
        win.set_child(notebook)
        win._ark_notebook = notebook
        notebook.append_page(self.system_page(), Gtk.Label(label="System"))
        notebook.append_page(self.hardware_page(), Gtk.Label(label="Hardware"))
        notebook.append_page(self.network_page(), Gtk.Label(label="Network"))
        notebook.append_page(self.audio_page(), Gtk.Label(label="Audio"))
        notebook.append_page(self.appearance_page(), Gtk.Label(label="Appearance"))
        return win

    def page_box(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for attr in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{attr}")(18)
        return box

    def system_page(self):
        box = self.page_box()
        title = Gtk.Label(label="Operating system")
        title.set_halign(Gtk.Align.START)
        title.add_css_class("section-title")
        box.append(title)
        hostrow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hostrow.append(Gtk.Label(label="Computer name"))
        hostname = Gtk.Entry()
        hostname.set_hexpand(True)
        hostname.set_text(run(["hostname"], 2).stdout.strip())
        hostrow.append(hostname)
        apply_host = Gtk.Button(label="Apply")
        apply_host.connect("clicked", lambda *_: self.set_hostname(hostname.get_text()))
        hostrow.append(apply_host)
        box.append(hostrow)
        self._hostname_entry = hostname
        box.append(Gtk.Separator())

        services_title = Gtk.Label(label="Core services")
        services_title.set_halign(Gtk.Align.START)
        services_title.add_css_class("section-title")
        box.append(services_title)
        for unit in (
            "ark.target",
            "ark-runtime-api.service",
            "ark-trading.service",
            "ark-hardwared.service",
            "NetworkManager.service",
            "nftables.service",
            "sshd.service",
        ):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            label = Gtk.Label(label=unit)
            label.set_hexpand(True)
            label.set_halign(Gtk.Align.START)
            state = Gtk.Label(label="unknown")
            restart = Gtk.Button(label="Restart")
            restart.connect("clicked", lambda _b, u=unit: self.service_action(u, "restart"))
            row.append(label)
            row.append(state)
            row.append(restart)
            box.append(row)
            self.service_rows[unit] = state

        box.append(Gtk.Separator())
        power = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        reboot = Gtk.Button(label="Restart computer")
        off = Gtk.Button(label="Shut down")
        reboot.connect("clicked", lambda *_: self.confirm_power("reboot"))
        off.connect("clicked", lambda *_: self.confirm_power("poweroff"))
        power.append(reboot)
        power.append(off)
        box.append(power)
        return box

    def hardware_page(self):
        box = self.page_box()
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title = Gtk.Label(label="Hardware")
        title.set_hexpand(True)
        title.set_halign(Gtk.Align.START)
        title.add_css_class("section-title")
        refresh = Gtk.Button(label="Refresh")
        refresh.connect("clicked", lambda *_: self.refresh_hardware())
        rescan = Gtk.Button(label="Rescan devices")
        rescan.connect("clicked", lambda *_: self.root_exec(["udevadm", "trigger", "--action=change"]))
        head.append(title)
        head.append(refresh)
        head.append(rescan)
        box.append(head)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        text = Gtk.TextView()
        text.set_editable(False)
        text.set_monospace(True)
        scroll.set_child(text)
        box.append(scroll)
        self.hardware_text = text
        return box

    def network_page(self):
        box = self.page_box()
        title = Gtk.Label(label="Network")
        title.set_halign(Gtk.Align.START)
        title.add_css_class("section-title")
        box.append(title)
        wifirow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        wifi_label = Gtk.Label(label="Wi-Fi radio")
        wifi_label.set_hexpand(True)
        wifi_label.set_halign(Gtk.Align.START)
        wifi = Gtk.Switch()
        wifi.connect("state-set", self.wifi_changed)
        wifirow.append(wifi_label)
        wifirow.append(wifi)
        box.append(wifirow)
        self._wifi_switch = wifi
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        text = Gtk.TextView()
        text.set_editable(False)
        text.set_monospace(True)
        scroll.set_child(text)
        box.append(scroll)
        self._network_text = text
        return box

    def audio_page(self):
        box = self.page_box()
        title = Gtk.Label(label="Audio")
        title.set_halign(Gtk.Align.START)
        title.add_css_class("section-title")
        box.append(title)
        label = Gtk.Label(label="Output volume")
        label.set_halign(Gtk.Align.START)
        box.append(label)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        scale.set_hexpand(True)
        scale.connect("value-changed", self.volume_changed)
        box.append(scale)
        self._volume_scale = scale
        return box

    def appearance_page(self):
        box = self.page_box()
        title = Gtk.Label(label="Appearance")
        title.set_halign(Gtk.Align.START)
        title.add_css_class("section-title")
        box.append(title)
        note = Gtk.Label(label="ARKlinux v0.1 uses the native dark-blue glass shell. Theme, wallpaper and icon-set selection will expand here.")
        note.set_wrap(True)
        note.set_halign(Gtk.Align.START)
        box.append(note)
        return box

    def refresh_settings(self):
        for unit, label in self.service_rows.items():
            result = run(["systemctl", "is-active", unit], 2)
            label.set_text(result.stdout.strip() or "inactive")
        self.refresh_hardware()
        radio = run(["nmcli", "radio", "wifi"], 2).stdout.strip().lower()
        if hasattr(self, "_wifi_switch"):
            self._wifi_switch.set_active(radio == "enabled")
        if hasattr(self, "_network_text"):
            net = run(["nmcli", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"], 3)
            self._network_text.get_buffer().set_text(net.stdout or net.stderr)
        if hasattr(self, "_volume_scale"):
            vol = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], 2).stdout
            try:
                self._volume_scale.set_value(float(vol.split()[1]) * 100)
            except Exception:
                pass

    def refresh_hardware(self):
        if not self.hardware_text:
            return
        chunks = []
        for title, argv in (
            ("CPU", ["lscpu"]),
            ("BLOCK DEVICES", ["lsblk", "-o", "NAME,SIZE,TYPE,FSTYPE,MODEL,MOUNTPOINTS"]),
            ("PCI", ["lspci"]),
            ("USB", ["lsusb"]),
            ("SENSORS", ["sensors"]),
        ):
            result = run(argv, 5)
            chunks.append(f"=== {title} ===\n{result.stdout or result.stderr}")
        self.hardware_text.get_buffer().set_text("\n\n".join(chunks))

    def root_exec(self, argv):
        try:
            return root_call({"op": "exec", "argv": argv})
        except Exception:
            return None

    def service_action(self, unit, action):
        try:
            root_call({"op": "service", "unit": unit, "action": action}, 130)
        except Exception:
            pass
        GLib.timeout_add(500, lambda: (self.refresh_settings(), False)[1])

    def set_hostname(self, hostname):
        hostname = hostname.strip()
        if hostname and not any(c.isspace() for c in hostname):
            self.root_exec(["hostnamectl", "set-hostname", hostname])

    def wifi_changed(self, _switch, state):
        self.root_exec(["nmcli", "radio", "wifi", "on" if state else "off"])
        return False

    def volume_changed(self, scale):
        value = max(0.0, min(scale.get_value() / 100.0, 1.5))
        run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value:.2f}"], 2)

    def confirm_power(self, action):
        win = Gtk.ApplicationWindow(application=self)
        win.set_title("Confirm")
        win.set_default_size(380, 150)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for attr in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{attr}")(18)
        verb = "restart" if action == "reboot" else "shut down"
        box.append(Gtk.Label(label=f"Do you want to {verb} ARKlinux?"))
        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        cancel = Gtk.Button(label="Cancel")
        proceed = Gtk.Button(label=verb.capitalize())
        cancel.connect("clicked", lambda *_: win.close())
        proceed.connect("clicked", lambda *_: self.power_action(action, win))
        buttons.append(cancel)
        buttons.append(proceed)
        box.append(buttons)
        win.set_child(box)
        win.present()

    def power_action(self, action, dialog):
        try:
            root_call({"op": "power", "action": action}, 15)
        except Exception:
            pass
        dialog.close()


def main():
    app = ArkDesktop()
    raise SystemExit(app.run(None))


if __name__ == "__main__":
    main()
