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

// The margin: the agent's side of the page — its reply, its proposals, the conversation
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: margin
  required property Item page
  readonly property var sheet: page.sheetItem
  property alias chatFieldRef: chatField
  property alias marginKeysRef: marginKeys

  visible: page.marginWidth > 0 && page.problem === "" && page.marginOpen && !page.wideOpen
  x: sheet.x + sheet.width + page.marginGap
  y: sheet.y
  height: sheet.height
  width: page.marginWidth
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(22)

  MouseArea { anchors.fill: parent; onClicked: {} }

  // Keyboard focus while in the margin (proposal rows or the tasks
  // panel). The chat field has its own handling.
  Item {
    id: marginKeys
    anchors.fill: parent
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      if (Sc.hit(event, "marginBack")) page.backToNote()
      else if (Sc.hit(event, "marginUp")) page.moveMarginFocus(-1)
      else if (Sc.hit(event, "marginDown")) page.moveMarginFocus(1)
      else if (Sc.hit(event, "marginAccept")) page.acceptProposal(page.marginFocus)
      else if (Sc.hit(event, "marginHelpful")) page.rateReply("up")
      else if (Sc.hit(event, "marginNotHelpful")) page.rateReply("down")
      else return
      event.accepted = true
    }
  }

  Flickable {
    id: marginFlick
    anchors.top: parent.top
    anchors.topMargin: margin.contentTopInset + page.sp(4)
    anchors.left: parent.left
    anchors.leftMargin: margin.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: margin.contentRightInset
    anchors.bottom: chatBox.top
    anchors.bottomMargin: page.sp(10)
    clip: true
    contentWidth: width
    contentHeight: marginColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    TouchScroll { flickable: marginFlick }

    Column {
      id: marginColumn
      width: parent.width
      spacing: page.sp(12)

      Text {
        width: parent.width
        visible: !!(page.currentRecord && page.currentRecord.reply)
        textFormat: Text.MarkdownText
        wrapMode: Text.WordWrap
        text: page.currentRecord && page.currentRecord.reply ? page.currentRecord.reply : ""
        color: page.foreground
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.title)
      }

      // What it read to answer (docs/agent.md, slice 4): the course
      // documents it asked for, and the pages, so a citation can be checked.
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.sayReads(page.currentRecord)
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      // Was it helpful? Two quiet words; the chosen one stays lit. What
      // the student says here is what the weekly review and the eval set
      // learn from.
      Row {
        visible: !!(page.currentRecord && page.currentRecord.reply)
        spacing: page.sp(14)
        Repeater {
          model: [{ text: "helpful", value: "up", act: "marginHelpful" }, { text: "not helpful", value: "down", act: "marginNotHelpful" }]
          Text {
            required property var modelData
            readonly property bool chosen: page.ratingOf(page.currentRec) === modelData.value
            textFormat: Text.PlainText
            text: modelData.text
            color: rateArea.containsMouse ? page.accent : chosen ? page.foreground : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
            font.underline: chosen
            MouseArea {
              id: rateArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.rateReply(modelData.value)
              PanelToolTip { visible: parent.containsMouse; text: page.tip(chosen ? "Take it back" : "Say it was " + modelData.text, modelData.act) }
            }
          }
        }
      }

      // Proposals: what the agent would like to do, done only when the
      // student says so. Enter on a row runs it through the CLI.
      Repeater {
        model: page.currentProposals
        Rectangle {
          required property var modelData
          required property int index
          readonly property bool hot: page.marginFocus === index && marginKeys.activeFocus
          readonly property bool done: !!modelData.accepted
          width: marginColumn.width
          height: propText.implicitHeight + page.sp(10)
          radius: Style.cornerRadius
          color: hot ? Style.selectedFill : propHover.hovered && !done ? Style.hoverFill : "transparent"
          border.width: hot ? 1 : 0
          border.color: page.accent
          HoverHandler { id: propHover }
          Text {
            id: propText
            anchors.fill: parent
            anchors.margins: page.sp(5)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: (done ? "✓ " : "○ ") + (modelData.kind === "deadline"
              ? "deadline: " + modelData.title + " — " + modelData.when + ((modelData.project || modelData.subject) ? " · " + (modelData.project || modelData.subject) : "")
                + (done && modelData.accepted.id ? "  #" + modelData.accepted.id : "")
                + (modelData.error ? "  (failed: " + modelData.error + ")" : "")
              : JSON.stringify(modelData))
            color: done ? page.dim : page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: parent.done ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: { page.marginFocus = index; page.acceptProposal(index) }
            PanelToolTip { visible: parent.containsMouse; text: page.tip("Do what it says", "marginAccept") }
          }
        }
      }

      Repeater {
        model: page.chatTurns
        Text {
          required property var modelData
          width: marginColumn.width
          textFormat: modelData.role === "agent" ? Text.MarkdownText : Text.PlainText
          wrapMode: Text.WordWrap
          text: modelData.text
          color: modelData.role === "agent" ? page.foreground : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.title)
        }
      }

      // Thinking: where the answer will appear, for as long as the
      // block is away. It breathes rather than spins, and after a few
      // seconds it says how long it has been — which is the difference
      // between a slow pass and a hung one. The word is the agent's
      // own state, not a spinner: nothing else in the page moves.
      Text {
        id: thinking
        property double since: 0
        width: parent.width
        visible: page.answering
        textFormat: Text.PlainText
        text: "thinking" + (thinking.elapsed >= 4 ? " · " + thinking.elapsed + "s" : "")
        property int elapsed: 0
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.italic: true
        font.pixelSize: page.fs(Style.font.title)
        onVisibleChanged: {
          thinking.since = visible ? Date.now() : 0
          thinking.elapsed = 0
        }
        Timer {
          interval: 1000
          repeat: true
          running: thinking.visible
          onTriggered: thinking.elapsed = Math.floor((Date.now() - thinking.since) / 1000)
        }
        SequentialAnimation on opacity {
          running: thinking.visible
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      Text {
        width: parent.width
        visible: !page.answered(page.currentRecord) && !page.answering
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Nothing from the agent on this block yet. " + page.keyName("ask") + " sends it, or ask below."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
    }
  }

  Item {
    id: chatBox
    anchors.left: parent.left
    anchors.leftMargin: margin.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: margin.contentRightInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: margin.contentBottomInset
    height: chatField.visible ? chatField.implicitHeight : 0

    TextField {
      id: chatField
      anchors.left: parent.left
      anchors.right: parent.right
      visible: page.marginOpen
      placeholderText: "…"
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.body)
      foreground: page.foreground
      Keys.onPressed: function (event) {
        if (page.anywhereKey(event)) { event.accepted = true; return }
        if (Sc.hit(event, "chatSend")) page.sendChat()
        else if (Sc.hit(event, "marginBack")) page.backToNote()
        else if (Sc.hit(event, "marginUp") && text === "" && page.currentProposals.length > 0) page.moveMarginFocus(-1)
        else return
        event.accepted = true
      }
    }
  }
}
