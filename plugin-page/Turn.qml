import QtQuick
import qs.Commons

// One turn of the one conversation, as every pane of the agent draws it
// (docs/agent.md, "One conversation", slice 2, 2026-11-18): the day's chat,
// a note's or a paper's, a block's in the margin, a task's beside the
// dashboard. Over it, what it pointed at (its chips, as sent) and, when it
// was said somewhere else than the pane is, where and when — "about this"
// is every turn about the thing, read from the one conversation's log, not
// only this place's own. Then the words (ChatTurn), and under an answer
// what it proposed that local code did not offer, and what it looked up to
// answer. Cards and ratings stay with the pane: each acts on its own place.
Column {
  id: turn
  required property Item page
  property var t: ({})                 // { role, text, error, refs, block, who, settled, revised, unoffered, elsewhere, place, when }
  property string pane: "day"          // whose box an answer to its words goes above: "day" or "margin"
  property Flickable flick: null       // scrolled to this turn when a quote of it is followed
  signal linkActivated(string link)

  readonly property bool mine: t.role !== "agent"
  readonly property bool away: !!t.elsewhere
  // A message answering passages (2026-11-18): each answer under the
  // passage it answers, the quote dim above it; what was said under no
  // quote last. A message with no quote is one part.
  readonly property var parts: mine ? page.passageParts(t.text || "") : []
  readonly property bool answers: parts.length > 1 || (parts.length === 1 && parts[0].quote !== "")
  // An answer to several replies, in its parts (Page.answerParts).
  readonly property var split: !mine && !away && !t.error ? page.answerParts(turn.pane, t) : null
  // A quote followed back to this answer: lit a moment, and shown.
  readonly property bool lit: !mine && !!t.at && page.litPassage === t.at + "|" + turn.pane
  onLitChanged: if (lit && flick) Qt.callLater(function () {
    var y = turn.mapToItem(flick.contentItem, 0, 0).y
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - page.sp(12)))
  })
  spacing: page.sp(2)

  // Said somewhere else: where, and when.
  Text {
    visible: turn.away
    width: parent.width
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: turn.mine ? Text.AlignRight : Text.AlignLeft
    text: (turn.t.when || "") + (turn.t.place ? (turn.t.when ? ", " : "") + turn.t.place : "")
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
  // What a message pointed at, as it was sent.
  Text {
    visible: turn.mine && !turn.away && (!!turn.t.block || (!!turn.t.refs && turn.t.refs.length > 0))
    width: parent.width
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignRight
    text: turn.t.refs && turn.t.refs.length > 0
      ? turn.t.refs.map(function (r) { return "↳ " + page.sayChip(r) }).join("   ")
      : turn.t.block ? "↳ " + page.blockHead(turn.t.block) : ""
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
  ChatTurn {
    visible: !turn.answers && !turn.split
    page: turn.page
    mine: turn.mine
    answerable: !turn.mine && !turn.away && !turn.t.error && (turn.t.text || "") !== ""
    pane: turn.pane
    at: String(turn.t.at || "")
    text: turn.t.error ? "could not answer: " + page.sayPlanError(turn.t.error)
      : turn.t.role === "agent" ? page.linkCitations(turn.t.text || "") : (turn.t.text || "")
    color: turn.t.error ? page.urgent : turn.away ? page.dim : page.foreground
    onLinkActivated: function (link) { turn.linkActivated(link) }
    onAnswer: function (passage) { page.addReply(turn.pane, passage, turn.t.at) }
    marks: !turn.mine && !turn.away ? page.passageMarks(turn.pane, turn.t.at) : []
    Rectangle {
      anchors.fill: parent
      anchors.margins: -page.sp(4)
      z: -1
      radius: Style.cornerRadius
      color: Style.selectedFill
      visible: turn.lit
    }
  }
  // An answer to several replies (2026-11-18, design A2): what it says
  // first, then each part under a small bubble of the reply it answers —
  // the student's own words and the pill's number. Under the pointer, a
  // hint names the passage replied to, and the passage lights in the
  // answer it came from; nothing moves.
  ChatTurn {
    visible: !!turn.split && turn.split.intro !== ""
    page: turn.page
    answerable: true
    pane: turn.pane
    at: String(turn.t.at || "")
    text: turn.split ? page.linkCitations(turn.split.intro) : ""
    onLinkActivated: function (link) { turn.linkActivated(link) }
    onAnswer: function (passage) { page.addReply(turn.pane, passage, turn.t.at) }
    marks: turn.split ? page.passageMarks(turn.pane, turn.t.at) : []
  }
  Repeater {
    model: turn.split ? turn.split.parts : []
    Column {
      id: part
      required property var modelData
      required property int index
      width: turn.width
      spacing: page.sp(4)
      topPadding: part.index > 0 || (turn.split && turn.split.intro !== "") ? page.sp(8) : 0
      Rectangle {
        id: echo
        visible: part.modelData.reply !== ""
        readonly property bool hot: echoArea.containsMouse
        width: Math.min(part.width, echoRow.implicitWidth + page.sp(16))
        height: echoRow.implicitHeight + page.sp(8)
        radius: Style.cornerRadius
        color: Util.alpha(page.accent, 0.14)
        border.width: 1
        border.color: echo.hot ? page.accent : "transparent"
        Row {
          id: echoRow
          anchors.left: parent.left
          anchors.leftMargin: page.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: page.sp(6)
          Rectangle {
            visible: part.modelData.n > 0
            anchors.top: parent.top
            anchors.topMargin: page.sp(2)
            width: Math.max(height, echoNum.implicitWidth + page.sp(8))
            height: echoNum.implicitHeight + page.sp(2)
            radius: height / 2
            color: echo.hot ? page.accent : page.dim
            Text {
              id: echoNum
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(part.modelData.n)
              color: page.background
              font.family: page.fontFamily
              font.pixelSize: Math.round(page.textSize * 0.68)
            }
          }
          Text {
            width: Math.min(implicitWidth, part.width - page.sp(48))
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: part.modelData.reply
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: Math.round(page.textSize * 0.85)
          }
        }
        MouseArea {
          id: echoArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: {
            if (containsMouse) page.hoverQuote = { pane: turn.pane, quote: part.modelData.passage }
            else if (page.hoverQuote && page.hoverQuote.quote === part.modelData.passage) page.hoverQuote = null
          }
          onClicked: page.showPassage(turn.pane, part.modelData.passage)
        }
        Tip {
          host: turn.page
          shown: echoArea.containsMouse
          text: "you replied to: “" + part.modelData.passage + "”"
        }
      }
      ChatTurn {
        visible: part.modelData.text !== ""
        page: turn.page
        answerable: true
        pane: turn.pane
        at: String(turn.t.at || "")
        text: page.linkCitations(part.modelData.text)
        onLinkActivated: function (link) { turn.linkActivated(link) }
        onAnswer: function (passage) { page.addReply(turn.pane, passage, turn.t.at) }
        marks: page.passageMarks(turn.pane, turn.t.at)
        Rectangle {
          anchors.fill: parent
          anchors.margins: -page.sp(4)
          z: -1
          radius: Style.cornerRadius
          color: Style.selectedFill
          visible: turn.lit && part.index === 0
        }
      }
    }
  }
  // Replies to passages: attached to the message, a pill each (its
  // number, the reply's start), over the message's own words. A click goes
  // back to the passage, lit in the answer it came from.
  Flow {
    visible: turn.answers
    width: turn.width
    layoutDirection: Qt.RightToLeft
    spacing: page.sp(6)
    Repeater {
      model: turn.answers ? turn.parts.filter(function (x) { return x.quote !== "" }) : []
      Rectangle {
        id: sentPill
        required property var modelData
        required property int index
        readonly property bool hot: sentArea.containsMouse && page.handOn
        width: Math.min(turn.width * 0.8, sentRow.implicitWidth + page.sp(16))
        height: sentRow.implicitHeight + page.sp(6)
        radius: Style.cornerRadius
        color: Util.alpha(page.accent, 0.10)
        border.width: 1
        border.color: sentPill.hot ? page.accent : Util.alpha(page.accent, 0.35)
        Row {
          id: sentRow
          anchors.left: parent.left
          anchors.leftMargin: page.sp(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: page.sp(6)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, sentNum.implicitWidth + page.sp(8))
            height: sentNum.implicitHeight + page.sp(2)
            radius: height / 2
            color: page.dim
            Text {
              id: sentNum
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(sentPill.index + 1)
              color: page.background
              font.family: page.fontFamily
              font.pixelSize: Math.round(page.textSize * 0.68)
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, turn.width * 0.8 - page.sp(48))
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "↩ " + sentPill.modelData.text
            color: turn.away ? page.dim : page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: Math.round(page.textSize * 0.82)
          }
        }
        MouseArea {
          id: sentArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.showPassage(turn.pane, sentPill.modelData.quote)
        }
        Tip {
          host: turn.page
          shown: sentArea.containsMouse
          text: "“" + sentPill.modelData.quote + "” → " + sentPill.modelData.text + "  ·  click: its passage"
        }
      }
    }
  }
  // The message's own words, under its replies.
  Repeater {
    model: turn.answers ? turn.parts.filter(function (x) { return x.quote === "" && x.text !== "" }) : []
    ChatTurn {
      required property var modelData
      width: turn.width
      page: turn.page
      mine: true
      text: modelData.text
      color: turn.away ? page.dim : page.foreground
    }
  }
  // How a talk about a proposal ended, said under the answer.
  Text {
    visible: text !== ""
    textFormat: Text.PlainText
    text: turn.t.role !== "agent" ? ""
      : turn.t.settled === "accept" ? "◇ settled: accepted" : turn.t.settled === "decline" ? "◇ settled: declined"
      : turn.t.revised ? "◇ revised the proposal" : ""
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
  // What it looked up to answer (slice 5: searched, read, a course's
  // document), and what it filed: under every answer, in every pane.
  Text {
    visible: text !== ""
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: turn.t.role === "agent" && !turn.away ? page.sayFetched(turn.t) : ""
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
  // A document it filed because the student asked: one click puts it back.
  Repeater {
    model: turn.t.role === "agent" && !turn.away ? (turn.t.filed || []).filter(function (f) { return f.id !== undefined }) : []
    Text {
      required property var modelData
      readonly property bool back: !!page.unfiled[modelData.id]
      textFormat: Text.PlainText
      text: back ? "put back: “" + String(modelData.name).replace(/\.pdf$/i, "") + "”"
        : "put “" + String(modelData.name).replace(/\.pdf$/i, "") + "” back"
      color: backArea.containsMouse && page.handOn && !back ? page.accent : page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
      font.underline: backArea.containsMouse && !back
      MouseArea {
        id: backArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: !parent.back
        cursorShape: Qt.PointingHandCursor
        onClicked: page.unfile(modelData.id)
      }
    }
  }
  // What it proposed that local code did not offer: said, so a reply
  // pointing at a card that is not there is not the last word.
  Text {
    visible: turn.t.role === "agent" && (turn.t.unoffered || []).length > 0
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: "◇ left out: " + page.sayLeftOut(turn.t.unoffered)
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
}
