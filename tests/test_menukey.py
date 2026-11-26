#!/usr/bin/env python3
"""Shift+F10 on Windows (windows/menukey.py, 2026-11-26): Windows sends it as
a keyboard context-menu event, without the key press, so the page's key for
its right-click menu never heard it. The host gives the window the key back;
a context-menu event without Shift (the Menu key, which also comes as a key)
and a right click are left alone.

Needs PySide6, the Windows host's Qt (`pip install -e windows`); without it
there is nothing of the host to check, and it says so.
Run: python3 tests/test_menukey.py
"""
import os
import pathlib
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
try:
    from PySide6.QtCore import QCoreApplication, QPoint, Qt
    from PySide6.QtGui import QContextMenuEvent, QGuiApplication, QWindow
except ImportError:
    print("no PySide6 (the Windows host's Qt): nothing to check here")
    sys.exit(0)

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "windows"))
import menukey  # noqa: E402

failures = 0


def check(ok, what):
    global failures
    print(("ok   " if ok else "FAIL ") + what)
    failures += 0 if ok else 1


class Win(QWindow):
    def __init__(self):
        super().__init__()
        self.keys = []

    def keyPressEvent(self, e):  # noqa: N802
        self.keys.append((e.key(), e.modifiers()))


app = QGuiApplication(sys.argv[:1])
shift = [True]
f = menukey.MenuKey(app, shift=lambda: shift[0])
app.installEventFilter(f)
w = Win()


def menu(reason):
    QCoreApplication.sendEvent(w, QContextMenuEvent(reason, QPoint(5, 5)))
    QCoreApplication.processEvents()


menu(QContextMenuEvent.Reason.Keyboard)
check(w.keys == [(Qt.Key.Key_F10, Qt.KeyboardModifier.ShiftModifier)], f"Shift+F10's menu event comes back as Shift+F10 ({w.keys})")
w.keys.clear()
shift[0] = False
menu(QContextMenuEvent.Reason.Keyboard)
check(w.keys == [], "the Menu key's (no Shift) is left alone: it comes as a key of its own")
shift[0] = True
menu(QContextMenuEvent.Reason.Mouse)
check(w.keys == [], "a right click is left alone")

print("PASS" if failures == 0 else f"{failures} FAILED")
sys.exit(1 if failures else 0)
