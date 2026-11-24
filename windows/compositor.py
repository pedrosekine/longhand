"""What Hyprland does for the page, on Windows: `hyprctl eval`, answered by
the host itself.

The page asks Hyprland three things, each as a line of Lua (Page.qml):

- raise its window (`raiseWindow`): `hl.dsp.focus({ window = "title:^…$" })`
  — a goto from the deadlines' popup, the tray, a second `longhand`, when
  the window is already open behind another;
- put the pointer where the keys are (`warpNow`, Settings → The pointer):
  `hl.dsp.cursor.move(…)`, from a monitor's corner (the overlay) or the
  window's, only while the window is the active one;
- while the keys sheet waits for one of the six keys from anywhere, a submap
  that binds nothing, so the key reaches the sheet instead of doing what it
  does (`hyprListen`), left by itself after 30 seconds.

Here the window is raised and activated with Qt, the pointer is put with
Qt (Windows' SetCursorPos), and the submap is the host letting go of its
keys (hotkeys.py) and taking them back. Nothing else Hyprland is asked is
known here: it is answered as Hyprland answers what it cannot do, an error
on stderr, and the page goes on as it does without Hyprland.

qs_io.Process sends a `hyprctl` command here instead of starting a program
(`qs_io.INSIDE`).
"""
from __future__ import annotations

import re

from PySide6.QtCore import QPoint, QTimer
from PySide6.QtGui import QCursor, QGuiApplication

# The host's keys (hotkeys.Keys), set when it registers them.
KEYS = None
_listening = QTimer()
_listening.setSingleShot(True)
_listening.setInterval(30000)           # as Hyprland leaves the submap by itself


def _give_back() -> None:
    if KEYS is not None:
        KEYS.register()


_listening.timeout.connect(_give_back)

FOCUS = re.compile(r'hl\.dsp\.focus\(\s*\{\s*window\s*=\s*"title:\^(.*?)\$"')
WARP_MONITOR = re.compile(r'hl\.get_monitor\("([^"]*)"\).*?x\s*=\s*m\.position\.x\s*\+\s*(-?\d+)\s*,\s*y\s*=\s*m\.position\.y\s*\+\s*(-?\d+)', re.S)
WARP_WINDOW = re.compile(r'hl\.get_window\("title:\^(.*?)\$"\).*?x\s*=\s*w\.at\.x\s*\+\s*(-?\d+)\s*,\s*y\s*=\s*w\.at\.y\s*\+\s*(-?\d+)', re.S)


def plain(name: str) -> str:
    """A screen's name as the page writes it into Lua (Page.qml warpNow)."""
    return re.sub(r"[^A-Za-z0-9_.-]", "", name)


def window(title: str):
    for w in QGuiApplication.allWindows():
        if w.title() == title:
            return w
    return None


def come_forward(w) -> bool:
    """A window to the front and given the keys, out of the taskbar if it
    was put there."""
    if w is None or not w.isVisible():
        return False
    from PySide6.QtGui import QWindow
    if w.visibility() == QWindow.Visibility.Minimized:
        w.showNormal()
    w.raise_()
    w.requestActivate()
    return True


def listen(on: bool) -> None:
    """The sheet waits for a key from anywhere: the host's keys let go, so it
    reaches the sheet; back when it stops waiting, or 30 seconds on."""
    if KEYS is None:
        return
    if on:
        KEYS.release()
        _listening.start()
    else:
        _listening.stop()
        KEYS.register()


def listening() -> bool:
    """Whether the keys are let go for the sheet just now."""
    return _listening.isActive()


def eval_lua(lua: str) -> tuple[int, str, str]:
    if 'define_submap("longhand-keys"' in lua:
        listen(True)
        return 0, "ok", ""
    if 'get_current_submap() == "longhand-keys"' in lua:
        listen(False)
        return 0, "ok", ""
    m = FOCUS.search(lua)
    if m:
        come_forward(window(m.group(1)))
        return 0, "ok", ""
    m = WARP_MONITOR.search(lua)
    if m:
        name, x, y = m.group(1), int(m.group(2)), int(m.group(3))
        for s in QGuiApplication.screens():
            # The page keeps only [A-Za-z0-9_.-] of a monitor's name for the
            # Lua it writes; a laptop's screen is "\\.\DISPLAY1" here, which
            # came as ".DISPLAY1", matched none, and the pointer stayed put on
            # that screen while it went where it should on the other.
            if plain(s.name()) == name or name == "":
                g = s.geometry()
                QCursor.setPos(s, g.x() + x, g.y() + y)
                break
        return 0, "ok", ""
    m = WARP_WINDOW.search(lua)
    if m:
        w = QGuiApplication.focusWindow()
        if w is not None and w.title() == m.group(1):
            QCursor.setPos(w.screen(), w.mapToGlobal(QPoint(int(m.group(2)), int(m.group(3)))))
        return 0, "ok", ""
    return 1, "", "hyprctl: not Hyprland (Longhand on Windows answers only the page's own calls)\n"


def hyprctl(args: list[str]) -> tuple[int, str, str]:
    """`hyprctl <args>` as the host answers it: (exit code, stdout, stderr)."""
    if len(args) >= 2 and args[0] == "eval":
        return eval_lua(args[1])
    return 1, "", "hyprctl: not Hyprland\n"
