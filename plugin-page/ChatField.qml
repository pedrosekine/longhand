import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The box a conversation is written in (2026-10-25). The one-line field it
// replaced ran a long message off sideways, out of sight; this one wraps,
// grows with what is written up to `maxLines`, then scrolls. The pane's
// keys come first (`keyPressed`: Enter sends, as before); Shift+Enter is
// left to the box, a new line. Drawn as the shell's TextField is.
FocusScope {
  id: box
  required property Item page
  property alias text: area.text
  property alias cursorPosition: area.cursorPosition
  property alias readOnly: area.readOnly
  property alias placeholderText: area.placeholderText
  readonly property alias selectedText: area.selectedText
  property int maxLines: 8
  // The pane's own keys, before the box's: a handler that takes one sets
  // `event.accepted`.
  signal keyPressed(var event)
  function remove(a, b) { area.remove(a, b) }

  readonly property var borderSpec: Border.controlSpec(area.activeFocus ? "focus" : area.hovered ? "hover-cursor" : "normal", page.foreground, page.accent)
  FontMetrics { id: lineMetrics; font: area.font }
  implicitHeight: Math.min(area.implicitHeight, Math.ceil(lineMetrics.lineSpacing * box.maxLines) + area.topPadding + area.bottomPadding)

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    TextArea.flickable: TextArea {
      id: area
      focus: true
      wrapMode: TextArea.Wrap
      color: page.foreground
      placeholderTextColor: Qt.darker(page.foreground, 1.6)
      selectionColor: page.palette.selection
      selectedTextColor: page.foreground
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.body)
      leftPadding: Style.spacing.controlPaddingX + Border.left(box.borderSpec)
      rightPadding: Style.spacing.controlPaddingX + Border.right(box.borderSpec)
      topPadding: Style.spacing.inputPaddingY + Border.top(box.borderSpec)
      bottomPadding: Style.spacing.inputPaddingY + Border.bottom(box.borderSpec)
      Keys.onPressed: function (event) { box.keyPressed(event) }
      background: BorderSurface {
        color: Style.controlFill(area.activeFocus, area.hovered, page.foreground, page.accent)
        borderSpec: box.borderSpec
        radius: Style.cornerRadius
      }
    }
  }
}
