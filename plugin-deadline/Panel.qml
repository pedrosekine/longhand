import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Deadline bar widget: countdown to the next open deadline + list popup.
//
// Deadlines are entered by hand through `pomo deadline add` — no feed to
// import from, by design. The popup is where they get closed out: mark one
// done when it is handed in, type the grade when it comes back, hide it once
// it is history. Nothing here writes the store directly; every action is a
// `pomo deadline ...` call and the file watcher paints the result.
//
// Keyboard model: a grid. Rows are deadlines, columns are
//   0 the deadline itself   Enter = open its line in the note (done when
//                           there is no line to open)
//   1 grade                 Enter = inline grade editor
//   2 hide                  Enter = keep the record, drop it from the list
//   3 remove                Enter = delete outright
// Up/Down pick a row, Left/Right a column, `d` `g` `x` are shortcuts for
// done, grade, remove; `o` (or a click on the title) opens the page at the
// note line as well. Mouse hover drives the same cursor so exactly one cell
// is highlighted at a time.
//
// Enter used to mean *done* here while it meant *go to it* in the page,
// which is one key doing two opposite things depending on which surface you
// opened (2026-10-15). It now opens the line everywhere; closing a deadline
// out is `d`, as it already was. The popup is the glance and the page's
// dashboard (Ctrl+T) is where the same list is worked through.
//
// The list is what is still in play: open deadlines, and done ones until
// the day after they were done. Done ones with no grade yet wait in a
// folded "waiting for a grade" row (`w` or a click unfolds it) until they
// are graded or hidden.
Panel {
  id: root
  moduleName: "longhand.deadline"
  ipcTarget: "longhand.deadline"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.2)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Match the pomodoro widget: underline the painted label, not the slot.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // A popup that grows without bound stops being glanceable and starts
  // clipping against the panel's height cap. Show the front of the queue and
  // count the rest. Done rows sort last, so they are the first to drop off.
  readonly property int maxRows: 8
  readonly property real todayStart: { svc.nowSec; var d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime() / 1000 }
  readonly property var listed: svc.items.filter(function (it) { return it.status === "open" || it.doneAt >= root.todayStart })
  readonly property var waiting: svc.items.filter(function (it) { return it.status === "done" && it.doneAt < root.todayStart && it.grade === "" })
  property bool showWaiting: false
  readonly property var shown: listed.slice(0, maxRows).concat(showWaiting ? waiting : [])
  readonly property int hiddenCount: Math.max(0, listed.length - maxRows)

  readonly property int cols: 4

  property bool cursorActive: false
  property int cursorRow: 0
  property int cursorCol: 0

  // Inline grade editor: the id being graded, 0 when closed. While open the
  // key catcher is blocked so typing lands in the field.
  property int gradingId: 0

  function cellHot(row, col) {
    return root.cursorActive && root.cursorRow === row && root.cursorCol === col
  }

  function clampCursor() {
    root.cursorRow = Math.max(0, Math.min(root.shown.length - 1, root.cursorRow))
    root.cursorCol = Math.max(0, Math.min(root.cols - 1, root.cursorCol))
  }

  function moveCursor(dx, dy) {
    if (!root.cursorActive) {
      root.cursorActive = true
      root.clampCursor()
      return
    }
    if (dx !== 0) root.cursorCol += dx
    if (dy !== 0) root.cursorRow += dy
    root.clampCursor()
  }

  function hoverCursor(row, col) {
    root.cursorActive = true
    root.cursorRow = row
    root.cursorCol = col
  }

  function selectedItem() {
    if (!root.cursorActive) return null
    return root.shown[root.cursorRow] || null
  }

  function activateCursor() {
    var item = root.selectedItem()
    if (!item) return
    // Enter opens the note, if there is a line to open — the page's rule,
    // kept here so the key means one thing. A deadline no line stands for
    // has nothing to open, so it closes out instead.
    if (root.cursorCol === 0) {
      if (/^\[\[[^\]#|]+#\^d\d+\]\]$/.test(item.link)) root.openLine(item)
      else svc.toggleDone(item)
    }
    else if (root.cursorCol === 1) root.startGrade(item)
    else if (root.cursorCol === 2) svc.hide(item.id)
    else svc.remove(item.id)
  }

  function toggleSelected() {
    var item = root.selectedItem()
    if (item) svc.toggleDone(item)
  }

  function gradeSelected() {
    var item = root.selectedItem()
    if (item) root.startGrade(item)
  }

  // To the note line that stands for a deadline: the page opens on it.
  function openLine(item) {
    if (!item || !/^\[\[[^\]#|]+#\^d\d+\]\]$/.test(item.link)) return
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "longhand.page", JSON.stringify({ goto: item.link })])
    root.close()
  }

  function removeSelected() {
    var item = root.selectedItem()
    if (item) svc.remove(item.id)
  }

  function startGrade(item) {
    root.hoverCursor(root.shown.indexOf(item), 1)
    root.gradingId = item.id
  }

  function finishGrade(item, text) {
    if (root.gradingId !== item.id) return
    root.gradingId = 0
    if (text !== item.grade) svc.grade(item.id, text)
    keyCatcher.forceActiveFocus()
  }

  function cancelGrade() {
    root.gradingId = 0
    keyCatcher.forceActiveFocus()
  }

  function rowColor(item) {
    if (item.status !== "open") return root.faint
    return svc.isUrgent(item.due) ? root.urgent : svc.isNear(item.due) ? root.foreground : root.dim
  }

  function statusText(item) { // right-hand column: countdown, or the grade once it is in
    if (item.status === "open") return svc.fmtRel(item.due)
    return item.grade !== "" ? item.grade : "done"
  }

  onOpenedChanged: {
    root.cursorActive = false
    root.cursorRow = 0
    root.cursorCol = 0
    root.gradingId = 0
  }

  Connections {
    target: svc
    function onItemsChanged() { root.clampCursor() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: svc
    settings: root.settings
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: svc.labelText
    // The bar label is the whole point of the widget, so it earns the theme's
    // urgent color once the next deadline is inside a day.
    foreground: svc.nextItem && svc.isUrgent(svc.nextItem.due)
      ? (bar ? bar.urgent : Color.urgent)
      : (bar ? bar.barForeground : Color.foreground)
    tooltipText: svc.tooltipText
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The grade field owns the keyboard while it is open (same pattern as
      // the wifi passphrase prompt): Esc/Enter there close it, nothing else
      // leaks out to the cursor model.
      blocked: root.gradingId > 0
      onCloseRequested: root.close()
      onMoveRequested: function (dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.removeSelected()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "d" || t === "D") root.toggleSelected()
        else if (t === "g" || t === "G") root.gradeSelected()
        else if (t === "o" || t === "O") root.openLine(root.selectedItem())
        else if (t === "w" || t === "W") root.showWaiting = !root.showWaiting
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader {
          text: "DEADLINES"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          visible: root.listed.length === 0 && root.waiting.length === 0
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Nothing due. Add one from a terminal:\npomo deadline add \"Essay draft\" next friday 17:00"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.shown

          CursorSurface {
            id: row
            required property var modelData
            required property int index

            readonly property bool isDone: modelData.status !== "open"
            readonly property bool grading: root.gradingId === modelData.id
            readonly property color textColor: isDone ? root.dim : root.foreground

            width: column.width
            implicitHeight: rowContent.implicitHeight + Style.space(10)
            hasCursor: root.cellHot(index, 0)
            foreground: root.foreground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.hoverCursor(row.index, 0)
              onClicked: svc.toggleDone(row.modelData)
            }

            ColumnLayout {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: (row.isDone ? "✓ " : "○ ") + row.modelData.title
                  color: row.textColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.strikeout: row.isDone
                  font.underline: titleMouse.containsMouse && titleMouse.enabled

                  // A deadline a note line stands for: its title opens it.
                  MouseArea {
                    id: titleMouse
                    anchors.fill: parent
                    enabled: /#\^d\d+\]\]$/.test(row.modelData.link)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.hoverCursor(row.index, 0)
                    onClicked: root.openLine(row.modelData)
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.statusText(row.modelData)
                  color: root.rowColor(row.modelData)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: svc.fmtWhen(row.modelData.due)
                    + (row.modelData.project !== "" ? " · " + row.modelData.project : "")
                    + (row.isDone && row.modelData.doneAt > 0 ? "  ·  handed in " + svc.fmtDay(row.modelData.doneAt) : "")
                  color: row.isDone ? root.faint : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // Action chips. Hidden while this row is being graded so the
                // editor gets the full line.
                Repeater {
                  model: row.grading ? [] : [
                    { col: 1, label: row.modelData.grade !== "" ? "grade " + row.modelData.grade : "grade", tip: "Type the grade (g)" },
                    { col: 2, label: "hide", tip: "Keep the record, drop it from the list" },
                    { col: 3, label: "✕", tip: "Delete (x)" }
                  ]

                  Button {
                    required property var modelData

                    text: modelData.label
                    tooltipText: modelData.tip
                    fontSize: Style.font.caption
                    fontFamily: root.fontFamily
                    foreground: row.textColor
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(1)
                    hasCursor: root.cellHot(row.index, modelData.col)
                    onHovered: function (h) {
                      if (h) root.hoverCursor(row.index, modelData.col)
                      // Leaving a chip for the row body hands the cursor
                      // back to column 0; the row's own MouseArea stays
                      // hovered throughout, so it would not re-fire.
                      else if (root.cellHot(row.index, modelData.col)) root.cursorCol = 0
                    }
                    onClicked: {
                      root.hoverCursor(row.index, modelData.col)
                      root.activateCursor()
                    }
                  }
                }
              }

              RowLayout {
                visible: row.grading
                Layout.fillWidth: true
                spacing: Style.space(6)

                TextField {
                  id: gradeField
                  Layout.fillWidth: true
                  placeholderText: "Grade, e.g. 7.5 or A- · empty clears"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  foreground: root.foreground
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  text: row.grading ? row.modelData.grade : ""

                  // Handle Return/Escape here and accept them. The text
                  // input itself ignores Return after emitting accepted, so
                  // the same press would bubble up to the key catcher — which
                  // finishGrade has just unblocked — and fire "activate" on
                  // whatever cell the cursor is on, reopening the editor.
                  Keys.onReturnPressed: function (event) { event.accepted = true; root.finishGrade(row.modelData, text.trim()) }
                  Keys.onEnterPressed: function (event) { event.accepted = true; root.finishGrade(row.modelData, text.trim()) }
                  Keys.onEscapePressed: function (event) { event.accepted = true; root.cancelGrade() }
                  onVisibleChanged: if (visible) Qt.callLater(function () { gradeField.forceActiveFocus(); gradeField.selectAll() })
                }
              }
            }
          }
        }

        // Done, not graded yet: folded until asked for.
        Text {
          visible: root.waiting.length > 0
          width: parent.width
          textFormat: Text.PlainText
          text: (root.showWaiting ? "▾ " : "▸ ") + "waiting for a grade · " + root.waiting.length
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showWaiting = !root.showWaiting }
        }

        Text {
          visible: root.hiddenCount > 0
          width: parent.width
          textFormat: Text.PlainText
          text: "+" + root.hiddenCount + " more · pomo deadline list"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.shown.length > 0
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.gradingId > 0
            ? "Enter saves the grade · Esc cancels"
            : "↑↓ ←→ move · Enter act · d done · g grade · o open its line · x remove" + (root.waiting.length > 0 ? " · w waiting" : "")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
