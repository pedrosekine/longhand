import Quickshell
import QtQuick
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

  visible: page.settingsOpen && page.settingsView === "search"
  x: page.wideX
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
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

      Text {
        id: searchTitle
        anchors.top: parent.top
        textFormat: Text.PlainText
        text: "SETTINGS · WHAT THE AGENT MAY SEARCH"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      Text {
        id: searchIntro
        anchors.top: searchTitle.bottom
        anchors.topMargin: page.sp(18)
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "When you talk to the day, the agent can search your files: the folders switched on here. "
          + "Never, whatever is on: a note marked private and every private block; _Secrets; anything but notes, "
          + "text and PDFs; documents named for identity, money, health, contracts or secrets; anything that looks "
          + "like a key or a password (checked by gitleaks before it is sent). What is held back is counted in the "
          + "log, never shown."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      Flickable {
        id: searchFlick
        anchors.top: searchIntro.bottom
        anchors.topMargin: page.sp(16)
        anchors.bottom: searchFoot.top
        anchors.bottomMargin: page.sp(10)
        width: parent.width
        clip: true
        contentWidth: width
        contentHeight: searchColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: searchColumn
          width: parent.width
          spacing: page.sp(4)

          Repeater {
            model: page.searchData ? page.searchData.folders : []
            Item {
              id: folderRow
              required property var modelData
              required property int index
              readonly property bool picked: page.searchFocus === index
              width: searchColumn.width
              height: folderLine.implicitHeight + page.sp(10)
              onPickedChanged: if (picked) {
                if (y < searchFlick.contentY) searchFlick.contentY = y
                else if (y + height > searchFlick.contentY + searchFlick.height) searchFlick.contentY = y + height - searchFlick.height
              }

              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -page.sp(10)
                anchors.rightMargin: -page.sp(10)
                radius: Style.cornerRadius
                color: folderRow.picked ? Style.selectedFill : "transparent"
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { page.searchFocus = folderRow.index; page.toggleSearchFolder(folderRow.index); searchKeys.forceActiveFocus() }
              }

              Row {
                id: folderLine
                anchors.verticalCenter: parent.verticalCenter
                spacing: page.sp(14)
                Text {
                  textFormat: Text.PlainText
                  text: folderRow.modelData.on ? "on " : "off"
                  color: folderRow.modelData.on ? page.accent : page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.bodySmall)
                }
                Text {
                  textFormat: Text.PlainText
                  text: folderRow.modelData.folder
                  color: folderRow.modelData.on ? page.foreground : page.dim
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }
                Text {
                  anchors.baseline: parent.children[1].baseline
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

      Text {
        id: searchFoot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "↑↓ pick a folder · Space or Enter (or a click) switches it · Esc back to settings"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
  }
}
