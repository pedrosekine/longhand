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
import "Say.js" as Say
import "Queue.js" as Queue

// The margin: the agent's side of the page — its reply, its proposals, the conversation
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: margin
  required property Item page
  readonly property var sheet: page.sheetItem
  property alias chatFieldRef: chatField
  readonly property bool busy: margin.talk ? page.talking || page.thinkHeld === "talk" : page.answering || page.thinkHeld === "margin"
  readonly property string thinkingText: thinking.text
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
    // On the pane's own edge, where the focus frame is drawn too.
    anchors.left: parent.left
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
      if (page.copyChatSelection(event, null)) { event.accepted = true; return }
      if (page.anywhereKey(event)) { event.accepted = true; return }
      if (margin.talk) { if (page.talkKey(event)) event.accepted = true; return }
      if (Sc.hit(event, "marginBack") && page.stopAgent(margin.talk ? "talk" : "margin")) {}
      else if (Sc.hit(event, "marginBack")) page.backToNote()
      else if (Sc.hit(event, "marginUp")) page.moveMarginFocus(-1)
      else if (Sc.hit(event, "marginDown")) page.moveMarginFocus(1)
      else if (Sc.hit(event, "marginAccept")) page.acceptProposal(page.marginFocus)
      else if (Sc.hit(event, "marginDecline")) page.settleListedCard(page.currentProposals[page.marginFocus], "decline")
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

      // "About this" (docs/agent.md, "One conversation", slice 2): the one
      // conversation's turns about this task or block. Its own chat is
      // below; what was said about it elsewhere — the day's chat pointing
      // at it, another day's margin for the same task — is here first,
      // folded when it is long.
      Text {
        visible: page.aboutChip !== null
        width: marginColumn.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: page.aboutChip ? "ABOUT THIS " + String(page.aboutChip.kind).toUpperCase() + "  ·  " + page.keyName("pane3") + " everything" : ""
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      // The proposal talked about, pinned at the top: what it is, and why.
      Rectangle {
        id: pinned
        readonly property bool hot: page.marginFocus === 0 && page.talkCardFocus < 0 && marginKeys.activeFocus
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
              : "◇ " + Say.sayAsk(page.talkItem, false)
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

      // The task's one conversation: its own turns (its margin, its talks
      // about proposals) and what was said about it anywhere else, read
      // from the log, in the order said (page.talkStream).
      Repeater {
        model: margin.talk ? page.talkStream : []
        Column {
          required property var modelData
          width: marginColumn.width
          spacing: page.sp(2)
          bottomPadding: modelData.role === "agent" ? page.chatTurnGap : Math.round(page.chatTurnGap * 0.55)   // as in the day's chat
          Turn {
            page: margin.page
            width: parent.width
            t: modelData
            pane: "margin"
            flick: marginFlick
            onLinkActivated: function (link) { page.openCitation(link) }
          }
          // What the margin agent proposed in the task's chat: its cards,
          // under the answer that made them, as beside the note
          // (2026-11-03: "Proposed", and nothing here to see).
          Repeater {
            model: modelData.cards || []
            MarginCard {
              required property var modelData
              width: marginColumn.width
              page: margin.page
              p: modelData
              hot: !!(page.talkCardFocus >= 0 && marginKeys.activeFocus && page.talkCards[page.talkCardFocus]
                && page.talkCards[page.talkCardFocus].index === modelData.index)
              onActivated: page.acceptTalkCard(modelData)
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: margin.talk && page.talkTurns.length === 0 && !page.talking
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: !page.talkItem ? "Think it through with the agent below — it knows your notes, this course's documents and "
          + "what the planner said about it. The chat stays with the task."
          : (page.talkItem.kind === "question"
          ? "Answer in your words below, or ask back. " : "Ask the planner about it below — why this, or what you would rather. ")
          + "If you two agree, that settles it."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      ChatTurn {
        visible: !margin.talk && !!(page.currentRecord && page.currentRecord.reply)
        page: margin.page
        text: page.currentRecord && page.currentRecord.reply ? page.currentRecord.reply : ""
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
            color: rateArea.containsMouse && page.handOn ? page.accent : chosen ? page.foreground : page.faint
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
              Tip { host: page; shown: parent.containsMouse; text: page.tip(chosen ? "Take it back" : "Say it was " + modelData.text, modelData.act) }
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
        model: margin.talk ? [] : page.marginStream
        Column {
          id: row
          required property var modelData
          readonly property bool isCard: modelData.card !== undefined
          readonly property var turn: modelData.turn || ({})
          readonly property int ci: isCard ? modelData.card : -1
          readonly property var p: isCard ? (page.currentProposals[ci] || ({})) : ({})
          width: marginColumn.width
          spacing: page.sp(2)
          // Room between turns, as in the day's chat; a card stays close
          // under the answer that made it.
          required property int index
          readonly property var next: page.marginStream[index + 1]
          bottomPadding: next && next.card !== undefined ? page.sp(6)
            : !isCard && turn.role !== "agent" ? Math.round(page.chatTurnGap * 0.55) : page.chatTurnGap

          Turn {
            visible: !row.isCard
            page: margin.page
            width: parent.width
            t: row.turn
            pane: "margin"
            flick: marginFlick
            onLinkActivated: function (link) { page.openCitation(link) }
          }

          MarginCard {
            visible: row.isCard
            width: parent.width
            page: margin.page
            p: row.p
            hot: row.isCard && page.marginFocus === row.ci && marginKeys.activeFocus
            onActivated: { page.marginFocus = row.ci; page.acceptProposal(row.ci) }
          }
        }
      }

      // Thinking: where the answer will appear, for as long as the
      // block is away. It breathes rather than spins, and after a few
      // seconds it says how long it has been — which is the difference
      // between a slow pass and a hung one. The word is the agent's
      // own state, not a spinner: nothing else in the page moves.
      // How long (2026-11-18); the box below has the square that stops it,
      // and a click on the word stops it too.
      Row {
        width: parent.width
        visible: margin.busy
      Text {
        id: thinking
        property double since: 0
        textFormat: Text.PlainText
        text: "thinking" + (thinking.elapsed >= 2 ? " · " + thinking.elapsed + "s" : "")
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
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: page.stopAgent(margin.talk ? "talk" : "margin")
        }
        SequentialAnimation on opacity {
          running: thinking.visible
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }
      }
      }

      Text {
        width: parent.width
        visible: !margin.talk && !Queue.answered(page.currentRecord) && !page.answering && page.noteTurns.length === 0
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Nothing from the agent on this block yet. " + (page.currentTrigger !== ""
          ? page.keyName("ask") + " sends it, or write below." : "Write below to start its chat.")
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
    height: chatField.visible ? chatField.implicitHeight + above.height + (above.height > 0 ? page.sp(6) : 0) : 0

    // Over the box, as in the day's: what `@` offers, then what this
    // message is about — this chat's own thing (letting it go leaves for
    // the day's chat, with what was typed) and what `@` added.
    Column {
      id: above
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: chatField.top
      anchors.bottomMargin: height > 0 ? page.sp(6) : 0
      spacing: page.sp(6)
      MentionList {
        page: margin.page
        width: parent.width
        shown: chatField.visible && !!page.dayMention && page.dayMention.margin
        onPicked: chatField.forceActiveFocus()
      }
      ReplyOffer {
        page: margin.page
        width: parent.width
        pane: "margin"
        visible: chatField.visible && !!page.replyOffer && page.replyOffer.pane === "margin"
      }
      ReplyPills {
        page: margin.page
        width: parent.width
        pane: "margin"
        visible: chatField.visible && page.marginReplies.length > 0
      }
      Text {
        visible: chatField.visible && !!page.marginReplying
        textFormat: Text.PlainText
        text: "REPLY " + page.replyNumber("margin") + " OF " + page.replyNumber("margin") + "  ·  "
          + page.keyName("chatSend") + " attaches · " + page.keyName("marginBack") + " cancels"
        color: page.accent
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      Chips {
        id: aboutChips
        page: margin.page
        width: parent.width
        fixed: true
        visible: chatField.visible && page.aboutChip !== null
        refs: page.aboutChip ? [page.aboutChip] : []
        onDrop: page.aboutToDay()
      }
      Chips {
        page: margin.page
        width: parent.width
        visible: chatField.visible && page.marginRefs.length > 0
        refs: page.marginRefs
        onDrop: function (i) { page.marginRefs = page.marginRefs.filter(function (r, k) { return k !== i }); chatField.forceActiveFocus() }
      }
    }

    ChatField {
      id: chatField
      page: margin.page
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: implicitHeight
      visible: page.marginOpen || margin.talk
      readOnly: margin.talk && !page.talkCanSend
      replyQuote: page.marginReplying ? page.marginReplying.quote : ""
      replyN: page.replyNumber("margin")
      onCancelReply: { page.cancelReply("margin"); chatField.forceActiveFocus() }
      placeholderText: margin.busy ? page.keyName("marginBack") + " stops" : margin.talk && !page.talkCanSend ? ""
        : page.marginReplying ? "your reply…"
        : page.marginReplies.length > 0 ? "write, or reply to another passage…"
        : page.marginCanPoint ? "@ points at a task, a note, a paper…" : "…"
      busy: margin.busy
      onStop: page.stopAgent(margin.talk ? "talk" : "margin")
      onTextChanged: Qt.callLater(page.updateMarginMention)
      onCursorPositionChanged: Qt.callLater(page.updateMarginMention)
      onKeyPressed: function (event) {
        if (page.copyChatSelection(event, chatField)) { event.accepted = true; return }
        if (page.marginMentionKey(event)) { event.accepted = true; return }
        if (page.answerSelected(event)) { event.accepted = true; return }
        if (page.replyKey("margin", event)) { event.accepted = true; return }
        if (page.anywhereKey(event)) { event.accepted = true; return }
        if (margin.talk) {
          if (Sc.hit(event, "chatSend")) page.sendTalk()
          else if (Sc.hit(event, "marginBack") && page.stopAgent("talk")) {}
          else if (Sc.hit(event, "marginBack")) page.leaveTalk()
          else if (Sc.hit(event, "marginUp") && text === "" && page.talkCards.length > 0) page.focusTalkCard(page.talkCards.length - 1)
          else if (Sc.hit(event, "marginUp") && text === "" && page.talkItem) { page.marginFocus = 0; marginKeys.forceActiveFocus() }
          else return
          event.accepted = true
          return
        }
        if (Sc.hit(event, "chatSend")) page.sendChat()
        else if (Sc.hit(event, "marginBack") && page.stopAgent("margin")) {}
        else if (Sc.hit(event, "marginBack")) page.backToNote()
        else if (Sc.hit(event, "marginUp") && text === "" && page.currentProposals.length > 0) page.moveMarginFocus(-1)
        else return
        event.accepted = true
      }
    }
  }
}
