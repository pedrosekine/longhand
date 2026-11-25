#!/usr/bin/env python3
"""winkeys — the six keys that reach Longhand from anywhere, on Windows,
kept by the page.

On Omarchy the keys sheet (Ctrl+/ in the page) lists Hyprland's six keys for
the page, the timer and the deadlines, and moves them through
plugin-page/hyprkeys.py. Here Windows keeps them (hotkeys.py registers them
with RegisterHotKey), and this answers the sheet in hyprkeys.py's own words,
so the page is the same page: the host sends the sheet's
`python3 …/hyprkeys.py <args>` here (qs_io.resolve).

    winkeys.py state
    winkeys.py adopt            (nothing to adopt: Longhand keeps these keys already)
    winkeys.py set <id> [--add] [--take] <key>...

The keys live in `<config>/longhand/windows-keys.json`, Longhand's own file
({"page": "Win+F9"}, several as a list, "" for none); only an action moved
off its own key is written there, so the file stays what a person would
write by hand, and can still be. The running Longhand watches it and takes
the new keys at once.

A key must hold Win, as Hyprland's hold Super: one without could take a key
an app needs. One that Windows or another program already has is refused
with that said (Windows lets no program take a key from another, so there
is no --take here; it is accepted and means nothing). A key one of the
other five has moves, as in hyprkeys.py.

Keys travel to and from the page as Shortcuts.js writes them,
"Alt+Super+=" — Super for Win.

A key is kept as its character, and Windows is given the key that types it
on the keyboard layout in use (`parse`), as Hyprland reads a keysym through
XKB's: "=" is not the same key on a German keyboard as on a US one.

What is shared with hotkeys.py (which needs Qt) lives here, so the agent's
manual can read the keys with nothing but Python.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "plugin-page"))
import hyprkeys  # noqa: E402  (the actions' ids and words, one list for both)

DEFAULTS = {"page": "Win+Alt+=", "alongside": "Win+Alt+\\", "pomoToggle": "Win+Alt+P", "pomoSkip": "Win+Alt+N",
            "pomoPopup": "Win+Alt+O", "deadlines": "Win+Alt+D"}
DOES = {aid: does for aid, does, _cmd, _key in hyprkeys.ACTIONS}
ORDER = [a[0] for a in hyprkeys.ACTIONS]

MODS = {"alt": 0x1, "ctrl": 0x2, "control": 0x2, "shift": 0x4, "win": 0x8, "super": 0x8, "meta": 0x8}
# Keys that are no character: the same key on every layout.
NAMED = {"space": 0x20, "enter": 0x0D, "return": 0x0D, "tab": 0x09, "home": 0x24, "end": 0x23, "pgup": 0x21,
         "pgdn": 0x22, "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28, "ins": 0x2D, "del": 0x2E}
# A symbol's word, as a key may be written by hand ("Win+Alt+equal").
CHARS = {"equal": "=", "plus": "+", "minus": "-", "backslash": "\\", "comma": ",", "period": ".", "slash": "/",
         "semicolon": ";"}
# A symbol is a key of the keyboard's layout, not of its own: "=" is the key
# right of 0 on a US keyboard, Shift+0 on a German one, and AltGr+ß types a
# German "\" where a US keyboard has a key of its own. So a symbol is asked
# of the layout being typed in (`scan`), and this, the US layout's, is only
# for a symbol that layout has not got at all, or where there is no Windows
# to ask: (modifiers it needs, virtual key).
US = {"=": (0, 0xBB), "+": (0x4, 0xBB), "-": (0, 0xBD), "_": (0x4, 0xBD), "\\": (0, 0xDC), "|": (0x4, 0xDC),
      ",": (0, 0xBC), "<": (0x4, 0xBC), ".": (0, 0xBE), ">": (0x4, 0xBE), "/": (0, 0xBF), "?": (0x4, 0xBF),
      ";": (0, 0xBA), ":": (0x4, 0xBA), "'": (0, 0xDE), '"': (0x4, 0xDE), "[": (0, 0xDB), "{": (0x4, 0xDB),
      "]": (0, 0xDD), "}": (0x4, 0xDD), "`": (0, 0xC0), "~": (0x4, 0xC0), "!": (0x4, 0x31), "@": (0x4, 0x32),
      "#": (0x4, 0x33), "$": (0x4, 0x34), "%": (0x4, 0x35), "^": (0x4, 0x36), "&": (0x4, 0x37), "*": (0x4, 0x38),
      "(": (0x4, 0x39), ")": (0x4, 0x30)}
# Windows' words for a key → the sheet's (Shortcuts.js).
SHEET_NAME = {"equal": "=", "plus": "Plus", "minus": "-", "backslash": "\\", "comma": ",", "period": ".",
              "slash": "/", "semicolon": ";", "space": "Space", "enter": "Enter", "return": "Enter", "tab": "Tab",
              "home": "Home", "end": "End", "pgup": "PgUp", "pgdn": "PgDn", "left": "Left", "up": "Up",
              "right": "Right", "down": "Down", "ins": "Ins", "del": "Del"}
# The sheet's → Windows' (what `parse` reads), where they differ.
WIN_NAME = {"Plus": "plus", "Space": "space", "Enter": "enter", "Tab": "tab", "Home": "home", "End": "end",
            "PgUp": "pgup", "PgDn": "pgdn", "Left": "left", "Up": "up", "Right": "right", "Down": "down",
            "Ins": "ins", "Del": "del"}
NOREPEAT = 0x4000


def keys_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "longhand" / "windows-keys.json"


def listed(v) -> list[str]:
    """A value of windows-keys.json as a list of keys: "" is none."""
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    return [str(v).strip()] if str(v).strip() else []


def mine() -> dict:
    try:
        d = json.loads(keys_file().read_text(encoding="utf-8"))
        return {k: v for k, v in d.items() if k in DEFAULTS} if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def wanted() -> dict[str, list[str]]:
    """Each action's keys, as Windows words them: the person's, else its own."""
    keys = {a: [k] for a, k in DEFAULTS.items()}
    keys.update({a: listed(v) for a, v in mine().items()})
    return keys


def words(key: str) -> list[str]:
    """"Win+Alt+=" as its parts; a key written "Win+Alt++" ends in plus."""
    key = key.strip()
    if key.endswith("++"):
        return [p.strip() for p in key[:-2].split("+") if p.strip()] + ["plus"]
    return [p.strip() for p in key.split("+") if p.strip()]


_user32 = None


def user32():
    global _user32
    if _user32 is None:
        import ctypes
        from ctypes import wintypes
        _user32 = ctypes.WinDLL("user32", use_last_error=True)
        _user32.GetForegroundWindow.restype = wintypes.HWND
        _user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.c_void_p]
        _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
        _user32.GetKeyboardLayout.argtypes = [wintypes.DWORD]
        _user32.GetKeyboardLayout.restype = wintypes.HKL
        _user32.VkKeyScanExW.argtypes = [wintypes.WCHAR, wintypes.HKL]
        _user32.VkKeyScanExW.restype = ctypes.c_short
    return _user32


def layout() -> int:
    """The keyboard layout a key pressed now is read in: the one of the
    window in front (Windows may keep a layout per window), else this
    program's; 0 where there is no Windows to ask."""
    if os.name != "nt":
        return 0
    u = user32()
    front = u.GetForegroundWindow()
    thread = u.GetWindowThreadProcessId(front, None) if front else 0
    return (u.GetKeyboardLayout(thread) if thread else 0) or u.GetKeyboardLayout(0) or 0


