import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
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

  onVisibleChanged: if (!visible) page.addingProject = false

  visible: page.sidebarOpen && page.problem === ""
  // Against the window's left edge, as the right pane is against its
  // right, whatever is in the middle (the student, 2026-10-24: no dead
  // strip outside a pane). The note moves only if it does not fit between
  // them (page.sheetX).
  x: page.edge
  y: sheet.y
  height: sheet.height
  width: page.sidebarWidth
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(16)

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
    // Inside a project: its sections, newest first. Enter opens one in
    // the sheet (the list stays), Left or Esc goes back to the list of
    // projects.
    if (page.projectOpen) {
      if (Sc.hit(event, "listUp")) page.moveSectionFocus(-1)
      else if (Sc.hit(event, "listDown")) page.moveSectionFocus(1)
      else if (Sc.hit(event, "listOpen")) page.openInProject()
      else if (Sc.hit(event, "listBack")) page.leaveProject()
      else return false
      return true
    }
    // Tab walks the sidebar: the days, the day's deadlines (when it
    // has some), the projects, and back to the days.
    // In the day's deadline list: up/down pick, Enter goes to the line,
    // Ctrl+L marks it done (again: not done), as in the note.
    // A key with Ctrl or Alt it does not use goes on to the calendar.
    if (page.dueFocus >= 0) {
      if (page.dueKey(event)) return true
      // Any other key leaves the list, one with Ctrl or Alt for the
      // calendar below.
      if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) { page.dueFocus = -1; return false }
    }
    if (page.projFocus >= 0) return page.projectsKey(event)
    // (The projects' list always has a row: the one that makes a new one.)
    if (Sc.hit(event, "calLists")) {
      if (page.focusDue.length > 0) page.dueFocus = 0
      else page.projFocus = 0
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
  }

  Column {
    id: calendar
    visible: !page.projectOpen
    anchors.fill: parent
    anchors.topMargin: sidebar.contentTopInset
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    anchors.bottomMargin: sidebar.contentBottomInset + sidebarFoot.height + page.sp(12)
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
        color: prevArea.containsMouse ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.title)
        MouseArea {
          id: prevArea
          anchors.fill: parent
          anchors.margins: -page.sp(6)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.moveCalendar(0, -1)
          PanelToolTip { visible: parent.containsMouse; text: page.tip("A month back", "calPrevMonth") }
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
        color: nextArea.containsMouse ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.title)
        MouseArea {
          id: nextArea
          anchors.fill: parent
          anchors.margins: -page.sp(6)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.moveCalendar(0, 1)
          PanelToolTip { visible: parent.containsMouse; text: page.tip("A month on", "calNextMonth") }
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
          readonly property bool lit: dayCell.isCursor && sidebarKeys.activeFocus
          onLitChanged: page.selected(dayCell, "left", lit)
          Component.onCompleted: if (lit) page.selected(dayCell, "left", true)

          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Style.cornerRadius
            visible: dayCell.isCursor && sidebarKeys.activeFocus
            color: Style.selectedFill
          }
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Style.cornerRadius
            visible: dayArea.containsMouse && !(dayCell.isCursor && sidebarKeys.activeFocus)
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
            readonly property var due: dayCell.k !== "" ? (page.dueByDay[dayCell.k] || []) : []
            readonly property bool open: due.some(function (d) { return d.status === "open" })
            readonly property bool late: due.some(function (d) { return d.status === "open" && d.due * 1000 < Date.now() })
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
            PanelToolTip { visible: parent.containsMouse && !!modelData; text: page.tips([["Open the day in the sheet", "calOpen"], ["Today", "calToday"]]) }
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
        readonly property bool late: modelData.status === "open" && modelData.due * 1000 < Date.now()
        readonly property bool lit: page.dueFocus === index && sidebarKeys.activeFocus
        onLitChanged: page.selected(dueCell, "left", lit)
        Component.onCompleted: if (lit) page.selected(dueCell, "left", true)
        width: calendar.width
        height: dueRow.implicitHeight + page.sp(6)
        radius: Style.cornerRadius
        color: page.dueFocus === index && sidebarKeys.activeFocus ? Style.selectedFill : dueArea.containsMouse ? Style.hoverFill : "transparent"
        Text {
          id: dueRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: page.sp(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: (modelData.status === "open" ? "○ " : "✓ ") + modelData.title
            + " · " + Qt.formatTime(new Date(modelData.due * 1000), "HH:mm")
            + (modelData.project ? " · " + modelData.project : "")
            + (Bound.parseLink(modelData.link) ? "" : " · no line")
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
          onClicked: page.goToDeadline(modelData)
          PanelToolTip { visible: parent.containsMouse; text: page.tips([["Go to its line", "listOpen"], ["Done (again: not done)", "listDone"]]) }
        }
      }
    }

    // The projects that exist: the tags to write, soonest session first.
    Text {
      topPadding: page.sp(8)
      textFormat: Text.PlainText
      text: "PROJECTS"
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
    Repeater {
      model: page.projects
      Rectangle {
        id: projCell
        required property var modelData
        required property int index
        readonly property bool lit: page.projFocus === index && sidebarKeys.activeFocus
        onLitChanged: page.selected(projCell, "left", lit)
        Component.onCompleted: if (lit) page.selected(projCell, "left", true)
        width: calendar.width
        height: projCol.implicitHeight + page.sp(6)
        radius: Style.cornerRadius
        color: page.projFocus === index && sidebarKeys.activeFocus ? Style.selectedFill : projArea.containsMouse ? Style.hoverFill : "transparent"
        Column {
          id: projCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: page.sp(4)
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
          PanelToolTip {
            visible: parent.containsMouse
            text: page.tips([["Its notes", "listOpen"], ["Shift-click: start its class", "listClass"], ["Ctrl-click: put its #tag at the cursor", "listTag"]])
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
      readonly property bool lit: page.projFocus === page.projects.length && sidebarKeys.activeFocus
      onLitChanged: page.selected(newCell, "left", lit)
      width: calendar.width
      height: newText.implicitHeight + page.sp(6)
      radius: Style.cornerRadius
      color: page.projFocus === page.projects.length && sidebarKeys.activeFocus ? Style.selectedFill : newArea.containsMouse ? Style.hoverFill : "transparent"
      Text {
        id: newText
        anchors.left: parent.left
        anchors.leftMargin: page.sp(4)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "+ new project"
        color: newArea.containsMouse ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      MouseArea {
        id: newArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.projFocus = page.projects.length; page.openSidebarProject() }
        PanelToolTip { visible: parent.containsMouse; text: page.tip("Make a project: in the sidebar, @ and #", "listOpen") }
      }
    }
    Column {
      visible: page.addingProject
      width: calendar.width
      spacing: page.sp(2)
      readonly property var made: Tags.fromField(projectField.text, page.projects)
      TextField {
        id: projectField
        width: parent.width
        placeholderText: "Master Thesis #thesis"
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
        foreground: page.foreground
        onVisibleChanged: if (visible) text = ""
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

    Text {
      width: parent.width
      visible: sidebarKeys.activeFocus
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.projFocus >= 0 && page.projFocus === page.projects.length ? page.keyName("listOpen") + " names a new project · " + page.keyName("listNext") + " back"
        : page.projFocus >= 0 ? page.keyName("listUp") + page.keyName("listDown") + " pick · " + page.keyName("listOpen") + " its notes · "
          + page.keyName("listClass") + " starts a class · " + page.keyName("listTag") + " puts the tag · " + page.keyName("listNext") + " back"
        : page.dueFocus >= 0 ? page.keyName("listUp") + page.keyName("listDown") + " pick · " + page.keyName("listOpen") + " goes to its line · "
          + page.keyName("listDone") + " done · " + page.keyName("listNext") + " on to the projects"
        : "arrows move · " + page.keyName("calPrevMonth") + page.keyName("calNextMonth") + " month · " + page.keyName("calToday") + " today · "
          + page.keyName("calOpen") + " opens · " + page.keyName("calLists") + ": " + (page.focusDue.length > 0 ? "this day's deadlines" : "the projects")
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }

  // The sidebar's foot: what supports the writing rather than the
  // writing itself — the keys and the settings — so the header keeps
  // only what belongs to the note (2026-10-17). Quiet, like the pin; a
  // word is bright while its sheet is open.
  Row {
    id: sidebarFoot
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.bottomMargin: sidebar.contentBottomInset
    spacing: page.sp(16)

    Repeater {
      model: [{ text: "keys", act: "keys", tip: "Every key the page answers to, and moving one" },
              { text: "settings", act: "settings", tip: "Settings: your calendars" }]
      Text {
        required property var modelData
        readonly property bool open: modelData.act === "keys" ? page.keysOpen : page.settingsOpen
        textFormat: Text.PlainText
        text: modelData.text
        color: footArea.containsMouse ? page.accent : open ? page.foreground : page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
        Behavior on color { ColorAnimation { duration: 240 } }
        MouseArea {
          id: footArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: modelData.act === "keys" ? page.toggleKeys() : page.toggleSettings()
          PanelToolTip { visible: parent.containsMouse; text: page.tip(modelData.tip, modelData.act) }
        }
      }
    }
  }

  // Drilled into a project: its sections across the days, newest first.
  // This is navigation, so it belongs on this side with the calendar —
  // the margin on the right is the agent's (decided 2026-10-15).
  Flickable {
    id: projectFlick
    visible: page.projectOpen
    anchors.fill: parent
    anchors.topMargin: sidebar.contentTopInset
    anchors.leftMargin: sidebar.contentLeftInset
    anchors.rightMargin: sidebar.contentRightInset
    anchors.bottomMargin: sidebar.contentBottomInset + sidebarFoot.height + page.sp(12)
    clip: true
    contentWidth: width
    contentHeight: projectColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    TouchScroll { flickable: projectFlick }

    function revealFocused() {
      var kids = projectColumn.children
      for (var i = 0; i < kids.length; i++) {
        var k = kids[i]
        if (k.index === undefined || k.index !== page.sectionFocus) continue
        if (contentY > k.y) contentY = k.y
        else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
        return
      }
    }
    Connections { target: page; function onSectionFocusChanged() { Qt.callLater(projectFlick.revealFocused) } }

    Column {
      id: projectColumn
      width: parent.width
      spacing: page.sp(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: "← #" + page.projectTag
        color: backArea.containsMouse ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
        MouseArea {
          id: backArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.leaveProject()
          PanelToolTip { visible: parent.containsMouse; text: page.tip("Back out of the project", "listBack") }
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

      // Its documents, filed from the inbox: opened in the PDF viewer.
      Text {
        visible: page.projectDocs().length > 0
        topPadding: page.sp(8)
        textFormat: Text.PlainText
        text: "DOCUMENTS"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      Repeater {
        model: page.projectDocs()
        Rectangle {
          id: docCell
          required property var modelData
          required property int index
          readonly property bool hot: page.docFocus === index && sidebarKeys.activeFocus
          onHotChanged: page.selected(docCell, "left", hot)
          Component.onCompleted: if (hot) page.selected(docCell, "left", true)
          width: projectColumn.width
          height: docText.implicitHeight + page.sp(6)
          radius: Style.cornerRadius
          color: hot ? Style.selectedFill : docArea.containsMouse ? Style.hoverFill : "transparent"
          Text {
            id: docText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: page.sp(4)
            anchors.rightMargin: page.sp(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: modelData.name + (modelData.pages ? "   " + modelData.pages + " p." : "")
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          MouseArea {
            id: docArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.docFocus = index; page.openDocument(modelData) }
            PanelToolTip { visible: parent.containsMouse; text: page.tip("Open it in the PDF viewer", "listOpen") }
          }
        }
      }

      Text {
        width: parent.width
        visible: page.sections.length === 0
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        topPadding: page.sp(6)
        text: sectionsProc.running ? "…" : "nothing under #" + page.projectTag + " yet — a “# Course #" + page.projectTag + "” heading starts one"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      Repeater {
        model: page.sections
        Rectangle {
          id: secCell
          required property var modelData
          required property int index
          readonly property bool hot: page.docFocus < 0 && page.sectionFocus === index && sidebarKeys.activeFocus
          onHotChanged: page.selected(secCell, "left", hot)
          Component.onCompleted: if (hot) page.selected(secCell, "left", true)
          width: projectColumn.width
          height: secCol.implicitHeight + page.sp(8)
          radius: Style.cornerRadius
          color: hot ? Style.selectedFill : secArea.containsMouse ? Style.hoverFill : "transparent"
          Column {
            id: secCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: page.sp(4)
            anchors.rightMargin: page.sp(4)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: page.sectionWhen(modelData)
                + (modelData.open > 0 ? "   ○ " + modelData.open : "")
                + (modelData.done > 0 ? "   ✓ " + modelData.done : "")
              color: modelData.date === svc.noteDate ? page.accent : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              text: page.sectionUnder(modelData)
              color: page.foreground
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
          }
          MouseArea {
            id: secArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.docFocus = -1; page.sectionFocus = index; page.openSection(modelData) }
            PanelToolTip { visible: parent.containsMouse; text: page.tip("Open the section", "listOpen") }
          }
        }
      }

      Text {
        width: parent.width
        visible: sidebarKeys.activeFocus
        topPadding: page.sp(6)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.keyName("listUp") + page.keyName("listDown") + " pick · " + page.keyName("listOpen") + " opens it in the sheet · "
          + page.keyName("listBack") + " back to the projects"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
  }
}
