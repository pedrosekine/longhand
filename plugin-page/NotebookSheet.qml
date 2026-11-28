import Quickshell
import QtQuick
import QtQuick.Controls as QC
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

  visible: page.centerView === "settings" && page.settingsView === "notebook"
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

  // The keys while nothing is being typed: ↑↓, correct, forget, Esc.
  Item {
    id: notebookKeys
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { if (page.notebookKey(event)) event.accepted = true }
  }

  // A click beside the list: the keys back, to the box while a line is
  // being corrected (it took them from the box and left it open, deaf).
  MouseArea { anchors.fill: parent; onClicked: (page.notebookCorrecting ? notebookField : notebookKeys).forceActiveFocus() }

  // The picked line in view once it has grown: its verbs and question are
  // drawn under it, and the box below the list takes room from it.
  function showPicked() { Qt.callLater(function () { if (notebookView.currentIndex >= 0) notebookView.positionViewAtIndex(notebookView.currentIndex, ListView.Contain) }) }
  Connections {
    target: page
    function onNotebookCorrectingChanged() { notebookSheet.showPicked() }
    function onNotebookAskingChanged() { notebookSheet.showPicked() }
  }

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

      SettingsCrumb {
        id: notebookTitle
        page: notebookSheet.page
        anchors.top: parent.top
        anchors.left: parent.left
        title: "WHAT THE AGENT KNOWS"
        onBack: page.closeNotebook()
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

      // Nothing in it: said, not a blank (its keys are not offered either).
      Text {
        visible: page.notebookList.length === 0
        anchors.top: notebookIntro.bottom
        anchors.topMargin: page.sp(16)
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: page.notebookData ? "Nothing here yet: the agent writes its notes as it works, and your answers and corrections join them."
          : page.sayUnread("notebook")
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      ListView {
        id: notebookView
        acceptedButtons: Qt.NoButton
        QC.ScrollBar.vertical: ScrollMark { page: notebookSheet.page }
        TouchScroll { flickable: notebookView }
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
        onCurrentIndexChanged: notebookSheet.showPicked()
        onHeightChanged: notebookSheet.showPicked()

        delegate: Item {
          id: nbRow
          required property var modelData
          required property int index
          readonly property bool picked: page.notebookFocus === index
          readonly property bool head: modelData.kind === "head"
          readonly property bool lit: picked && !head && page.here === "center" && notebookSheet.visible
          onLitChanged: page.selected(nbRow, "center", lit)
          Component.onCompleted: if (lit) page.selected(nbRow, "center", true)
          width: notebookView.width
          height: nbCol.implicitHeight + (head ? page.sp(index === 0 ? 4 : 20) : page.sp(8))

          Rectangle {
            visible: !nbRow.head
            anchors.fill: parent
            radius: Style.cornerRadius
            color: nbRow.picked ? Style.selectedFill : nbHover.hovered && page.handOn ? Style.hoverFill : "transparent"
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
            // The picked line's two verbs, for the mouse; while Del asks,
            // the question and its two answers.
            Flow {
              visible: nbRow.picked && !page.notebookCorrecting
              width: parent.width
              spacing: page.sp(16)
              Text {
                visible: page.notebookAsking
                textFormat: Text.PlainText
                text: (nbRow.modelData.kind === "correction" ? "Take this correction back?" : "Forget this note?") + " Enter / Esc"
                color: page.urgent
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
              }
              Repeater {
                model: page.notebookAsking
                  ? [{ text: nbRow.modelData.kind === "correction" ? "take it back" : "forget it", act: "yes" }, { text: "keep it", act: "no" }]
                  : nbRow.modelData.kind === "line"
                  ? [{ text: "correct", act: "notebookCorrect" }, { text: "forget", act: "notebookForget" }]
                  : [{ text: nbRow.modelData.kind === "correction" ? "take back" : "forget", act: "notebookForget" }]
                Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  text: modelData.text
                  color: verbArea.containsMouse && page.handOn ? page.accent : page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                  MouseArea {
                    id: verbArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData.act === "notebookCorrect") page.startCorrect()
                      else if (modelData.act === "yes") page.forgetNote()
                      else if (modelData.act === "no") page.notebookAsking = false
                      else page.askForgetNote()
                    }
                    Tip {
                      host: page
                      shown: parent.containsMouse && modelData.act !== "yes" && modelData.act !== "no"
                      text: page.tip(modelData.text, modelData.act)
                    }
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
          FieldMenu { page: notebookSheet.page; field: parent }
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

        SettingsFoot {
          page: notebookSheet.page
          width: parent.width
          keys: page.notebookCorrecting ? "Enter keeps your words · Esc leaves the line as it is"
            : page.notebookAsking ? "Enter " + (page.notebookList[page.notebookFocus] && page.notebookList[page.notebookFocus].kind === "correction" ? "takes it back" : "forgets it") + " · Esc keeps it"
            : page.notebookList.length === 0 ? "Esc back to settings"
            : "↑↓ pick a line · Enter or " + page.keyName("notebookCorrect") + " corrects it · "
              + page.keyName("notebookForget") + " forgets it, asking first (on a correction: takes it back) · Esc back to settings"
        }
      }
    }
  }
}
