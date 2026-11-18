import QtQuick
import qs.Commons

// A key drawn as the hover hints draw it (Tip.qml, 2026-10-30): each part a
// cap on the sheet's paper, a faint edge and a lip along its foot. `key` is
// as Shortcuts.js names it ("Ctrl+R"), read live by the caller
// (page.keyName), so a moved key is the one shown.
Row {
  id: caps
  required property Item page
  property string key: ""
  property int size: page.fs(Style.font.bodySmall)
  readonly property color edge: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
  spacing: page.sp(3)
  Repeater {
    model: caps.key === "" ? [] : caps.key.split(/\+(?=.)/)
    Rectangle {
      required property string modelData
      width: Math.max(capText.implicitWidth + caps.page.sp(10), height)
      height: capText.implicitHeight + caps.page.sp(3)
      radius: Style.cornerRadius
      color: caps.page.sheetColor
      border.width: 1
      border.color: caps.edge
      Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 1; height: 1; color: caps.edge }
      Text {
        id: capText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: parent.modelData
        color: caps.page.dim
        font.family: caps.page.fontFamily
        font.styleName: caps.page.fontStyle
        font.pixelSize: Math.round(caps.size * 0.9)
      }
    }
  }
}
