import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QC
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
  property alias mentionListRef: marginMentionList
  readonly property bool busy: margin.talk ? page.talking || page.thinkHeld === "talk" : page.answering || page.thinkHeld === "margin"
  readonly property string thinkingText: thinking.text
  property alias marginKeysRef: marginKeys
  property alias flickRef: marginFlick
  function toFoot() {
    marginFlick.atFoot = true
    marginFlick.contentY = Math.max(0, marginFlick.contentHeight - marginFlick.height)
  }
  // Another block or task: its chat opens at its foot.
  Connections {
    target: margin.page
    function onMarginSubjectChanged() { margin.askAt = -1; Qt.callLater(margin.toFoot) }
  }

  // Your own questions, one after another (Alt+↑ / Alt+↓), as in the day's
  // pane (2026-11-28: the keys were said here and did nothing).
  property int askAt: -1
  function questions() {
    var rep = margin.talk ? talkRep : streamRep, out = []
    for (var i = 0; i < rep.count; i++) {
      var it = rep.itemAt(i)
      if (it && it.asked) out.push(i)
    }
    return out
  }
  function jumpQuestion(d) {
    var q = margin.questions(), rep = margin.talk ? talkRep : streamRep
    if (q.length === 0) { page.showHint("nothing asked here yet"); return }
    var k = margin.askAt < 0 || q.indexOf(margin.askAt) < 0 ? (d < 0 ? q.length - 1 : -1) : q.indexOf(margin.askAt) + d
    if (k < 0 || k >= q.length) {
      margin.askAt = -1
      if (d > 0) margin.toFoot()
      else page.showHint("the first thing you asked here")
      return
    }
    margin.askAt = q[k]
    var it = rep.itemAt(q[k])
    marginFlick.contentY = Math.max(0, Math.min(marginFlick.contentHeight - marginFlick.height, it.y - page.sp(12)))
    page.showHint("your questions: " + (k + 1) + " of " + q.length)
  }
  // The keys every box of the pane shares: a screen up or down, your
  // questions, the last answer's rating.
  function paneKeys(event) {
    if (page.pageFlick(marginFlick, event)) return true
    if (Sc.hit(event, "menu") && page.chatSelection && page.chatSelection.visible && page.chatSelection.selectedText !== "") { page.menuKey(); return true }
    if (Sc.hit(event, "chatPrevQuestion")) { margin.jumpQuestion(-1); return true }
    if (Sc.hit(event, "chatNextQuestion")) { margin.jumpQuestion(1); return true }
    if (!margin.talk && Sc.hit(event, "dayHelpful")) { page.rateMarginLast("up"); return true }
    if (!margin.talk && Sc.hit(event, "dayNotHelpful")) { page.rateMarginLast("down"); return true }
    return false
  }

  // Beside the note, on the block the cursor is in; or beside the
  // dashboard, on a proposal the person is talking with the planner about
  // (`talk`, 2026-10-20) — the same margin, the same keys.
  readonly property bool talk: page.talkOpen
  visible: talk || (page.marginWidth > 0 && page.problem === "" && page.marginOpen && !page.wideOpen)
  // Against the window's right edge, beside the note or the dashboard;
  // past it while one at a time the middle is shown (Page.paneTucked).
  x: page.paneAlone && page.paneTucked && !talk ? page.contentItem.width + page.sp(40) : page.contentItem.width - page.edge - width
  y: talk ? (page.alongside ? 0 : page.sheetMargin) : sheet.y
  height: talk ? (page.alongside ? page.contentItem.height : page.contentItem.height - page.sheetMargin * 2) : sheet.height
  width: talk ? page.talkWidth : page.marginWidth
  radius: page.alongside ? 0 : page.overlayRadius
  color: page.background
  borderSpec: page.cardSpec
  padding: page.sp(22)

  // A click in the pane is the keys into it, as everywhere (docs/navigation.md).
  MouseArea { anchors.fill: parent; onClicked: page.focusPane("right") }

  // Its edge, dragged, and which split it is in (PaneEdge, PaneSplit).
  PaneEdge { page: margin.page }

  // The header's line, as the day's pane has it (2026-11-28): what this
  // chat is about, and the split's word at its right. It scrolled away with
  // the turns, and said a key without being one; a click on it goes to the
  // whole chat, as the key does.
  Item {
    id: titleRow
    anchors.top: parent.top
    anchors.topMargin: margin.contentTopInset
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(aboutTitle.visible ? aboutTitle.implicitHeight : 0, paneSplit.visible ? paneSplit.implicitHeight : 0)
  }
  Text {
    id: aboutTitle
    visible: page.aboutChip !== null
    anchors.verticalCenter: titleRow.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: margin.contentLeftInset
    anchors.right: paneSplit.visible ? paneSplit.left : parent.right
    anchors.rightMargin: paneSplit.visible ? page.sp(10) : margin.contentRightInset
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: page.aboutChip ? "ABOUT THIS " + String(page.aboutChip.kind).toUpperCase() + "  ·  " + page.keyName("pane3") + " the whole chat" : ""
    color: aboutArea.containsMouse && page.handOn ? page.accent : page.dim
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
    MouseArea {
      id: aboutArea
      anchors.fill: parent
      anchors.margins: -page.sp(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { page.focusPane("right"); page.paneKey("right") }
      Tip { host: margin.page; shown: parent.containsMouse; act: "pane3"; text: page.tip("The whole chat", "pane3") }
    }
  }
  PaneSplit {
    id: paneSplit
    page: margin.page
    visible: shown && !margin.talk
    anchors.verticalCenter: titleRow.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: margin.contentRightInset
  }

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
      page.keysSeen(event)
      if (page.copyChatSelection(event, null)) { event.accepted = true; return }
      if (page.anywhereKey(event)) { event.accepted = true; return }
      if (margin.paneKeys(event)) { event.accepted = true; return }
      if (margin.talk) { if (page.talkKey(event)) event.accepted = true; return }
      if (Sc.hit(event, "marginBack") && page.stopAgent(margin.talk ? "talk" : "margin")) {}
      else if (Sc.hit(event, "marginBack")) page.backToNote()
      else if (Sc.hit(event, "marginUp")) page.moveMarginFocus(-1)
      else if (Sc.hit(event, "marginDown")) page.moveMarginFocus(1)
      else if (Sc.hit(event, "marginAccept")) page.acceptProposal(page.marginFocus)
      else if (Sc.hit(event, "marginDecline")) page.declineProposal(page.marginFocus)
      else if (Sc.hit(event, "undo")) { if (!page.undoLastCard()) return }
      else if (Sc.hit(event, "keysHere")) page.toggleKeys()
      else if (Sc.hit(event, "marginHelpful")) page.rateMarginLast("up")
      else if (Sc.hit(event, "marginNotHelpful")) page.rateMarginLast("down")
      else return
      event.accepted = true
    }
  }

  Flickable {
    id: marginFlick
    acceptedButtons: Qt.NoButton
    QC.ScrollBar.vertical: ScrollMark { page: margin.page }
    anchors.top: titleRow.bottom
    anchors.topMargin: titleRow.height > 0 ? page.sp(14) : page.sp(4)
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

    // Kept at its foot, as the day's is (2026-11-28: it never scrolled — a
    // long chat opened on its first turn, and what was sent, "thinking"
    // and the answer all came in under the fold): what comes is followed
    // while at the foot; scrolled up to read, it stays; the box growing
    // under it keeps the last turn in view.
    property bool atFoot: true
    property bool resizing: false
    property real seenCh: 0
    property real seenH: 0
    function keepFoot() {
      if (!(marginFlick.atFoot || contentY >= contentHeight - height - page.sp(4)) || contentHeight <= height) return
      marginFlick.atFoot = true
      marginFlick.resizing = true
      contentY = contentHeight - height
      marginFlick.resizing = false
    }
    onContentHeightChanged: { marginFlick.seenCh = contentHeight; marginFlick.keepFoot() }
    onHeightChanged: { marginFlick.seenH = height; if (marginFlick.atFoot) marginFlick.keepFoot() }
    // A move of the reader's, not the layout's (as in the day's pane).
    onContentYChanged: if (!marginFlick.resizing && contentHeight === marginFlick.seenCh && height === marginFlick.seenH)
      marginFlick.atFoot = contentY >= contentHeight - height - page.sp(4)

    Column {
      id: marginColumn
      // At the chat's measure, however wide the pane (2026-11-22).
      width: Math.min(parent.width, page.chatMeasure)
      spacing: page.sp(12)

      // "About this" (docs/agent.md, "One conversation", slice 2): the one
      // conversation's turns about this task or block, its header above
      // (titleRow). What was said about it elsewhere — the day's chat
      // pointing at it, another day's margin for the same task — is merged
      // in by time.
      // The proposal talked about, pinned at the top: what it is, and why.
      Rectangle {
        id: pinned
        readonly property bool hot: page.marginFocus === 0 && page.talkCardFocus < 0 && marginKeys.activeFocus
        onHotChanged: { page.selected(pinned, "right", hot); if (hot) Qt.callLater(function () { page.revealIn(marginFlick, pinned) }) }
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
          // Option A quiet footer links on the pinned proposal card when live.
          Item {
            visible: !!page.talkItem
            width: parent.width
            height: visible ? pinnedActRow.implicitHeight + page.sp(7) : 0
            Rectangle {
              anchors.top: parent.top
              anchors.topMargin: page.sp(2)
              width: parent.width
              height: 1
              color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.09)
            }
            Row {
              id: pinnedActRow
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              spacing: page.sp(14)
              Row {
                spacing: page.sp(5)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: page.talkItem && page.talkItem.told ? "keep"
                    : page.talkItem && page.talkItem.kind === "question" ? "accept recommended" : "accept"
                  color: pinAccArea.containsMouse && page.handOn ? page.accent : page.foreground
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.weight: Font.Medium
                  font.pixelSize: page.fs(Style.font.caption)
                  font.underline: pinAccArea.containsMouse && page.handOn
                  MouseArea {
                    id: pinAccArea
                    anchors.fill: parent
                    anchors.margins: -page.sp(4)   // wider than the word (the second pass)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.focusPane("right"); page.acceptTalked() }
                  }
                }
                KeyCaps { visible: pinned.hot; anchors.verticalCenter: parent.verticalCenter; page: margin.page; key: page.keyName("marginAccept"); size: page.fs(Style.font.caption) }
              }
              Row {
                spacing: page.sp(5)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: page.talkItem && page.talkItem.told ? "undo"
                    : page.talkItem && page.talkItem.kind === "question" ? "set aside" : "decline"
                  color: pinDecArea.containsMouse && page.handOn ? (page.talkItem && page.talkItem.told ? page.accent : page.urgent) : (page.talkItem && page.talkItem.told ? page.accent : page.dim)
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                  font.underline: pinDecArea.containsMouse && page.handOn
                  MouseArea {
                    id: pinDecArea
                    anchors.fill: parent
                    anchors.margins: -page.sp(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.focusPane("right"); page.declineTalked() }
                  }
                }
                KeyCaps { visible: pinned.hot; anchors.verticalCenter: parent.verticalCenter; page: margin.page; key: page.keyName("marginDecline"); size: page.fs(Style.font.caption) }
              }
            }
          }
          Text {
            width: parent.width
            visible: !page.talkItem && page.talkSettled === ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: page.tip("Back to the list", "marginBack")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }
        MouseArea {
          anchors.fill: parent
          z: -1
          enabled: !!page.talkItem
          cursorShape: Qt.PointingHandCursor
          onClicked: { page.marginFocus = 0; marginKeys.forceActiveFocus() }
        }
      }

      // The task's one conversation: its own turns (its margin, its talks
      // about proposals) and what was said about it anywhere else, read
      // from the log, in the order said (page.talkStream).
      Repeater {
        id: talkRep
        model: margin.talk ? page.talkStream : []
        Column {
          required property var modelData
          readonly property bool asked: modelData.role !== "agent" && !modelData.elsewhere
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
              flick: marginFlick
              hot: !!(page.talkCardFocus >= 0 && marginKeys.activeFocus && page.talkCards[page.talkCardFocus]
                && page.talkCards[page.talkCardFocus].index === modelData.index)
              onFocused: {
                for (var k = 0; k < page.talkCards.length; k++)
                  if (page.talkCards[k].index === modelData.index) { page.focusTalkCard(k); return }
                marginKeys.forceActiveFocus()
              }
              onAccepted: page.acceptTalkCard(modelData)
              onDeclinedClick: page.declineTalkCard(modelData)
              onUndone: if (modelData.ledger) page.undoSettledCard(modelData.ledger)
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

      // The block's first reply, a turn as any other (Turn.qml): its
      // citations open, its words can be replied to (2026-11-28: bare
      // words, neither).
      Turn {
        visible: !margin.talk && !!(page.currentRecord && page.currentRecord.reply)
        page: margin.page
        width: parent.width
        t: page.currentRecord && page.currentRecord.reply
          ? ({ role: "agent", text: page.currentRecord.reply, at: String(page.currentRecord.at || ""), payload: page.currentRecord.payload || "" }) : ({})
        pane: "margin"
        flick: marginFlick
        onLinkActivated: function (link) { page.openCitation(link) }
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
        id: replyRate
        visible: !margin.talk && !!(page.currentRecord && page.currentRecord.reply)
        // As under the day's answers: with its keys while it is the last
        // answer, else once chosen or under the pointer.
        readonly property bool last: page.marginLastAnswer === null
        opacity: last || page.ratingOf(page.currentRec) !== "" || replyHover.hovered && page.handOn ? 1 : 0
        spacing: page.sp(14)
        HoverHandler { id: replyHover }
        Repeater {
          model: [{ text: "helpful", value: "up", act: "marginHelpful" }, { text: "not helpful", value: "down", act: "marginNotHelpful" }]
          Text {
            required property var modelData
            readonly property bool chosen: page.ratingOf(page.currentRec) === modelData.value
            textFormat: Text.PlainText
            text: (chosen ? "✓ " : "") + modelData.text   // as the follow-up's rating below says it
            color: rateArea.containsMouse && page.handOn ? page.accent : chosen ? page.foreground : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
            font.underline: chosen
            MouseArea {
              id: rateArea
              anchors.fill: parent
              anchors.margins: -page.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { page.focusPane("right"); page.rateReply(modelData.value) }
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
        id: streamRep
        model: margin.talk ? [] : page.marginStream
        Column {
          id: row
          required property var modelData
          readonly property bool isCard: modelData.card !== undefined
          readonly property bool asked: !isCard && turn.role !== "agent" && !turn.elsewhere
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

          // Each answer of the block's own chat rated on its own (the
          // runner's `rate --turn`; 2026-11-28: these rated the first reply,
          // or nothing). The planner's turns and what was said elsewhere are
          // rated where they were said. Shown as under the day's answers.
          HoverHandler { id: rowHover }
          Row {
            readonly property bool showRate: !row.isCard && page.marginTurnRatable(row.turn)
            visible: showRate
            opacity: row.turn === page.marginLastAnswer || page.marginTurnRating(row.turn) !== "" || rowHover.hovered && page.handOn ? 1 : 0
            topPadding: page.sp(4)
            spacing: page.sp(14)
            Repeater {
              model: [{ text: "helpful", value: "up", act: "marginHelpful" }, { text: "not helpful", value: "down", act: "marginNotHelpful" }]
              Text {
                required property var modelData
                readonly property bool chosen: page.marginTurnRating(row.turn) === modelData.value
                textFormat: Text.PlainText
                text: (chosen ? "✓ " : "") + modelData.text
                color: mRateArea.containsMouse && page.handOn ? page.accent : chosen ? page.foreground : page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
                font.underline: chosen
                // Wider than its word; a click puts the keys in the pane
                // (2026-11-25, the mouse pass).
                MouseArea {
                  id: mRateArea
                  anchors.fill: parent
                  anchors.margins: -page.sp(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { page.focusPane("right"); page.rateMarginTurn(row.turn, modelData.value) }
                  Tip { host: page; shown: parent.containsMouse; text: page.tip(chosen ? "Take it back" : "Say it was " + modelData.text, modelData.act) }
                }
              }
            }
          }

          MarginCard {
            visible: row.isCard
            width: parent.width
            page: margin.page
            p: row.p
            flick: marginFlick
            declined: row.isCard && page.blockCardDeclined(page.currentRec, row.ci)
            hot: row.isCard && page.marginFocus === row.ci && marginKeys.activeFocus
            onFocused: { page.marginFocus = row.ci; marginKeys.forceActiveFocus() }
            onAccepted: { page.marginFocus = row.ci; page.acceptProposal(row.ci) }
            onDeclinedClick: { page.marginFocus = row.ci; page.declineProposal(row.ci) }
            onUndone: if (row.p && row.p.ledger) page.undoSettledCard(row.p.ledger)
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
        readonly property string phaseText: margin.talk ? page.talkPhase : page.runnerPhase
        textFormat: Text.PlainText
        text: (thinking.phaseText !== "" ? thinking.phaseText : "thinking") + (thinking.elapsed >= 2 ? " · " + thinking.elapsed + "s" : "")
        property int elapsed: 0
        // As the day's pane says it (2026-11-28: a title's size, italic).
        color: thinkStopArea.containsMouse && page.handOn ? page.accent : page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
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
          id: thinkStopArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.stopAgent(margin.talk ? "talk" : "margin")
          // What a click does, and its key (the second pass: it said nothing).
          Tip { host: margin.page; shown: parent.containsMouse; act: "marginBack"; text: page.tip("Stop it: your words back in the box", "marginBack") }
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
    // At the chat's measure, as the answers above (2026-11-22).
    width: Math.min(margin.width - margin.contentLeftInset - margin.contentRightInset, page.chatMeasure)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: margin.contentBottomInset
    height: chatField.visible ? chatField.implicitHeight + above.height + (above.height > 0 ? page.sp(6) : 0)
      + (foot.visible ? foot.implicitHeight + page.sp(6) : 0) : 0

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
        id: marginMentionList
        page: margin.page
        width: parent.width
        shown: chatField.visible && !!page.dayMention && page.dayMention.margin
        onPicked: chatField.forceActiveFocus()
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
        text: page.replyLabel("margin") + "  ·  "
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
        onDrop: function (i) { if (page.marginRefs[i]) chatField.dropMention(page.refKey(page.marginRefs[i])); page.marginRefs = page.marginRefs.filter(function (r, k) { return k !== i }); chatField.forceActiveFocus() }
      }
    }

    ChatField {
      id: chatField
      page: margin.page
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: foot.visible ? foot.top : parent.bottom
      anchors.bottomMargin: foot.visible ? page.sp(6) : 0
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
      chipKeys: page.marginRefs.map(page.refKey)
      onMentionGone: function (key) { page.marginRefs = page.marginRefs.filter(function (r) { return page.refKey(r) !== key }) }
      onCursorPositionChanged: Qt.callLater(page.updateMarginMention)
      onKeyPressed: function (event) {
        page.keysSeen(event)
        if (page.copyChatSelection(event, chatField)) { event.accepted = true; return }
        if (page.marginMentionKey(event)) { event.accepted = true; return }
        if (page.answerSelected(event)) { event.accepted = true; return }
        if (page.replyKey("margin", event)) { event.accepted = true; return }
        if (page.anywhereKey(event)) { event.accepted = true; return }
        if (margin.paneKeys(event)) { event.accepted = true; return }
        if (margin.talk) {
          if (Sc.hit(event, "chatSend")) { page.sendTalk(); if (text === "") margin.toFoot() }
          else if (Sc.hit(event, "marginBack") && page.stopAgent("talk")) {}
          else if (Sc.hit(event, "marginBack")) page.leaveTalk()
          // The card's Ctrl+Z, said on it, done here too (2026-11-28).
          else if (Sc.hit(event, "undo") && text === "" && page.undoLastCard()) {}
          else if (Sc.hit(event, "marginUp") && text === "" && page.talkCards.length > 0) page.focusTalkCard(page.talkCards.length - 1)
          else if (Sc.hit(event, "marginUp") && text === "" && page.talkItem) { page.marginFocus = 0; marginKeys.forceActiveFocus() }
          else return
          event.accepted = true
          return
        }
        if (Sc.hit(event, "chatSend")) { page.sendChat(); if (text === "") margin.toFoot() }
        else if (Sc.hit(event, "marginBack") && page.stopAgent("margin")) {}
        else if (Sc.hit(event, "marginBack")) page.backToNote()
        else if (Sc.hit(event, "undo") && text === "" && page.undoLastCard()) {}
        else if (Sc.hit(event, "marginUp") && text === "" && page.marginLiveCards.length > 0) page.moveMarginFocus(-1)
        else return
        event.accepted = true
      }
    }

    // The keys, a line under the box, as under the day's (2026-11-28: the
    // margin said none).
    Text {
      id: foot
      visible: chatField.visible && !chatField.readOnly && !page.marginReplying
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: page.marginReplies.length > 0 ? page.marginReplies.length + (page.marginReplies.length === 1 ? " reply" : " replies")
          + " · " + page.keyName("chatSend") + " sends · " + page.keyName("chatAnswer") + " more"
        : page.keyName("chatSend") + " sends · " + (page.marginCanPoint ? "@ attach · " : "") + page.keyName("chatAnswer") + " reply · "
          + page.keyName("marginBack") + (margin.talk ? " the list" : " back") + " · " + page.keyName("keys") + " keys"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
