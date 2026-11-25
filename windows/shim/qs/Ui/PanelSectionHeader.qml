import QtQuick
import qs.Commons
import qs.Commons as Commons

// omarchy-shell's PanelSectionHeader: the small bold word over a part of a
// popup ("DEADLINES").
Text {
  id: root

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption

  textFormat: Text.PlainText
  // Toward the popup's ground, not Qt.darker, which on a light ground made
  // the header darker than the rows under it.
  color: Style.mix(foreground, Commons.Color.menu.background, 0.30)
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true
  topPadding: Math.ceil(fontSize * 0.15)
}
