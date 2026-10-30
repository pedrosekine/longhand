import QtQuick
import qs.Commons

// A key named while Ctrl is held (docs/hints.md, F; the canvas's direction
// 5): the rest of the key after Ctrl, on the thing it acts on, and in words
// what it does when the thing does not say so itself. Shown only while
// the page says Ctrl is held (`ctrlShown`), and only for an action that has
// a Ctrl key; read from Shortcuts.js, so a key moved in the sheet is the
// one named.
Rectangle {
  id: badge
  required property Item host   // the page
  property string act: ""
  property string words: ""
  property bool place: true     // the thing it names is there to name
  readonly property string key: badge.host.ctrlKey(badge.act)
  visible: host.ctrlShown && place && key !== ""
  z: 60
  width: label.implicitWidth + host.sp(8)
  height: label.implicitHeight + host.sp(2)
  color: host.sunk
  border.width: 1
  border.color: Qt.rgba(host.accent.r, host.accent.g, host.accent.b, 0.45)

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: badge.key + (badge.words !== "" ? "  " + badge.words : "")
    color: badge.host.accent
    font.family: badge.host.fontFamily
    font.styleName: badge.host.fontStyle
    font.pixelSize: Math.round(badge.host.fs(Style.font.bodySmall) * 0.92)
  }
}
