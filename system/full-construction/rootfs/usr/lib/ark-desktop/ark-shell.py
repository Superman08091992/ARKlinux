#!/usr/bin/env python3
"""ARKlinux shell bootstrap.

Keeps the desktop implementation importable while applying compositor-specific
layer-shell policy in one small bootstrap: the background never takes keyboard
focus, while the exclusive bottom panel may request it for the search field.
"""
import importlib.util

SPEC = importlib.util.spec_from_file_location(
    "ark_desktop_impl", "/usr/lib/ark-desktop/ark-desktop.py"
)
impl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(impl)


def layer_window(win, layer, *, top=False, bottom=False, left=False, right=False, exclusive=False):
    ls = impl.Gtk4LayerShell
    ls.init_for_window(win)
    ls.set_layer(win, layer)
    ls.set_anchor(win, ls.Edge.TOP, top)
    ls.set_anchor(win, ls.Edge.BOTTOM, bottom)
    ls.set_anchor(win, ls.Edge.LEFT, left)
    ls.set_anchor(win, ls.Edge.RIGHT, right)
    ls.set_keyboard_mode(
        win,
        ls.KeyboardMode.ON_DEMAND if exclusive else ls.KeyboardMode.NONE,
    )
    if exclusive:
        ls.auto_exclusive_zone_enable(win)


impl.layer_window = layer_window
impl.main()
