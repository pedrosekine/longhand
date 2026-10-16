import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Pomodoro bar widget: countdown label + progress popup (clock-style).
//
// Left click toggles the progress popup, right click toggles pause/resume,
// middle click skips to the next phase.
Panel {
  id: root
  moduleName: "longhand.pomo"
  ipcTarget: "longhand.pomo"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
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
  // vertically), Enter/Space activate the cell, and mouse hover drives the
  // same state so exactly one highlight is on screen at any time.
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

  function hoverCursor(row, col) {
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
          hasCursor: root.cellHot(0, 0)
          foreground: root.foreground

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) root.hoverCursor(0, 0)
            onClicked: if (svc.phase === "idle") idleTimer.focus = true; else svc.toggle()
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
            hasCursor: root.cellHot(0, 1)
            onHovered: function (h) { if (h) root.hoverCursor(0, 1) }
            onClicked: svc.toggle()
          }

          PanelActionButton {
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: "\uf051"
            tooltipText: "Skip to next phase"
            hasCursor: root.cellHot(0, 2)
            onHovered: function (h) { if (h) root.hoverCursor(0, 2) }
            onClicked: svc.skip()
          }

          PanelActionButton {
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: "\uf021"
            tooltipText: "Reset to idle"
            hasCursor: root.cellHot(0, 3)
            onHovered: function (h) { if (h) root.hoverCursor(0, 3) }
            onClicked: svc.reset()
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
              hasCursor: root.cellHot(1, index)
              onHovered: function (h) { if (h) root.hoverCursor(1, index) }
              onClicked: modelData === "Up" ? svc.startCountup() : svc.startFocus(modelData)
            }
          }
        }

        Rectangle {
          id: track
          width: parent.width
          implicitHeight: Style.space(6)
          radius: height / 2
          color: Qt.darker(root.foreground, 3.2)

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
              hasCursor: root.cellHot(root.scopeRow, index)
              onHovered: function (h) { if (h) root.hoverCursor(root.scopeRow, index) }
              onClicked: root.scopeIndex = index
            }
          }
        }

        CursorSurface {
          id: autoRow
          hasCursor: root.cellHot(root.autoRow, 0)
          foreground: root.foreground

          Layout.fillWidth: true
          implicitHeight: Math.max(autoLabel.implicitHeight, autoToggle.implicitHeight) + Style.space(10)

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) root.hoverCursor(root.autoRow, 0)
            onClicked: svc.autostartToggle()
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
              hasCursor: autoRow.hasCursor
              onHovered: function (h) { if (h) root.hoverCursor(root.autoRow, 0) }
              onToggled: svc.autostartToggle()
            }
          }
        }
      }
    }
  }
}
