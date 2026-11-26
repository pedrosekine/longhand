"""menukey — Shift+F10 reaches the page on Windows.

Windows turns Shift+F10 into its "context menu" message, and Qt hands the
window that message without the key press itself, so the page's key for the
right-click menu (Shift+F10 or the Menu key, Shortcuts.js "menu") heard only
the Menu key (measured on the ThinkPad, 2026-11-26). The page draws its own
menu and has no handler for Qt's context-menu event, so here a keyboard
context-menu event with Shift held is given back to the window as the key
it was. The Menu key keeps arriving as a key of its own, so it is left as
it is, and so is a right click.
"""
from PySide6.QtCore import QCoreApplication, QEvent, QObject, Qt
from PySide6.QtGui import QContextMenuEvent, QGuiApplication, QKeyEvent, QWindow


def shift_held() -> bool:
    return bool(QGuiApplication.queryKeyboardModifiers() & Qt.KeyboardModifier.ShiftModifier)


class MenuKey(QObject):
    def __init__(self, parent=None, shift=shift_held):
        super().__init__(parent)
        self.shift = shift          # the tests' stand-in for the keyboard

    def eventFilter(self, obj, ev):  # noqa: N802 (Qt's name)
        if (ev.type() == QEvent.Type.ContextMenu and isinstance(obj, QWindow)
                and ev.reason() == QContextMenuEvent.Reason.Keyboard and self.shift()):
            for kind in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
                QCoreApplication.postEvent(obj, QKeyEvent(kind, Qt.Key.Key_F10, Qt.KeyboardModifier.ShiftModifier))
            return True
        return False


def install(app) -> MenuKey:
    """Watch every window of `app`; keep the answer alive as long as it."""
    f = MenuKey(app)
    app.installEventFilter(f)
    return f
