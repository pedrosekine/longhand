import QtQuick
import qs.Commons
import qs.Ui

// One of a block's cards, as the margin draws it under the answer that made
// it — beside the note and, since 2026-11-03, beside the dashboard, where
// the task's chat opens on the same block: ◇ and its kind, what changes,
// the day as a pill. Done only when the student says so (`activated`: the
// CLI's `accept`). Moved out of Margin.qml the same day, for the two places.
// A day for a box, or dropping one (2026-11-15), is an item of the one
// list (`ledger`, its id), as the day conversation's cards are: open while
// the list has it, settled — here, on its row, or by a plan — as the list
// says.
Rectangle {
  id: card
  required property Item page
  property var p: ({})
  property bool hot: false
  property bool declined: false
  property Flickable flick: null       // the pane's: scrolled to show the card when the keys come to it
  signal focused()
  signal accepted()
  signal declinedClick()
  signal undone()

  readonly property bool listed: !!p.ledger
  readonly property var item: listed ? page.dayCardLive({ id: p.ledger }) : null
  readonly property string listedState: !listed ? "" : item ? (item.told ? "done by itself" : "")
    : page.dayCardState({ id: p.ledger }, p.at || "")
  readonly property bool told: !!(item && item.told)
  readonly property bool done: listed ? !item && listedState !== "arriving" : !!p.accepted
  readonly property bool replaced: !listed && !done && !!p.superseded
  readonly property bool isDeclined: !listed && !done && !replaced && (card.declined || !!p.declined)
  readonly property bool live: listed ? !!item : !done && !replaced && !isDeclined
  readonly property bool canUndo: listed && !live && page.cardCanUndo(p.ledger)
  readonly property bool undoLast: canUndo && page.cardUndoIsLast(p.ledger)
  readonly property color ruleColor: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.09)
  onHotChanged: { page.selected(card, "right", hot); if (hot) Qt.callLater(function () { page.revealIn(card.flick, card) }) }
  Component.onCompleted: if (hot) page.selected(card, "right", true)
  height: cardColumn.implicitHeight + page.sp(14)
  radius: Style.cornerRadius
  color: hot ? Style.selectedFill : cardHover.hovered && page.handOn && live ? Style.hoverFill : "transparent"
  border.width: 1
  border.color: hot ? page.accent : page.faint
  // Not on the list read yet, so not settled: drawn as an open one.
  opacity: live || listedState === "arriving" ? 1 : canUndo ? 0.78 : 0.55
  HoverHandler { id: cardHover }

  // Clicking the card body focuses it — never auto-accepts.
  MouseArea {
    anchors.fill: parent
    cursorShape: card.live ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: card.focused()
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
      text: "◇ " + (card.listed ? card.page.dayCardKind(card.p)
          : card.p.moves ? "move deadline" : card.p.kind === "deadline" ? "new deadline" : (card.p.kind || ""))
        + (card.listed ? (card.listedState !== "" && card.listedState !== "arriving" ? " · " + card.listedState : "")
           : card.done ? " · " + (card.p.accepted.moved ? "moved" : "added")
           : card.isDeclined ? " · declined"
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
        text: card.listed ? page.dayCardFacts(card.p) + (card.p.deadline && !card.p.key ? " · a deadline in no note" : "")
          : card.p.kind === "deadline" ? page.marginCardFacts(card.p) : JSON.stringify(card.p)
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
        readonly property string label: card.listed ? page.dayCardPill(card.p)
          : card.p.kind === "deadline" && card.p.when ? page.marginCardPill(card.p) : ""
        readonly property bool fits: width <= parent.width * 0.5
        visible: label !== "" && fits
        anchors.right: parent.right
        width: cardPillText.implicitWidth + Math.round(page.textSize * 0.9)
        height: cardPillText.implicitHeight + Math.round(page.textSize * 0.25)
        radius: Style.cornerRadius
        color: card.p.kind === "do-date" ? Style.selectedFill : "transparent"
        border.width: card.p.kind === "do-date" ? 0 : 1
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
      visible: !!card.p.why
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: card.p.why || ""
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
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

    // Option A: Quiet footer links separated by a subtle hairline.
    Item {
      visible: card.live || card.canUndo
      width: parent.width
      height: visible ? actRow.implicitHeight + page.sp(7) : 0
      Rectangle {
        anchors.top: parent.top
        anchors.topMargin: page.sp(2)
        width: parent.width
        height: 1
        color: card.ruleColor
      }
      Row {
        id: actRow
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        spacing: page.sp(14)

        // Primary action: Accept (or Keep for auto-applied `told` cards)
        Row {
          visible: card.live
          spacing: page.sp(5)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: card.told ? "keep" : "accept"
            color: acceptArea.containsMouse && page.handOn ? page.accent : page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.weight: Font.Medium
            font.pixelSize: page.fs(Style.font.caption)
            font.underline: acceptArea.containsMouse && page.handOn
            // Wider than its word, the links a gap apart; a click first
            // does what one on the card does, so the keys come to it
            // (2026-11-25, the mouse pass).
            MouseArea {
              id: acceptArea
              anchors.fill: parent
              anchors.margins: -page.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { card.focused(); card.accepted() }
              Tip { host: card.page; act: "marginAccept"; shown: parent.containsMouse; text: card.page.tip(card.told ? "Let it stand" : "Accept this proposal", "marginAccept") }
            }
          }
          KeyCaps {
            visible: card.hot
            anchors.verticalCenter: parent.verticalCenter
            page: card.page
            key: page.keyName("marginAccept")
            size: page.fs(Style.font.caption)
          }
        }

        // Secondary action: Decline (or Undo for auto-applied `told` cards)
        Row {
          visible: card.live
          spacing: page.sp(5)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: card.told ? "undo" : "decline"
            color: declineArea.containsMouse && page.handOn ? (card.told ? page.accent : page.urgent) : (card.told ? page.accent : page.dim)
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
            font.underline: declineArea.containsMouse && page.handOn
            MouseArea {
              id: declineArea
              anchors.fill: parent
              anchors.margins: -page.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { card.focused(); card.declinedClick() }
              Tip { host: card.page; act: "marginDecline"; shown: parent.containsMouse; text: card.page.tip(card.told ? "Undo what it did" : "Decline this proposal", "marginDecline") }
            }
          }
          KeyCaps {
            visible: card.hot
            anchors.verticalCenter: parent.verticalCenter
            page: card.page
            key: page.keyName("marginDecline")
            size: page.fs(Style.font.caption)
          }
        }

        // Settled & undoable: inline Undo link (+ Ctrl+Z keycap on the latest)
        Row {
          visible: card.canUndo
          spacing: page.sp(5)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "undo"
            color: undoArea.containsMouse && page.handOn ? page.foreground : page.accent
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
            font.underline: undoArea.containsMouse && page.handOn
            MouseArea {
              id: undoArea
              anchors.fill: parent
              anchors.margins: -page.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { card.focused(); card.undone() }
              Tip { host: card.page; act: "undo"; shown: parent.containsMouse; text: card.page.tip("Undo this change", "undo") }
            }
          }
          KeyCaps {
            visible: card.undoLast
            anchors.verticalCenter: parent.verticalCenter
            page: card.page
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
