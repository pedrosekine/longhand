import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// omarchy-shell's Button under its own names: words, a picture or both;
// `active` and `selected` fill it, `hasCursor` (or the pointer) lights it.
BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false

  property color foreground: Commons.Color.foreground
  property color background: "transparent"
  property color accent: Commons.Color.accent

  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  readonly property bool hot: mouse.containsMouse || hasCursor
  readonly property var glyph: Glyphs.drawn(iconText, Style.families, fontFamily)
  readonly property real edge: Border.top(borderSpec)

  implicitWidth: row.implicitWidth + horizontalPadding * 2 + 2
  implicitHeight: row.implicitHeight + verticalPadding * 2 + 2
  radius: Style.cornerRadius
  color: mouse.pressed ? Style.pressedFillFor(foreground, accent)
    : (active || selected) ? Style.selectedFillFor(foreground, accent)
    : hot ? Style.hoverFillFor(foreground, accent)
    : background
  borderSpec: (focusable && activeFocus) ? Border.controlSpec("focus", foreground, accent)
    : hot ? Border.controlSpec("hover", foreground, accent)
    : bordered ? Border.controlSpec("normal", foreground, accent)
    : Border.none()

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: root.leftAlign ? root.horizontalPadding + 1 : Math.round((root.width - width) / 2)
    spacing: Style.space(6)

    Text {
      visible: root.iconText !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.glyph.text
      color: root.foreground
      font.family: root.glyph.face
      font.pixelSize: root.iconSize
    }
    Text {
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: function (m) { if (m.button === Qt.RightButton) root.rightClicked(); else root.clicked() }
  }

  PanelToolTip { text: root.tooltipText; visible: mouse.containsMouse && root.tooltipText !== "" }
}
