import Quickshell
import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui

// What the agent may search (Settings → The agent, Ctrl+F): each folder of
// the vault, on or off, with how many files the agent could read in it
// (docs/agent.md, "The day conversation", slice 2). Settings' fourth view,
// drawn in its place; Esc goes back. What is never searched is said, not
// switchable. `page` is the page itself.
BorderSurface {
  id: searchSheet
  required property Item page
  readonly property var content: page.contentItem
  property alias searchKeysRef: searchKeys

  visible: page.centerView === "settings" && page.settingsView === "search"
  x: page.wideX
  // Making room for the sidebar slides, as Settings' main sheet does.
  Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : page.overlayRadius
  color: page.background
  borderSpec: page.cardSpec
  padding: page.sheetPadding

  Item {
    id: searchKeys
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { if (page.searchFoldersKey(event)) event.accepted = true }
  }

  MouseArea { anchors.fill: parent; onClicked: searchKeys.forceActiveFocus() }

  Item {
    anchors.fill: parent
    anchors.topMargin: searchSheet.contentTopInset
    anchors.rightMargin: searchSheet.contentRightInset
    anchors.bottomMargin: searchSheet.contentBottomInset
    anchors.leftMargin: searchSheet.contentLeftInset

    Item {
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: parent.height

      SettingsCrumb {
        id: searchTitle
        page: searchSheet.page
        anchors.top: parent.top
        anchors.left: parent.left
        title: "WHAT THE AGENT MAY SEARCH"
        onBack: page.closeNotebook()
      }

      Text {
        id: searchIntro
        anchors.top: searchTitle.bottom
        anchors.topMargin: page.sp(18)
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "When you talk to the day, the agent can search your files: the folders switched on here. "
          + "Never, whatever is on: a note marked private and every private block; daily notes from before the "
          + "horizon; _Secrets; anything but notes, "
          + "text and PDFs; documents named for identity, money, health, contracts or secrets; anything that looks "
          + "like a key or a password (checked by gitleaks before it is sent). What is held back is counted in the "
          + "log, never shown."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      // The horizon (docs/files.md, 2026-10-26): row -1, above the folders.
      // Daily notes from before it are private, whatever is switched on.
      Item {
        id: horizonRow
        readonly property var h: page.horizonData
        readonly property bool picked: page.searchFocus === -1
        readonly property bool lit: picked && page.here === "center" && searchSheet.visible
        onLitChanged: page.selected(horizonRow, "center", lit)
        anchors.top: searchIntro.bottom
        anchors.topMargin: page.sp(16)
        width: parent.width
        height: horizonCol.implicitHeight + page.sp(10)
        visible: !!h

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -page.sp(10)
          anchors.rightMargin: -page.sp(10)
          radius: Style.cornerRadius
          color: horizonRow.picked ? Style.selectedFill : horizonArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
        }
        MouseArea {
          id: horizonArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { page.searchFocus = -1; searchKeys.forceActiveFocus() }
        }

        Column {
          id: horizonCol
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          spacing: page.sp(2)
          Row {
            spacing: page.sp(10)
            Text {
              textFormat: Text.PlainText
              text: horizonRow.h ? "Daily notes from " + page.sayHorizon(horizonRow.h.horizon) + " on" : ""
              color: page.foreground
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.body)
            }
            // A month earlier or later by the mouse too, as ← and → on the
            // row (2026-11-25, the mouse pass: only the keys moved it).
            // › is faint and inert at today: the horizon goes no later.
            Repeater {
              model: [{ glyph: "‹", months: -1, says: "A month earlier   ←" }, { glyph: "›", months: 1, says: "A month later   →" }]
              Text {
                required property var modelData
                readonly property bool inert: modelData.months > 0 && page.horizonAtToday
                textFormat: Text.PlainText
                text: modelData.glyph
                color: inert ? page.faint : stepArea.containsMouse && page.handOn ? page.accent : page.dim
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.body)
                MouseArea {
                  id: stepArea
                  anchors.fill: parent
                  anchors.margins: -page.sp(6)
                  enabled: !parent.inert
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { page.searchFocus = -1; searchKeys.forceActiveFocus(); page.moveHorizon(parent.modelData.months) }
                  Tip { host: page; shown: parent.containsMouse; text: parent.parent.modelData.says }
                }
              }
            }
          }
          Flow {
            width: parent.width
            spacing: page.sp(10)
            Text {
              width: Math.min(implicitWidth, parent.width)
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              // Counted again by the runner after a change: the old count
              // stood beside the new day until it answered.
              text: !horizonRow.h ? "" : (horizonRow.h.before < 0 ? "Counting the days before it…"
                  : horizonRow.h.before + (horizonRow.h.before === 1 ? " day" : " days") + " before it never searched or read, as if private")
                + (horizonRow.h.set ? " · changed by you" : " · the first day the agent kept")
              color: page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
            // The default back, by the mouse too (Backspace on the row).
            Text {
              visible: !!horizonRow.h && horizonRow.h.set
              textFormat: Text.PlainText
              text: horizonRow.h ? "back to " + page.sayHorizon(horizonRow.h["default"]) : ""
              color: resetArea.containsMouse && page.handOn ? page.accent : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
              MouseArea {
                id: resetArea
                anchors.fill: parent
                anchors.margins: -page.sp(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { page.searchFocus = -1; searchKeys.forceActiveFocus(); page.setHorizon("") }
                Tip { host: page; shown: parent.containsMouse; text: "The first day the agent kept   Backspace" }
              }
            }
          }
        }
      }

      Flickable {
        id: searchFlick
        acceptedButtons: Qt.NoButton
        QC.ScrollBar.vertical: ScrollMark { page: searchSheet.page }
        TouchScroll { flickable: searchFlick }
        anchors.top: horizonRow.visible ? horizonRow.bottom : searchIntro.bottom
        anchors.topMargin: page.sp(16)
        anchors.bottom: searchFoot.top
        anchors.bottomMargin: page.sp(10)
        // Wider than the column by the rows' fill, as in the other sheets:
        // the fill was clipped square at the edges, narrower than the
        // horizon's above it.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: -page.sp(10)
        anchors.rightMargin: -page.sp(10)
        clip: true
        contentWidth: width
        contentHeight: searchColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: searchColumn
          x: page.sp(10)
          width: searchFlick.width - page.sp(20)
          spacing: page.sp(4)

          Text {
            visible: !page.searchData
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: page.sayUnread("search")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }

          Repeater {
            model: page.searchData ? page.searchData.folders : []
            Item {
              id: folderRow
              required property var modelData
              required property int index
              readonly property bool picked: page.searchFocus === index
              readonly property bool lit: picked && page.here === "center" && searchSheet.visible
              onLitChanged: page.selected(folderRow, "center", lit)
              Component.onCompleted: if (lit) page.selected(folderRow, "center", true)
              width: searchColumn.width
              height: folderLine.implicitHeight + page.sp(10)
              onPickedChanged: if (picked) {
                if (y < searchFlick.contentY) searchFlick.contentY = Math.max(0, y)
                else if (y + height > searchFlick.contentY + searchFlick.height) searchFlick.contentY = Math.max(0, y + height - searchFlick.height)
              }

              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -page.sp(10)
                anchors.rightMargin: -page.sp(10)
                radius: Style.cornerRadius
                color: folderRow.picked ? Style.selectedFill : folderArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
              }
              MouseArea {
                id: folderArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { page.searchFocus = folderRow.index; page.toggleSearchFolder(folderRow.index); searchKeys.forceActiveFocus() }
                Tip { host: page; shown: parent.containsMouse; text: (folderRow.modelData.on ? "Switch it off" : "Switch it on") + "   Space" }
              }

              Flow {
                id: folderLine
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: page.sp(14)
                Text {
                  // A column of its own width, so the names line up
                  // whichever it says (a space after "on" did not, in a
                  // face whose letters differ in width).
                  width: offMetrics.advanceWidth("off")
                  FontMetrics { id: offMetrics; font: parent.font }
                  topPadding: Math.max(0, folderName.baselineOffset - offMetrics.ascent)
                  textFormat: Text.PlainText
                  text: folderRow.modelData.on ? "on" : "off"
                  color: folderRow.modelData.on ? page.accent : page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.bodySmall)
                }
                Text {
                  id: folderName
                  width: Math.min(implicitWidth, parent.width - offMetrics.advanceWidth("off") - parent.spacing)
                  elide: Text.ElideMiddle
                  textFormat: Text.PlainText
                  text: folderRow.modelData.folder
                  color: folderRow.modelData.on ? page.foreground : page.dim
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }
                Text {
                  topPadding: Math.max(0, folderName.baselineOffset - filesMetrics.ascent)
                  FontMetrics { id: filesMetrics; font: parent.font }
                  textFormat: Text.PlainText
                  text: folderRow.modelData.files + (folderRow.modelData.files === 1 ? " file" : " files")
                    + (folderRow.modelData.on !== folderRow.modelData.default ? " · changed by you" : "")
                  color: page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                }
              }
            }
          }
        }
      }

      SettingsFoot {
        id: searchFoot
        page: searchSheet.page
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        keys: "↑↓ pick a folder · Space or Enter (or a click) switches it · on the horizon, ←→ a month, "
          + "Shift a year, Backspace the default · Esc back to settings"
      }
    }
  }
}
