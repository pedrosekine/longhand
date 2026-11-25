"""What Windows' window manager is asked for a window's frame, where
Hyprland's own look has nothing to say: Hyprland draws no title bar, and
gives every window its rounding and its shadow from the theme.

- The page's window keeps Windows' title bar (Snap, the taskbar, a frame
  to drag and size it by), so the title bar is painted the page's paper,
  its words in the page's text, and its buttons light or dark to match:
  the bar reads as the top of the page rather than a second header over
  it (`paint_title_bar`). The private paper sinks the bar with it.
- A popup by the clock is a frameless window; asked for Windows 11's
  rounded corners it is given the shadow and the hairline edge of
  Windows' own flyouts as well (`round_corners`; seen on the screen
  2026-11-25: corners alone bring both).

Each says whether Windows took it. Where it cannot (Windows 10 has no
rounding, or no title-bar colour; the offscreen platform has no native
windows at all), the window keeps the look it has.
"""
from __future__ import annotations

import os

DWMWA_USE_IMMERSIVE_DARK_MODE = 20
DWMWA_WINDOW_CORNER_PREFERENCE = 33
DWMWA_CAPTION_COLOR = 35
DWMWA_TEXT_COLOR = 36
DWMWCP_ROUND = 2


def colorref(hex_colour: str) -> int:
    """"#rrggbb" (or QML's "#aarrggbb") as Windows' COLORREF, 0x00bbggrr."""
    c = str(hex_colour).strip().lstrip("#")
    c = c[-6:]
    r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    return r | (g << 8) | (b << 16)


def is_dark(hex_colour: str) -> bool:
    """Whether a ground wants light words and light caption buttons on it."""
    c = colorref(hex_colour)
    r, g, b = c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF

    def ch(x: int) -> float:
        x /= 255
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b) < 0.18


def _set(hwnd: int, attribute: int, value: int) -> bool:
    import ctypes
    from ctypes import wintypes
    try:
        dwm = ctypes.WinDLL("dwmapi")
    except OSError:
        return False
    dwm.DwmSetWindowAttribute.argtypes = (wintypes.HWND, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD)
    dwm.DwmSetWindowAttribute.restype = ctypes.c_long
    v = wintypes.DWORD(value)
    return dwm.DwmSetWindowAttribute(hwnd, attribute, ctypes.byref(v), ctypes.sizeof(v)) == 0


def native(window) -> int:
    """The window's handle, where it is a window Windows knows (shown, on
    Windows' own platform); else 0. Never makes one: asking a window not yet
    shown for its handle would create it, on whatever screen."""
    if os.name != "nt" or window is None:
        return 0
    try:
        from PySide6.QtGui import QGuiApplication
        if QGuiApplication.platformName() != "windows" or not window.isVisible():
            return 0
        return int(window.winId())
    except (AttributeError, RuntimeError, TypeError):
        return 0


def paint_title_bar(hwnd: int, ground: str, text: str) -> bool:
    """The title bar in `ground`, its title in `text`, its buttons drawn for
    a dark or a light ground as `ground` is (not as Windows' mode is: a
    light colors.toml under dark Windows would otherwise get white buttons
    on light paper)."""
    if not hwnd:
        return False
    dark = _set(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, 1 if is_dark(ground) else 0)
    return _set(hwnd, DWMWA_CAPTION_COLOR, colorref(ground)) and _set(hwnd, DWMWA_TEXT_COLOR, colorref(text)) and dark


def round_corners(hwnd: int) -> bool:
    return bool(hwnd) and _set(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND)
