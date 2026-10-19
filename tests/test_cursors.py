#!/usr/bin/env python3
"""The mouse cursor over the note, as Qt picks it (2026-10-19).

The note sits in a Flickable with the touchpad scroller, as the page has it.
Laid over the content, the scroller hid every cursor under it: the note
showed an arrow instead of a text cursor. This loads the editor that way,
moves a real (offscreen) mouse, and reads the cursor the window was given:
a text cursor over the words, a hand over a checkbox, and touchpad and wheel
scrolling still working.

Needs PyQt6 built against the system's Qt 6.
Run: QT_QPA_PLATFORM=offscreen python3 tests/test_cursors.py
"""
import os
import pathlib
import sys
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PyQt6.QtCore import QObject, QPoint, QPointF, Qt, QUrl  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QWheelEvent  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402
from PyQt6.QtTest import QTest  # noqa: E402

PAGE = pathlib.Path(__file__).resolve().parent.parent / "plugin-page"

QML = """import QtQuick
import "%s"
Item {
  width: 600; height: 500
  MouseArea { anchors.fill: parent }   // the sheet's own, under everything
  Flickable {
    id: flick
    objectName: "flick"
    anchors.fill: parent
    contentWidth: width; contentHeight: 5000
    boundsBehavior: Flickable.StopAtBounds
    TouchScroll { flickable: flick }
    NoteEditor {
      id: ed
      objectName: "ed"
      x: 20; width: 540; height: implicitHeight
      textSize: 16
    }
  }
  function boxAt(i) {
    var it = ed.rowItem(i)
    var p = it.box.mapToItem(null, it.box.width / 2, it.box.height / 2)
    return Qt.point(p.x, p.y)
  }
  function wordsAt(i) {
    var it = ed.rowItem(i)
    var p = it.field.mapToItem(null, 40, it.field.height / 2)
    return Qt.point(p.x, p.y)
  }
  Component.onCompleted: { ed.load("\\nPlain prose line with words\\n- [ ] a task line\\nmore prose here"); ed.setCursor(1, true) }
}
""" % PAGE.as_uri()

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    app = QGuiApplication(sys.argv)  # noqa: F841
    with tempfile.TemporaryDirectory() as d:
        src = pathlib.Path(d) / "cursors.qml"
        src.write_text(QML)
        v = QQuickView()
        v.setSource(QUrl.fromLocalFile(str(src)))
        if v.status() != QQuickView.Status.Ready:
            print("\n".join(e.toString() for e in v.errors()))
            return 1
        v.show()
        QTest.qWaitForWindowExposed(v)
        QTest.qWait(150)
        root = v.rootObject()
        flick = root.findChild(QObject, "flick")

        def point(fn, i):
            p = getattr(root, fn)(i)
            p = p.toPointF() if hasattr(p, "toPointF") else p
            return QPoint(round(p.x()), round(p.y()))

        def cursor_at(p):
            QTest.mouseMove(v, p)
            QTest.qWait(30)
            return v.cursor().shape()

        check(cursor_at(point("wordsAt", 1)) == Qt.CursorShape.IBeamCursor, "a text cursor over the words")
        check(cursor_at(point("boxAt", 2)) == Qt.CursorShape.PointingHandCursor, "a hand over a checkbox")
        check(cursor_at(point("wordsAt", 2)) == Qt.CursorShape.IBeamCursor, "a text cursor again over the task's words")

        def wheel(pixel, angle, phase):
            p = QPointF(point("wordsAt", 1))
            e = QWheelEvent(p, QPointF(v.mapToGlobal(p.toPoint())), pixel, angle,
                            Qt.MouseButton.NoButton, Qt.KeyboardModifier.NoModifier, phase, False)
            QGuiApplication.sendEvent(v, e)
            QTest.qWait(20)

        wheel(QPoint(0, 0), QPoint(0, 0), Qt.ScrollPhase.ScrollBegin)
        for _ in range(3):
            wheel(QPoint(0, -10), QPoint(0, -30), Qt.ScrollPhase.ScrollUpdate)
        check(flick.property("contentY") == 60, f"the touchpad scrolls by its gain ({flick.property('contentY')})")
        wheel(QPoint(0, 0), QPoint(0, 0), Qt.ScrollPhase.ScrollEnd)
        QTest.qWait(50)
        flick.setProperty("contentY", 0)
        wheel(QPoint(0, 0), QPoint(0, -120), Qt.ScrollPhase.NoScrollPhase)
        QTest.qWait(400)
        check(flick.property("contentY") > 0, f"a mouse wheel still scrolls ({flick.property('contentY')})")
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
