import QtQuick
import "Shortcuts.js" as Sc

// What was read on the calendar's day (plan.md item 15, step 3), moved out of
// Page.qml on 2026-11-16 (plan item 4): the sidebar's READ list under the
// day's deadlines, and its keys. `page` is the page.
Item {
  id: rt
  required property Item page
  visible: false

  property int at: -1         // in the day's read papers (-1: not there)

  // What was read on the calendar's day (plan.md item 15, step 3): the
  // papers marked that day, from the reading notes' own days (`longhand-read
  // days`) — computed, nothing written into the day's note. Enter opens
  // one where it was left.
  property var days: ({})
  readonly property var rows: rt.days[Qt.formatDate(page.calFocus, "yyyy-MM-dd")] || []
  Connections {
    target: rt.page
    function onCalFocusChanged() { rt.at = -1 }
  }
  // Read again by the page (`longhand-read days`, its readDaysProc), which
  // sets `days`; a moment later when asked while a read is under way.
  function refresh() {
    if (!page.noteService.configured) return
    if (!page.readDaysRun()) readDaysTimer.restart()
  }
  Timer { id: readDaysTimer; interval: 700; onTriggered: rt.refresh() }
  // Marks made or taken away change what the day shows as read.
  Connections {
    target: rt.page.pdfItem
    function onReadChanged() { readDaysTimer.restart() }
  }
  function keyPressed(event) {
    var n = rt.rows.length
    if (Sc.hit(event, "listUp")) rt.at = Math.max(0, rt.at - 1)
    else if (Sc.hit(event, "listDown")) rt.at = Math.min(n - 1, rt.at + 1)
    else if (Sc.hit(event, "listOpen")) { var r = rt.rows[rt.at]; if (r) { page.used("read-today", "open"); page.remember(); page.openPdf(r.pdf) } }
    else if (Sc.hit(event, "listNext")) { rt.at = -1; page.projFocus = 0 }
    else if (Sc.hit(event, "listBack")) rt.at = -1
    else return false
    return true
  }
  function summary(r) {
    var parts = []
    if (r.h) parts.push(r.h + (r.h === 1 ? " highlight" : " highlights"))
    if (r.q) parts.push(r.q + (r.q === 1 ? " question" : " questions"))
    return parts.join(", ")
  }
}
