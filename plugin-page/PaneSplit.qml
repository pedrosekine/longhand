import QtQuick
import qs.Commons

// Which split the agent's pane is in, at its header's right (2026-11-22,
// docs/explorations/chat-width, look b): a small glyph of the split, whose
// filled part is the chat's share of the window, so it moves while the
// edge is dragged or nudged, and the word. A click flips (Alt+Z); under the
// mouse it names the three ways to size the pane.
Item {
  id: split
  required property Item page
  readonly property bool shown: page.paneSizable
  readonly property string word: page.paneAlone ? "the chat" : page.paneSplit
  visible: shown
  implicitWidth: shown ? row.implicitWidth + page.sp(12) : 0
  implicitHeight: shown ? row.implicitHeight + page.sp(4) : 0

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, area.containsMouse && page.handOn ? 0.07 : 0)
  }
  Row {
    id: row
    anchors.centerIn: parent
    spacing: page.sp(7)
    // The split: the window as a box, the chat's share of it filled.
    Rectangle {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      width: page.sp(18)
      height: page.sp(11)
      radius: page.sp(2)
      color: "transparent"
      border.width: 1
      border.color: label.color
      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        readonly property real share: page.contentItem.width > 0 ? page.marginWidth / page.contentItem.width : 0.3
        width: Math.max(page.sp(2), Math.round((glyph.width - 2) * Math.min(1, share)))
        color: label.color
        opacity: 0.75
      }
    }
    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: split.word
      color: area.containsMouse && page.handOn ? page.dim : page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: page.flipPane()
  }
  Tip { host: split.page; act: "paneFlip"; shown: area.containsMouse; text: split.page.paneTip }
}
