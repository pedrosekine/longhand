import QtQuick
import QtTest
import "../plugin-page"

// A drag held past the note's edge keeps selecting and scrolling while the
// pointer rests there (NoteEditor's `pointer`, its `viewAt`). Until the
// second mouse pass (2026-11-25) it ran one tick and stopped: the line it
// reached was scrolled into view, and the pointer, kept in the lines' own
// coordinates, was no longer past the edge.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_dragscroll.qml
Item {
  id: top
  width: 600
  height: 400

  Flickable {
    id: flick
    width: 600
    height: 300
    clip: true
    contentWidth: width
    contentHeight: ed.height
    boundsBehavior: Flickable.StopAtBounds
    acceptedButtons: Qt.NoButton
    NoteEditor {
      id: ed
      width: 560
      height: implicitHeight
      textSize: 16
      fontFamily: "monospace"
      viewport: flick
    }
  }

  TestCase {
    name: "DragScroll"
    when: windowShown

    function test_a_drag_held_below_keeps_going() {
      var lines = []
      for (var i = 0; i < 120; i++) lines.push("line " + i + " of the note")
      ed.load(lines.join("\n"))
      flick.contentY = 0
      wait(50)
      var r = ed.rowItem(2)
      mousePress(flick, 40, r.y + r.height / 2)
      mouseMove(flick, 40, 200, 10, Qt.LeftButton)
      mouseMove(flick, 40, flick.height + 40, 10, Qt.LeftButton)   // past the bottom, then still
      var first = flick.contentY
      wait(700)
      var later = flick.contentY
      mouseRelease(flick, 40, flick.height + 40)
      verify(later > first + 100, "it kept scrolling while held still (" + first + " → " + later + ")")
      verify(ed.spanning, "the selection grew across lines")
      verify(ed.selEnd > ed.rows[20].start, "…well past what first showed (" + ed.selEnd + ")")
    }
  }
}
