import Quickshell
import QtQuick
import QtQuick.Controls as QC
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
  property alias mentionListRef: dayMentionList
  // Where the pane stands (the live suite reads it): how far it is
  // scrolled, where today's rule is, the room under today, the header.
  function viewState() {
    return { y: dayFlick.contentY, top: historyColumn.visible ? historyColumn.y + todayRule.y : -1, h: dayFlick.height,
             ch: dayFlick.contentHeight, room: todayRoom.height, title: dayTitle.text }
  }
  property alias paperKeysRef: paperKeys
  // A turn shown on purpose (a question's answer, from the PDF): the
  // conversation held at it, not at its foot, until a new turn comes; it
  // and the answer after it lit a moment.
  property int pinTurn: -1
  property int pinCount: 0
  property int litTurn: -1
  // The day's last answer: the one its rating keys (Alt+= / Alt+-) act on,
  // and so the one whose "helpful" stays in view.
  readonly property int lastAnswer: {
    for (var i = page.dayTurns.length - 1; i >= 0; i--) if (page.dayTurns[i].role === "agent") return i
    return -1
  }
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

  // Your own questions, one after another (Alt+↑ / Alt+↓, 2026-11-22): the
  // first Alt+↑ goes to the last thing you asked, each next one to the one
  // before; Alt+↓ past the last goes back to the foot. Before the first
  // shown, the earlier sessions unfold.
  property int askAt: -1
  function questions() {
    var out = []
    for (var i = 0; i < page.dayTurns.length; i++)
      if (page.dayTurns[i].role !== "agent" && !(dayPane.folded && i < dayPane.earlier)) out.push(i)
    return out
  }
  function jumpQuestion(d) {
    var q = dayPane.questions()
    if (q.length === 0) { page.showHint("nothing asked here yet"); return }
    var k = dayPane.askAt < 0 ? (d < 0 ? q.length - 1 : -1) : q.indexOf(dayPane.askAt) + d
    if (dayPane.askAt >= 0 && q.indexOf(dayPane.askAt) < 0) k = d < 0 ? q.length - 1 : -1
    if (k < 0 && d < 0 && dayPane.folded) {
      dayPane.earlierOpen = true
      Qt.callLater(function () { dayPane.jumpQuestion(-1) })
      return
    }
    if (k < 0 || k >= q.length) {
      dayPane.askAt = -1
      if (d > 0) dayFlick.contentY = Math.max(0, dayFlick.contentHeight - dayFlick.height)
      else page.showHint("the first thing you asked here")
      return
    }
    dayPane.askAt = q[k]
    dayPane.showTurn(q[k])
    page.showHint("your questions: " + (k + 1) + " of " + q.length)
  }
  Connections {
    target: dayPane.page
    function onDayTurnsChanged() { dayPane.askAt = -1 }
    function onRoomRelChanged() { dayPane.askAt = -1; dayPane.earlierOpen = false }
  }

  // A paper's or a note's chat: its earlier sessions folded to one line
  // (2026-11-22), all but their last exchange, today's turns under it; a
  // click on the line, or Alt+↑ before the first question, unfolds them.
  property bool earlierOpen: false
  readonly property int earlier: {
    if (!(page.paper.room || page.noteRoom)) return 0
    var today = Qt.formatDate(new Date(), "yyyy-MM-dd"), n = 0
    for (var i = 0; i < page.dayTurns.length; i++) {
      if (String(page.dayTurns[i].at || "").slice(0, 10) >= today) break
      n++
    }
    // The last exchange before today stays in view, so the chat opens on
    // where it was left.
    for (var j = n - 1; j >= 0; j--) if (page.dayTurns[j].role !== "agent") return j
    return 0
  }
  readonly property bool folded: !dayPane.earlierOpen && dayPane.earlier >= 2
  Connections {
    target: dayPane.page
    function onDayTurnsChanged() { if (dayPane.pinTurn >= 0 && dayPane.page.dayTurns.length !== dayPane.pinCount) dayPane.pinTurn = -1 }
    function onNoteRoomChanged() { dayPane.pinTurn = -1 }
  }
  // A paper's room (plan.md item 15, step 2): its marks as a list, or its
  // chat; the pane turns between them.
  readonly property bool listing: page.paper.room && page.paper.listing

  readonly property bool besideDash: page.dayBesideDash
  // The flip, named under the box (2026-11-22): where Alt+Z goes from here.
  readonly property string flipHint: !page.paneSizable || besideDash ? ""
    : page.keyName("paneFlip") + " " + (page.paneAlone ? (page.paneKind === "paper" ? "the paper" : "the note")
      : page.paneSplit === "reading" ? "discussing" : "reading") + " · "
  // The rail of quoted words, beside a paper's answers when the pane is wide
  // enough for the measure (at least about 53 characters) and a rail of
  // 180 px; the measure gives way to it down to 440 px.
  readonly property int railFor: page.paper.room && dayFlick.width >= page.sp(440) + page.railGap + page.sp(180)
    ? Math.max(page.sp(180), Math.min(page.railWidth, dayFlick.width - page.railGap - page.chatMeasure)) : 0
  readonly property int columnWidth: dayPane.railFor > 0 ? Math.min(page.chatMeasure, dayFlick.width - page.railGap - dayPane.railFor)
    : Math.min(dayFlick.width, page.chatMeasure)
  visible: page.dayShown && (besideDash || (page.marginWidth > 0 && page.problem === ""))
  // Against the window's right edge, beside the note or the dashboard;
  // past it while one at a time the middle is shown (Page.paneTucked).
  x: page.paneAlone && page.paneTucked && !besideDash ? page.contentItem.width + page.sp(40) : page.contentItem.width - page.edge - width
  y: besideDash ? (page.alongside ? 0 : page.sheetMargin) : sheet.y
  height: besideDash ? (page.alongside ? page.contentItem.height : page.contentItem.height - page.sheetMargin * 2) : sheet.height
  width: besideDash ? page.talkWidth : page.marginWidth
  radius: page.alongside ? 0 : page.overlayRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sp(22)

  MouseArea { anchors.fill: parent; onClicked: page.dayKeysItem().forceActiveFocus() }

  // Its edge, dragged (PaneEdge.qml).
  PaneEdge { page: dayPane.page }

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

  // The header's line: the title, and the split's word (PaneSplit) at its
  // right, so the line is there for the word even over today's chat.
  Item {
    id: titleRow
    anchors.top: parent.top
    anchors.topMargin: dayPane.contentTopInset
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(dayTitle.text === "" ? 0 : dayTitle.implicitHeight, paneSplit.visible ? paneSplit.implicitHeight : 0)
  }
  Text {
    id: dayTitle
    anchors.verticalCenter: titleRow.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    anchors.right: paneSplit.left
    anchors.rightMargin: page.sp(10)
    elide: Text.ElideRight
    textFormat: Text.PlainText
    // Today's whole chat has no header (2026-11-21): its first line is
    // today's rule, which says where and when. A past day, a note's and a
    // paper's chat still say whose they are.
    visible: text !== ""
    text: page.paper.room ? (dayPane.listing ? "MARKS · " : "CHAT · ") + (page.roomLabel || "").toUpperCase()
      : page.noteRoom ? "ABOUT " + (page.roomLabel || "").toUpperCase()
      : page.noteService.isToday ? "" : (page.dateLabel || "").toUpperCase()
    color: page.dim
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }

  // Which split the pane is in, and the way to flip it (PaneSplit.qml).
  PaneSplit {
    id: paneSplit
    page: dayPane.page
    visible: shown && !dayPane.besideDash
    anchors.verticalCenter: titleRow.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: dayPane.contentRightInset
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
    anchors.top: titleRow.bottom
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
          radius: Style.cornerRadius
          // Under the hand, the hover's fill, as other chips (2026-11-25, the
          // mouse pass).
          color: on ? Style.selectedFill : chipArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
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
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
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
      color: hot ? Style.selectedFill : wholeArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
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
        id: wholeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.paper.pick(-1); page.paper.marks = []; page.paper.showChat() }
      }
    }

    ListView {
      id: paperListView
      acceptedButtons: Qt.NoButton
      QC.ScrollBar.vertical: ScrollMark { page: dayPane.page }
      TouchScroll { flickable: paperListView }
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
        // Its "chat": on the lit row, and on the one under the hand.
        readonly property bool offersChat: hot || shown || (markHover.hovered && page.handOn)
        width: paperListView.width
        height: markColumn.implicitHeight + page.sp(8)
        radius: Style.cornerRadius
        color: hot || shown ? Style.selectedFill : markHover.hovered && page.handOn ? Style.hoverFill : "transparent"
        border.width: shown && !hot ? 1 : 0
        border.color: page.accent
        onHotChanged: page.selected(markRow, "right", hot)
        HoverHandler { id: markHover }
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
              // Room kept for "chat" at the right whether it shows or not,
              // so nothing moves when it does.
              width: Math.min(implicitWidth, markColumn.width - page.sp(13) - markChat.width - page.sp(8))
              elide: Text.ElideRight
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
          // remove it there. A double click asked about it until
          // 2026-11-25 (the mouse pass), but its first click had already
          // jumped: "chat" on the row asks instead.
          onClicked: page.paper.edit(markRow.index)
        }
        Text {
          id: markChat
          anchors.top: parent.top
          anchors.topMargin: page.sp(4)
          anchors.right: parent.right
          anchors.rightMargin: page.sp(8)
          opacity: markRow.offersChat ? 1 : 0
          textFormat: Text.PlainText
          text: "chat"
          color: markChatArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
          font.underline: markChatArea.containsMouse && page.handOn
          MouseArea {
            id: markChatArea
            anchors.fill: parent
            anchors.margins: -page.sp(4)
            enabled: markRow.offersChat
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.paper.attach(markRow.modelData.id); page.paper.showChat() }
            Tip { host: dayPane.page; act: "paperOpen"; shown: parent.containsMouse; text: page.tip("Ask about this mark in the paper's chat", "paperOpen") }
          }
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
    acceptedButtons: Qt.NoButton
    QC.ScrollBar.vertical: ScrollMark { page: dayPane.page }
    visible: !dayPane.listing
    anchors.top: titleRow.bottom
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
      // Earlier days brought in at the top: what was in view stays put.
      if (dayFlick.keepFromBottom >= 0) {
        contentY = Math.max(0, contentHeight - dayFlick.keepFromBottom)
        dayFlick.keepFromBottom = -1
        return
      }
      if (dayPane.pinTurn >= 0) dayPane.toPin()
      else if (contentHeight > height) contentY = contentHeight - height
      // Too little to scroll: the days before fill the pane first.
      else if (page.historyMore && page.historyRows.length > 0) Qt.callLater(page.moreHistory)
    }
    // At the top, the days before come in, a few at a time (2026-11-21).
    property real keepFromBottom: -1
    onContentYChanged: {
      if (!dayFlick.resizing) dayFlick.atFoot = contentY >= contentHeight - height - page.sp(4)
      if (keepFromBottom < 0 && contentHeight > height && contentY < page.sp(40)
          && contentHeight - contentY - height > page.sp(40) && page.historyMore) {
        keepFromBottom = contentHeight - contentY
        if (!page.moreHistory()) keepFromBottom = -1
      }
    }

    TouchScroll { flickable: dayFlick }

    // Kept at its foot when the box grows or shrinks under it (2026-11-22):
    // the last answer's rating stayed half under a box of three lines.
    property bool atFoot: true
    property bool resizing: false
    onHeightChanged: if (dayFlick.atFoot && contentHeight > height) {
      dayFlick.resizing = true
      contentY = contentHeight - height
      dayFlick.resizing = false
    }

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
      // At the chat's measure, against the left (2026-11-22): a wide pane
      // keeps its lines readable, and beside a paper the room past them
      // holds the rail of the words an answer quotes (ChatTurn).
      width: dayPane.columnWidth
      spacing: page.sp(12)

      // The days before, one chat with today's (2026-11-21): each day's
      // rule, then what was said in its own chat, whole, and its other
      // places a line each, in the order said. An answer there can be
      // replied to (Ctrl+R), which brings it into today's message. Cards
      // and ratings stay with their own day.
      Column {
        id: historyColumn
        width: dayColumn.width
        spacing: 0
        visible: page.historyRows.length > 0
        Repeater {
          model: page.historyRows
          Loader {
            id: hrow
            required property var modelData
            width: historyColumn.width
            sourceComponent: modelData.kind === "day" ? dayRuleRow : modelData.kind === "fold" ? foldRow : turnRow
          }
        }
        DayRule {
          id: todayRule
          page: dayPane.page
          width: historyColumn.width
          label: page.todayLabel
          today: true
        }
      }
      Component {
        id: dayRuleRow
        DayRule {
          page: dayPane.page
          label: parent ? parent.modelData.label : ""
        }
      }
      Component {
        id: foldRow
        Item {
          readonly property var row: parent ? parent.modelData : ({})
          implicitHeight: hfold.height + page.sp(8)
          FoldLine {
            id: hfold
            page: dayPane.page
            width: parent.width
            rowKey: parent.row.key || ""
            head: parent.row.g ? page.sayFold(parent.row.g) : ""
            tail: parent.row.g ? page.sayFoldLast(parent.row.g) : ""
            onAct: page.convoAct(rowKey)
          }
        }
      }
      Component {
        id: turnRow
        Column {
          readonly property var t: parent ? parent.modelData.t : ({})
          spacing: page.sp(2)
          bottomPadding: t.role === "agent" ? page.chatTurnGap : Math.round(page.chatTurnGap * 0.55)
          Text {
            visible: parent.t.where === "open"
            textFormat: Text.PlainText
            text: "when you opened the page" + (parent.t.at ? " · " + String(parent.t.at).slice(11, 16) : "")
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          Turn {
            page: dayPane.page
            width: parent.width
            t: parent.t
            pane: "day"
            flick: dayFlick
            onLinkActivated: function (link) { page.openCitation(link) }
          }
        }
      }

      FoldLine {
        visible: dayPane.folded
        page: dayPane.page
        width: dayColumn.width
        head: dayPane.earlier + " earlier turns about this " + (page.paper.room ? "paper" : "note")
        tail: page.keyName("chatPrevQuestion") + " or a click unfolds them"
        onAct: dayPane.earlierOpen = true
      }
      Repeater {
        id: turnsRep
        model: page.dayTurns
        Column {
          id: turn
          required property var modelData
          visible: !(dayPane.folded && index < dayPane.earlier)
          required property int index
          width: dayColumn.width
          spacing: page.sp(2)
          // Room between turns, so each exchange reads as one (2026-11-19):
          // at 2 px apart the answer, its rating, the next quote and the
          // next bubble ran together.
          // A question sits closer to its answer than to the turn before,
          // so each exchange reads as a pair.
          bottomPadding: modelData.role === "agent" ? page.chatTurnGap : Math.round(page.chatTurnGap * 0.55)
          HoverHandler { id: turnHover }
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
          // The marks a message about a paper pointed at, over its bubble — clickable to jump to the mark.
          TurnRef {
            page: dayPane.page
            alignTo: dayTurn.bubbleWidth
            clickable: modelData.role === "student" && !!modelData.marks && modelData.marks.length > 0
            onClicked: if (modelData.marks && modelData.marks.length > 0) page.jumpToMark(modelData.marks[0])
            text: modelData.role === "student" && !!modelData.marks ? modelData.marks.map(function (id) { return page.paper.head(id) }).join("  ·  ") : ""
          }
          // The turn, drawn as every pane draws one (Turn.qml).
          Turn {
            id: dayTurn
            page: dayPane.page
            width: turn.width
            t: modelData
            pane: "day"
            railRoom: dayPane.railFor
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
              readonly property bool told: state_ === "done by itself"
              readonly property bool canUndo: !live && page.cardCanUndo(modelData.id)
              readonly property bool undoLast: canUndo && page.cardUndoIsLast(modelData.id)
              readonly property bool focused: live && page.dayCardFocus >= 0 && !!page.dayOpenCards[page.dayCardFocus]
                && page.dayOpenCards[page.dayCardFocus].id === modelData.id
              readonly property color ruleColor: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.09)
              onFocusedChanged: page.selected(card, "right", focused)
              width: parent.width
              height: cardColumn.implicitHeight + page.sp(14)
              radius: Style.cornerRadius
              color: focused ? Style.selectedFill : dayCardHover.hovered && page.handOn && live ? Style.hoverFill : "transparent"
              border.width: 1
              border.color: focused ? page.accent : page.faint
              opacity: live || state_ === "arriving" ? 1 : canUndo ? 0.78 : 0.55
              HoverHandler { id: dayCardHover }

              // Clicking the card body focuses it — never auto-accepts.
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
                spacing: page.sp(4)
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

                // Option A: Quiet footer links matching MarginCard.
                Item {
                  visible: card.live || card.canUndo
                  width: parent.width
                  height: visible ? dayActRow.implicitHeight + page.sp(7) : 0
                  Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: page.sp(2)
                    width: parent.width
                    height: 1
                    color: card.ruleColor
                  }
                  Row {
                    id: dayActRow
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: page.sp(14)

                    Row {
                      visible: card.live
                      spacing: page.sp(5)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: card.told ? "keep" : "accept"
                        color: dayAccArea.containsMouse && page.handOn ? page.accent : page.foreground
                        font.family: page.fontFamily
                        font.styleName: page.fontStyle
                        font.weight: Font.Medium
                        font.pixelSize: page.fs(Style.font.caption)
                        font.underline: dayAccArea.containsMouse && page.handOn
                        // Wider than its word, the links a gap apart; a
                        // click puts the keys in the pane, as one on the
                        // card does (2026-11-25, the mouse pass).
                        MouseArea {
                          id: dayAccArea
                          anchors.fill: parent
                          anchors.margins: -page.sp(4)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: { page.focusPane("right"); page.settleDayCardById(card.modelData.id, "accept") }
                          Tip { host: dayPane.page; act: "marginAccept"; shown: parent.containsMouse; text: page.tip(card.told ? "Let it stand" : "Accept this proposal", "marginAccept") }
                        }
                      }
                      KeyCaps {
                        visible: card.focused
                        anchors.verticalCenter: parent.verticalCenter
                        page: dayPane.page
                        key: page.keyName("marginAccept")
                        size: page.fs(Style.font.caption)
                      }
                    }

                    Row {
                      visible: card.live
                      spacing: page.sp(5)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: card.told ? "undo" : "decline"
                        color: dayDecArea.containsMouse && page.handOn ? (card.told ? page.accent : page.urgent) : (card.told ? page.accent : page.dim)
                        font.family: page.fontFamily
                        font.styleName: page.fontStyle
                        font.pixelSize: page.fs(Style.font.caption)
                        font.underline: dayDecArea.containsMouse && page.handOn
                        MouseArea {
                          id: dayDecArea
                          anchors.fill: parent
                          anchors.margins: -page.sp(4)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: { page.focusPane("right"); page.settleDayCardById(card.modelData.id, "decline") }
                          Tip { host: dayPane.page; act: "marginDecline"; shown: parent.containsMouse; text: page.tip(card.told ? "Undo what it did" : "Decline this proposal", "marginDecline") }
                        }
                      }
                      KeyCaps {
                        visible: card.focused
                        anchors.verticalCenter: parent.verticalCenter
                        page: dayPane.page
                        key: page.keyName("marginDecline")
                        size: page.fs(Style.font.caption)
                      }
                    }

                    Row {
                      visible: card.canUndo
                      spacing: page.sp(5)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "undo"
                        color: dayUndoArea.containsMouse && page.handOn ? page.foreground : page.accent
                        font.family: page.fontFamily
                        font.styleName: page.fontStyle
                        font.pixelSize: page.fs(Style.font.caption)
                        font.underline: dayUndoArea.containsMouse && page.handOn
                        MouseArea {
                          id: dayUndoArea
                          anchors.fill: parent
                          anchors.margins: -page.sp(4)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: { page.focusPane("right"); page.undoSettledCard(card.modelData.id) }
                          Tip { host: dayPane.page; act: "undo"; shown: parent.containsMouse; text: page.tip("Undo this change", "undo") }
                        }
                      }
                      KeyCaps {
                        visible: card.undoLast
                        anchors.verticalCenter: parent.verticalCenter
                        page: dayPane.page
                        key: page.keyName("undo")
                        size: page.fs(Style.font.caption)
                      }
                    }
                  }

                  Text {
                    visible: card.told || card.canUndo
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    textFormat: Text.PlainText
                    text: card.told ? "auto-applied" : "written to note"
                    color: page.faint
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.caption)
                  }
                }
              }
            }
          }
          // Helpful or not: the student's word on the answer, for the
          // weekly review and the eval cases. A word again takes it back.
          // Under the last answer, with its keys; under an earlier one only
          // while the pointer is on it, or once chosen (2026-11-19): "helpful
          // not helpful" under every answer was noise between the turns. Its
          // room is kept, so nothing moves when it shows.
          Row {
            id: rateRow
            readonly property bool last: turn.index === dayPane.lastAnswer
            readonly property bool rated: page.dayRatingOf(turn.index) !== ""
            visible: modelData.role === "agent" && !modelData.error && !!modelData.text
            opacity: last || rated || turnHover.hovered && page.handOn ? 1 : 0
            topPadding: page.sp(4)
            spacing: page.sp(12)
            Repeater {
              model: [{ value: "up", text: "helpful", act: "dayHelpful" }, { value: "down", text: "not helpful", act: "dayNotHelpful" }]
              Row {
                required property var modelData
                readonly property bool chosen: page.dayRatingOf(turn.index) === modelData.value
                spacing: page.sp(5)
                KeyCaps {
                  visible: rateRow.last
                  anchors.verticalCenter: parent.verticalCenter
                  page: dayPane.page
                  size: page.fs(Style.font.caption)
                  key: page.keyName(parent.modelData.act)
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: (parent.chosen ? "✓ " : "") + parent.modelData.text
                  color: parent.chosen ? page.accent : rateArea.containsMouse && page.handOn ? page.foreground : page.faint
                  font.family: page.fontFamily
                  font.pixelSize: page.fs(Style.font.caption)
                  MouseArea {
                    id: rateArea
                    anchors.fill: parent
                    anchors.margins: -page.sp(4)
                    enabled: rateRow.opacity > 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.focusPane("right"); page.rateDay(turn.index, parent.parent.modelData.value) }
                  }
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
          id: dayStopArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.stopAgent("day")
          // What a click does, and its key (the second pass: it said nothing).
          Tip { host: dayPane.page; shown: parent.containsMouse; act: "marginBack"; text: page.tip("Stop it: your words back in the box", "marginBack") }
        }
        text: (page.runnerPhase !== "" ? page.runnerPhase : "thinking") + (elapsed >= 2 ? " · " + elapsed + "s" : "")
        color: dayStopArea.containsMouse && page.handOn ? page.accent : page.faint
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
      // A new day starts blank (2026-11-21, design A of
      // docs/explorations/chat-history/compare-blank.png): room under
      // today's turns so that, kept to its foot, the pane opens at today's
      // rule, the days before above it, out of sight until scrolled to.
      // Once today fills the pane it is no room at all.
      Item {
        id: todayRoom
        width: 1
        readonly property real below: historyColumn.visible ? todayRoom.y - (historyColumn.y + todayRule.y) : 0
        height: historyColumn.visible ? Math.max(0, dayFlick.height - below) : 0
      }
    }
  }

  Column {
    id: dayBox
    visible: !dayPane.listing
    anchors.left: parent.left
    anchors.leftMargin: dayPane.contentLeftInset
    // As wide as the answers above it (2026-11-22): what you write lines up
    // with what you read, at the chat's measure.
    width: dayPane.columnWidth
    anchors.bottom: parent.bottom
    anchors.bottomMargin: dayPane.contentBottomInset
    spacing: page.sp(6)

    // `@`: what to point at (MentionList.qml, the same in every box).
    MentionList {
      id: dayMentionList
      page: dayPane.page
      width: dayBox.width
      shown: !!page.dayMention && !page.dayMention.margin
      onPicked: dayField.forceActiveFocus()
    }

    // The marks the next message points at: removable Chips matching dayChips.
    Chips {
      page: dayPane.page
      width: dayBox.width
      refs: page.paper.room ? page.paper.marks.map(function (id) { return { kind: "mark", head: page.paper.head(id) } }) : []
      onDrop: function (i) {
        page.paper.marks = page.paper.marks.filter(function (_, k) { return k !== i })
        dayField.forceActiveFocus()
      }
    }
    // Replies attached to this message, a pill each (design A).
    ReplyPills {
      page: dayPane.page
      width: parent.width
      pane: "day"
    }

    // What the next message is about: its chips. Backspace in the empty
    // box lets go of the last; a click on one lets it go.
    Chips {
      page: dayPane.page
      width: parent.width
      refs: page.noteRoom ? page.dayRefs : page.dayChips
      onDrop: function (i) { page.dropDayChipAt(i); dayField.forceActiveFocus() }
    }

    // While the box is a reply: which one it is.
    Text {
      visible: !!page.dayReplying
      textFormat: Text.PlainText
      text: "REPLY " + page.replyNumber("day") + " OF " + page.replyNumber("day")
      color: page.accent
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
      busy: page.dayThinking || page.thinkHeld === "day"
      onStop: page.stopAgent("day")
      placeholderText: busy ? page.keyName("marginBack") + " stops"
        : page.dayReplying ? "your reply…"
        : page.dayReplies.length > 0 ? "write, or reply to another passage…"
        : page.paper.room ? (page.paper.marks.length > 0 ? "ask about it…" : "ask about this paper…")
        : page.noteRoom ? "chat about this note…"
        : page.dayCanSend ? "chat with the day…" : "a past day: today's is where you chat (" + page.keyName("today") + ")"
      replyQuote: page.dayReplying ? page.dayReplying.quote : ""
      replyN: page.replyNumber("day")
      onCancelReply: { page.cancelReply("day"); dayField.forceActiveFocus() }
      onKeyPressed: function (event) { if (page.dayKey(event)) event.accepted = true }
      onTextChanged: { page.dayTyped(text); Qt.callLater(page.updateDayMention) }
      chipKeys: (page.noteRoom ? page.dayRefs : page.dayChips).map(page.refKey)
      onMentionGone: function (key) { page.dayRefs = page.dayRefs.filter(function (r) { return page.refKey(r) !== key }) }
      onCursorPositionChanged: Qt.callLater(page.updateDayMention)
    }

    // Calm 1-line footer matching Longhand's editorial voice (P2 #16).
    Text {
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: page.dayReplying ? page.keyName("chatSend") + " attaches reply · " + page.keyName("marginBack") + " cancels"
        : page.dayReplies.length > 0 ? page.dayReplies.length + (page.dayReplies.length === 1 ? " reply" : " replies")
          + " · " + page.keyName("chatSend") + " sends · " + page.keyName("chatAnswer") + " more"
        : page.paper.room ? page.keyName("chatSend") + " sends · ^ mark · @ paper · " + dayPane.flipHint + page.keyName("marginBack") + " marks · " + page.keyName("keys") + " keys"
        : page.keyName("chatSend") + " sends · @ attach · " + page.keyName("chatAnswer") + " reply · " + dayPane.flipHint + page.keyName("keys") + " keys"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
