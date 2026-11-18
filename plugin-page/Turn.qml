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
    visible: !turn.answers
    page: turn.page
    mine: turn.mine
    answerable: !turn.mine && !turn.away && !turn.t.error && (turn.t.text || "") !== ""
    text: turn.t.error ? "could not answer: " + page.sayPlanError(turn.t.error)
      : turn.t.role === "agent" ? page.linkCitations(turn.t.text || "") : (turn.t.text || "")
    color: turn.t.error ? page.urgent : turn.away ? page.dim : page.foreground
    onLinkActivated: function (link) { turn.linkActivated(link) }
    onAnswer: function (passage) { page.addReply(turn.pane, passage) }
    Rectangle {
      anchors.fill: parent
      anchors.margins: -page.sp(4)
      z: -1
      radius: Style.cornerRadius
      color: Style.selectedFill
      visible: turn.lit
    }
  }
  // Answers to passages: each under its own, the quote a way back to it.
  Repeater {
    model: turn.answers ? turn.parts : []
    Column {
      required property var modelData
      width: turn.width
      spacing: page.sp(2)
      Text {
        visible: modelData.quote !== ""
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        text: "“" + modelData.quote + "”"
        color: quoteArea.containsMouse && page.handOn ? page.accent : page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.italic: true
        font.pixelSize: page.fs(Style.font.caption)
        MouseArea {
          id: quoteArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.showPassage(turn.pane, modelData.quote)
        }
      }
      ChatTurn {
        visible: modelData.text !== ""
        page: turn.page
        mine: true
        text: modelData.text
        color: turn.away ? page.dim : page.foreground
      }
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