def vk_key_scan(ch: str, hkl: int) -> int:
    """Windows' VkKeyScanExW: the key that types `ch` on the layout `hkl`,
    its shift state in the high byte (1 Shift, 2 Ctrl, 4 Alt, so 6 is
    AltGr), -1 when the layout has no such key. The tests put a layout of
    their own here."""
    if os.name != "nt":
        return -1
    return user32().VkKeyScanExW(ch, hkl)


def char_key(ch: str, hkl: int | None = None):
    """The key that types `ch` on the layout, as (modifiers it needs,
    virtual key); the US layout's when this layout has no such key, and
    None when neither has, or it needs a shift no hot key can hold.

    A symbol that needs Shift or AltGr is kept with them: the person types
    "=" on a German keyboard as Shift+0, and Windows says AltGr is Ctrl+Alt,
    so Win+Alt+= is Win+Alt+Shift+0 there and Win+Alt+\\ Win+Ctrl+Alt+ß,
    the very keys pressed to type the symbol with Win and Alt held (and the
    keys the sheet heard, when it was the sheet that wrote them)."""
    got = vk_key_scan(ch, layout() if hkl is None else hkl)
    if got == -1 or got & 0xFF == 0xFF:
        return US.get(ch)
    state = (got >> 8) & 0xFF
    if state & ~0x7:
        return None                     # Kana, or a layout's own shift
    return (0x4 if state & 1 else 0) | (0x2 if state & 2 else 0) | (0x1 if state & 4 else 0), got & 0xFF


