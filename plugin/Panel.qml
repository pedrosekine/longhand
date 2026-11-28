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
// Left click toggles the progress popup, right click toggles pause/resume
// (or starts a focus session), middle click skips to the next phase.
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

  // The length typed (idle only), in minutes, as the hint under it says
  // and as `pomo start` takes it: 25 is 25:00, 5 is 5:00, up to 999. It
  // was a microwave's until the bar pass (2026-11-28): 25 was 25 seconds,
  // which started a 1-minute session, and the seconds could never be kept,
  // since pomo counts whole minutes. Nothing typed shows the usual length,
  // faint, and Enter starts that.
  property string entryDigits: ""

  function entryText() {
    return root.entryDigits === "" ? svc.fmt(svc.focusLen) : parseInt(root.entryDigits, 10) + ":00"
  }

  function startFromEntry() {
    var m = parseInt(root.entryDigits, 10)
    if (root.entryDigits === "") svc.toggle()
    else if (m > 0) svc.startFocus(m)
    else return
    root.entryDigits = ""
  }

  // The first Esc lets go of what was typed; the next closes.
  function escapeEntry() {
    if (root.entryDigits !== "") root.entryDigits = ""
    else root.close()
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

  // Skip and reset are not there while idle: nothing to skip or reset.
  function gridCols(row) {
    if (row === 0) return svc.phase === "idle" ? 2 : 4
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

  // Enter or Space before the keys have a place shows where they are, as
  // an arrow does: the first press is never lost, and never acts blind.
  function activateCursor() {
    if (!root.cursorActive) {
      root.cursorActive = true
      root.clampCursor()
      return
    }
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

  // Back to idle (reset, or a session left): the keys go to the length,
  // which is what there is to do next, not to a cell that has gone.
  Connections {
    target: svc
    function onPhaseChanged() {
      if (svc.phase === "idle") {
        root.cursorRow = 0
        root.cursorCol = 0
        if (root.opened) idleTimer.focus = true
      }
      root.clampCursor()
    }
  }

  // What the play button and the time do now, in words.
  readonly property string playTip: svc.phase === "idle" ? "Start focus · " + svc.fmt(svc.focusLen)
    : svc.expired ? "Start the " + (svc.phase === "focus" ? "break" : "focus")
    : svc.live ? "Pause"
    : svc.ready ? "Start" : "Resume"
  // Skip logs a count-up and an expired session, and nothing else; reset
  // logs nothing. Said, since the two looked alike and one loses the time.
  readonly property string skipTip: svc.countup ? "Finish: count this session, then a break"
    : svc.expired ? "Start the " + (svc.phase === "focus" ? "break" : "focus")
    : "Skip to the " + (svc.phase === "focus" ? "break · not counted" : "focus")
  readonly property string resetTip: svc.countup ? "Drop this session · not counted" : "Reset to idle"

  // The deadline a session is for (`pomo start --for`), by its name. The
  // store is read only while there is one.
  readonly property string storePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/longhand/deadlines.tsv"
  property string targetTitle: ""
  FileView {
    id: targetStore
    path: svc.target > 0 ? root.storePath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.findTarget()
    onLoadFailed: root.targetTitle = ""
  }
  function findTarget() {
    var lines = String(targetStore.text() || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("\t")
      if (f.length >= 3 && parseInt(f[0], 10) === svc.target) { root.targetTitle = f[2]; return }
    }
    root.targetTitle = ""
  }
  Connections {
    target: svc
    function onTargetChanged() { if (svc.target > 0) root.findTarget(); else root.targetTitle = "" }
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
  // modifier alone puts them away, so a cell the keys reach under a still
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
  // The shell's buttons paint their own hover from a MouseArea of theirs,
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
  component HandAction: PanelActionButton {
    id: handAction
    hasCursor: handActionArea.containsMouse && root.handOn
    Component.onCompleted: root.quietOwnHover(handAction, handActionArea, handActionTip)
    MouseArea {
      id: handActionArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.PointingHandCursor
    }
    PanelToolTip {
      id: handActionTip
      visible: handAction.tooltipText !== "" && handActionArea.containsMouse && root.handOn
      text: handAction.tooltipText
      fontFamily: handAction.fontFamily
    }
  }

  onOpenedChanged: {
    root.handOn = false
    root.handSeeded = false
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
    // The accent while a focus runs, as the tray's glyph is on Windows: a
    // break and a focus read the same "● 4:59" before.
    foreground: svc.live && svc.phase === "focus" ? Commons.Color.accent
      : (bar ? bar.barForeground : Commons.Color.foreground)
    // What it is doing and the day's count, then what each button does.
    // (No time: the bar takes the tip once, as the pointer comes, and the
    // label beside it already counts.)
    tooltipText: svc.stateText
      + (root.targetTitle !== "" ? " · for " + root.targetTitle : "")
      + " · " + (svc.dayCount === 1 ? "1 session" : svc.dayCount + " sessions") + " today"
      + "\nleft: the timer · right: " + (svc.phase === "idle" ? "start focus" : svc.live ? "pause"
        : svc.expired ? "start the next" : svc.ready ? "start" : "resume")
      + (svc.phase !== "idle" ? " · middle: skip" : "")
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
        // Leaving the duration entry returns control to the grid cursor.
        if (idleTimer.activeFocus) idleTimer.focus = false
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }
      // Every key passes here first (both handlers run), the hand's
      // marks go away with it.
      Keys.onPressed: function (event) { root.keysTook(event) }

      HoverHandler {
        onPointChanged: if (hovered) root.handMoved(point.scenePosition)
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // What state it is in, as the deadlines' popup names itself: focus
        // or break, paused or ready, counting up, done (the bar pass).
        Column {
          width: parent.width
          spacing: Style.space(2)
          PanelSectionHeader {
            text: svc.stateText.toUpperCase()
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            visible: root.targetTitle !== ""
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "for " + root.targetTitle
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

        CursorSurface {
          id: timerCell
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          implicitHeight: idleTimer.implicitHeight + Style.space(8)
          hasCursor: timerMouse.containsMouse && root.handOn && !root.cellHot(0, 0)
          foreground: root.foreground

          KeyMark { visible: root.cellHot(0, 0) }

          MouseArea {
            id: timerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: svc.phase === "idle" ? Qt.IBeamCursor : Qt.PointingHandCursor
            onClicked: {
              root.pickCursor(0, 0)
              if (svc.phase === "idle") idleTimer.focus = true; else svc.toggle()
            }
          }
          PanelToolTip {
            visible: timerMouse.containsMouse && root.handOn
            text: svc.phase === "idle" ? "Type the minutes · Enter starts" : root.playTip
            fontFamily: root.fontFamily
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

            // The digits stop here, before the key catcher hears them.
            Keys.onPressed: function (event) {
              root.keysTook(event)
              if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                if (root.entryDigits.length < 3 && !(root.entryDigits === "" && event.key === Qt.Key_0))
                  root.entryDigits += (event.key - Qt.Key_0)
                event.accepted = true
              } else if (event.key === Qt.Key_Backspace) {
                root.entryDigits = root.entryDigits.slice(0, -1)
                event.accepted = true
              }
            }
            Keys.onReturnPressed: root.startFromEntry()
            Keys.onEnterPressed: root.startFromEntry()
            Keys.onEscapePressed: root.escapeEntry()
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

          HandAction {
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: svc.live ? "\uf04c" : "\uf04b"
            tooltipText: root.playTip
            onClicked: { root.pickCursor(0, 1); svc.toggle() }
            KeyMark { visible: root.cellHot(0, 1) }
          }

          HandAction {
            visible: svc.phase !== "idle"
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: "\uf051"
            tooltipText: root.skipTip
            onClicked: { root.pickCursor(0, 2); svc.skip() }
            KeyMark { visible: root.cellHot(0, 2) }
          }

          HandAction {
            visible: svc.phase !== "idle"
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            iconText: "\uf021"
            tooltipText: root.resetTip
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

            HandButton {
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

        // How far along: only where there is a length to be along (not
        // idle, not counting up, where it was an empty bar).
        Rectangle {
          id: track
          visible: svc.effTotal > 0 && svc.phase !== "idle"
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

            HandButton {
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
          hasCursor: autoMouse.containsMouse && root.handOn && !root.cellHot(root.autoRow, 0)
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

        // Its keys, said as the deadlines popup says its own (2026-11-25,
        // the keyboard pass): the digits and Tab were found by no one.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: svc.phase === "idle"
            ? "↑↓ ←→ move · Enter picks · on the time: type minutes, Enter · Tab the deadlines · Esc"
            : "↑↓ ←→ move · Enter picks · Tab the deadlines · Esc"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
