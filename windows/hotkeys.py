"""The keys that reach Longhand from anywhere, on Windows.

On Omarchy these are Hyprland's (plugin-page/hyprkeys.py): Super+Alt+= for
the page over everything, Super+Alt+\\ for the page as a window, and the
timer's two. Here Windows keeps them (RegisterHotKey), under the same names
with Win for Super:

    page         Win+Alt+=     the page over everything, and away again
    alongside    Win+Alt+\\     the page as a window
    pomoToggle   Win+Alt+P     the timer: start, pause, resume
    pomoSkip     Win+Alt+N     the timer: on to the next phase
    pomoPopup    Win+Alt+O     the timer's popup, by the clock
    deadlines    Win+Alt+D     the deadlines' popup

A key is written as the page writes one ("Alt+Win+=", any order, Super for
Win). `<config>/longhand/windows-keys.json` moves them — {"page": "Win+F9"},
several as a list — or, with "", leaves an action without one. The keys
sheet in the page (Ctrl+/) writes it (winkeys.py), and the running Longhand
takes what is written at once. As with Hyprland's, a key must
hold Win: one without could take a key an app needs. A key Windows or
another program already has is not taken; `problems` says which.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes

from PySide6.QtCore import QAbstractNativeEventFilter

# The keys themselves — their defaults, the file, how one is read — are
# winkeys.py's, which the keys sheet moves them with and the agent's manual
# reads them from.
from winkeys import DEFAULTS, NAMED, NOREPEAT, keys_file, parse, shown, wanted, words  # noqa: F401

WM_HOTKEY = 0x0312


class Keys(QAbstractNativeEventFilter):
    """Registers the keys with Windows and hears them: `on_key(action id)`."""

    def __init__(self, on_key):
        super().__init__()
        self.on_key = on_key
        self.user32 = ctypes.WinDLL("user32", use_last_error=True)
        self.ids: dict[int, str] = {}
        self.held: dict[str, str] = {}          # action -> the key Windows keeps for it
        self.problems: dict[str, str] = {}      # action -> why it has none
        self.on_register = None                 # told each time the keys are taken again

    def register(self) -> None:
        self.release()
        n = 0x4C48
        for action, keys in wanted().items():
            for key in keys:
                n += 1
                got = parse(key)
                if not got:
                    self.problems[action] = f"{key!r} is not a key Windows can keep (it must hold Win)"
                elif not self.user32.RegisterHotKey(None, n, got[0] | NOREPEAT, got[1]):
                    self.problems[action] = f"{shown(key)} is taken by Windows or another program"
                else:
                    self.ids[n] = action
                    self.held.setdefault(action, shown(key))     # the menu says the first
        if self.on_register:
            self.on_register()

    def release(self) -> None:
        for n in self.ids:
            self.user32.UnregisterHotKey(None, n)
        self.ids, self.held, self.problems = {}, {}, {}

    def nativeEventFilter(self, event_type, message):
        if bytes(event_type) == b"windows_generic_MSG":
            msg = wintypes.MSG.from_address(int(message))
            if msg.message == WM_HOTKEY and msg.wParam in self.ids:
                self.on_key(self.ids[msg.wParam])
                return True, 0
        return False, 0
