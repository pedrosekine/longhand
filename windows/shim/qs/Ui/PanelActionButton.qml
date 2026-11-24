import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// omarchy-shell's PanelActionButton: a small square button with a picture
// on it (the timer's start, skip and reset). The picture is Windows' own
// for the same thing (Glyphs.js).
BorderSurface {
  id: root

  property string iconText: ""
  property string iconSource: ""
  property string tooltipText: ""
  property color foreground: Commons.Color.foreground
  property color hoverColor: foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.icon
  property real size: Math.round(Math.max(Style.space(22), fontSize + Style.spacing.sm * 2)) | 1
  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false
  property bool outlined: false

  signal clicked()
  signal hovered(bool isHovered)

  readonly property var glyph: Glyphs.drawn(iconText, Style.families, fontFamily)
  readonly property bool hot: (mouse.containsMouse || hasCursor) && enabled

  implicitWidth: size
  implicitHeight: size
  radius: Style.cornerRadius
  color: mouse.pressed ? Style.pressedFillFor(foreground) : hot ? Style.hoverFillFor(foreground) : "transparent"
  borderSpec: hot ? Border.controlSpec("hover", foreground) : (bordered || outlined) ? Border.controlSpec("normal", foreground) : Border.none()

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.glyph.text
    color: root.hot ? root.hoverColor : root.foreground
    font.family: root.glyph.face
    font.pixelSize: root.fontSize
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: root.clicked()
  }

  PanelToolTip { text: root.tooltipText; visible: mouse.containsMouse && root.tooltipText !== "" }
}
