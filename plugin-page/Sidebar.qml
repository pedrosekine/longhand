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
  property alias sidebarKeysRef: sidebarKeys

  visible: page.sidebarOpen && page.problem === ""
  // Beside whichever sheet is showing: the note's moves to stay centred,
  // the dashboard's and the keys' leave room for this.
  x: page.alongside ? 0 : (page.wideOpen ? page.wideX : sheet.x) - page.marginGap - page.sidebarWidth
  y: sheet.y
  height: sheet.height
  width: page.sidebarWidth
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(16)

  MouseArea { anchors.fill: parent; onClicked: {} }

  // In the window the sidebar sits on the same ground as the sheet; a
  // hairline keeps them apart.
  Rectangle {
    visible: page.alongside
    anchors.right: parent.right
    anchors.rightMargin: -Math.round(page.marginGap / 2)
    width: 1
    height: parent.height
    color: page.faint
  }

  Item {
    id: sidebarKeys
    anchors.fill: parent
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      // Wherever the sidebar's focus is: back to the note, or close it.
      if (Sc.hit(event, "toNote")) { editor.focusNote(); event.accepted = true; return }
      if (Sc.hit(event, "today")) { page.goToday(); event.accepted = true; return }
      if (Sc.hit(event, "sidebar")) {
        page.sidebarOpen = false
        page.projectOpen = false
        editor.focusNote()
        event.accepted = true
        return
      }
      // Inside a project: its sections, newest first. Enter opens one in
      // the sheet (the list stays), Left or Esc goes back to the list of
      // projects.
      if (page.projectOpen) {
        if (Sc.hit(event, "listUp")) page.moveSectionFocus(-1)
        else if (Sc.hit(event, "listDown")) page.moveSectionFocus(1)
        else if (Sc.hit(event, "listOpen")) page.openInProject()
        else if (Sc.hit(event, "listBack")) page.leaveProject()
        else return
        event.accepted = true
        return
      }
      // Tab walks the sidebar: the days, the day's deadlines (when it
      // has some), the projects, and back to the days.
      // In the day's deadline list: up/down pick, Enter goes to the line,
      // Ctrl+L marks it done (again: not done), as in the note.
      // A key with Ctrl or Alt it does not use goes on to the calendar.
      if (page.dueFocus >= 0) {
        if (page.dueKey(event)) { event.accepted = true; return }
        // Any other key leaves the list, one with Ctrl or Alt for the
        // calendar below.
        if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) { page.dueFocus = -1; return }
      }
      if (page.projFocus >= 0) {
        if (page.projectsKey(event)) event.accepted = true
        return
      }
      if (Sc.hit(event, "calLists") && (page.focusDue.length > 0 || page.projects.length > 0)) {
        if (page.focusDue.length > 0) page.dueFocus = 0
        else page.projFocus = 0
      } else if (Sc.hit(event, "calBack")) {
        editor.focusNote()
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
        return
      }
      event.accepted = true
    }
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
          readonly property bool isToday: k !== "" && k === Days.key(new Date())
          width: calendar.cell
          height: Math.round(calendar.cell * 0.92)

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
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData ? modelData.getDate() : ""
            color: dayCell.hasNote ? page.foreground : page.faint
            font.family: page.fontFamily
            font.pixelSize: page.fs(Style.font.body)
            font.weight: dayCell.isOpen ? Font.DemiBold : Font.Normal
          }
          Rectangle {
            visible: dayCell.isToday
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(2, Math.round(calendar.cell * 0.1))
            width: Math.max(3, Math.round(calendar.cell * 0.12))
            height: width
            radius: width / 2
            color: page.accent
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
        required property var modelData
        required property int index
        readonly property bool late: modelData.status === "open" && modelData.due * 1000 < Date.now()
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
      visible: page.projects.length > 0
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
        required property var modelData
        required property int index
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

    Text {
      width: parent.width
      visible: sidebarKeys.activeFocus
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.projFocus >= 0 ? page.keyName("listUp") + page.keyName("listDown") + " pick · " + page.keyName("listOpen") + " its notes · "
          + page.keyName("listClass") + " starts a class · " + page.keyName("listTag") + " puts the tag · " + page.keyName("listNext") + " back"
        : page.dueFocus >= 0 ? page.keyName("listUp") + page.keyName("listDown") + " pick · " + page.keyName("listOpen") + " goes to its line · "
          + page.keyName("listDone") + " done · " + page.keyName("listNext") + " on to the projects"
        : "arrows move · " + page.keyName("calPrevMonth") + page.keyName("calNextMonth") + " month · " + page.keyName("calToday") + " today · "
          + page.keyName("calOpen") + " opens" + (page.focusDue.length > 0 || page.projects.length > 0
            ? " · " + page.keyName("calLists") + ": " + (page.focusDue.length > 0 ? "this day's deadlines" : "the projects") : "")
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
          required property var modelData
          required property int index
          readonly property bool hot: page.docFocus === index && sidebarKeys.activeFocus
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
          required property var modelData
          required property int index
          readonly property bool hot: page.docFocus < 0 && page.sectionFocus === index && sidebarKeys.activeFocus
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