def parse(key: str, hkl: int | None = None):
    """"Win+Alt+=" as (modifiers, virtual key) on the keyboard layout `hkl`
    (the one typed in now when None), or None when it is no key Windows
    could keep for us.

    A letter A–Z and a digit are the keys Windows names after them on every
    layout (VK_A…, VK_0…), as Qt reads them with Ctrl or Alt held. A symbol
    is what the layout types it with, and carries no Shift of its own, as
    the sheet writes one ("Win+Alt+?", not "Win+Alt+Shift+/")."""
    parts = words(key)
    if not parts:
        return None
    mods, last = 0, parts[-1]
    for p in parts[:-1]:
        if p.lower() not in MODS:
            return None
        mods |= MODS[p.lower()]
    if not mods & 0x8:
        return None                     # a key must hold Win
    low = last.lower()
    if low in NAMED:
        return mods, NAMED[low]
    if low.startswith("f") and low[1:].isdigit() and 1 <= int(low[1:]) <= 24:
        return mods, 0x70 + int(low[1:]) - 1
    ch = CHARS.get(low, last)
    if len(ch) != 1:
        return None
    if ch.isascii() and ch.isalnum():
        return mods, ord(ch.upper())
    if ch.upper() == ch.lower():
        mods &= ~0x4                    # a symbol's Shift is the layout's to say
    else:
        ch = ch.lower()                 # ß, é: the letter's key, Shift as written
    got = char_key(ch, hkl)
    return (mods | got[0], got[1]) if got else None


def shown(key: str) -> str:
    """A key as a menu says it: Win, Ctrl, Alt, Shift, then the key."""
    if not parse(key):
        return ""
    last = words(key)[-1]
    last = "+" if last == "plus" else last
    mods = 0                            # as written: a German "=" is said "=", not "Shift+0"
    for p in words(key)[:-1]:
        mods |= MODS[p.lower()]
    if is_symbol(last):
        mods &= ~0x4
    return "+".join([n for bit, n in ((0x8, "Win"), (0x2, "Ctrl"), (0x1, "Alt"), (0x4, "Shift")) if mods & bit]
                    + [upper(last) if len(last) == 1 else last.capitalize()])


def upper(ch: str) -> str:
    """A letter's capital, as the sheet writes one; ß has none of one letter
    ("SS"), and stays ß."""
    up = ch.upper()
    return up if len(up) == 1 else ch


def is_symbol(name: str) -> bool:
    """As Shortcuts.js: a key that is not a letter has no Shift of its own."""
    return name == "Plus" or (len(name) == 1 and name.upper() == name.lower())


def to_sheet(key: str) -> str:
    """"Win+Alt+=" → "Alt+Super+=", the sheet's spelling; "" when it is not a key."""
    got = parse(key)
    if not got:
        return ""
    mods, last = got[0], words(key)[-1]
    low = last.lower()
    if low in SHEET_NAME:
        name = SHEET_NAME[low]
    elif len(last) == 1:
        name = upper(last)
    else:
        name = last.upper()              # F1…F24
    shift = bool(mods & 0x4) and not is_symbol(name)
    return ("Ctrl+" if mods & 0x2 else "") + ("Alt+" if mods & 0x1 else "") + ("Shift+" if shift else "") + "Super+" + name


