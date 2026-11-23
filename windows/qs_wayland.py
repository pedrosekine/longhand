"""Quickshell.Wayland's names, so the page's overlay block parses off Wayland.

The page asks its overlay for a layer, a namespace and the keyboard; on
Windows the host's PanelWindow is a frameless topmost window and reads none
of these. They are kept so Page.qml loads as it is.
"""
from enum import IntEnum

from PySide6.QtCore import Property, QEnum, QObject, Signal
from PySide6.QtQml import QmlAnonymous, QmlAttached, QmlElement, QmlUncreatable

QML_IMPORT_NAME = "Quickshell.Wayland"
QML_IMPORT_MAJOR_VERSION = 1


@QmlElement
@QmlUncreatable("an enum")
class WlrLayer(QObject):
    @QEnum
    class Enum(IntEnum):
        Background = 0
        Bottom = 1
        Top = 2
        Overlay = 3


@QmlElement
@QmlUncreatable("an enum")
class WlrKeyboardFocus(QObject):
    @QEnum
    class Enum(IntEnum):
        None_ = 0
        Exclusive = 1
        OnDemand = 2


@QmlAnonymous
class WlrLayershellAttached(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._namespace = ""
        self._layer = 2
        self._keyboard = 0
        self._zone = 0

    def _make(attr, kind):
        def get(self):
            return getattr(self, attr)

        def put(self, v):
            setattr(self, attr, kind(v))
            self.changed.emit()
        return get, put

    namespace = Property(str, *_make("_namespace", str), notify=changed)
    layer = Property(int, *_make("_layer", int), notify=changed)
    keyboardFocus = Property(int, *_make("_keyboard", int), notify=changed)
    exclusiveZone = Property(int, *_make("_zone", int), notify=changed)


@QmlElement
@QmlAttached(WlrLayershellAttached)
class WlrLayershell(QObject):
    @staticmethod
    def qmlAttachedProperties(self, o):
        return WlrLayershellAttached(o)
