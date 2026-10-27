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
  // Against the window's right edge, beside the note or the dashboard.
  x: page.contentItem.width - page.edge - width
  y: besideDash ? (page.alongside ? 0 : page.sheetMargin) : sheet.y
  height: besideDash ? (page.alongside ? page.contentItem.height : page.contentItem.height - page.sheetMargin * 2) : sheet.height
  width: besideDash ? page.talkWidth : page.marginWidth
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(22)

  MouseArea { anchors.fill: parent; onClicked: dayField.forceActiveFocus() }

  // In the window the pane sits on the same ground as the note; a
  // hairline keeps them apart, as the sidebar's does on its side.
  Rectangle {
    visible: page.alongside
    // On the pane's own edge, where the focus frame is drawn too.
    anchors.left: parent.left
    width: 1
    height: parent.height
    color: page.faint
  }

  Text {
    id: dayTitle
    anchors.top: parent.top
    anchors.topMargin: dayPane.contentTopInset
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    textFormat: Text.PlainText
    text: page.noteRoom ? "ABOUT " + (page.noteLabel || "").toUpperCase()
      : page.noteService.isToday ? "TODAY" : (page.dateLabel || "").toUpperCase()
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
          ChatTurn {
            page: dayPane.page
            text: modelData
            color: page.dim
          }
        }
      }

      Repeater {
        model: page.dayTurns
        Column {
          id: turn
          required property var modelData
          required property int index
          width: dayColumn.width
          spacing: page.sp(2)
          // The block a message pointed at, over its bubble.
          Text {
            visible: modelData.role === "student" && !!modelData.block
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: "↳ " + page.blockHead(modelData.block)
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          ChatTurn {
            page: dayPane.page
            mine: modelData.role !== "agent"
            text: modelData.error ? "could not answer: " + page.sayPlanError(modelData.error)
              : modelData.role === "agent" ? page.linkCitations(modelData.text) : modelData.text
            color: modelData.error ? page.urgent : page.foreground
            onLinkActivated: function (link) { page.openCitation(link) }
          }
          // What it proposed: a card each, the same item as the dashboard's
          // row — structured, not prose: ◇ and its kind, the box and what
          // changes in it, the day as a pill, the reason faint.
          Repeater {
            id: cards
            readonly property string turnAt: modelData.at || ""
            model: modelData.role === "agent" ? (modelData.proposals || []) : []
            Rectangle {
              id: card
              required property var modelData
              readonly property var item: page.dayCardLive(modelData) || modelData
              readonly property string state_: page.dayCardState(modelData, cards.turnAt)
              readonly property bool live: state_ === "open" || state_ === "done by itself"
              readonly property bool focused: live && page.dayCardFocus >= 0 && !!page.dayOpenCards[page.dayCardFocus]
                && page.dayOpenCards[page.dayCardFocus].id === modelData.id
              onFocusedChanged: page.selected(card, "right", focused)
              width: parent.width
              height: cardColumn.implicitHeight + page.sp(14)
              radius: Style.cornerRadius
              color: focused ? Style.selectedFill : "transparent"
              border.width: 1
              border.color: focused ? page.accent : page.faint
              opacity: live || state_ === "arriving" ? 1 : 0.55

              MouseArea {
                anchors.fill: parent
                enabled: card.live
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  for (var i = 0; i < page.dayOpenCards.length; i++)
                    if (page.dayOpenCards[i].id === card.modelData.id) page.dayCardFocus = i
                  dayField.forceActiveFocus()
                }
              }

              Column {
                id: cardColumn
                x: page.sp(10)
                y: page.sp(7)
                width: parent.width - page.sp(20)
                spacing: page.sp(3)
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "◇ " + page.dayCardKind(card.item) + (card.state_ === "open" || card.state_ === "arriving" ? "" : " · " + card.state_)
                  color: card.live ? page.accent : page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.capitalization: Font.SmallCaps
                  font.pixelSize: page.fs(Style.font.caption)
                }
                Item {
                  width: parent.width
                  height: Math.max(cardFacts.implicitHeight, cardPill.visible ? cardPill.height : 0)
                  Text {
                    id: cardFacts
                    anchors.left: parent.left
                    anchors.right: cardPill.visible ? cardPill.left : parent.right
                    anchors.rightMargin: cardPill.visible ? page.sp(8) : 0
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    text: page.dayCardFacts(card.item)
                    color: page.foreground
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.body)
                  }
                  Rectangle {
                    id: cardPill
                    readonly property string label: page.dayCardPill(card.item)
                    visible: label !== ""
                    anchors.right: parent.right
                    width: cardPillText.implicitWidth + Math.round(page.textSize * 0.9)
                    height: cardPillText.implicitHeight + Math.round(page.textSize * 0.25)
                    radius: height / 2
                    color: card.item.kind === "do-date" ? Style.selectedFill : "transparent"
                    border.width: card.item.kind === "do-date" ? 0 : 1
                    border.color: page.faint
                    Text {
                      id: cardPillText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: cardPill.label
                      color: page.dim
                      font.family: page.fontFamily
                      font.styleName: page.fontStyle
                      font.pixelSize: Math.round(page.textSize * 0.78)
                    }
                  }
                }
                Text {
                  visible: !!card.item.why
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  text: card.item.why || ""
                  color: page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.bodySmall)
                }
                Text {
                  visible: card.focused
                  textFormat: Text.PlainText
                  text: page.keyName("marginAccept") + (card.state_ === "open" ? " does it · " : " lets it stand · ")
                    + page.keyName("marginDecline") + (card.state_ === "open" ? " declines" : " undoes")
                  color: page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                }
              }
            }
          }
          // What it proposed that local code did not offer (refused, or a
          // key it made up): said here, so a reply pointing at a card that
          // is not there is not the last word (2026-10-27).
          Text {
            visible: modelData.role === "agent" && (modelData.unoffered || []).length > 0
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "◇ not offered as a card: " + (modelData.unoffered || []).join("; ")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }

          // Helpful or not: the student's word on the answer, for the
          // weekly review and the eval cases. A word again takes it back.
          Row {
            visible: modelData.role === "agent" && !modelData.error && !!modelData.text && !page.noteRoom
            spacing: page.sp(10)
            Repeater {
              model: [{ value: "up", text: "helpful", act: "dayHelpful" }, { value: "down", text: "not helpful", act: "dayNotHelpful" }]
              Text {
                required property var modelData
                readonly property bool chosen: page.dayRatingOf(turn.index) === modelData.value
                textFormat: Text.PlainText
                text: (chosen ? "✓ " : "") + modelData.text
                color: chosen ? page.accent : page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: page.rateDay(turn.index, parent.modelData.value)
                }
              }
            }
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
        text: page.noteRoom
          ? "Ask about this note. Asking shares it with the agent, for this conversation only; the note itself is never written. Point at a part with " + page.keyName("dayHere") + "."
          : page.dayCanSend
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

    // `@`: the blocks of the open note to point at.
    Repeater {
      model: page.dayMention ? page.dayMention.items : []
      Rectangle {
        required property var modelData
        required property int index
        width: dayBox.width
        height: mentionText.implicitHeight + page.sp(4)
        radius: Style.cornerRadius
        color: page.dayMentionFocus === index ? Style.selectedFill : "transparent"
        Text {
          id: mentionText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: page.sp(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: "↳ " + modelData.head
          color: page.foreground
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { page.dayMentionFocus = index; page.pickDayMention(index); dayField.forceActiveFocus() }
        }
      }
    }

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

    ChatField {
      id: dayField
      page: dayPane.page
      width: parent.width
      height: implicitHeight
      // Read-only rather than disabled on a past day: the pane still takes
      // the keys, so Esc and the panes' keys work in it.
      readOnly: !page.dayCanSend
      placeholderText: page.noteRoom ? "ask about this note…"
        : page.dayCanSend ? "talk to the day…" : "a past day: today's is where you talk (" + page.keyName("today") + ")"
      onKeyPressed: function (event) { if (page.dayKey(event)) event.accepted = true }
      onTextChanged: Qt.callLater(page.updateDayMention)
      onCursorPositionChanged: Qt.callLater(page.updateDayMention)
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.keyName("chatSend") + " sends · Shift+Enter a new line · @ points at a block"
        + (page.dayOpenCards.length > 0 ? " · " + page.keyName("marginUp") + " to its proposals" : "")
        + " · " + page.keyName("marginBack") + " closes · " + page.keyName("day") + " from anywhere"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
