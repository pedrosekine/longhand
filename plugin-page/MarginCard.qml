import QtQuick
import qs.Commons
import qs.Ui

// One of a block's cards, as the margin draws it under the answer that made
// it — beside the note and, since 2026-11-03, beside the dashboard, where
// the task's chat opens on the same block: ◇ and its kind, what changes,
// the day as a pill. Done only when the student says so (`activated`: the
// CLI's `accept`). Moved out of Margin.qml the same day, for the two places.
Rectangle {
  id: card
  required property Item page
  property var p: ({})
  property bool hot: false
  signal activated()

  readonly property bool done: !!p.accepted
  readonly property bool replaced: !done && !!p.superseded
  readonly property bool live: !done && !replaced
  onHotChanged: page.selected(card, "right", hot)
  Component.onCompleted: if (hot) page.selected(card, "right", true)
  height: cardColumn.implicitHeight + page.sp(14)
  radius: Style.cornerRadius
  color: hot ? Style.selectedFill : cardHover.hovered && page.handOn && live ? Style.hoverFill : "transparent"
  border.width: 1
  border.color: hot ? page.accent : page.faint
  opacity: live ? 1 : 0.55
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
      text: "◇ " + (card.p.moves ? "move deadline #" + card.p.moves.id : card.p.kind === "deadline" ? "new deadline" : (card.p.kind || ""))
        + (card.done ? " · " + (card.p.accepted.moved ? "moved" : "added" + (card.p.accepted.id ? " #" + card.p.accepted.id : ""))
           : card.replaced ? " · replaced by a later one" : card.p.error ? " · failed" : "")
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
        text: card.p.kind === "deadline" ? page.marginCardFacts(card.p) : JSON.stringify(card.p)
        color: page.foreground
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.body)
      }
      // The day as a pill while it is short enough to be one; words the
      // agent wrote about when ("Mondays from 2 November, aside from …")
      // are a line under them instead, or the pill outgrew the card and
      // drew over its words (2026-11-03).
      Rectangle {
        id: cardPill
        readonly property string label: card.p.kind === "deadline" && card.p.when ? page.marginCardPill(card.p) : ""
        readonly property bool fits: width <= parent.width * 0.5
        visible: label !== "" && fits
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
      visible: cardPill.label !== "" && !cardPill.fits
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: cardPill.label
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: Math.round(page.textSize * 0.78)
    }
    Text {
      visible: !!card.p.error && card.live
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: card.p.error || ""
      color: page.urgent
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
    }
    Text {
      visible: card.hot && card.live
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
    cursorShape: card.live ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: card.activated()
    Tip { host: card.page; shown: parent.containsMouse && card.live; text: card.page.tip("Do what it says", "marginAccept") }
  }
}
