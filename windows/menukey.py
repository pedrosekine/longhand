"""menukey — Shift+F10 reaches the page on Windows.

F10 is a system key on Windows: Shift+F10 arrives as WM_SYSKEYDOWN, which
Windows turns into its "context menu" message and, on the release, into
the window's menu mode, where the next key goes to the system menu
(Restore, Move, … Close). Qt hands the window the context-menu event
without the key press, so the page's key for the right-click menu
(Shift+F10 or the Menu key, Shortcuts.js "menu") never heard it (measured
on the ThinkPad, 2026-11-26). So the host takes Shift+F10 out of Windows'
hands at the message itself, before Windows acts on it, and gives the
window the key: no context-menu message, no menu mode. Shift is read with
GetKeyState, which follows the messages as they are handled, so keys sent
in one burst (a macro, a remapper) are read right too. The Menu key comes
as a key of its own and is left alone, and so is everything else.
"""
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x0100, 0x0101, 0x0104, 0x0105
VK_SHIFT, VK_F10 = 0x10, 0x79


def taken(message: int, vk: int, shift: bool):
    """For one Windows key message: "press" or "release" when it is Shift+F10
    and the host gives it to the page itself, else None (Windows keeps it)."""
    if vk != VK_F10 or not shift:
        return None
    if message in (WM_SYSKEYDOWN, WM_KEYDOWN):
        return "press"
    if message in (WM_SYSKEYUP, WM_KEYUP):
        return "release"
    return None


def install(app):
    """On Windows, read every message of `app`'s windows; else nothing.
    The filter is returned, to be kept alive as long as the app."""
    import sys
    if sys.platform != "win32":
        return None
    import ctypes
    from ctypes import wintypes

    from PySide6.QtCore import QAbstractNativeEventFilter, QCoreApplication, QEvent, Qt
    from PySide6.QtGui import QGuiApplication, QKeyEvent

    user32 = ctypes.windll.user32
    user32.GetKeyState.restype = ctypes.c_short
    kinds = {"press": QEvent.Type.KeyPress, "release": QEvent.Type.KeyRelease}

    class ShiftF10(QAbstractNativeEventFilter):
        def nativeEventFilter(self, event_type, message):  # noqa: N802 (Qt's name)
            try:
                if bytes(event_type) != b"windows_generic_MSG":
                    return False, 0
                msg = wintypes.MSG.from_address(int(message))
                kind = taken(msg.message, msg.wParam, user32.GetKeyState(VK_SHIFT) < 0)
                if kind is None:
                    return False, 0
                hwnd = msg.hWnd or 0
                win = next((w for w in QGuiApplication.topLevelWindows() if int(w.winId()) == hwnd), None)
                if win is None:
                    return False, 0
                QCoreApplication.postEvent(win, QKeyEvent(kinds[kind], Qt.Key.Key_F10, Qt.KeyboardModifier.ShiftModifier))
                return True, 0
            except Exception:       # never let a key fail to reach Windows over this
                return False, 0

    f = ShiftF10()
    app.installNativeEventFilter(f)
    return f
