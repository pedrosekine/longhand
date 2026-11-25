import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import qs.Ui

// Pomodoro bar widget: countdown label + progress popup (clock-style).
//
// Left click toggles the progress popup, right click toggles pause/resume,
// middle click skips to the next phase.
Panel {
  id: root
  moduleName: "longhand.pomo"
  ipcTarget: "longhand.pomo"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color background: Commons.Color.menu.background
  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
  // Blend toward the background rather than Qt.darker, as the deadline
  // popup does: on a light theme Qt.darker made the "quiet" text darker
  // than the text it should sit under, and the empty track as black as
  // the filled one, so the progress bar disappeared.
  readonly property color dim: root.mix(foreground, background, 0.40)
  readonly property color track: root.mix(foreground, background, 0.78)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Open-panel underline hint: span the painted label ("○ --:--") instead of
  // the bar's 55%-of-slot fallback, which floats over the middle of the text.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Counter scope toggle: 0 = day, 1 = week, 2 = month.
  property int scopeIndex: 0

  // Microwave-style duration entry (idle only): digits shift in from the
  // right, e.g. 2 -> --:-2, 25 -> --:25, 2500 -> 25:00, 25000 -> 250:00.
  property string entryDigits: ""

  function entryText() {
    var d = entryDigits
    while (d.length < 4) d = "-" + d
    if (d.length > 4) return d.substring(0, d.length - 2) + ":" + d.substring(d.length - 2)
    return d.substring(0, 2) + ":" + d.substring(2, 4)
  }

  function entrySeconds() {
    var d = entryDigits
    while (d.length < 4) d = "0" + d
    var ss = parseInt(d.substring(d.length - 2), 10)
    var mm = parseInt(d.substring(0, d.length - 2), 10)
    return mm * 60 + ss
  }

  function startFromEntry() {
    var s = entrySeconds()
    if (s <= 0) return
    svc.startFocus(Math.max(1, Math.round(s / 60)))
    root.entryDigits = ""
  }

  // Keyboard grid cursor. The panel is treated as a grid: row 0 is the
  // timer + action buttons, row 1 the presets (idle only), then scope and
  // auto-start. Arrows move the cursor (column preserved when moving
  // vertically), Enter/Space activate the cell. Hover never moves it, as in
  // the page (docs/hints.md): the pointer paints the controls' own faint
  // hover look, the keys' cell wears `KeyMark` (the selected fill and a
  // ring, so it never reads as hover or as the chosen scope). A click is a
  // deliberate act, so it does bring the keys' cursor to what was clicked.
  property bool cursorActive: false
  property int cursorRow: 0
  property int cursorCol: 0

  // Row addresses shift when the preset row collapses outside idle.
  readonly property int scopeRow: svc.phase === "idle" ? 2 : 1
  readonly property int autoRow: svc.phase === "idle" ? 3 : 2

  function gridRows() {
    return svc.phase === "idle" ? 4 : 3
  }

  function gridCols(row) {
    if (row === 0) return 4
    if (row === 1) return svc.phase === "idle" ? 4 : 3
    if (row === 2) return svc.phase === "idle" ? 3 : 1
    return 1
  }

  function cellHot(row, col) {
    return root.cursorActive && root.cursorRow === row && root.cursorCol === col
  }

  function clampCursor() {
    root.cursorRow = Math.max(0, Math.min(root.gridRows() - 1, root.cursorRow))
    root.cursorCol = Math.max(0, Math.min(root.gridCols(root.cursorRow) - 1, root.cursorCol))
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

  function pickCursor(row, col) {
    root.cursorActive = true
    root.cursorRow = row
    root.cursorCol = col
  }

  function activateCursor() {
    if (!root.cursorActive) return
    var r = root.cursorRow
    var c = root.cursorCol
    if (r === 0) {
      if (c === 0) { if (svc.phase === "idle") idleTimer.focus = true; else svc.toggle() }
      else if (c === 1) svc.toggle()
      else if (c === 2) svc.skip()
      else svc.reset()
    } else if (r === 1) {
      if (svc.phase === "idle") {
        if (c === 3) svc.startCountup()
        else svc.startFocus([15, 25, 45][c])
      } else root.scopeIndex = c
    } else if (r === 2) {
      if (svc.phase === "idle") root.scopeIndex = c
      else svc.autostartToggle()
    } else svc.autostartToggle()
  }

  Connections {
    target: svc
    function onPhaseChanged() { root.clampCursor() }
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

  onOpenedChanged: {
    console.debug("pomo-debug opened", opened, "phase", svc.phase)
    if (opened) {
      root.cursorActive = false
      root.cursorRow = 0
      root.cursorCol = 0
      if (svc.phase === "idle") idleTimer.focus = true
    } else root.entryDigits = ""
  }

  function scopeCount() {
    return scopeIndex === 0 ? svc.dayCount : scopeIndex === 1 ? svc.weekCount : svc.monthCount
  }

  function scopeSec() {
    return scopeIndex === 0 ? svc.daySec : scopeIndex === 1 ? svc.weekSec : svc.monthSec
  }

  function focusedText() {
    var s = scopeSec()
    var h = Math.floor(s / 3600)
    var m = Math.round((s % 3600) / 60)
    if (m === 60) { h++; m = 0 }
    return h > 0 ? h + "h " + (m < 10 ? "0" + m : m) + "m" : m + "m"
  }

  function scopeText() {
    var n = scopeCount()
    return (n === 1 ? "1 session" : n + " sessions") + "   ·   " + root.focusedText()
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
    tooltipText: "Pomodoro — left: progress, right: pause/resume, middle: skip"
    onPressed: function (b) {
      if (b === Qt.RightButton) svc.toggle()
      else if (b === Qt.MiddleButton) svc.skip()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function (dx, dy) {
        console.debug("pomo-debug move", dx, dy, "cursorActive", root.cursorActive)
        // Leaving the duration entry returns control to the grid cursor.
        if (idleTimer.activeFocus) idleTimer.focus = false
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

        CursorSurface {
          id: timerCell
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          implicitHeight: idleTimer.implicitHeight + Style.space(8)
          hasCursor: timerMouse.containsMouse && !root.cellHot(0, 0)
          foreground: root.foreground

          KeyMark { visible: root.cellHot(0, 0) }

          MouseArea {
            id: timerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.pickCursor(0, 0)
              if (svc.phase === "idle") idleTimer.focus = true; else svc.toggle()
            }
          }

          Text {
            id: idleTimer
            visible: svc.phase === "idle"
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.entryText()
            color: root.entryDigits === "" ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display

            Keys.onPressed: function (event) {
              if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                if (root.entryDigits.length < 5) root.entryDigits += (event.key - Qt.Key_0)
                event.accepted = true
              } else if (event.key === Qt.Key_Backspace) {
                root.entryDigits = root.entryDigits.slice(0, -1)
                event.accepted = true
              }
            }
            Keys.onReturnPressed: root.startFromEntry()
            Keys.onEnterPressed: root.startFromEntry()
            Keys.onEscapePressed: root.close()
          }

          Text {
            id: runTimer
            visible: svc.phase !== "idle"
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (svc.countup && svc.runStatus !== "paused" ? "↑ " : "") + svc.fmt(svc.remaining)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
        }

          PanelActionButton {
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: svc.runStatus === "running" && !svc.expired ? "\uf04c" : "\uf04b"
            tooltipText: svc.expired ? "Start next phase" : svc.runStatus === "running" ? "Pause" : svc.ready ? "Start" : "Resume"
            onClicked: { root.pickCursor(0, 1); svc.toggle() }
            KeyMark { visible: root.cellHot(0, 1) }
          }

          PanelActionButton {
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: "\uf051"
            tooltipText: "Skip to next phase"
            onClicked: { root.pickCursor(0, 2); svc.skip() }
            KeyMark { visible: root.cellHot(0, 2) }
          }

          PanelActionButton {
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: "\uf021"
            tooltipText: "Reset to idle"
            onClicked: { root.pickCursor(0, 3); svc.reset() }
            KeyMark { visible: root.cellHot(0, 3) }
          }
        }

        RowLayout {
          visible: svc.phase === "idle"
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: ["15", "25", "45", "Up"]

            Button {
              required property string modelData
              required property int index

              Layout.fillWidth: true
              text: modelData === "Up" ? "Count up" : modelData + " min"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              onClicked: {
                root.pickCursor(1, index)
                if (modelData === "Up") svc.startCountup(); else svc.startFocus(modelData)
              }
              KeyMark { visible: root.cellHot(1, index) }
            }
          }
        }

        Rectangle {
          id: track
          width: parent.width
          implicitHeight: Style.space(6)
          radius: height / 2
          color: root.track

          Rectangle {
            width: track.width * svc.progress
            height: parent.height
            radius: parent.radius
            color: root.foreground
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: svc.effTotal > 0
          width: parent.width
          horizontalAlignment: Text.AlignLeft
          text: "Up next: " + (svc.phase === "focus" ? "break " : "focus ") + svc.fmt(svc.phase === "focus" ? svc.breakLen : svc.focusLen)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignLeft
          text: root.scopeText()
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: ["Day", "Week", "Month"]

            Button {
              required property string modelData
              required property int index

              Layout.fillWidth: true
              text: modelData
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.scopeIndex === index
              onClicked: { root.pickCursor(root.scopeRow, index); root.scopeIndex = index }
              KeyMark { visible: root.cellHot(root.scopeRow, index) }
            }
          }
        }

        CursorSurface {
          id: autoRow
          objectName: "pomoAutoRow"
          hasCursor: autoMouse.containsMouse && !root.cellHot(root.autoRow, 0)
          foreground: root.foreground

          width: parent.width
          implicitHeight: Math.max(autoLabel.implicitHeight, autoToggle.implicitHeight) + Style.space(10)

          KeyMark { visible: root.cellHot(root.autoRow, 0) }

          MouseArea {
            id: autoMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.pickCursor(root.autoRow, 0); svc.autostartToggle() }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(8)

            Text {
              id: autoLabel
              Layout.fillWidth: true
              textFormat: Text.PlainText
              verticalAlignment: Text.AlignVCenter
              text: "Auto-start breaks & focus"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            ToggleSwitch {
              id: autoToggle
              Layout.alignment: Qt.AlignVCenter
              checked: svc.autoStart
              foreground: root.foreground
              interactive: false
              // The row owns the click and both marks (interactive: false).
              onToggled: svc.autostartToggle()
            }
          }
        }
      }
    }
  }
}
