import Quickshell
import QtQuick
import qs.Commons
import qs.Ui

// What the agent knows (Settings → The agent, Ctrl+K): its notebook line by
// line, the student's answers, and their corrections — each line to correct
// in their own words or forget (docs/agent.md, slice 3). Settings' second
// view, drawn in its place; Esc goes back. The page asks the runner, which
// writes; `page` is the page itself.
BorderSurface {
  id: notebookSheet
  required property Item page
  readonly property var content: page.contentItem
  readonly property var pal: page.palette
  property alias notebookKeysRef: notebookKeys
  property alias notebookFieldRef: notebookField

  visible: page.settingsOpen && page.settingsView === "notebook"
  x: page.wideX
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sheetPadding

  // The keys while nothing is being typed: ↑↓, correct, forget, Esc.
  Item {
    id: notebookKeys
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { if (page.notebookKey(event)) event.accepted = true }
  }

  MouseArea { anchors.fill: parent; onClicked: notebookKeys.forceActiveFocus() }

  Item {
    anchors.fill: parent
    anchors.topMargin: notebookSheet.contentTopInset
    anchors.rightMargin: notebookSheet.contentRightInset
    anchors.bottomMargin: notebookSheet.contentBottomInset
    anchors.leftMargin: notebookSheet.contentLeftInset

    Item {
      id: notebookColumn
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: parent.height

      Text {
        id: notebookTitle
        anchors.top: parent.top
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: "SETTINGS · WHAT THE AGENT KNOWS"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      Text {
        id: notebookIntro
        anchors.top: notebookTitle.bottom
        anchors.topMargin: page.sp(18)
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "What it has written down about you and your projects, and — the morning after — what each day's "
          + "conversation came to, read at every run. Correct a line in your words, "
          + "or forget it: either is kept in your corrections, which it reads every time and never writes, so it "
          + "stays made. " + page.sayNotebook()
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      ListView {
        id: notebookView
        anchors.top: notebookIntro.bottom
        anchors.topMargin: page.sp(16)
        anchors.bottom: notebookFoot.top
        anchors.bottomMargin: page.sp(10)
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.notebookList
        currentIndex: page.notebookFocus
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
          id: nbRow
          required property var modelData
          required property int index
          readonly property bool picked: page.notebookFocus === index
          readonly property bool head: modelData.kind === "head"
          readonly property bool lit: picked && !head && page.here === "center"
          onLitChanged: page.selected(nbRow, "center", lit)
          Component.onCompleted: if (lit) page.selected(nbRow, "center", true)
          width: notebookView.width
          height: nbCol.implicitHeight + (head ? page.sp(index === 0 ? 4 : 20) : page.sp(8))

          Rectangle {
            visible: !nbRow.head
            anchors.fill: parent
            radius: Style.cornerRadius
            color: nbRow.picked ? Style.selectedFill : nbHover.hovered ? Style.hoverFill : "transparent"
          }
          HoverHandler { id: nbHover; enabled: !nbRow.head && !nbRow.picked }

          MouseArea {
            anchors.fill: parent
            enabled: !nbRow.head
            cursorShape: nbRow.picked ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: page.pickNotebook(nbRow.index)
          }

          Column {
            id: nbCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: nbRow.head ? page.sp(2) : page.sp(4)
            anchors.leftMargin: page.sp(8) + nbRow.modelData.depth * page.sp(16)
            anchors.rightMargin: page.sp(8)
            spacing: page.sp(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: nbRow.modelData.text
              color: nbRow.head ? (pal.headings.length > 0 ? pal.headings[0] : page.accent)
                : nbRow.modelData.kind === "correction" ? page.dim : page.foreground
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(nbRow.head ? Style.font.body : Style.font.bodySmall)
            }
            Text {
              visible: !!nbRow.modelData.note
              textFormat: Text.PlainText
              text: nbRow.modelData.note || ""
              color: page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
            // The picked line's two verbs, for the mouse.
            Row {
              visible: nbRow.picked && !page.notebookCorrecting
              spacing: page.sp(16)
              Repeater {
                model: nbRow.modelData.kind === "line"
                  ? [{ text: "correct", act: "notebookCorrect" }, { text: "forget", act: "notebookForget" }]
                  : [{ text: nbRow.modelData.kind === "correction" ? "take back" : "forget", act: "notebookForget" }]
                Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  text: modelData.text
                  color: verbArea.containsMouse ? page.accent : page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                  MouseArea {
                    id: verbArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (modelData.act === "notebookCorrect") page.startCorrect(); else page.forgetNote() }
                    PanelToolTip { visible: parent.containsMouse; text: page.tip(modelData.text, modelData.act) }
                  }
                }
              }
            }
          }
        }
      }

      Column {
        id: notebookFoot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: page.sp(8)

        TextField {
          id: notebookField
          visible: page.notebookCorrecting
          width: parent.width
          placeholderText: "the line in your words"
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
          foreground: page.foreground
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) { if (page.notebookKey(event)) event.accepted = true }
        }

        Text {
          visible: page.notebookNote !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: page.notebookNote
          color: page.accent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: page.notebookCorrecting ? "Enter keeps your words · Esc leaves the line as it is"
            : "↑↓ pick a line · Enter or " + page.keyName("notebookCorrect") + " corrects it · "
              + page.keyName("notebookForget") + " forgets it (on a correction: takes it back) · Esc back to settings"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
    }
  }
}
