import QtQuick
import qs.Commons

// What `@` offers to point at, under the words typed after it: blocks of the
// open note, open tasks of other days, notes and papers the agent may see
// (Page.updateDayMention). The same list in every box of the agent's panes
// (slice 2 of "One conversation"): ↑↓ move, Enter or Tab picks, Esc closes,
// a click picks.
Column {
  id: list
  required property Item page
  property bool shown: false
  signal picked()
  visible: shown
  spacing: 0

  Repeater {
    model: list.shown && page.dayMention ? page.dayMention.items : []
    Rectangle {
      required property var modelData
      required property int index
      width: list.width
      height: mentionText.implicitHeight + page.sp(4)
      radius: Style.cornerRadius
      color: page.dayMentionFocus === index ? Style.selectedFill : "transparent"
      Text {
        id: mentionText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: page.sp(4)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: "↳ " + modelData.head
        color: page.foreground
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.dayMentionFocus = index; page.pickDayMention(index); list.picked() }
      }
    }
  }
}
