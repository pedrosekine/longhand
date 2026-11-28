import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QC
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "Blocks.js" as Blocks
import "Bound.js" as Bound
import "Dates.js" as Dates
import "Days.js" as Days
import "Task.js" as Task
import "Authorship.js" as Authorship
import "Shortcuts.js" as Sc
import "Tags.js" as Tags
import "Say.js" as Say

// The sidebar: the calendar, the day's deadlines, the projects, keys and settings at its foot
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: sidebar
  required property Item page
  readonly property var editor: page.editorItem
  readonly property var sectionsProc: page.sectionsProcess
  readonly property var sheet: page.sheetItem
  readonly property var svc: page.noteService
  // Today, as the calendar keys its days. Read again whenever the service's
  // clock moves to another day, so a page left open overnight marks the
  // new one (until 2026-10-19 it kept marking the day it was opened).
  readonly property string todayKey: { svc.today; return Days.key(new Date()) }
  property alias sidebarKeysRef: sidebarKeys
  property alias projectFieldRef: projectField
  property alias projectAskRef: projectAsk   // a press outside it closes it (Page.pressedAt)
  property alias filesFilterRef: filesPane.filterFieldRef
  property alias filesPaneRef: filesPane

  onVisibleChanged: if (!visible) page.addingProject = false

  visible: page.sidebarOpen && page.problem === ""
  // Against the window's left edge, as the right pane is against its
  // right, whatever is in the middle (the student, 2026-10-24: no dead
  // strip outside a pane). The note is centred in the room between them
  // (page.sheetX, 2026-11-25).
  x: page.edge
  y: sheet.y
  height: sheet.height
  width: page.sidebarWidth
  radius: page.alongside ? 0 : page.overlayRadius
  // Each space has its own tint, so where you are is known before it is
  // read (docs/files.md): Time on the sheet's own ground, Files a breath of
  // the accent over it.
  color: page.sidebarSpace === "files" ? Qt.tint(page.background, Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0.06)) : page.background
  Behavior on color { ColorAnimation { duration: 240 } }
  borderSpec: page.cardSpec
  padding: page.sp(16)

  // A space slides in from the side it was called from, as Zen's do.
  property real spaceShift: 0
  NumberAnimation { id: spaceSlide; target: sidebar; property: "spaceShift"; to: 0; duration: 220; easing.type: Easing.OutCubic }
  Connections {
    target: page
    function onSidebarSpaceChanged() {
      sidebar.spaceShift = page.spaceStep * page.sp(28)
      spaceSlide.restart()
    }
  }

  // Swiping between the spaces: two fingers sideways on the sidebar, one
  // space per gesture. Ctrl and the wheel did it too until 2026-11-25 (the
  // mouse pass); that is the page's zoom now, everywhere (Page.qml).
  property real swipeTravel: 0
  property bool swiped: false
  Timer { id: swipeRest; interval: 280; onTriggered: { sidebar.swipeTravel = 0; sidebar.swiped = false } }
  WheelHandler {
    target: null
    onWheel: function (e) {
      var dx = e.pixelDelta.x !== 0 ? e.pixelDelta.x : e.angleDelta.x / 4
      var dy = e.pixelDelta.y !== 0 ? e.pixelDelta.y : e.angleDelta.y / 4
      var d = Math.abs(dx) > Math.abs(dy) ? -dx : 0
      if (d === 0) return
      swipeRest.restart()
      if (sidebar.swiped) return
      sidebar.swipeTravel += d
      if (Math.abs(sidebar.swipeTravel) < page.sp(60)) return
      sidebar.swiped = true
      page.used("space-swipe")
      page.switchSpace(sidebar.swipeTravel > 0 ? 1 : -1)
    }
  }

  // A click in the pane is the keys into it, as everywhere (docs/navigation.md).
  MouseArea { anchors.fill: parent; onClicked: page.focusPane("left") }

  // In the window the sidebar sits on the same ground as the sheet; a
  // hairline keeps them apart.
  Rectangle {
    visible: page.alongside
    // On the pane's own edge, where the focus frame is drawn too: one line
    // (it sat half a gap outside until 2026-10-24, from when the pane
    // hugged the note, and the frame ran inside it).
    anchors.right: parent.right
    width: 1
    height: parent.height
    color: page.faint
  }

  // The sidebar's keys, in one function so the page can be driven without
  // a keyboard (tests/page/run.py). True when the key was taken.
  function keyPressed(event) {
    // The panes' keys are global (page.anywhereKey): Ctrl+[ closes the
    // sidebar from here, Alt+→ moves on and leaves it open.
    if (page.anywhereKey(event)) return true
    // Words selected in an answer beside it: Ctrl+C copies them, Ctrl+R
    // answers them, as from the note and the PDF (2026-11-25, the mouse pass).
    if (page.chatSelectionKey(event, false)) return true
    // `?`: the keys, from any of its lists (the files' filter types it).
    if (Sc.hit(event, "keysHere")) { page.toggleKeys(); return true }
    if (page.sidebarSpace === "files") return filesPane.keyPressed(event)
    // Inside a project: its sections, newest first. Enter opens one in
    // the sheet (the list stays), Left or Esc goes back to the list of
    // projects.
    // The ends, a screenful, a fold opened by → and closed by ← where it
    // is, and the row keys a project has on the list of projects (a new
    // section, its tag) — the same vocabulary inside it as on it
    // (2026-11-28, the sidebar pass).
    if (page.projectOpen) {
      var row = page.projectRow
      var fold = row && row.kind === "fold" ? row : null
      if (Sc.hit(event, "listPage")) page.openProjectPage(page.projectTag)
      else if (Sc.hit(event, "listWeek")) page.openProjectWeek(page.projectTag)
      else if (Sc.hit(event, "listUp")) page.moveSectionFocus(-1)
      else if (Sc.hit(event, "listDown")) page.moveSectionFocus(1)
      else if (Sc.hit(event, "listFirst")) page.moveSectionFocus(-page.projectRows.length)
      else if (Sc.hit(event, "listLast")) page.moveSectionFocus(page.projectRows.length)
      else if (Sc.hit(event, "listScreenUp")) page.moveSectionFocus(-sidebar.screenRows())
      else if (Sc.hit(event, "listScreenDown")) page.moveSectionFocus(sidebar.screenRows())
      else if (Sc.hit(event, "listClass")) { var c = page.projectHere(); if (c) page.startClass(c) }
      else if (Sc.hit(event, "listTag")) { var t = page.projectHere(); if (t) page.insertTag(t) }
      else if (Sc.hit(event, "listOpen")) page.openInProject()
      else if (Sc.hit(event, "listInto") && fold) { if (!fold.open) page.openInProject() }
      else if (event.key === Qt.Key_Left && fold && fold.open) page.openInProject()
      else if (Sc.hit(event, "listBack")) page.leaveProject()
      else return false
      return true
    }
    // Type to go (plan.md item 19): once `#` is pressed, the letters pick
    // a project, wherever the keys are under the calendar or in it.
    if (page.sideTyping && page.sideTypeKey(event)) return true
    if (Sc.hit(event, "sideReach")) { page.sideReachStart(); return true }
    if (page.sideFindStart(event)) return true
    // Under the calendar the lists are one walk (plan.md item 19): the
    // arrows go on from one list into the next, Tab skips a list, and the
    // keys of the row (Enter, done, a section…) are the list's own.
    if (page.sideList !== "" && page.listWalk(event)) return true
    // In the day's deadline list: Enter goes to the line, Ctrl+L marks it
    // done (again: not done), as in the note.
    // A key with Ctrl or Alt it does not use goes on to the calendar.
    // Ctrl+Z takes back a deadline ticked here, as on the dashboard.
    if (Sc.hit(event, "dashUndo")) { page.untickLast(); return true }
    if (page.dueFocus >= 0) {
      if (page.dueKey(event)) return true
      // Any other key leaves the list, one with Ctrl or Alt for the
      // calendar below.
      if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) { page.dueFocus = -1; return false }
    }
    if (page.readToday.at >= 0) {
      if (page.readToday.keyPressed(event)) return true
      if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) { page.readToday.at = -1; return false }
    }
    // As from the deadlines: a key with Ctrl or Alt the list does not use
    // goes on to the calendar (Ctrl+← a month back from any list).
    if (page.projFocus >= 0) {
      if (page.projectsKey(event)) return true
      if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) return false
    }
    // (The projects' list always has a row: the one that makes a new one.)
    if (Sc.hit(event, "calLists")) {
      if (page.focusDue.length > 0) page.dueFocus = 0
      else if (page.readToday.rows.length > 0) page.readToday.at = 0
      else page.projFocus = 0
    } else if (Sc.hit(event, "calProjects")) {
      page.sidePut("proj", 0)
    } else if (Sc.hit(event, "calBack")) {
      page.toggleSidebar()
    } else if (Sc.hit(event, "calPrevDay")) {
      page.moveCalendar(-1, 0)
    } else if (Sc.hit(event, "calNextDay")) {
      page.moveCalendar(1, 0)
    } else if (Sc.hit(event, "calPrevWeek")) {
      page.moveCalendar(-7, 0)
    } else if (Sc.hit(event, "calNextWeek")) {
      page.moveCalendar(7, 0)
    } else if (Sc.hit(event, "calPrevMonth")) {
      page.moveCalendar(0, -1)
    } else if (Sc.hit(event, "calNextMonth")) {
      page.moveCalendar(0, 1)
    } else if (Sc.hit(event, "calToday")) {
      page.calFocus = new Date()
    } else if (Sc.hit(event, "calOpen")) {
      page.openCalendarDay(page.calFocus)
    } else {
      return false
    }
    return true
  }

  Item {
    id: sidebarKeys
    anchors.fill: parent
    Keys.onPressed: function (event) { if (sidebar.keyPressed(event)) event.accepted = true }
    onActiveFocusChanged: if (!activeFocus) page.sideTyping = false
  }

  // How many rows a screenful of the project's list is, about: PgUp/PgDn
  // move by it.
  function screenRows() { return Math.max(3, Math.floor(projectFlick.height / page.sp(44))) }

  // What the keys are on, scrolled into view: the lists grow with every
  // project, and the calendar and its lists scroll, clipped above the foot
  // (2026-11-17: they ran under it). Margin enough to see the row's
  // neighbour, so a walk never ends at the very edge.
  // `keep`: an item above it that must stay in sight too (the find box
  // while letters are typed into it), when both fit.
  function reveal(item, flick, content, keep) {
    Qt.callLater(function () {
      if (!item || !flick.visible) return
      var y = item.mapToItem(content, 0, 0).y
      var pad = page.sp(24)
      var top = flick.contentY, bottom = flick.contentY + flick.height
      var to = top
      if (y - pad < top) to = y - pad
      else if (y + item.height + pad > bottom) to = y + item.height + pad - flick.height
      if (keep) {
        var ky = keep.mapToItem(content, 0, 0).y - page.sp(8)
        if (ky < to && y + item.height - ky <= flick.height) to = ky
      }
      flick.contentY = Math.max(0, Math.min(to, flick.contentHeight - flick.height))
    })
  }
  Connections {
    target: page
    function onSideTypingChanged() { if (page.sideTyping && timeFlick.visible) sidebar.reveal(findBox, timeFlick, calendar) }
  }

  // A clipped edge with more beyond it fades out, so a row cut in half
  // reads as "there is more", not as a mistake (2026-11-17).
  component EdgeFade: Rectangle {
    required property Flickable flick
    property bool atTop: false
    visible: flick.visible && (atTop ? flick.contentY > 1 : flick.contentY + flick.height < flick.contentHeight - 1)
    x: flick.x
    width: flick.width
    y: atTop ? flick.y : flick.y + flick.height - height
    height: page.sp(28)
    z: 5
    transform: Translate { x: sidebar.spaceShift }
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(sidebar.color.r, sidebar.color.g, sidebar.color.b, atTop ? 1 : 0) }
      GradientStop { position: 1; color: Qt.rgba(sidebar.color.r, sidebar.color.g, sidebar.color.b, atTop ? 0 : 1) }
    }
  }
  // The find box: where typed letters show (they need no key before them),
  // how many projects they leave, and a click to start. Not a field: the
  // sidebar's keys feed it, so arrows and Enter keep working on the list.
  component FindBox: Rectangle {
    id: box
    readonly property bool typing: page.sideTyping
    readonly property bool keysHere: sidebarKeys.activeFocus
    height: findRow.implicitHeight + page.sp(10)
    radius: Style.cornerRadius
    color: typing ? Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.05) : "transparent"
    border.width: 1
    border.color: typing ? page.dim : Qt.rgba(page.faint.r, page.faint.g, page.faint.b, findArea.containsMouse && page.handOn ? 0.9 : 0.5)
    Row {
      id: findRow
      anchors.left: parent.left
      anchors.leftMargin: page.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: page.sp(8)
      readonly property real room: box.width - page.sp(8) - findCount.implicitWidth - page.sp(16) - findIcon.implicitWidth - spacing
      Text {
        id: findIcon
        readonly property string winIcons: {
          var f = Qt.fontFamilies()
          return f.indexOf("Segoe Fluent Icons") >= 0 ? "Segoe Fluent Icons"
            : f.indexOf("Segoe MDL2 Assets") >= 0 ? "Segoe MDL2 Assets" : ""
        }
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: winIcons !== "" ? "\ue721" : "\uf002"
        color: box.typing ? page.foreground : page.faint
        font.family: winIcons !== "" ? winIcons : Style.font.family
        font.pixelSize: Math.round(page.fs(Style.font.caption) * 0.95)
      }
      Text {
        id: findText
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, findRow.room))
        // The last letters typed stay in sight (the start goes first).
        elide: box.typing ? Text.ElideLeft : Text.ElideRight
        textFormat: Text.PlainText
        text: box.typing && page.sideTyped !== "" ? page.sideTyped
          : box.keysHere ? "type to find a project" : "find a project"
        color: box.typing && page.sideTyped !== "" ? page.foreground : page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
    }
    // The caret, after the letters, while they are being typed.
    Rectangle {
      visible: box.typing
      x: findRow.x + findText.x + (page.sideTyped !== "" ? findText.width + page.sp(1) : 0)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(1, page.sp(1.5))
      height: findText.implicitHeight * 0.9
      color: page.accent
      SequentialAnimation on opacity {
        running: box.typing
        loops: Animation.Infinite
        NumberAnimation { to: 0; duration: 530; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1; duration: 530; easing.type: Easing.InOutQuad }
      }
    }
    Text {
      id: findCount
      anchors.right: parent.right
      anchors.rightMargin: page.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: box.typing && page.sideTyped !== "" ? page.sideMatches.length + " of " + page.projects.length
        : page.projects.length + (page.projects.length === 1 ? " project" : " projects")
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
    MouseArea {
      id: findArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.IBeamCursor
      // A click while letters are in it clears them, as Esc does.
      onClicked: { page.focusPane("left"); if (!page.sideTyping) page.sideReachStart(); else { page.sideTyped = ""; page.sideTyping = false } }
      Tip { host: page; shown: parent.containsMouse; text: page.sideTyping && page.sideTyped !== "" ? page.tip("Clear the letters", "") : page.tip("Find a project: type its letters wherever the sidebar has the keys", "sideReach") }
    }
  }
  EdgeFade { flick: timeFlick; atTop: true }
  EdgeFade { flick: timeFlick }
  EdgeFade { flick: projectFlick; atTop: true }
  EdgeFade { flick: projectFlick }

  Flickable {
    id: timeFlick
    acceptedButtons: Qt.NoButton
    QC.ScrollBar.vertical: ScrollMark { page: sidebar.page }
    visible: page.sidebarSpace === "time" && !page.projectOpen
    transform: Translate { x: sidebar.spaceShift }
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footTop.top
    anchors.topMargin: sidebar.contentTopInset
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    clip: true
    contentWidth: width
    contentHeight: calendar.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    TouchScroll { flickable: timeFlick }

    Column {
      id: calendar
      width: timeFlick.width
      spacing: page.sp(10)

      readonly property real cell: Math.floor(width / 7)

      // Month, with a way to step it by mouse.
      Item {
        width: parent.width
        height: monthText.implicitHeight

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "‹"
          color: prevArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.title)
          MouseArea {
            id: prevArea
            anchors.fill: parent
            anchors.margins: -page.sp(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.focusPane("left"); page.moveCalendar(0, -1) }
            Tip { host: page; shown: parent.containsMouse; text: page.tip("A month back", "calPrevMonth") }
          }
        }
        Text {
          id: monthText
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: Days.monthLabel(page.calFocus)
          color: page.foreground
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.body)
          font.weight: Font.DemiBold
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "›"
          color: nextArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.title)
          MouseArea {
            id: nextArea
            anchors.fill: parent
            anchors.margins: -page.sp(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.focusPane("left"); page.moveCalendar(0, 1) }
            Tip { host: page; shown: parent.containsMouse; text: page.tip("A month on", "calNextMonth") }
          }
        }
      }

      Grid {
        columns: 7

        // Weekday initials, from the locale's first day.
        Repeater {
          model: 7
          Text {
            required property int index
            width: calendar.cell
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: Qt.locale().dayName((page.firstDow + index) % 7, Locale.NarrowFormat)
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }

        // The days: full where a note exists, faded where none does.
        Repeater {
          model: page.calCells
          Item {
            id: dayCell
            required property var modelData
            readonly property string k: modelData ? Days.key(modelData) : ""
            readonly property bool hasNote: k !== "" && !!page.dayIndex[k]
            readonly property bool isOpen: k !== "" && k === page.openKey
            readonly property bool isCursor: k !== "" && k === Days.key(page.calFocus)
            readonly property bool isToday: k !== "" && k === sidebar.todayKey
            width: calendar.cell
            height: Math.round(calendar.cell * 0.92)
            // The pointer follows the keys (page.selected).
            // Only while the keys are on the grid: on a list under it, the
            // day keeps its outline and the row alone is lit (2026-11-28: both
            // were filled alike, two selections at once).
            readonly property bool lit: dayCell.isCursor && sidebarKeys.activeFocus && page.sideList === "" && !page.sideTyping
            onLitChanged: { page.selected(dayCell, "left", lit); if (lit) sidebar.reveal(dayCell, timeFlick, calendar) }
            Component.onCompleted: if (lit) page.selected(dayCell, "left", true)

            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: Style.cornerRadius
              visible: dayCell.isCursor && sidebarKeys.activeFocus
              color: dayCell.lit ? Style.selectedFill : Qt.rgba(Style.selectedFill.r, Style.selectedFill.g, Style.selectedFill.b, Style.selectedFill.a * 0.4)
            }
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: Style.cornerRadius
              visible: dayArea.containsMouse && page.handOn && !dayCell.lit
              color: Style.hoverFill
            }
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: Style.cornerRadius
              visible: dayCell.isOpen
              color: "transparent"
              border.width: 1
              border.color: page.dim
            }
            Text {
              id: dayNum
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: modelData ? modelData.getDate() : ""
              color: dayCell.isToday || dayCell.hasNote ? page.foreground : page.faint
              font.family: page.fontFamily
              font.pixelSize: page.fs(Style.font.body)
              font.weight: dayCell.isOpen || dayCell.isToday ? Font.DemiBold : Font.Normal
            }
            // Today: a short bar close under the number, in the text colour
            // (2026-10-19). It marks the day without looking like a choice —
            // the open day's outline and the keys' fill stay the only marks
            // of what is selected — and, close to the digits, it never meets
            // the outline's edge. It was a dot in the accent, lost in a theme
            // whose accent is grey; a coloured disc read as a selection.
            Rectangle {
              visible: dayCell.isToday
              anchors.horizontalCenter: parent.horizontalCenter
              y: dayNum.y + dayNum.baselineOffset + page.sp(2)
              width: Math.round(calendar.cell * 0.25)
              height: Math.max(2, page.sp(2))
              radius: height / 2
              color: page.foreground
            }
            // Deadlines on this day: a corner mark — accent while one is
            // open, urgent when one is late, hollow when all are done.
            Rectangle {
              readonly property var due: dayCell.k !== "" ? (page.dueByDay[dayCell.k] || []).filter(function (d) { return d.status === "open" || d.status === "done" }) : []
              readonly property bool open: due.some(function (d) { return d.status === "open" })
              readonly property bool late: due.some(function (d) { return d.status === "open" && d.due * 1000 < page.sideNow })
              visible: due.length > 0
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.topMargin: Math.round(calendar.cell * 0.12)
              anchors.rightMargin: Math.round(calendar.cell * 0.12)
              width: Math.max(4, Math.round(calendar.cell * 0.16))
              height: width
              radius: Math.max(1, Math.round(width * 0.3))
              color: late ? page.urgent : (open ? page.accent : "transparent")
              border.width: open ? 0 : 1
              border.color: page.dim
            }
            MouseArea {
              id: dayArea
              anchors.fill: parent
              enabled: !!modelData
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.openCalendarDay(modelData)
              Tip { host: page; shown: parent.containsMouse && !!modelData; text: page.tips([["Open the day in the sheet", "calOpen"], ["Today", "calToday"]]) }
            }
          }
        }
      }

      // The day under the cursor, and whether it has a note yet.
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: svc.configured
          ? Days.longLabel(Days.format(page.calFocus, svc.dailyFormat()), svc.dailyFormat())
            + (page.dayIndex[Days.key(page.calFocus)] ? "" : " · no note")
          : ""
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      // That day's deadlines. Tab goes into the list; Enter or a click
      // goes to the line that stands for one, Ctrl+L marks it done.
      Repeater {
        model: page.focusDue
        Rectangle {
          id: dueCell
          required property var modelData
          required property int index
          readonly property bool late: modelData.status === "open" && modelData.due * 1000 < page.sideNow
          readonly property bool lit: page.dueFocus === index && sidebarKeys.activeFocus
          onLitChanged: { page.selected(dueCell, "left", lit); if (lit) sidebar.reveal(dueCell, timeFlick, calendar) }
          Component.onCompleted: if (lit) page.selected(dueCell, "left", true)
          width: calendar.width
          height: dueRow.implicitHeight + page.sp(6)
          radius: Style.cornerRadius
          color: page.dueFocus === index && sidebarKeys.activeFocus ? Style.selectedFill
            : (dueArea.containsMouse || dueTick.containsMouse) && page.handOn ? Style.hoverFill : "transparent"
          // Its mark by what it is (done ✓, dropped ✕, hidden –: the
          // calendar is history), and its hour unless it is the day's end,
          // as on the dashboard and in the note.
          readonly property var at: new Date(modelData.due * 1000)
          Text {
            id: dueRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: page.sp(4)
            anchors.rightMargin: page.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: (modelData.status === "open" ? "○ " : modelData.status === "done" ? "✓ " : modelData.status === "cancelled" ? "✕ " : "– ")
              + modelData.title
              + (dueCell.at.getHours() === 23 && dueCell.at.getMinutes() === 59 ? "" : " · " + Qt.formatTime(dueCell.at, "HH:mm"))
              + (modelData.project ? " · " + modelData.project : "")
              + (modelData.status === "cancelled" ? " · dropped" : modelData.status === "hidden" ? " · hidden" : "")
              + (Bound.parseLink(modelData.link) ? "" : " · no line")
            font.strikeout: modelData.status === "cancelled"
            color: late ? page.urgent : (modelData.status === "open" ? page.foreground : page.dim)
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          MouseArea {
            id: dueArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.focusPane("left"); page.dueFocus = dueCell.index; page.goToDeadline(modelData) }
            Tip { host: page; shown: parent.containsMouse; text: page.tips([["Go to its line", "listOpen"], [dueCell.modelData.status === "open" || dueCell.modelData.status === "done" ? "Done (again: not done)" : "Open it again", "listDone"]]) }
          }
          // The ○ (or ✓) ticks it, as Ctrl+L on the row, as a box does in
          // the note and on the dashboard (2026-11-25, the mouse pass: it
          // looked like a box and only went to the line).
          TextMetrics { id: tickInk; font: dueRow.font; text: "○ " }
          MouseArea {
            id: dueTick
            x: dueRow.x - page.sp(4)
            y: dueRow.y - page.sp(3)
            width: tickInk.advanceWidth + page.sp(6)
            height: tickInk.height + page.sp(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              page.focusPane("left")
              page.dueFocus = dueCell.index
              page.sideTick(dueCell.modelData)
            }
            Rectangle {
              anchors.centerIn: parent
              width: Math.round(tickInk.height * 0.9)
              height: width
              radius: width / 2
              color: "transparent"
              border.width: 1
              border.color: page.accent
              visible: dueTick.containsMouse && page.handOn
            }
            Tip { host: page; shown: parent.containsMouse; text: page.tip("Done (again: not done)", "listDone"); act: "listDone" }
          }
        }
      }

      // The papers marked that day (plan.md item 15, step 3): Tab goes into
      // the list after the deadlines; Enter or a click opens one where it
      // was left.
      Text {
        visible: page.readToday.rows.length > 0
        topPadding: page.sp(8)
        textFormat: Text.PlainText
        text: "READ"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      Repeater {
        model: page.readToday.rows
        Rectangle {
          id: readCell
          required property var modelData
          required property int index
          readonly property bool lit: page.readToday.at === index && sidebarKeys.activeFocus
          onLitChanged: { page.selected(readCell, "left", lit); if (lit) sidebar.reveal(readCell, timeFlick, calendar) }
          Component.onCompleted: if (lit) page.selected(readCell, "left", true)
          width: calendar.width
          height: readRow.implicitHeight + page.sp(6)
          radius: Style.cornerRadius
          color: lit ? Style.selectedFill : readArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
          Text {
            id: readRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: page.sp(4)
            anchors.rightMargin: page.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: (modelData.name || modelData.title) + " · " + page.readToday.summary(modelData)
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          MouseArea {
            id: readArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.focusPane("left"); page.readToday.at = readCell.index; page.remember(); page.openPdf(readCell.modelData.pdf) }
            Tip { host: page; shown: parent.containsMouse; text: page.tips([["Open it where it was left", "listOpen"]]) }
          }
        }
      }

      // The projects that exist: the tags to write, soonest session first.
      // In place of the "PROJECTS" heading (2026-11-22): the find box,
      // which names the list and shows what is typed to find in it.
      Item { width: 1; height: page.sp(4) }
      FindBox { id: findBox; width: calendar.width }
      // While letters are typed, only what they match, the best first.
      Repeater {
        model: page.sideTyping && page.sideTyped !== "" ? page.sideMatches : page.projects
        Rectangle {
          id: projCell
          required property var modelData
          // Its place in the list of projects, which the keys and Alt+digit go by.
          readonly property int index: page.projectIndex(modelData.tag)
          readonly property bool lit: page.projFocus === index && sidebarKeys.activeFocus
          // While letters are typed the box they show in stays in sight, its
          // matches under it (sidebar.revealFind).
          onLitChanged: { page.selected(projCell, "left", lit); if (lit) sidebar.reveal(projCell, timeFlick, calendar, page.sideTyping ? findBox : null) }
          Component.onCompleted: if (lit) page.selected(projCell, "left", true)
          width: calendar.width
          height: projCol.implicitHeight + page.sp(6)
          radius: Style.cornerRadius
          color: page.projFocus === index && sidebarKeys.activeFocus ? Style.selectedFill : projArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
          // Its key from anywhere, Alt and its place, shown by Hold Ctrl.
          KeyBadge {
            host: page
            fixedKey: projCell.index < 9 ? "Alt+" + (projCell.index + 1) : ""
            anchors.right: parent.right
            anchors.rightMargin: page.sp(2)
            anchors.top: parent.top
            anchors.topMargin: page.sp(2)
          }
          Column {
            id: projCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: page.sp(4)
            // Clear of Alt+digit, drawn over the row's corner while Ctrl is held.
            anchors.rightMargin: page.ctrlShown && projCell.index < 9 ? page.sp(44) : page.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: "#" + modelData.tag + "  " + modelData.name
              color: page.foreground
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.bodySmall)
            }
            Text {
              visible: !!modelData.next
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: page.sessionLabel(modelData.next)
              color: page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
          }
          MouseArea {
            id: projArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Tip {
              host: page
              shown: parent.containsMouse
              text: page.tips([["Its notes", "listOpen"], ["Shift-click: a new section for it", "listClass"], ["Ctrl-click: put its #tag at the cursor", "listTag"]])
            }
            onClicked: function (mouse) {
              if (mouse.modifiers & Qt.ControlModifier) page.insertTag(modelData)
              else if (mouse.modifiers & Qt.ShiftModifier) page.startClass(modelData)
              else page.openProject(modelData)
            }
          }
        }
      }

      // A new project (2026-10-22): its name, and its #tag when it should not
      // be the name's words. The runner makes its file; the list reads it.
      Rectangle {
        id: newCell
        visible: !page.addingProject
        // Lit too while the letters typed match nothing: Enter makes it.
        readonly property bool lit: sidebarKeys.activeFocus && (page.projFocus === page.projects.length
          || (page.sideTyping && page.sideTyped !== "" && page.sideMatches.length === 0))
        onLitChanged: { page.selected(newCell, "left", lit); if (lit) sidebar.reveal(newCell, timeFlick, calendar) }
        Component.onCompleted: if (lit) page.selected(newCell, "left", true)
        width: calendar.width
        height: newText.implicitHeight + page.sp(6)
        radius: Style.cornerRadius
        color: lit ? Style.selectedFill : newArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
        Text {
          id: newText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: page.sp(4)
          anchors.rightMargin: page.sp(8)
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: page.sideTyping && page.sideTyped !== "" ? "+ new project “" + page.sideTyped + "”" : "+ new project"
          color: newArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        MouseArea {
          id: newArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { var typed = page.sideTyping ? page.sideTyped : ""; page.sideTyping = false; page.projFocus = page.projects.length; page.openSidebarProject(typed) }
          Tip { host: page; shown: parent.containsMouse; text: page.tip("Make a project: in the sidebar, @ and #", "listOpen") }
        }
      }
      Column {
        id: projectAsk
        visible: page.addingProject
        width: calendar.width
        spacing: page.sp(2)
        readonly property var made: Tags.fromField(projectField.text, page.projects)
        TextField {
          FieldMenu { page: sidebar.page; field: parent }
          id: projectField
          width: parent.width
          placeholderText: "Master Thesis #thesis"
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
          foreground: page.foreground
          onVisibleChanged: if (visible) { text = ""; sidebar.reveal(projectAsk, timeFlick, calendar) }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            if (page.anywhereKey(event)) { event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { page.submitSidebarProject(text); event.accepted = true }
            else if (event.key === Qt.Key_Escape) { page.closeSidebarProject(); event.accepted = true }
          }
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: parent.made.tag === "" ? "its name, and its #tag when not the name's words · Esc leaves it"
            : parent.made.taken ? "#" + parent.made.tag + " is a project already"
            : "Enter makes #" + parent.made.tag + "  " + parent.made.name
          color: parent.made.taken ? page.urgent : page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }

    }
  }

  // The sidebar's foot: what supports the writing rather than the
  // writing itself — the keys and the settings — so the header keeps
  // only what belongs to the note (2026-10-17). Quiet, like the pin; a
  // word is bright while its sheet is open.
  // The Files space (docs/files.md): yours and the agent's notes, as
  // folders. Laid where the calendar is, above the foot.
  FilesPane {
    id: filesPane
    page: sidebar.page
    sidebar: sidebar
    visible: page.sidebarSpace === "files"
    transform: Translate { x: sidebar.spaceShift }
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footTop.top
    anchors.topMargin: sidebar.contentTopInset
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
  }

  // The keys for where you are, pinned above the foot (2026-11-17): at most
  // three, the ones not guessed — no arrows, no Esc — then `?` for every
  // key. It was a line at the end of each list, four lines long, moving
  // with the list and running under the foot. Only while the sidebar has
  // the keys: it is the keyboard's hint, as hover is the mouse's.
  // Each is [key, what it does]; a key of "" is words alone. The key is
  // drawn as a cap (KeyCaps), so it reads as a key, not as a word.
  readonly property var hintItems: {
    page.keysVersion
    var k = function (id) { return page.keyName(id) }
    var all = [k("keysHere"), "every key"]
    if (page.sidebarSpace === "files") return [[k("filesOpen"), "open"], [k("filesFilter"), "filter by name"], all]
    if (page.projectOpen) return [[k("listOpen"), "open"], [k("listPage"), "its page"], [k("listWeek"), "its week"], all]
    if (page.sideTyping) {
      var on = page.projects[page.projFocus]
      var hit = on && page.sideMatchTags.indexOf(on.tag) >= 0
      if (!hit && page.sideTyped !== "") return [[k("listOpen"), "new project"], ["Esc", "clear"]]
      return [[k("listOpen"), "notes"], [k("listClass"), "new section"], [k("listTag"), "put the tag"], ["Esc", "clear"]]
    }
    if (page.projFocus >= 0 && page.projFocus === page.projects.length) return [[k("listOpen"), "names a new project"], all]
    if (page.projFocus >= 0) return [[k("listOpen"), "notes"], [k("listClass"), "new section"], [k("listTag"), "put the tag"], all]
    if (page.dueFocus >= 0) return [[k("listOpen"), "to its line"], [k("listDone"), "done"], all]
    if (page.readToday.at >= 0) return [[k("listOpen"), "open where it was left"], all]
    return [[k("calOpen"), "open the day"], [k("calLists"), "the lists"], ["a–z", "find a project"], all]
  }
  readonly property bool hintShown: page.here === "left" && !page.addingProject

  // Where the scrolling stops: above the hint while it shows, else above
  // the rule over the foot.
  Item {
    id: footTop
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: sidebar.hintShown ? keysHint.top : footRule.top
    anchors.bottomMargin: page.sp(8)
    height: 0
  }
  Flow {
    id: keysHint
    visible: sidebar.hintShown
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footRule.top
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    anchors.bottomMargin: page.sp(10)
    spacing: page.sp(10)
    Repeater {
      model: sidebar.hintItems
      Row {
        required property var modelData
        spacing: page.sp(5)
        KeyCaps {
          anchors.verticalCenter: parent.verticalCenter
          page: sidebar.page
          key: modelData[0].replace(/^Shift\+/, "⇧+")
          size: page.fs(Style.font.caption)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData[1]
          color: page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
    }
  }
  // What scrolls, and the foot that stays: a hairline between.
  Rectangle {
    id: footRule
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: sidebarFoot.top
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    anchors.bottomMargin: page.sp(10)
    height: 1
    color: page.faint
    opacity: 0.6
  }

  // The foot, the same in every space (Zen's essentials), one row since
  // 2026-11-22 (the student: two rows of words, one split left and right,
  // "not a great experience"): which space, as a switch of two, then the
  // places that are not the sidebar's own — today, the dashboard, the
  // keys, the settings — as icons with their tips (as words they did not
  // fit in one row).
  Item {
    id: sidebarFoot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    anchors.bottomMargin: sidebar.contentBottomInset
    height: Math.max(spaceSwitch.height, footButtons.implicitHeight)

    Rectangle {
      id: spaceSwitch
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: spaceRow.implicitWidth + page.sp(4)
      height: spaceRow.implicitHeight + page.sp(4)
      radius: Style.cornerRadius + page.sp(2)
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(page.faint.r, page.faint.g, page.faint.b, 0.5)
      Row {
        id: spaceRow
        anchors.centerIn: parent
        spacing: 0
        Repeater {
          model: [{ space: "time", tip: "Time: the calendar, the day's deadlines, the projects" },
                  { space: "files", tip: "Files: your notes and the agent's, as folders" }]
          Rectangle {
            required property var modelData
            readonly property bool here: page.sidebarSpace === modelData.space
            width: spaceWord.implicitWidth + page.sp(18)
            height: spaceWord.implicitHeight + page.sp(6)
            radius: Style.cornerRadius
            color: here ? Style.selectedFill : spaceArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: 180 } }
            Text {
              id: spaceWord
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: modelData.space
              color: parent.here ? page.foreground : spaceArea.containsMouse && page.handOn ? page.accent : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
            MouseArea {
              id: spaceArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.setSpace(modelData.space, 0)
              // The key goes to the space not shown; the one shown just says what it is.
              Tip { host: page; act: parent.parent.here ? "" : "pane1"; shown: parent.containsMouse; text: parent.parent.here ? modelData.tip : page.tip(modelData.tip, "pane1") }
            }
          }
        }
      }
    }

    Row {
      id: footButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: page.sp(4)
      // The icons are a Nerd Font's, which the shell's face is on Omarchy.
      // Windows has no Nerd Font (the shell's face there is Cascadia Mono,
      // and the four came out as empty boxes), and has the same pictures in
      // its own icon face (`win`), as the find box's magnifier does.
      readonly property string winIcons: {
        var f = Qt.fontFamilies()
        return f.indexOf("Segoe Fluent Icons") >= 0 ? "Segoe Fluent Icons"
          : f.indexOf("Segoe MDL2 Assets") >= 0 ? "Segoe MDL2 Assets" : ""
      }
      Repeater {
        model: [{ icon: "\udb80\udcf6", win: "\ue8bf", act: "today", tip: "Today's note" },
                { icon: "\udb81\udd6e", win: "\uf246", act: "dashGo", tip: "The dashboard: every open task and deadline" },
                { icon: "\udb80\udf0c", win: "\ue765", act: "keys", tip: "Every key the page answers to, and moving one" },
                { icon: "\udb81\udc93", win: "\ue713", act: "settings", tip: "Settings: your calendars, the agent, sound" }]
        Rectangle {
          id: footButton
          required property var modelData
          readonly property bool open: modelData.act === "keys" ? page.keysOpen : modelData.act === "settings" ? page.centerView === "settings"
            : modelData.act === "dashGo" ? page.dashOpen
            : page.noteService.isToday && !page.dashOpen && !page.keysOpen && !page.settingsOpen && !page.pdfShown && !page.exportOpen
          width: height
          // As tall as a side of the switch beside it, so the one that is
          // open is filled the same as the space that is.
          height: spaceSwitch.height - page.sp(4)
          radius: Style.cornerRadius
          color: open ? Style.selectedFill : footArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
          Behavior on color { ColorAnimation { duration: 180 } }
          Text {
            id: footWord
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: footButtons.winIcons !== "" ? modelData.win : modelData.icon
            color: footArea.containsMouse && page.handOn ? page.accent : footButton.open ? page.foreground : page.dim
            font.family: footButtons.winIcons !== "" ? footButtons.winIcons : Style.font.family
            font.pixelSize: Math.round(page.fs(Style.font.bodySmall) * 1.15)
            Behavior on color { ColorAnimation { duration: 180 } }
          }
          MouseArea {
            id: footArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.act === "keys" ? page.toggleKeys() : modelData.act === "settings" ? page.toggleSettings()
              : modelData.act === "dashGo" ? page.showDash() : page.goToday()
            Tip { host: page; act: modelData.act; shown: parent.containsMouse; text: page.tip(modelData.tip, modelData.act) }
          }
        }
      }
    }
  }

  // The project's name and how much it holds, pinned over its list, so
  // the way back and what this is stay in sight while the list scrolls
  // (2026-11-28; they scrolled away with it).
  Column {
    id: projectHead
    visible: projectFlick.visible
    transform: Translate { x: sidebar.spaceShift }
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: sidebar.contentTopInset
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    spacing: page.sp(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: "← #" + page.projectTag
        color: backArea.containsMouse && page.handOn ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
        MouseArea {
          id: backArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.leaveProject()
          Tip { host: page; shown: parent.containsMouse; text: page.tip("Back out of the project", "listBack") }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.projectName
        color: page.foreground
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      // How much there is, and what is still open, before the list.
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: Say.projectSummary(page.sections, page.projectPapers)
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
  }

  // Drilled into a project: its sections across the days, newest first.
  // This is navigation, so it belongs on this side with the calendar —
  // the margin on the right is the agent's (decided 2026-10-15).
  Flickable {
    id: projectFlick
    acceptedButtons: Qt.NoButton
    QC.ScrollBar.vertical: ScrollMark { page: sidebar.page }
    visible: page.sidebarSpace === "time" && page.projectOpen
    transform: Translate { x: sidebar.spaceShift }
    anchors.top: projectHead.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footTop.top
    anchors.topMargin: page.sp(6)
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    clip: true
    contentWidth: width
    contentHeight: projectColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    TouchScroll { flickable: projectFlick }

    // One reveal, the rows' own (sidebar.reveal, with room to see the next
    // row); a second one here put the row under the fade. Another project
    // starts at its top.
    Connections { target: page; function onProjectTagChanged() { projectFlick.contentY = 0 } }

    Column {
      id: projectColumn
      width: parent.width
      spacing: page.sp(4)

      // The project as one list (ProjectView.js, 2026-11-16): what is open
      // (boxes, then the questions waiting in its papers), then writing and
      // reading by day, then the shelf and the files folded. A row's three
      // lines: when (quiet), what (the words), under (quiet).
      Repeater {
        model: page.projectRows
        Rectangle {
          id: rowCell
          required property var modelData
          required property int index
          readonly property string rowKey: modelData.key
          readonly property string kind: modelData.kind
          readonly property bool hot: !!modelData.pick && page.projectFocusKey === modelData.key && sidebarKeys.activeFocus
          onHotChanged: { page.selected(rowCell, "left", hot); if (hot) sidebar.reveal(rowCell, projectFlick, projectColumn) }
          Component.onCompleted: if (hot) page.selected(rowCell, "left", true)
          width: projectColumn.width
          height: kind === "cap" ? capText.implicitHeight
            : kind === "page" ? pageCol.implicitHeight + page.sp(14)
            : rowCol.implicitHeight + page.sp(kind === "fold" || kind === "doc" || kind === "paper" ? 4 : 8)
          radius: Style.cornerRadius
          color: hot ? Style.selectedFill : rowArea.containsMouse && modelData.pick && page.handOn ? Style.hoverFill
            : kind === "page" ? Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.03) : "transparent"
          // The project's and the week's pages are boxes of their own
          // (2026-11-21): where they lead, said before they are opened.
          border.width: kind === "page" ? 1 : 0
          border.color: Qt.rgba(page.faint.r, page.faint.g, page.faint.b, 0.55)
          readonly property var sec: modelData.section || null
          // A paper read is someone else's words (❝), a section is the
          // person's own writing (✎): told apart at a glance (2026-11-21).
          readonly property string sectionTitle: kind === "section" ? Say.sectionTitle(sec, page.projectName) : ""
          readonly property string whenLine: kind === "section" ? page.sectionWhen(sec) + (Say.sectionCounts(sec) !== "" ? "  ·  " + Say.sectionCounts(sec) : "")
            : kind === "read" ? page.isoWhen(modelData.day) + (modelData.said ? "  ·  " + modelData.said : "")
            : ""
          // Its own column, dim, so the words after it line up and a second
          // line hangs under the words, not under the sign.
          readonly property string glyph: kind === "read" || kind === "paper" ? "❝" : kind === "section" ? "✎" : ""
          readonly property string whatLine: kind === "section" ? sectionTitle
            : kind === "box" ? "○  " + modelData.text
            : kind === "question" ? "?  " + modelData.text
            : kind === "read" ? modelData.label
            : kind === "fold" ? (modelData.open ? "▾  " : "▸  ") + modelData.text
            : kind === "paper" ? modelData.label
            : kind === "doc" ? modelData.name
            : ""
          readonly property string underLine: kind === "section" ? Say.sectionUnder(sec)
            : kind === "box" ? page.sectionWhen(sec)
            : kind === "question" ? modelData.label + " · p. " + modelData.page + (modelData.note ? " · " + modelData.note : "")
            : kind === "paper" ? modelData.title
            : ""
          Text {
            id: capText
            visible: rowCell.kind === "cap"
            topPadding: page.sp(10)
            bottomPadding: page.sp(2)
            textFormat: Text.PlainText
            text: rowCell.kind === "cap" ? modelData.text : ""
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          // The page's key, at the right in the middle of the box, the words
          // kept clear of it: the key as it is now (Alt+P, Alt+W), so a key
          // moved in the keys sheet is the one drawn (it drew a bare P and
          // W, which did nothing; 2026-11-28).
          KeyCaps {
            id: pageKey
            visible: rowCell.kind === "page"
            anchors.right: parent.right
            anchors.rightMargin: page.sp(6)
            anchors.verticalCenter: parent.verticalCenter
            page: sidebar.page
            key: { page.keysVersion; return rowCell.kind === "page" ? page.keyName(modelData.act) : "" }
            size: page.fs(Style.font.caption)
          }
          // A page: its name, what it is for, and (the week's) what is in
          // it now.
          Column {
            id: pageCol
            visible: rowCell.kind === "page"
            anchors.left: parent.left
            anchors.right: pageKey.left
            anchors.leftMargin: page.sp(4)
            anchors.rightMargin: page.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: page.sp(2)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: rowCell.kind === "page" ? modelData.text : ""
              color: page.foreground
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.bodySmall)
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: rowCell.kind === "page" ? modelData.role : ""
              color: page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
            Text {
              width: parent.width
              visible: text !== ""
              topPadding: page.sp(2)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: rowCell.kind === "page" ? (modelData.said || "") : ""
              color: page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
          }
          Column {
            id: rowCol
            visible: rowCell.kind !== "cap" && rowCell.kind !== "page"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: page.sp(4) + (rowCell.kind === "paper" || rowCell.kind === "doc" ? page.sp(14) : 0)
            anchors.rightMargin: page.sp(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: page.sp(1)
            Text {
              width: parent.width
              visible: rowCell.whenLine !== ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: rowCell.whenLine
              color: rowCell.sec && rowCell.sec.date === svc.noteDate ? page.accent : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
            Text {
              id: whatText
              width: parent.width
              visible: rowCell.whatLine !== ""
              leftPadding: rowCell.glyph !== "" ? page.sp(12) : 0
              textFormat: Text.StyledText
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              text: rowCell.kind === "question"
                ? '<font color="' + page.accent + '">?</font>' + Say.quietTag(rowCell.whatLine.slice(1), page.projectTag, page.faint)
                : Say.quietTag(rowCell.whatLine, page.projectTag, page.faint)
              color: rowCell.kind === "fold" || rowCell.kind === "doc" ? page.dim : page.foreground
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(rowCell.kind === "fold" || rowCell.kind === "paper" || rowCell.kind === "doc" ? Style.font.caption : Style.font.bodySmall)
            }
            Text {
              id: underText
              width: parent.width
              visible: rowCell.underLine !== ""
              leftPadding: rowCell.glyph !== "" ? page.sp(12) : 0
              textFormat: Text.StyledText
              wrapMode: Text.WordWrap
              maximumLineCount: rowCell.kind === "paper" ? 1 : 2
              elide: Text.ElideRight
              text: Say.quietTag(rowCell.underLine, page.projectTag, page.faint)
              color: rowCell.kind === "section" && rowCell.whatLine === "" ? page.foreground : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
          }
          // The sign of a paper (❝) or a note (✎), beside the first line of
          // its words: the title's, or the boxes' when a section has none.
          Text {
            readonly property Item line: whatText.visible ? whatText : underText
            visible: rowCell.glyph !== "" && rowCol.visible
            x: rowCol.x
            // On the words' baseline, as a letter of them would be.
            y: rowCol.y + line.y + line.baselineOffset - baselineOffset
            textFormat: Text.PlainText
            text: rowCell.glyph
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          MouseArea {
            id: rowArea
            anchors.fill: parent
            enabled: !!modelData.pick
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.focusPane("left"); page.pickProjectRow(modelData.key); page.openInProject() }
            // What a click does, and its key, as on every other row.
            Tip {
              host: page
              shown: parent.containsMouse && !!modelData.pick
              text: rowCell.kind === "page" ? page.tips([["Open it", modelData.act || ""]])
                : page.tip(rowCell.kind === "fold" ? (modelData.open ? "Fold it" : "Unfold it")
                  : rowCell.kind === "box" ? "Go to its line"
                  : rowCell.kind === "question" ? "Open the paper on this question"
                  : rowCell.kind === "read" || rowCell.kind === "paper" ? "Open it where it was left"
                  : rowCell.kind === "doc" ? "Open it"
                  : "Open it in the note", "listOpen")
            }
          }
        }
      }
      Text {
        width: parent.width
        visible: page.projectBare
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        topPadding: page.sp(6)
        text: page.projectReading ? "…" : "nothing under #" + page.projectTag + " yet — a “# Course #" + page.projectTag + "” heading starts one"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
  }
}
