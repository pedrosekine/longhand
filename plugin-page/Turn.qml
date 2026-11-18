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
  signal linkActivated(string link)

  readonly property bool mine: t.role !== "agent"
  readonly property bool away: !!t.elsewhere
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
    page: turn.page
    mine: turn.mine
    text: turn.t.error ? "could not answer: " + page.sayPlanError(turn.t.error)
      : turn.t.role === "agent" ? page.linkCitations(turn.t.text || "") : (turn.t.text || "")
    color: turn.t.error ? page.urgent : turn.away ? page.dim : page.foreground
    onLinkActivated: function (link) { turn.linkActivated(link) }
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
  // What it proposed that local code did not offer: said, so a reply
  // pointing at a card that is not there is not the last word.
  Text {
    visible: turn.t.role === "agent" && (turn.t.unoffered || []).length > 0
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: "◇ not offered as a card: " + (turn.t.unoffered || []).join("; ")
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
}
