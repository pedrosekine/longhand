import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
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
//   0 the deadline itself   Enter = open its line in the note (only said
//                           when there is no line to open; Space ticks)
//   1 grade                 Enter = inline grade editor
//   2 hide                  Enter = keep the record, drop it from the list
//   3 cancel                Enter = cancel it: its line becomes `[-]`, the
//                           deadline is kept as history (nothing is deleted
//                           outside the note, docs/tasks.md)
// Up/Down pick a row, Left/Right a column, `d` `g` `x` are shortcuts for
// done, grade, cancel (Ctrl+L is done too, the note's tick); `o` opens the
// page at the note line as well. Ctrl+Z takes back the last change made
// here (a tick, a grade, a hide, a cancel), as on the dashboard.
//
// While it is open, the rows stay where they were when it opened: a tick
// leaves its row in place (it used to sort to the bottom, and the cursor,
// left on its number, was on the next deadline, so a second Space ticked
// that one), and the keys' cursor follows its deadline, not its number.
//
// The mouse, as on the dashboard: a click on a row's ○ ticks it; a click on
// the row or its title opens its line in the note, or, with no line to
// open, only puts the keys' cursor there (a row click never ticks). Hover
// never moves the keys' cursor (docs/hints.md): the pointer paints the faint
// hover look, the keys' cell wears `KeyMark`, and the two never read alike.
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

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color background: Commons.Color.menu.background
  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
  // Blend toward background rather than Qt.darker so muted text stays
  // legible and quiet on both dark and light Omarchy themes.
  readonly property color dim: root.mix(foreground, background, 0.30)
  readonly property color faint: root.mix(foreground, background, 0.45)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Match the pomodoro widget: underline the painted label, not the slot.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // A popup that grows without bound stops being glanceable and starts
  // clipping against the panel's height cap. Show the front of the queue and
  // count the rest. Done rows sort last, so they are the first to drop off.
  readonly property int maxRows: 8
  readonly property real todayStart: { svc.nowSec; var d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime() / 1000 }
  readonly property var listed: root.held(svc.items.filter(function (it) { return it.status === "open" || it.doneAt >= root.todayStart }))
  readonly property var waiting: root.held(svc.items.filter(function (it) { return it.status === "done" && it.doneAt < root.todayStart && it.grade === "" }))
  property bool showWaiting: false
  readonly property var listedShown: listed.slice(0, maxRows)
  readonly property var waitingShown: showWaiting ? waiting : []
  readonly property var shown: listedShown.concat(waitingShown)
  readonly property int hiddenCount: Math.max(0, listed.length - maxRows)

  // The order the rows had when the popup opened (ids), kept while it is
  // open; one that comes meanwhile goes after them, in the store's order.
  property var order: []
  function held(list) {
    if (root.order.length === 0) return list
    var pos = {}
    for (var i = 0; i < root.order.length; i++) pos[root.order[i]] = i
    var keyed = list.map(function (it, i) { return { it: it, k: pos[it.id] !== undefined ? pos[it.id] : root.order.length + i } })
    keyed.sort(function (a, b) { return a.k - b.k })
    return keyed.map(function (x) { return x.it })
  }

  readonly property int cols: 4

  property bool cursorActive: false
  property int cursorRow: 0
  property int cursorCol: 0
  // The deadline the keys are on, so they stay on it when rows move.
  property int cursorId: 0
  function noteCursor() {
    var it = root.cursorActive ? root.shown[root.cursorRow] : null
    root.cursorId = it ? it.id : 0
  }
  onShownChanged: {
    if (root.cursorActive && root.cursorId > 0) {
      for (var i = 0; i < root.shown.length; i++) if (root.shown[i].id === root.cursorId) { root.cursorRow = i; return }
    }
    root.clampCursor()
    root.noteCursor()
  }

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
      root.noteCursor()
      return
    }
    if (dx !== 0) root.cursorCol += dx
    if (dy !== 0) root.cursorRow += dy
    root.clampCursor()
    root.noteCursor()
  }

  function pickCursor(row, col) {
    root.cursorActive = true
    root.cursorRow = row
    root.cursorCol = col
    root.noteCursor()
  }

  // A key that acts on a row, before the keys have a place: it shows where
  // they are, as an arrow does, rather than doing nothing (or acting on a
  // row no mark was on).
  function placed() {
    if (root.cursorActive || root.shown.length === 0) return root.cursorActive
    root.cursorActive = true
    root.clampCursor()
    root.noteCursor()
    return false
  }

  // A deadline a note line stands for: it has a line to open.
  function hasLine(item) {
    return !!item && /^\[\[[^\]#|]+#\^d\d+\]\]$/.test(item.link)
  }

  function selectedItem() {
    if (!root.cursorActive) return null
    return root.shown[root.cursorRow] || null
  }

  // Space ticks on a row, as on the dashboard's (2026-11-25, the keyboard
  // pass); Enter goes to its line. The shell's catcher sends both as
  // "activate", Enter after "return", so which one came is kept here.
  property bool viaReturn: false
  function spaceOrReturn() {
    var ret = root.viaReturn
    root.viaReturn = false
    if (!root.placed()) return
    if (!ret && root.cursorCol === 0) root.toggleSelected()
    else root.activateCursor()
  }

  function activateCursor() {
    var item = root.selectedItem()
    if (!item) return
    // Enter opens the note, if there is a line to open — the page's rule,
    // kept here so the key means one thing. A deadline no line stands for
    // has nothing to open: that is said (it used to tick it, the opposite
    // of what a click on the row does, which only picks it).
    if (root.cursorCol === 0) {
      if (root.hasLine(item)) root.openLine(item)
      else root.say("“" + item.title + "” has no line in a note · Space ticks it")
    }
    else if (root.cursorCol === 1) root.startGrade(item)
    else if (root.cursorCol === 2) root.hideItem(item)
    else root.cancelItem(item)
  }

  function toggleSelected() {
    if (!root.placed()) return
    var item = root.selectedItem()
    if (item) root.tickItem(item)
  }

  // ------------------------------------------------ what just happened

  // Said for a moment above the keys: what a key did that the list does not
  // show (a row gone when hidden or cancelled, an undo, a key with nothing
  // to do).
  property string said: ""
  function say(text) { root.said = text; saidTimer.restart() }
  Timer { id: saidTimer; interval: 4000; onTriggered: root.said = "" }

  // Ctrl+Z: what was changed here, newest last, each with what it was
  // before, so it can be put back. A hide and a cancel take the row off
  // the list, and before this nothing in the popup brought one back.
  property var changes: []
  function changed(item, what, after) {
    var c = { what: what, id: item.id, title: item.title, status: item.status, doneAt: item.doneAt, grade: item.grade,
              afterStatus: after.status !== undefined ? after.status : item.status,
              afterGrade: after.grade !== undefined ? after.grade : item.grade }
    root.changes = root.changes.concat([c]).slice(-20)
  }
  function undo() {
    if (root.changes.length === 0) { root.say("nothing to take back here"); return }
    var c = root.changes[root.changes.length - 1]
    root.changes = root.changes.slice(0, -1)
    var now = c.afterStatus
    if (now === "hidden") { svc.unhide(c.id); now = "done" }
    if (c.afterGrade !== c.grade) {
      svc.grade(c.id, c.grade)
      if (c.grade !== "" && now === "open") now = "done"
    }
    if (c.status === "open" && now !== "open") svc.reopen(c.id)
    else if (c.status === "done" && now !== "done") svc.markDoneAt(c.id, c.doneAt)
    root.say("took back: " + c.what + " “" + c.title + "”")
  }

  function hideItem(item) {
    root.changed(item, "hid", { status: "hidden" })
    svc.hide(item.id)
    root.say("hid “" + item.title + "” · Ctrl+Z brings it back")
  }
  function cancelItem(item) {
    root.changed(item, "cancelled", { status: "cancelled" })
    svc.cancel(item.id)
    root.say("cancelled “" + item.title + "” · Ctrl+Z brings it back")
  }

  // The tick, as the page's (2026-10-18): a short, soft sound when a
  // deadline is marked done — never on reopening it, never while
  // notifications are silenced, never when the page's Settings turned the
  // sound off — and the row's mark pops, the strike is drawn left to right,
  // the row glows and settles. The day it was done is the check's to write.
  property int justTicked: 0
  property int ticksHeard: 0
  readonly property string tickFile: String(Qt.resolvedUrl("tick.wav")).replace(/^file:\/\//, "")
  readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/longhand/settings.json"
  FileView { id: pageSettings; path: root.settingsPath; watchChanges: true; onFileChanged: reload(); printErrors: false }
  function tickSoundOn() {
    try { return (JSON.parse(pageSettings.text()) || {}).tickSound !== false } catch (e) { return true }
  }
  Process { id: tickSoundProc }
  function tickItem(item) {
    if (item.status === "open") {
      root.justTicked = item.id
      if (root.tickSoundOn()) {
        root.ticksHeard++
        // LONGHAND_SILENT unset is null, not "" (the tick was never heard
        // while this compared with "": 2026-10-19).
        if (!tickSoundProc.running && !Quickshell.env("LONGHAND_SILENT")) {
          tickSoundProc.command = ["sh", "-c", '[ "$(omarchy-shell notifications isDnd 2>/dev/null)" = on ] && exit 0; '
            + 'if command -v pw-play >/dev/null; then exec pw-play --volume=0.6 "$0"; else exec paplay "$0"; fi', root.tickFile]
          tickSoundProc.running = true
        }
      }
    }
    root.changed(item, item.status === "open" ? "ticked" : "unticked", { status: item.status === "open" ? "done" : "open" })
    svc.toggleDone(item)
  }

  function gradeSelected() {
    if (!root.placed()) return
    var item = root.selectedItem()
    if (item) root.startGrade(item)
  }

  // To the note line that stands for a deadline: the page opens on it.
  function openLine(item) {
    if (!root.hasLine(item)) return
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "longhand.page", JSON.stringify({ goto: item.link })])
    root.close()
  }

  function removeSelected() {
    if (!root.placed()) return
    var item = root.selectedItem()
    if (item) root.cancelItem(item)
  }

  // The rest of the list, where it is all worked through: the page's
  // dashboard.
  function openDashboard() {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "longhand.page", JSON.stringify({ view: "dashboard" })])
    root.close()
  }

  function startGrade(item) {
    root.pickCursor(root.shown.indexOf(item), 1)
    root.gradingId = item.id
  }

  function finishGrade(item, text) {
    if (root.gradingId !== item.id) return
    root.gradingId = 0
    if (text !== item.grade) {
      root.changed(item, "graded", { grade: text, status: text !== "" && item.status === "open" ? "done" : item.status })
      svc.grade(item.id, text)
    }
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
    root.handOn = false
    root.handSeeded = false
    root.cursorActive = false
    root.cursorRow = 0
    root.cursorCol = 0
    root.cursorId = 0
    root.gradingId = 0
    root.said = ""
    // The rows as they are now, held until it closes.
    root.order = root.opened ? svc.items.map(function (it) { return it.id }) : []
    // Edits made while the page was closed (in Obsidian, a deleted line)
    // are caught when the popup opens, so it never shows a stale list.
    if (root.opened) svc.check()
  }

  // The keys' mark: drawn under a control's own paint, so the control's
  // hover fill (the pointer's) still shows over it, and the two read apart.
  component KeyMark: Rectangle {
    property color tint: root.foreground
    anchors.fill: parent
    z: -1
    radius: Style.cornerRadius
    color: Style.selectedFillFor(tint, Commons.Color.accent)
    border.width: 1
    border.color: Commons.Util.alpha(tint, 0.6)
  }

  // The hand on the mouse (docs/hints.md A and D), as in the page, which
  // this popup is not part of: the pointer's marks show only while the
  // hand moves it in here (more than 2 px), and any key that is not a
  // modifier alone puts them away, so a row the keys reach under a still
  // pointer is lit by the keys alone. Clicks act either way.
  property bool handOn: false
  property point handAt: Qt.point(-1, -1)
  function keysTook(event) {
    var k = event.key
    if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta
        || k === Qt.Key_AltGr || k === Qt.Key_Super_L || k === Qt.Key_Super_R) return
    root.handOn = false
  }
  // The first place heard after it opens is only where the pointer is,
  // not a move: a popup opened by a key under a still pointer lit what was
  // under it (its last place was from before; the third pass, 2026-11-25).
  property bool handSeeded: false
  function handMoved(p) {
    if (!root.handSeeded) { root.handAt = p; root.handSeeded = true; return }
    var moved = Math.abs(p.x - root.handAt.x) + Math.abs(p.y - root.handAt.y) > 2
    root.handAt = p
    if (moved) root.handOn = true
  }
  // The shell's Button paints its own hover from a MouseArea of its own,
  // with nothing to ask it by. Its hover is turned off, and one laid over
  // it that takes no button (so every click still reaches the button)
  // tells the button when the hand is on it, through `hasCursor`.
  function quietOwnHover(control, keep, keepTip) {
    for (var i = 0; i < control.children.length; i++) {
      var c = control.children[i]
      if (c !== keep && c.containsMouse !== undefined && c.hoverEnabled !== undefined) c.hoverEnabled = false
    }
    // Its own hint too: a long press still set its area's containsMouse,
    // and the shell's hint came up beside ours (the third pass).
    for (var j = 0; j < control.data.length; j++) {
      var d = control.data[j]
      if (d && d !== keepTip && d.delay !== undefined && d.text !== undefined && d.visible !== undefined)
        d.visible = Qt.binding(function () { return false })
    }
  }
  component HandButton: Button {
    id: handButton
    hasCursor: handButtonArea.containsMouse && root.handOn
    Component.onCompleted: root.quietOwnHover(handButton, handButtonArea, handButtonTip)
    MouseArea {
      id: handButtonArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.PointingHandCursor
    }
    PanelToolTip {
      id: handButtonTip
      visible: handButton.tooltipText !== "" && handButtonArea.containsMouse && root.handOn
      text: handButton.tooltipText
      fontFamily: handButton.fontFamily
    }
  }

  // The keys' row kept in sight when the list scrolls.
  function reveal(item) {
    var y = item.mapToItem(rows, 0, 0).y
    if (y < flick.contentY) flick.contentY = y
    else if (y + item.height > flick.contentY + flick.height) flick.contentY = y + item.height - flick.height
  }

  // One deadline's row. `item` is the deadline drawn there, `rowIndex` its
  // place in `shown` (the keys' row number).
  component DeadlineRow: CursorSurface {
    id: row
    property var item: ({})
    property int rowIndex: 0

    readonly property bool isDone: item.status !== undefined && item.status !== "open"
    // Only the row just ticked plays the tick; one already done is
    // simply drawn done.
    // (The strike is set here, not bound: the animation writes it.)
    onIsDoneChanged: {
      if (isDone && root.justTicked === item.id) { root.justTicked = 0; tickAnim.restart() }
      else { tickAnim.stop(); strike.progress = isDone ? 1 : 0; markText.scale = 1 }
    }
    Component.onCompleted: strike.progress = isDone ? 1 : 0
    SequentialAnimation {
      id: tickAnim
      ParallelAnimation {
        NumberAnimation { target: markText; property: "scale"; from: 1; to: 1.45; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: tickGlow; property: "opacity"; from: 0; to: 0.16; duration: 110 }
        NumberAnimation { target: strike; property: "progress"; from: 0; to: 0.15; duration: 110 }
      }
      ParallelAnimation {
        NumberAnimation { target: markText; property: "scale"; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 3 }
        NumberAnimation { target: strike; property: "progress"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: tickGlow; property: "opacity"; to: 0; duration: 650; easing.type: Easing.OutQuad }
      }
    }
    readonly property bool grading: root.gradingId > 0 && root.gradingId === item.id
    readonly property bool hasLine: root.hasLine(item)
    readonly property color textColor: isDone ? root.dim : root.foreground
    readonly property bool keyed: root.cursorActive && root.cursorRow === rowIndex
    // Its buttons show on the row the keys or the hand are on: on every
    // row at once they were twenty-four small words in an eight-row list.
    readonly property bool chipsShown: !grading && (keyed || (rowHover.hovered && root.handOn))
    onKeyedChanged: if (keyed) Qt.callLater(function () { root.reveal(row) })
    onGradingChanged: {
      if (!grading) return
      gradeField.text = item.grade || ""
      Qt.callLater(function () { gradeField.forceActiveFocus(); gradeField.selectAll() })
    }

    width: rows.width
    implicitHeight: rowContent.implicitHeight + Style.space(10)
    // Lit by the hand only where a click opens something: a row
    // with no line to open shows the arrow, so no fill either (its
    // ○ keeps a hover of its own).
    hasCursor: rowMouse.containsMouse && root.handOn && row.hasLine && !root.cellHot(rowIndex, 0)
    foreground: root.foreground

    HoverHandler { id: rowHover }

    KeyMark { visible: root.cellHot(row.rowIndex, 0) }

    // The glow a tick leaves for a moment.
    Rectangle {
      id: tickGlow
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.foreground
      opacity: 0
    }

    // The row (and its title) opens its line; one with no line to
    // open is only picked. Ticking is the mark's alone.
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.hasLine ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (row.hasLine) root.openLine(row.item)
        else root.pickCursor(row.rowIndex, 0)
      }
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

        // The mark on its own, so a tick can pop it. A click on it
        // ticks (or unticks), as the dashboard's box does, and puts the
        // keys there; its hit area reaches a little past the glyph.
        Text {
          id: markText
          textFormat: Text.PlainText
          text: row.isDone ? "✓" : "○"
          color: markMouse.containsMouse && root.handOn ? root.foreground : row.textColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: markMouse.containsMouse && root.handOn

          MouseArea {
            id: markMouse
            anchors.fill: parent
            anchors.margins: -Style.space(5)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.pickCursor(row.rowIndex, 0); root.tickItem(row.item) }
          }
        }

        Text {
          id: titleText
          Layout.fillWidth: true
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: row.item.title || ""
          color: row.textColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.underline: row.hasLine && rowMouse.containsMouse && root.handOn && !markMouse.containsMouse

          // Struck through, drawn rather than the font's, so a tick
          // can draw it left to right.
          Rectangle {
            id: strike
            property real progress: 0
            visible: progress > 0
            y: Math.round(titleText.height / 2)
            height: Math.max(1, Math.round(titleText.font.pixelSize * 0.07))
            width: Math.min(titleText.implicitWidth, titleText.width) * progress
            color: root.dim
          }
        }

        Text {
          textFormat: Text.PlainText
          text: row.item.status !== undefined ? root.statusText(row.item) : ""
          color: row.item.status !== undefined ? root.rowColor(row.item) : root.dim
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
          text: row.item.due === undefined ? "" : svc.fmtWhen(row.item.due)
            + (row.item.project ? " · " + row.item.project : "")
            + (row.isDone && row.item.doneAt > 0 ? "  ·  handed in " + svc.fmtDay(row.item.doneAt) : "")
            + (!row.hasLine && row.keyed ? "  ·  no line in a note" : "")
          color: row.isDone ? root.faint : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Its buttons. Hidden while this row is being graded so the
        // editor gets the full line, and on rows neither the keys nor
        // the hand are on (their room kept, so nothing moves).
        RowLayout {
          spacing: Style.space(4)
          opacity: row.chipsShown ? 1 : 0
          enabled: row.chipsShown
          visible: !row.grading
          Repeater {
            model: [
              // The grade itself is on the right already: once there is one,
              // the button only says what it does.
              { col: 1, label: "grade", tip: row.item.grade ? "Change the grade (g)" : "Type the grade (g)" },
              { col: 2, label: "hide", tip: "Keep the record, drop it from the list · Ctrl+Z brings it back" },
              { col: 3, label: "✕", tip: "Cancel (x) · Ctrl+Z brings it back" }
            ]

            HandButton {
              required property var modelData

              text: modelData.label
              tooltipText: modelData.tip
              fontSize: Style.font.caption
              fontFamily: root.fontFamily
              foreground: row.textColor
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(1)
              onClicked: {
                root.pickCursor(row.rowIndex, modelData.col)
                root.activateCursor()
              }
              KeyMark { tint: row.textColor; visible: root.cellHot(row.rowIndex, modelData.col) }
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

          // Handle Return/Escape here and accept them. The text
          // input itself ignores Return after emitting accepted, so
          // the same press would bubble up to the key catcher — which
          // finishGrade has just unblocked — and fire "activate" on
          // whatever cell the cursor is on, reopening the editor.
          Keys.onReturnPressed: function (event) { event.accepted = true; root.finishGrade(row.item, text.trim()) }
          Keys.onEnterPressed: function (event) { event.accepted = true; root.finishGrade(row.item, text.trim()) }
          Keys.onEscapePressed: function (event) { event.accepted = true; root.cancelGrade() }
          // Typing here is the keys too: the hand's marks go.
          Keys.onPressed: function (event) { root.keysTook(event) }
          // A click elsewhere keeps what was typed and gives the keys
          // back. Before, the field stayed open without them, and the
          // catcher, still blocked for it, let no Esc through.
          onActiveFocusChanged: if (!activeFocus && row.grading) root.finishGrade(row.item, text.trim())
        }
      }
    }
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
      ? (bar ? bar.urgent : Commons.Color.urgent)
      : (bar ? bar.barForeground : Commons.Color.foreground)
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
      onReturnRequested: root.viaReturn = true
      onActivateRequested: root.spaceOrReturn()
      onDeleteRequested: root.removeSelected()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      // Ctrl+L ticks, as it does in the note, the dashboard and the
      // sidebar's list; `e` as on the dashboard, and `d` stays beside it. The catcher reads keys by
      // their text, so the Ctrl key is read here, beside it, by its code.
      // Every key passes here first (both this and the catcher's own
      // handler run); the hand's marks go away with it.
      Keys.onPressed: function (event) {
        root.keysTook(event)
        if (root.gradingId > 0) return
        var ctrlOnly = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier)) === Qt.ControlModifier
        if (event.key === Qt.Key_L && ctrlOnly) {
          root.toggleSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Z && ctrlOnly) {
          root.undo()
          event.accepted = true
        }
      }
      onTextKey: function (t) {
        if (t === "d" || t === "D" || t === "e" || t === "E") root.toggleSelected()
        else if (t === "g" || t === "G") root.gradeSelected()
        else if (t === "o" || t === "O") { if (root.placed()) root.openLine(root.selectedItem()) }
        else if (t === "w" || t === "W") root.showWaiting = !root.showWaiting
      }

      HoverHandler {
        onPointChanged: if (hovered) root.handMoved(point.scenePosition)
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
          visible: root.listed.length === 0
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.waiting.length > 0 ? "Nothing due." : "Nothing due. A checkbox with a date in a Longhand note becomes one."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // The rows scroll once there are more than fit (eight open ones and
        // a few waiting, unfolded, ran past the popup's foot and were cut).
        Flickable {
          id: flick
          visible: root.shown.length > 0 || root.waiting.length > 0
          width: parent.width
          height: Math.min(rows.implicitHeight, Style.space(380))
          contentWidth: width
          contentHeight: rows.implicitHeight
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          clip: true

          Column {
            id: rows
            width: flick.width
            spacing: Style.space(6)

            Repeater {
              // A count, not the list: the rows stay the same rows when the
              // store is read again, so a tick is seen ticking and a grade
              // being typed is not wiped by the check that follows.
              model: root.listedShown.length
              DeadlineRow {
                required property int index
                item: root.listedShown[index] || ({})
                rowIndex: index
              }
            }

            // Done, not graded yet: folded until asked for, and drawn
            // above what it folds. A click folds or unfolds it, so the hand
            // lights it as it does a row.
            CursorSurface {
              visible: root.waiting.length > 0
              width: parent.width
              implicitHeight: waitingText.implicitHeight + Style.space(6)
              hasCursor: waitingMouse.containsMouse && root.handOn
              foreground: root.foreground

              Text {
                id: waitingText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: (root.showWaiting ? "▾ " : "▸ ") + "waiting for a grade · " + root.waiting.length + "   w"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: waitingMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showWaiting = !root.showWaiting
              }
            }

            Repeater {
              model: root.waitingShown.length
              DeadlineRow {
                required property int index
                item: root.waitingShown[index] || ({})
                rowIndex: root.listedShown.length + index
              }
            }
          }
        }

        // The rest are on the dashboard: a click goes there.
        Text {
          visible: root.hiddenCount > 0
          width: parent.width
          textFormat: Text.PlainText
          text: "+" + root.hiddenCount + " more · on the dashboard"
          color: moreMouse.containsMouse && root.handOn ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: moreMouse.containsMouse && root.handOn
          MouseArea {
            id: moreMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openDashboard()
          }
        }

        Text {
          visible: root.said !== ""
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.said
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.shown.length > 0 || root.waiting.length > 0
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.gradingId > 0
            ? "Enter saves the grade · Esc cancels"
            : root.shown.length === 0
              ? "w waiting · Tab the timer · Esc"
              : "↑↓ ←→ move · Enter its line · Space or Ctrl+L done · g grade · x cancel · Ctrl+Z undo · Tab the timer" + (root.waiting.length > 0 ? " · w waiting" : "")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
