import QtQuick
import qs.Commons

// The rule between two days of the one conversation (2026-11-21): the
// day's chat scrolls up into the days before it, and a faint line with the
// day's name says where one day ends and the next begins. Today's is a
// shade stronger: it is where the conversation stands.
Item {
  id: rule
  required property Item page
  property string label: ""
  property bool today: false

  implicitHeight: name.implicitHeight + page.sp(14)
  Rectangle {
    anchors.left: parent.left
    anchors.right: name.left
    anchors.rightMargin: page.sp(10)
    anchors.verticalCenter: name.verticalCenter
    height: 1
    color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.1)
  }
  Text {
    id: name
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: rule.label
    color: rule.today ? page.dim : page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    font.pixelSize: page.fs(Style.font.caption)
  }
  Rectangle {
    anchors.left: name.right
    anchors.leftMargin: page.sp(10)
    anchors.right: parent.right
    anchors.verticalCenter: name.verticalCenter
    height: 1
    color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.1)
  }
}
