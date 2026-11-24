"""What the QML shim asks the host itself — the environment, a detached run —
and what the host tells the page's holder (Main.qml): a summon, a global key."""
import os
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Signal, Slot
from PySide6.QtQml import QmlElement, QmlSingleton

import qs_io

QML_IMPORT_NAME = "LonghandHost"
QML_IMPORT_MAJOR_VERSION = 1


class Bridge(QObject):
    """From the host to Main.qml, as signals: what a second `longhand`, a
    global key or the tray asked for. And the keys' names, for the menu."""
    summonRequested = Signal(str)       # a payload, as `omarchy-shell shell summon longhand.page` takes
    toggleRequested = Signal(str)
    pomoRequested = Signal(str)         # toggle | skip
    popupRequested = Signal(str)        # timer | deadlines: the bar's two popups
    quitRequested = Signal()
    keysChanged = Signal()

    def __init__(self):
        super().__init__()
        self.keys = {}                  # action -> the key as shown
        self.problems = {}

    @Slot(str, result=str)
    def keyName(self, action):
        return self.keys.get(action, "")

    @Slot(result=str)
    def keyProblems(self):
        return "\n".join(self.problems.values())

    def act(self, action: str) -> None:
        """A global key's action, by Omarchy's name for it."""
        if action == "page":
            self.toggleRequested.emit("{}")
        elif action == "alongside":
            self.summonRequested.emit('{"shape":"alongside"}')
        elif action == "pomoToggle":
            self.pomoRequested.emit("toggle")
        elif action == "pomoSkip":
            self.pomoRequested.emit("skip")
        elif action == "pomoPopup":
            self.popupRequested.emit("timer")
        elif action == "deadlines":
            self.popupRequested.emit("deadlines")


BRIDGE = Bridge()


@QmlElement
@QmlSingleton
class Host(QObject):
    @Slot(str, result="QVariant")
    def env(self, name):
        v = os.environ.get(name)
        if v:
            return v.replace("\\", "/") if name in ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME") else v
        if name == "HOME":
            # The page builds paths as HOME + "/.config/…": forward slashes,
            # which Windows and Qt both take.
            return Path.home().as_posix()
        return ""

    @Slot(result="QVariant")
    def workArea(self):
        """The main screen's room, the taskbar left out: where a popup by
        the clock may be put (shim/qs/Ui/KeyboardPanel.qml)."""
        from PySide6.QtGui import QGuiApplication
        screen = QGuiApplication.primaryScreen()
        if screen is None:
            return {"x": 0, "y": 0, "width": 0, "height": 0}
        g = screen.availableGeometry()
        return {"x": g.x(), "y": g.y(), "width": g.width(), "height": g.height()}

    @Slot("QVariantList")
    def execDetached(self, command):
        argv = [str(x) for x in command or []]
        if not argv:
            return
        # `omarchy-shell shell summon longhand.page '{…}'`: the shell is this
        # host, and the page is in it.
        if argv[:2] == ["omarchy-shell", "shell"] and len(argv) >= 4 and argv[3] == "longhand.page":
            payload = argv[4] if len(argv) > 4 else "{}"
            if argv[2] == "summon":
                BRIDGE.summonRequested.emit(payload)
                return
            if argv[2] == "toggle":
                BRIDGE.toggleRequested.emit(payload)
                return
        program, args = qs_io.resolve(argv)
        QProcess.startDetached(program, args)
