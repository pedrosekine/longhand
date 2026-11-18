import QtQuick
import qs.Commons
import qs.Ui

// What the next message is about (docs/agent.md, "One conversation",
// slice 2, 2026-11-18): a chip each, saying its kind and its name, seen
// before the message is sent. The automatic one — what the student is
// looking at — is drawn dimmer. A click on a chip's × lets it go (Backspace
// in the empty box lets go of the last).
Flow {
  id: chips
  required property Item page
  property var refs: []           // [{ kind, head, auto }]
  property bool fixed: false      // a chat about one thing: its chip is what the chat is, × leaves for the day's
  signal drop(int index)

  spacing: page.sp(6)
  visible: refs.length > 0

  Repeater {
    model: chips.refs
    Rectangle {
      id: chip
      required property var modelData
      required property int index
      readonly property bool hot: dropArea.containsMouse && page.handOn
      width: Math.min(chips.width, label.implicitWidth + cross.implicitWidth + Math.round(page.textSize * 1.5))
      height: label.implicitHeight + Math.round(page.textSize * 0.3)
      radius: Style.cornerRadius
      color: "transparent"
      border.width: 1
      border.color: chip.hot ? page.accent : page.faint
      Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: Math.round(page.textSize * 0.45)
        anchors.right: cross.left
        anchors.rightMargin: Math.round(page.textSize * 0.3)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: page.sayChip(chip.modelData)
        color: chip.modelData.auto ? page.faint : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: Math.round(page.textSize * 0.78)
      }
      Text {
        id: cross
        anchors.right: parent.right
        anchors.rightMargin: Math.round(page.textSize * 0.45)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "×"
        color: chip.hot ? page.accent : page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: Math.round(page.textSize * 0.78)
      }
      MouseArea {
        id: dropArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chips.drop(chip.index)
      }
      Tip {
        host: chips.page
        shown: dropArea.containsMouse
        text: chips.fixed ? "Talk about nothing in particular: the day's chat"
          : chip.modelData.auto ? "What you are looking at goes with the message · click to let it go"
          : "Goes with the message · click to let it go"
      }
    }
  }
}
