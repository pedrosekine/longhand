import QtQuick
import qs.Commons

// The foot of a Settings sheet: its keys, or for a moment what just
// happened (page.status), as the dashboard's foot does. Settings hid the
// note's status line and drew none of its own, so a check-in's "3 lines to
// go", a save that failed, or Ctrl+S said nothing there (2026-11-28).
Text {
  id: foot
  required property Item page
  property string keys: ""
  readonly property bool saying: page.status !== ""
  textFormat: Text.PlainText
  wrapMode: Text.WordWrap
  maximumLineCount: saying ? 2 : 4
  elide: Text.ElideRight
  text: saying ? page.status : keys
  color: saying ? page.accent : page.faint
  font.family: page.fontFamily
  font.styleName: page.fontStyle
  font.pixelSize: page.fs(saying ? Style.font.bodySmall : Style.font.caption)
}
