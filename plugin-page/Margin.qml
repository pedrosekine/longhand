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

  // Beside the note, on the block the cursor is in; or beside the
  // dashboard, on a proposal the person is talking with the planner about
  // (`talk`, 2026-10-20) — the same margin, the same keys.
  readonly property bool talk: page.talkOpen
  visible: talk || (page.marginWidth > 0 && page.problem === "" && page.marginOpen && !page.wideOpen)
  // Against the window's right edge, beside the note or the dashboard.
  x: page.contentItem.width - page.edge - width
  y: talk ? (page.alongside ? 0 : page.sheetMargin) : sheet.y
  height: talk ? (page.alongside ? page.contentItem.height : page.contentItem.height - page.sheetMargin * 2) : sheet.height
  width: talk ? page.talkWidth : page.marginWidth
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(22)

  // A click in the pane is the keys into it, as everywhere (docs/navigation.md).
  MouseArea { anchors.fill: parent; onClicked: page.focusPane("right") }

  // In the window the pane sits on the same ground as the note; a
  // hairline keeps them apart, as the sidebar's does on its side.
  Rectangle {
    visible: page.alongside
    anchors.left: parent.left
    anchors.leftMargin: -Math.round(page.marginGap / 2)
    width: 1
    height: parent.height
    color: page.faint
  }

  // Keyboard focus while in the margin (proposal rows or the tasks
  // panel). The chat field has its own handling.
  Item {
    id: marginKeys
    anchors.fill: parent
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      if (margin.talk) { if (page.talkKey(event)) event.accepted = true; return }
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

      // The proposal talked about, pinned at the top: what it is, and why.
      Rectangle {
        id: pinned
        readonly property bool hot: page.marginFocus === 0 && marginKeys.activeFocus
        onHotChanged: page.selected(pinned, "right", hot)
        visible: margin.talk
        width: marginColumn.width
        height: pinnedCol.implicitHeight + page.sp(12)
        radius: Style.cornerRadius
        color: hot ? Style.selectedFill : "transparent"
        border.width: 1
        border.color: hot ? page.accent : page.faint
        Column {
          id: pinnedCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: page.sp(6)
          spacing: page.sp(4)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: !page.talkItem ? (page.talkSettled !== "" ? "◇ " + page.talkSettled
                : page.talkData ? "☐ " + page.talkData.title : "…")
              : page.talkItem.kind === "question" ? "◇ " + page.talkItem.question
              : "◇ " + page.sayAsk(page.talkItem, false)
            color: page.talkItem ? page.foreground : page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.body)
          }
          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: !page.talkItem ? ""
              : page.talkItem.kind === "question" ? "recommended: " + (page.talkItem.recommended || "")
              : (page.talkItem.why || "")
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            width: parent.width
            visible: !!page.talkItem || page.talkSettled === ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: !page.talkItem ? page.tip("Back to the list", "marginBack")
              : page.talkItem.kind === "question"
              ? page.tips([["Accept the recommended answer", "marginAccept"], ["Set it aside", "marginDecline"], ["Back to the list", "marginBack"]])
              : page.talkItem && page.talkItem.told
              ? page.tips([["Let it stand", "marginAccept"], ["Undo it", "marginDecline"], ["Back to the list", "marginBack"]])
              : page.tips([["Accept", "marginAccept"], ["Decline", "marginDecline"], ["Back to the list", "marginBack"]])
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }
        MouseArea {
          anchors.fill: parent
          enabled: !!page.talkItem
          cursorShape: Qt.PointingHandCursor
          onClicked: { page.marginFocus = 0; marginKeys.forceActiveFocus() }
        }
      }

      // The box's one conversation with the planner, every proposal's turns.
      Repeater {
        model: margin.talk ? page.talkTurns : []
        Column {
          required property var modelData
          width: marginColumn.width
          spacing: page.sp(2)
          Text {
            width: parent.width
            textFormat: modelData.role === "agent" ? Text.MarkdownText : Text.PlainText
            wrapMode: Text.WordWrap
            text: modelData.text
            color: modelData.role === "agent" ? page.foreground : page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.title)
          }
          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            text: modelData.role !== "agent" ? ""
              : [modelData.who === "planner" ? "the planner" : "",
                 modelData.settled === "accept" ? "◇ settled: accepted" : modelData.settled === "decline" ? "◇ settled: declined"
                 : modelData.revised ? "◇ revised the proposal" : ""].filter(function (x) { return x !== "" }).join(" · ")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }
      }

      Text {
        width: parent.width
        visible: margin.talk && page.talkTurns.length === 0 && !page.talking
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: !page.talkItem ? "Think it through with the agent below — it knows your notes, this course's documents and "
          + "what the planner said about it. The conversation stays with the task."
          : (page.talkItem.kind === "question"
          ? "Answer in your words below, or ask back. " : "Ask the planner about it below — why this, or what you would rather. ")
          + "If you two agree, that settles it."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      Text {
        width: parent.width
        visible: !margin.talk && !!(page.currentRecord && page.currentRecord.reply)
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
        visible: !margin.talk && text !== ""
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
        visible: !margin.talk && !!(page.currentRecord && page.currentRecord.reply)
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

      // The block's conversation, with what was said about its box with
      // the planner merged in by time (one conversation per task), and
      // what the agent proposed as cards in it, each under the answer that
      // made it (page.marginRows) — the day pane's card: ◇ and its kind,
      // what changes, the day as a pill. Done only when the student says
      // so: Enter on a card runs it through the CLI.
      Repeater {
        model: margin.talk ? [] : page.marginRows
        Column {
          id: row
          required property var modelData
          readonly property bool isCard: modelData.card !== undefined
          readonly property var turn: modelData.turn || ({})
          readonly property int ci: isCard ? modelData.card : -1
          readonly property var p: isCard ? (page.currentProposals[ci] || ({})) : ({})
          width: marginColumn.width
          spacing: page.sp(2)

          Text {
            visible: !row.isCard
            width: parent.width
            textFormat: row.turn.role === "agent" ? Text.MarkdownText : Text.PlainText
            wrapMode: Text.WordWrap
            text: row.turn.text || ""
            color: row.turn.role === "agent" ? page.foreground : page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.title)
          }
          Text {
            visible: !row.isCard && row.turn.who === "planner" && row.turn.role === "agent"
            textFormat: Text.PlainText
            text: "the planner"
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }

          Rectangle {
            id: card
            visible: row.isCard
            readonly property bool done: !!row.p.accepted
            readonly property bool hot: page.marginFocus === row.ci && marginKeys.activeFocus
            onHotChanged: page.selected(card, "right", hot)
            Component.onCompleted: if (hot) page.selected(card, "right", true)
            width: parent.width
            height: cardColumn.implicitHeight + page.sp(14)
            radius: Style.cornerRadius
            color: hot ? Style.selectedFill : cardHover.hovered && !done ? Style.hoverFill : "transparent"
            border.width: 1
            border.color: hot ? page.accent : page.faint
            opacity: done ? 0.55 : 1
            HoverHandler { id: cardHover }

            Column {
              id: cardColumn
              x: page.sp(10)
              y: page.sp(7)
              width: parent.width - page.sp(20)
              spacing: page.sp(3)
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "◇ " + (row.p.moves ? "move deadline #" + row.p.moves.id : row.p.kind === "deadline" ? "new deadline" : (row.p.kind || ""))
                  + (card.done ? " · " + (row.p.accepted.moved ? "moved" : "added" + (row.p.accepted.id ? " #" + row.p.accepted.id : ""))
                     : row.p.error ? " · failed" : "")
                color: card.done ? page.faint : page.accent
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
                  text: row.p.kind === "deadline" ? page.marginCardFacts(row.p) : JSON.stringify(row.p)
                  color: page.foreground
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }
                Rectangle {
                  id: cardPill
                  readonly property string label: row.p.kind === "deadline" && row.p.when ? page.marginCardPill(row.p) : ""
                  visible: label !== ""
                  anchors.right: parent.right
                  width: cardPillText.implicitWidth + Math.round(page.textSize * 0.9)
                  height: cardPillText.implicitHeight + Math.round(page.textSize * 0.25)
                  radius: height / 2
                  color: "transparent"
                  border.width: 1
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
                visible: !!row.p.error
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: row.p.error || ""
                color: page.urgent
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.bodySmall)
              }
              Text {
                visible: card.hot && !card.done
                textFormat: Text.PlainText
                text: page.keyName("marginAccept") + " does it · it waits for you until then"
                color: page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
              }
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: card.done ? Qt.ArrowCursor : Qt.PointingHandCursor
              onClicked: { page.marginFocus = row.ci; page.acceptProposal(row.ci) }
              PanelToolTip { visible: parent.containsMouse && !card.done; text: page.tip("Do what it says", "marginAccept") }
            }
          }
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
        visible: margin.talk ? page.talking : page.answering
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
        visible: !margin.talk && !page.answered(page.currentRecord) && !page.answering && page.noteTurns.length === 0
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
      visible: page.marginOpen || margin.talk
      readOnly: margin.talk && !page.talkCanSend
      placeholderText: margin.talk && !page.talkCanSend ? "" : "…"
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.body)
      foreground: page.foreground
      Keys.onPressed: function (event) {
        if (page.anywhereKey(event)) { event.accepted = true; return }
        if (margin.talk) {
          if (Sc.hit(event, "chatSend")) page.sendTalk()
          else if (Sc.hit(event, "marginBack")) page.leaveTalk()
          else if (Sc.hit(event, "marginUp") && text === "" && page.talkItem) { page.marginFocus = 0; marginKeys.forceActiveFocus() }
          else return
          event.accepted = true
          return
        }
        if (Sc.hit(event, "chatSend")) page.sendChat()
        else if (Sc.hit(event, "marginBack")) page.backToNote()
        else if (Sc.hit(event, "marginUp") && text === "" && page.currentProposals.length > 0) page.moveMarginFocus(-1)
        else return
        event.accepted = true
      }
    }
  }
}
