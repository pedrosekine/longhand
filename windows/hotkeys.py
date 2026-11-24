"""The keys that reach Longhand from anywhere, on Windows.

On Omarchy these are Hyprland's (plugin-page/hyprkeys.py): Super+Alt+= for
the page over everything, Super+Alt+\\ for the page as a window, and the
timer's two. Here Windows keeps them (RegisterHotKey), under the same names
with Win for Super:

    page         Win+Alt+=     the page over everything, and away again
    alongside    Win+Alt+\\     the page as a window
    pomoToggle   Win+Alt+P     the timer: start, pause, resume
    pomoSkip     Win+Alt+N     the timer: on to the next phase

A key is written as the page writes one ("Alt+Win+=", any order, Super for
Win). `<config>/longhand/windows-keys.json` moves them — {"page": "Win+F9"} —
or, with "", leaves an action without one. As with Hyprland's, a key must
hold Win: one without could take a key an app needs. A key Windows or
another program already has is not taken; `problems` says which.
"""
from __future__ import annotations

import ctypes
import json
import os
from ctypes import wintypes
from pathlib import Path

from PySide6.QtCore import QAbstractNativeEventFilter

DEFAULTS = {"page": "Win+Alt+=", "alongside": "Win+Alt+\\", "pomoToggle": "Win+Alt+P", "pomoSkip": "Win+Alt+N"}
MODS = {"alt": 0x1, "ctrl": 0x2, "control": 0x2, "shift": 0x4, "win": 0x8, "super": 0x8, "meta": 0x8}
NAMED = {"=": 0xBB, "equal": 0xBB, "plus": 0xBB, "-": 0xBD, "minus": 0xBD, "\\": 0xDC, "backslash": 0xDC,
         ",": 0xBC, "comma": 0xBC, ".": 0xBE, "period": 0xBE, "/": 0xBF, "slash": 0xBF, ";": 0xBA, "semicolon": 0xBA,
         "'": 0xDE, "[": 0xDB, "]": 0xDD, "`": 0xC0, "space": 0x20, "enter": 0x0D, "return": 0x0D, "tab": 0x09,
         "home": 0x24, "end": 0x23, "pgup": 0x21, "pgdn": 0x22, "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
         "ins": 0x2D, "del": 0x2E}
WM_HOTKEY = 0x0312
NOREPEAT = 0x4000


def keys_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "longhand" / "windows-keys.json"


def wanted() -> dict[str, str]:
    """Each action's key: the person's, else its own."""
    keys = dict(DEFAULTS)
    try:
        mine = json.loads(keys_file().read_text(encoding="utf-8"))
        keys.update({k: str(v) for k, v in mine.items() if k in DEFAULTS})
    except (OSError, ValueError, AttributeError):
        pass
    return keys


def words(key: str) -> list[str]:
    """"Win+Alt+=" as its parts; a key written "Win+Alt++" ends in plus."""
    key = key.strip()
    if key.endswith("++"):
        return [p.strip() for p in key[:-2].split("+") if p.strip()] + ["plus"]
    return [p.strip() for p in key.split("+") if p.strip()]


def parse(key: str):
    """"Win+Alt+=" as (modifiers, virtual key), or None when it is no key
    Windows could keep for us."""
    parts = words(key)
    if not parts:
        return None
    mods, last = 0, parts[-1].lower()
    for p in parts[:-1]:
        if p.lower() not in MODS:
            return None
        mods |= MODS[p.lower()]
    if not mods & 0x8:
        return None                     # a key must hold Win
    if last in NAMED:
        return mods, NAMED[last]
    if len(last) == 1 and (last.isascii() and last.isalnum()):
        return mods, ord(last.upper())
    if last.startswith("f") and last[1:].isdigit() and 1 <= int(last[1:]) <= 24:
        return mods, 0x70 + int(last[1:]) - 1
    return None


def shown(key: str) -> str:
    """A key as a menu says it: Win, Ctrl, Alt, Shift, then the key."""
    got = parse(key)
    if not got:
        return ""
    last = words(key)[-1]
    last = "+" if last == "plus" else last
    mods = got[0]
    return "+".join([n for bit, n in ((0x8, "Win"), (0x2, "Ctrl"), (0x1, "Alt"), (0x4, "Shift")) if mods & bit]
                    + [last.upper() if len(last) == 1 else last.capitalize()])


class Keys(QAbstractNativeEventFilter):
    """Registers the keys with Windows and hears them: `on_key(action id)`."""

    def __init__(self, on_key):
        super().__init__()
        self.on_key = on_key
        self.user32 = ctypes.WinDLL("user32", use_last_error=True)
        self.ids: dict[int, str] = {}
        self.held: dict[str, str] = {}          # action -> the key Windows keeps for it
        self.problems: dict[str, str] = {}      # action -> why it has none

    def register(self) -> None:
        self.release()
        for n, (action, key) in enumerate(wanted().items(), start=0x4C48):
            if not key.strip():
                continue
            got = parse(key)
            if not got:
                self.problems[action] = f"{key!r} is not a key Windows can keep (it must hold Win)"
            elif not self.user32.RegisterHotKey(None, n, got[0] | NOREPEAT, got[1]):
                self.problems[action] = f"{shown(key)} is taken by Windows or another program"
            else:
                self.ids[n] = action
                self.held[action] = shown(key)

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
