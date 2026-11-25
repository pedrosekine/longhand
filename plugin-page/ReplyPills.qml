import QtQuick
import qs.Commons

// Replies attached to the message being written (2026-11-18, design A):
// a pill each over the box, like an attached file — its number, the
// passage, and the start of the reply. A click puts it back in the box to
// change; × lets it go. Sent with the box's words on the next Enter.
Flow {
  id: pills
  required property Item page
  property string pane: "day"
  readonly property var list: pane === "margin" ? page.marginReplies : page.dayReplies
  visible: list.length > 0
  spacing: page.sp(6)

  Repeater {
    model: pills.list
    Rectangle {
      id: pill
      required property var modelData
      required property int index
      readonly property bool hot: pillArea.containsMouse && page.handOn
      width: Math.min(pills.width, row.implicitWidth + page.sp(16))
      height: row.implicitHeight + page.sp(6)
      radius: Style.cornerRadius
      color: Util.alpha(page.foreground, 0.05)
      border.width: 1
      border.color: pill.hot ? page.accent : page.faint
      MouseArea {
        id: pillArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: page.editReply(pills.pane, pill.index)
      }
      Row {
        id: row
        anchors.left: parent.left
        anchors.leftMargin: page.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: page.sp(6)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(height, num.implicitWidth + page.sp(8))
          height: num.implicitHeight + page.sp(2)
          radius: height / 2
          color: page.dim
          Text {
            id: num
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(pill.index + 1)
            color: page.background
            font.family: page.fontFamily
            font.pixelSize: Math.round(page.textSize * 0.68)
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, pills.width - page.sp(80))
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: "↩ " + pill.modelData.quote + " · " + pill.modelData.text
          color: pill.hot ? page.foreground : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: Math.round(page.textSize * 0.78)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "×"
          color: dropArea.containsMouse && page.handOn ? page.accent : page.faint
          font.family: page.fontFamily
          font.pixelSize: Math.round(page.textSize * 0.78)
          MouseArea {
            id: dropArea
            anchors.fill: parent
            anchors.margins: -page.sp(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.dropReply(pills.pane, pill.index)
          }
        }
      }
      Tip {
        host: pills.page
        shown: pillArea.containsMouse
        text: "“" + pill.modelData.quote + "” → " + pill.modelData.text + "  ·  click to change it"
      }
    }
  }
}
