import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc
import "Answers.js" as Answers

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
  property alias paperKeysRef: paperKeys
  // A turn shown on purpose (a question's answer, from the PDF): the
  // conversation held at it, not at its foot, until a new turn comes; it
  // and the answer after it lit a moment.
  property int pinTurn: -1
  property int pinCount: 0
  property int litTurn: -1
  function showTurn(i) {
    dayPane.pinTurn = i
    dayPane.pinCount = page.dayTurns.length
    dayPane.litTurn = i
    litTimer.restart()
    Qt.callLater(dayPane.toPin)
  }
  function toPin() {
    var it = dayPane.pinTurn >= 0 ? turnsRep.itemAt(dayPane.pinTurn) : null
    if (!it) return
    dayFlick.contentY = Math.max(0, Math.min(dayFlick.contentHeight - dayFlick.height, it.y - page.sp(12)))
  }
  Timer { id: litTimer; interval: 2600; onTriggered: dayPane.litTurn = -1 }
  Connections {
    target: dayPane.page
    function onDayTurnsChanged() { if (dayPane.pinTurn >= 0 && dayPane.page.dayTurns.length !== dayPane.pinCount) dayPane.pinTurn = -1 }
    function onNoteRoomChanged() { dayPane.pinTurn = -1 }
  }
  // A paper's room (plan.md item 15, step 2): its marks as a list, or its
  // chat; the pane turns between them.
  readonly property bool listing: page.paper.room && page.paper.listing

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

  MouseArea { anchors.fill: parent; onClicked: page.dayKeysItem().forceActiveFocus() }

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
    text: page.paper.room ? (dayPane.listing ? "MARKS · " : "CHAT · ") + (page.noteLabel || "").toUpperCase()
      : page.noteRoom ? "ABOUT " + (page.noteLabel || "").toUpperCase()
      : page.noteService.isToday ? "EVERYTHING · TODAY" : (page.dateLabel || "").toUpperCase()
    color: page.dim
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }

  // ------------------------------------------------- the paper's marks
  Item {
    id: paperKeys
    anchors.fill: parent
    Keys.onPressed: function (event) { if (page.paper.keyPressed(event)) event.accepted = true }
  }
  Column {
    id: paperView
    visible: dayPane.listing
    anchors.top: dayTitle.bottom
    anchors.topMargin: page.sp(12)
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: dayPane.contentRightInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: dayPane.contentBottomInset
    spacing: page.sp(8)

    // The strip: all, highlights, questions — as the dashboard's courses.
    Row {
      spacing: page.sp(6)
      Repeater {
        model: [{ f: "all", label: "all", key: "paperAll" }, { f: "h", label: "highlights", key: "paperHighlights" },
                { f: "q", label: "questions", key: "paperQuestions" }]
        Rectangle {
          required property var modelData
          readonly property bool on: page.paper.filter === modelData.f
          readonly property int n: page.paper.count(modelData.f)
          width: chipText.implicitWidth + page.sp(14)
          height: chipText.implicitHeight + page.sp(6)
          radius: height / 2
          color: on ? Style.selectedFill : "transparent"
          border.width: 1
          border.color: on ? page.accent : page.faint
          Text {
            id: chipText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: parent.modelData.label + " " + parent.n
              + (parent.modelData.f === "q" && page.paper.waiting.length > 0 ? " · " + page.paper.waiting.length + " waiting" : "")
            color: parent.on ? page.foreground : page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.paper.filter = parent.modelData.f; page.paper.at = 0; paperKeys.forceActiveFocus() }
          }
        }
      }
    }

    // The first row: the paper as a whole — Enter asks about it with
    // nothing attached.
    Rectangle {
      id: wholeRow
      readonly property bool hot: page.paper.at === -1 && paperKeys.activeFocus
      width: parent.width
      height: wholeColumn.implicitHeight + page.sp(8)
      radius: Style.cornerRadius
      color: hot ? Style.selectedFill : "transparent"
      border.width: 1
      border.color: hot ? page.accent : page.faint
      onHotChanged: page.selected(wholeRow, "right", hot)
      Column {
        id: wholeColumn
        x: page.sp(8)
        y: page.sp(4)
        width: parent.width - page.sp(16)
        spacing: page.sp(1)
        Text {
          textFormat: Text.PlainText
          text: "the whole paper"
          color: page.foreground
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "ask about it as a whole: a summary, its main ideas, anything"
            + (page.noteTalkTurns > 0 ? " · " + Math.floor(page.noteTalkTurns / 2) + (page.noteTalkTurns > 3 ? " answers" : " answer") + " so far" : "")
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.paper.pick(-1); page.paper.marks = []; page.paper.showChat() }
      }
    }

    ListView {
      id: paperListView
      width: parent.width
      height: parent.height - y - paperFoot.implicitHeight - page.sp(8)
      clip: true
      spacing: page.sp(2)
      model: page.paper.rows
      currentIndex: page.paper.at
      boundsBehavior: Flickable.StopAtBounds
      highlightFollowsCurrentItem: false
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
      delegate: Rectangle {
        id: markRow
        required property var modelData
        required property int index
        readonly property bool hot: index === page.paper.at && paperKeys.activeFocus
        // Picked in the PDF, the keys there: lit still, so the row and the
        // mark being changed are seen as one.
        readonly property bool shown: page.pdfItem.picked === modelData.id
        readonly property bool kept: page.paper.kept.indexOf(modelData.id) >= 0
        readonly property string state_: page.paper.markState(modelData)
        width: paperListView.width
        height: markColumn.implicitHeight + page.sp(8)
        radius: Style.cornerRadius
        color: hot || shown ? Style.selectedFill : "transparent"
        border.width: shown && !hot ? 1 : 0
        border.color: page.accent
        onHotChanged: page.selected(markRow, "right", hot)
        Rectangle {
          visible: markRow.kept
          width: 2
          height: parent.height
          color: page.accent
        }
        Column {
          id: markColumn
          x: page.sp(8)
          y: page.sp(4)
          width: parent.width - page.sp(16)
          spacing: page.sp(1)
          Row {
            spacing: page.sp(6)
            Rectangle {
              width: page.sp(7)
              height: page.sp(7)
              radius: 2
              anchors.verticalCenter: parent.verticalCenter
              color: markRow.modelData.kind === "q" ? page.palette.blue : page.palette.yellow
            }
            Text {
              textFormat: Text.PlainText
              text: "p. " + markRow.modelData.page + (markRow.modelData.placed ? "" : " · not found on its page")
                + (markRow.state_ === "waiting" ? " · waiting" : markRow.state_ === "answered" ? " · answered" : "")
              color: markRow.state_ === "waiting" ? page.accent : page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
            }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: "“" + markRow.modelData.text + "”"
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.italic: true
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          // An answered question's answer, its first words.
          Text {
            readonly property var answer: markRow.state_ === "answered" ? page.paper.answerOf(markRow.modelData.id) : null
            visible: answer !== null
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: answer ? "→ " + Answers.gist(answer.text, 160).text : ""
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          Text {
            visible: !!markRow.modelData.note
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: markRow.modelData.note || ""
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          // A click takes the keys to the mark in the PDF, to change or
          // remove it there; a double click asks about it.
          onClicked: page.paper.edit(markRow.index)
          onDoubleClicked: { page.paper.attach(markRow.modelData.id); page.paper.showChat() }
        }
      }
    }

    Text {
      visible: page.paper.rows.length === 0
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.paper.count("all") === 0
        ? "Nothing marked yet. Select words in the PDF, then " + page.keyName("pdfMark") + " for a highlight or "
          + page.keyName("pdfQuestion") + " for a question."
        : "None here."
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
    }

    Text {
      id: paperFoot
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.keyName("paperOpen") + (page.paper.at < 0 ? " chats about the whole paper · " : " asks about this mark · ")
        + page.keyName("paperKeep") + " keeps several · "
        + page.keyName("paperChat") + " the chat · "
        + (page.paper.at >= 0 ? page.keyName("paperEdit") + " or a click edits it in the PDF · " : "")
        + "1 2 3 the strip"
        + (page.paper.waiting.length > 0 ? " · " + page.keyName("paperAskWaiting") + " asks the " + page.paper.waiting.length + " waiting" : "")
        + " · " + page.keyName("paperBack") + " closes"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }

  Flickable {
    id: dayFlick
    visible: !dayPane.listing
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
    // A new turn is seen: the conversation keeps to its foot — but for a
    // turn shown on purpose, which it keeps to.
    onContentHeightChanged: {
      if (dayPane.pinTurn >= 0) dayPane.toPin()
      else if (contentHeight > height) contentY = contentHeight - height
    }

    TouchScroll { flickable: dayFlick }

    // The exchange shown on purpose, lit behind its turns a moment.
    Rectangle {
      readonly property Item from: dayPane.litTurn >= 0 ? turnsRep.itemAt(dayPane.litTurn) : null
      readonly property Item to: dayPane.litTurn >= 0 ? turnsRep.itemAt(dayPane.litTurn + 1) || from : null
      visible: from !== null
      x: -page.sp(6)
      y: from ? from.y - page.sp(4) : 0
      width: dayColumn.width + page.sp(12)
      height: from && to ? to.y + to.height - from.y + page.sp(8) : 0
      radius: Style.cornerRadius
      color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0.12)
      opacity: litTimer.running ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 500 } }
    }

    Column {
      id: dayColumn
      width: parent.width
      spacing: page.sp(12)

      // "Everything": the earlier days, a line each; unfolded, the places
      // talked in that day, a line each, opening what they are about.
      Column {
        width: dayColumn.width
        spacing: 0
        visible: page.convoDays.length > 0
        Repeater {
          model: page.convoDays
          Column {
            id: dayFold
            required property var modelData
            width: parent.width
            spacing: 0
            FoldLine {
              page: dayPane.page
              width: parent.width
              day: true
              rowKey: "d:" + dayFold.modelData.date
              unfolded: !!page.convoOpenDays[dayFold.modelData.date]
              head: dayFold.modelData.label + " · " + dayFold.modelData.subjects
                + (dayFold.modelData.subjects === 1 ? " subject · " : " subjects · ") + dayFold.modelData.turns + " turns"
              onAct: page.convoAct(rowKey)
            }
            Repeater {
              model: page.convoOpenDays[dayFold.modelData.date] ? dayFold.modelData.groups : []
              FoldLine {
                required property var modelData
                page: dayPane.page
                width: dayFold.width
                indent: page.sp(14)
                rowKey: "g:" + dayFold.modelData.date + ":" + modelData.thread
                head: page.sayFold(modelData)
                tail: page.sayFoldLast(modelData)
                onAct: page.convoAct(rowKey)
              }
            }
          }
        }
      }

      Repeater {
        id: turnsRep
        model: page.dayTurns
        Column {
          id: turn
          required property var modelData
          required property int index
          width: dayColumn.width
          spacing: page.sp(2)
          // What the agent said unasked on opening the page, before this
          // turn: a turn of its own, answered in the box like any other.
          Repeater {
            model: page.openingBefore(turn.index)
            Column {
              required property var modelData
              width: turn.width
              spacing: page.sp(2)
              Text {
                textFormat: Text.PlainText
                text: "when you opened the page" + (modelData.at ? " · " + modelData.at.slice(11, 16) : "")
                color: page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
              }
              ChatTurn {
                page: dayPane.page
                text: modelData.text
              }
            }
          }
          // Today's other places — a task's chat, a paper's — said before
          // this turn: a line each, in the order said.
          Repeater {
            model: page.convoBefore(turn.index)
            FoldLine {
              required property var modelData
              page: dayPane.page
              width: turn.width
              rowKey: "g::" + modelData.thread
              head: page.sayFold(modelData)
              tail: page.sayFoldLast(modelData)
              onAct: page.convoAct(rowKey)
            }
          }
          // The marks a message about a paper pointed at, over its bubble.
          Text {
            visible: modelData.role === "student" && !!modelData.marks && modelData.marks.length > 0
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: (modelData.marks || []).map(function (id) { return "↳ " + page.paper.head(id) }).join("  ")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          // The turn, drawn as every pane draws one (Turn.qml).
          Turn {
            page: dayPane.page
            width: turn.width
            t: modelData
            pane: "day"
            flick: dayFlick
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
                    radius: Style.cornerRadius
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
          // Helpful or not: the student's word on the answer, for the
          // weekly review and the eval cases. A word again takes it back.
          Row {
            visible: modelData.role === "agent" && !modelData.error && !!modelData.text
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
        }
      }

      // The morning's words with no turn after them yet.
      Repeater {
        model: page.openingBefore(page.dayTurns.length)
        Column {
          required property var modelData
          width: dayColumn.width
          spacing: page.sp(2)
          Text {
            textFormat: Text.PlainText
            text: "when you opened the page" + (modelData.at ? " · " + modelData.at.slice(11, 16) : "")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          ChatTurn {
            page: dayPane.page
            text: modelData.text
          }
        }
      }
      // …and those said since the day's last turn.
      Column {
        width: dayColumn.width
        spacing: 0
        visible: tailRep.count > 0
        Repeater {
          id: tailRep
          model: page.convoBefore(page.dayTurns.length)
          FoldLine {
            required property var modelData
            page: dayPane.page
            width: dayColumn.width
            rowKey: "g::" + modelData.thread
            head: page.sayFold(modelData)
            tail: page.sayFoldLast(modelData)
            onAct: page.convoAct(rowKey)
          }
        }
      }

      // How long (2026-11-18); the box below has the square that stops it,
      // and a click on the word stops it too.
      Row {
        spacing: page.sp(12)
        visible: page.dayThinking || page.thinkHeld === "day"
      Text {
        id: dayThinking
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        property double since: 0
        property int elapsed: 0
        onVisibleChanged: { since = visible ? Date.now() : 0; elapsed = 0 }
        Timer {
          interval: 1000
          repeat: true
          running: dayThinking.visible
          onTriggered: dayThinking.elapsed = Math.floor((Date.now() - dayThinking.since) / 1000)
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: page.stopAgent("day")
        }
        text: "thinking" + (elapsed >= 2 ? " · " + elapsed + "s" : "")
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
      }

      Text {
        visible: page.dayTurns.length === 0 && page.dayOpening.length === 0 && !page.dayThinking
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.paper.room
          ? "Chat about this paper. Asking shares what you marked and the passages you attach; the paper whole only when the agent needs it. Attach a mark with ^."
          : page.noteRoom
          ? "Chat about this note. Chatting shares it with the agent, for this chat only; the note itself is never written. Point at a part with @."
          : page.dayCanSend
          ? "The day's chat: your tasks, your courses, what you wrote. Point at a block, a task, a note or a paper with @."
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
    visible: !dayPane.listing
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: dayPane.contentRightInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: dayPane.contentBottomInset
    spacing: page.sp(6)

    // `@`: what to point at (MentionList.qml, the same in every box).
    MentionList {
      page: dayPane.page
      width: dayBox.width
      shown: !!page.dayMention && !page.dayMention.margin
      onPicked: dayField.forceActiveFocus()
    }

    // The marks the next message points at; Backspace in the empty box
    // lets go of the last.
    Repeater {
      model: page.paper.room ? page.paper.marks : []
      Text {
        required property var modelData
        width: dayBox.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: "↳ " + page.paper.head(modelData)
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
    // Answers to passages of the agent's, each under its own (Ctrl+R).
    ReplyDrafts {
      page: dayPane.page
      width: parent.width
      pane: "day"
      box: dayField
      onSend: { if (page.sendDay(dayField.text)) dayField.text = "" }
    }

    // What the next message is about: its chips. Backspace in the empty
    // box lets go of the last; a click on one lets it go.
    Chips {
      page: dayPane.page
      width: parent.width
      refs: page.noteRoom ? page.dayRefs : page.dayChips
      onDrop: function (i) {
        if (page.noteRoom) page.dayRefs = []
        else page.dropDayChip(i)
        dayField.forceActiveFocus()
      }
    }

    ChatField {
      id: dayField
      page: dayPane.page
      width: parent.width
      height: implicitHeight
      // Read-only rather than disabled on a past day: the pane still takes
      // the keys, so Esc and the panes' keys work in it.
      readOnly: !page.dayCanSend
      busy: page.dayThinking || page.thinkHeld === "day"
      onStop: page.stopAgent("day")
      placeholderText: busy ? page.keyName("marginBack") + " stops"
        : page.paper.room ? (page.paper.marks.length > 0 ? "ask about it…" : "ask about this paper…")
        : page.noteRoom ? "chat about this note…"
        : page.dayCanSend ? "chat with the day…" : "a past day: today's is where you chat (" + page.keyName("today") + ")"
      onKeyPressed: function (event) { if (page.dayKey(event)) event.accepted = true }
      onTextChanged: { page.dayTyped(text); Qt.callLater(page.updateDayMention) }
      onCursorPositionChanged: Qt.callLater(page.updateDayMention)
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.paper.room ? page.keyName("chatSend") + " sends · ^ attaches a mark · quotes link to the page · "
          + page.keyName("marginBack") + " back to the marks"
        : page.keyName("chatSend") + " sends · Shift+Enter a new line · @ points at " + (page.noteRoom ? "a part of it" : "a block, a task, a note")
        + " · " + page.keyName("chatAnswer") + " answers words you select"
        + (page.dayOpenCards.length > 0 ? " · " + page.keyName("marginUp") + " to its proposals"
           : page.convoRows.length > 0 ? " · " + page.keyName("marginUp") + " to the other chats" : "")
        + " · " + page.keyName("marginBack") + " closes · " + page.keyName("dayChat") + " from anywhere"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
