import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc

// The day conversation (docs/agent.md, "The day conversation", 2026-10-21):
// the right pane's home. The student talks to the day, not to a line:
// the morning's observation waits at the top, then the day's turns, then
// the box. Beside the note, in the margin's place; beside the dashboard, in
// the room a task's conversation takes. A past day's conversation reads
// here too, and is talked in no more: today's is where you talk. `page` is
// the page itself.
BorderSurface {
  id: dayPane
  required property Item page
  readonly property var sheet: page.sheetItem
  property alias dayFieldRef: dayField

  readonly property bool besideDash: page.dayBesideDash
  visible: page.dayShown && (besideDash || (page.marginWidth > 0 && page.problem === ""))
  x: besideDash ? page.wideX + page.dashWidth + page.marginGap : sheet.x + sheet.width + page.marginGap
  y: besideDash ? (page.alongside ? 0 : page.sheetMargin) : sheet.y
  height: besideDash ? (page.alongside ? page.contentItem.height : page.contentItem.height - page.sheetMargin * 2) : sheet.height
  width: besideDash ? page.talkWidth : page.marginWidth
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(22)

  MouseArea { anchors.fill: parent; onClicked: dayField.forceActiveFocus() }

  Text {
    id: dayTitle
    anchors.top: parent.top
    anchors.topMargin: dayPane.contentTopInset
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    textFormat: Text.PlainText
    text: page.noteService.isToday ? "TODAY" : (page.dateLabel || "").toUpperCase()
    color: page.dim
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }

  Flickable {
    id: dayFlick
    anchors.top: dayTitle.bottom
    anchors.topMargin: page.sp(14)
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: dayPane.contentRightInset
    anchors.bottom: dayBox.top
    anchors.bottomMargin: page.sp(10)
    clip: true
    contentWidth: width
    contentHeight: dayColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    // A new turn is seen: the conversation keeps to its foot.
    onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height

    TouchScroll { flickable: dayFlick }

    Column {
      id: dayColumn
      width: parent.width
      spacing: page.sp(12)

      // What the morning's pass noticed, waiting at the top.
      Repeater {
        model: page.dayOpening
        Column {
          required property var modelData
          width: dayColumn.width
          spacing: page.sp(2)
          Text {
            textFormat: Text.PlainText
            text: "this morning"
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          Text {
            width: parent.width
            textFormat: Text.MarkdownText
            wrapMode: Text.WordWrap
            text: modelData
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.title)
          }
        }
      }

      Repeater {
        model: page.dayTurns
        Column {
          required property var modelData
          width: dayColumn.width
          spacing: page.sp(2)
          // The block a message pointed at.
          Text {
            visible: modelData.role === "student" && !!modelData.block
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "↳ " + page.blockHead(modelData.block)
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          Text {
            width: parent.width
            textFormat: modelData.role === "agent" ? Text.MarkdownText : Text.PlainText
            wrapMode: Text.WordWrap
            text: modelData.error ? "could not answer: " + page.sayPlanError(modelData.error)
              : modelData.role === "agent" ? page.linkCitations(modelData.text) : modelData.text
            color: modelData.error ? page.urgent : modelData.role === "agent" ? page.foreground : page.dim
            linkColor: page.accent
            onLinkActivated: function (link) { page.openCitation(link) }
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.title)
          }
          Text {
            visible: text !== ""
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: modelData.role === "agent" ? page.sayFetched(modelData) : ""
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }
      }

      Text {
        id: dayThinking
        visible: page.dayThinking
        textFormat: Text.PlainText
        text: "thinking"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
        SequentialAnimation on opacity {
          running: dayThinking.visible
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      Text {
        visible: page.dayTurns.length === 0 && page.dayOpening.length === 0 && !page.dayThinking
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.dayCanSend
          ? "Talk to the day: your tasks, your courses, what you wrote. Point at a block with " + page.keyName("dayHere") + " from the note."
          : "Nothing was said on this day."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
    }
  }

  Column {
    id: dayBox
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: dayPane.contentRightInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: dayPane.contentBottomInset
    spacing: page.sp(6)

    // The block the next message points at; Backspace in the empty box lets go.
    Text {
      visible: page.dayBlock !== ""
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: "↳ " + page.dayBlockText
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }

    TextField {
      id: dayField
      width: parent.width
      enabled: page.dayCanSend
      placeholderText: page.dayCanSend ? "talk to the day…" : "a past day: today's is where you talk (" + page.keyName("today") + ")"
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.body)
      foreground: page.foreground
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) { if (page.dayKey(event)) event.accepted = true }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.keyName("chatSend") + " sends · " + page.keyName("marginBack") + " closes · " + page.keyName("day") + " from anywhere"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
