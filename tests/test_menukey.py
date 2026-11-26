#!/usr/bin/env python3
"""Shift+F10 on Windows (windows/menukey.py, 2026-11-26): F10 is a system key
there, so Shift+F10 became Windows' context-menu message and, on its release,
the window's menu mode; the page never heard the key, and the next key went
to the system menu. The host takes exactly Shift+F10's own messages (both
the system and the plain kind, the press and the release) and nothing else:
F10 alone, other keys and the Menu key stay Windows'.

The decision is plain Python, checked here on every system; the native
filter itself is checked by hand on the ThinkPad (real input).
Run: python3 tests/test_menukey.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "windows"))
import menukey as m  # noqa: E402

failures = 0


def check(ok, what):
    global failures
    print(("ok   " if ok else "FAIL ") + what)
    failures += 0 if ok else 1


check(m.taken(m.WM_SYSKEYDOWN, m.VK_F10, True) == "press", "Shift+F10 pressed: the page's (the system kind)")
check(m.taken(m.WM_SYSKEYUP, m.VK_F10, True) == "release", "…and let go: the page's too, so no menu mode")
check(m.taken(m.WM_KEYDOWN, m.VK_F10, True) == "press", "…the plain kind as well")
check(m.taken(m.WM_SYSKEYDOWN, m.VK_F10, False) is None, "F10 alone stays Windows'")
check(m.taken(m.WM_KEYDOWN, 0x5D, True) is None, "the Menu key (VK_APPS) stays as it comes, a key of its own")
check(m.taken(m.WM_KEYDOWN, 0x41, True) is None, "Shift+A is no business of this")
check(m.taken(0x0102, m.VK_F10, True) is None, "a character message is left alone")
if sys.platform != "win32":
    check(m.install(object()) is None, "off Windows nothing is installed")

print("PASS" if failures == 0 else f"{failures} FAILED")
sys.exit(1 if failures else 0)
