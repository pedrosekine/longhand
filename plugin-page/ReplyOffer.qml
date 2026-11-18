import QtQuick
import qs.Commons

// Words selected in one of the agent's answers, offered over the box
// (2026-11-18): "↩ reply to “…”" with its key. Faint at rest, its words in
// the accent — an offer waiting, as a new thing is said; the frame stays
// faint, the accent of a frame being the box one is typing in. A click,
// or the key, makes the box the reply.
Rectangle {
  id: offer
  required property Item page
  property string pane: "day"
  readonly property var o: page.replyOffer && page.replyOffer.pane === pane ? page.replyOffer : null
  readonly property bool hot: offerArea.containsMouse && page.handOn
  visible: !!o
  height: visible ? offerRow.implicitHeight + page.sp(10) : 0
  radius: Style.cornerRadius
  color: offer.hot ? Style.hoverFill : "transparent"
  border.width: 1
  border.color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
  Item {
    id: offerRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: page.sp(10)
    anchors.rightMargin: page.sp(8)
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Math.max(offerText.implicitHeight, offerKeys.implicitHeight)
    Text {
      id: offerText
      anchors.left: parent.left
      anchors.right: offerKeys.left
      anchors.rightMargin: page.sp(18)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      elide: Text.ElideRight
      text: "<font color=\"" + page.accent + "\">↩ reply</font> to <i><font color=\"" + page.faint + "\">“"
        + String(offer.o ? offer.o.quote : "").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "”</font></i>"
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
    KeyCaps {
      id: offerKeys
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      page: offer.page
      key: page.keyName("chatAnswer")
      size: page.fs(Style.font.caption)
    }
  }
  MouseArea {
    id: offerArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: offer.page.takeOffer()
  }
}
