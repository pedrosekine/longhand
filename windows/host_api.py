"""What the QML shim asks the host itself: the environment, a detached run."""
import os
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Slot
from PySide6.QtQml import QmlElement, QmlSingleton

import qs_io

QML_IMPORT_NAME = "LonghandHost"
QML_IMPORT_MAJOR_VERSION = 1


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

    @Slot("QVariantList")
    def execDetached(self, command):
        argv = [str(x) for x in command or []]
        if not argv:
            return
        program, args = qs_io.resolve(argv)
        QProcess.startDetached(program, args)