def from_sheet(key: str) -> tuple[str, str]:
    """"Alt+Super+=" → ("Win+Alt+=", "") or ("", why not)."""
    parts = str(key).split("+")
    if len(parts) > 1 and parts[-1] == "":          # "Super++": the key is the plus
        parts = parts[:-2] + ["Plus"]
    mods, name = parts[:-1], parts[-1]
    if not name or not set(mods) <= {"Ctrl", "Alt", "Shift", "Super"}:
        return "", "not a key"
    if "Super" not in mods:
        return "", "a key from anywhere holds Win, so it never takes a key an app needs"
    out = "+".join(["Win"] + [m for m in ("Ctrl", "Alt", "Shift") if m in mods] + [WIN_NAME.get(name, name)])
    if not parse(out):
        return "", (f"Windows cannot keep {name} as a key from anywhere: no key of this keyboard types it "
                    "— pick a letter, a digit, an F-key or a symbol your keyboard has")
    return out, ""


def free(key: str) -> bool:
    """Whether Windows would give this key to Longhand: asked of Windows
    itself, by taking it and letting it go at once."""
    if os.name != "nt":
        return True
    import ctypes
    got = parse(key)
    if not got:
        return False
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    if not user32.RegisterHotKey(None, 0x4C3F, got[0] | NOREPEAT, got[1]):
        return False
    user32.UnregisterHotKey(None, 0x4C3F)
    return True


def state(note: str = "", **extra) -> dict:
    keys = wanted()
    return {
        "owned": True,               # Longhand's own file: nothing to adopt
        "wired": True,
        "file": str(keys_file()),
        "bindings": "",
        "lines": 0,
        "actions": [{"id": aid, "does": DOES[aid], "keys": [k for k in map(to_sheet, keys[aid]) if k],
                     "own": [to_sheet(DEFAULTS[aid])]} for aid in ORDER],
        "taken": {},
        "others": [],
        "note": note,
        **extra,
    }


def write(keys: dict[str, list[str]]) -> None:
    """Only what differs from an action's own key; the rest of the person's
    file (a key of theirs for an action, as they wrote it) is kept."""
    out = {}
    for aid in ORDER:
        ks = keys[aid]
        if [to_sheet(k) for k in ks] == [to_sheet(DEFAULTS[aid])]:
            continue
        out[aid] = "" if not ks else ks[0] if len(ks) == 1 else ks
    path = keys_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def set_keys(aid: str, new: list[str], add: bool = False) -> dict:
    if aid not in DEFAULTS:
        return state(error=f"no action {aid}")
    asked = []
    for k in new:
        w, why = from_sheet(k)
        if not w:
            return state(error=why, key=k)
        asked.append(w)
    keys = wanted()
    hkl = layout()

    def held(k):
        # The key Windows would hold for it: Win+Alt+\ and Win+Ctrl+Alt+\
        # are both Win+AltGr+ß on a German keyboard, one key.
        return parse(k, hkl) or to_sheet(k)
    ours = {held(k) for ks in keys.values() for k in ks}
    for w in asked:
        if held(w) not in ours and not free(w):
            return state(error=f"{shown(w)} is taken by Windows or another program — pick another, Esc keeps the old one",
                         key=to_sheet(w))
    moved_from = []
    for w in asked:
        for o in ORDER:
            if o != aid and held(w) in [held(k) for k in keys[o]]:
                keys[o] = [k for k in keys[o] if held(k) != held(w)]
                moved_from.append(DOES[o])
    if add:
        keys[aid] = [k for k in keys[aid] if held(k) not in {held(w) for w in asked}] + asked
    else:
        keys[aid] = asked
    write(keys)
    note = f"moved here from “{'”, “'.join(moved_from)}”" if moved_from else ""
    return state(note)


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("state", "migrate"):
        out = state()
    elif argv[0] == "adopt":
        out = state("Longhand keeps these keys already")
    elif argv[0] == "set" and len(argv) >= 2:
        flags = {a for a in argv[2:] if a in ("--add", "--take")}
        out = set_keys(argv[1], [a for a in argv[2:] if a not in flags], "--add" in flags)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(out))
    return 1 if out.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
