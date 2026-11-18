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
  // While the agent answers (2026-11-18): a square at the box's end stops
  // it, as a send button turns into one in the chat apps — drawn the page's
  // way, flat, dim, the accent under the pointer. Esc does the same.
  property bool busy: false
  signal stop()
  readonly property Item stopButton: stopSquare
  // The pane's own keys, before the box's: a handler that takes one sets
  // `event.accepted`.
  signal keyPressed(var event)
  function remove(a, b) { area.remove(a, b) }
  // Replying to a passage of the agent's (2026-11-18, design A): the box
  // itself says so — a bar inside it, its number and the words, × to let
  // it go — and keeps the accent while it is a reply.
  property string replyQuote: ""
  property int replyN: 0
  signal cancelReply()
  readonly property bool replying: replyQuote !== ""

  readonly property var borderSpec: Border.controlSpec(area.activeFocus || box.replying ? "focus" : area.hovered && page.handOn ? "hover-cursor" : "normal", page.foreground, page.accent)
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
      rightPadding: Style.spacing.controlPaddingX + Border.right(box.borderSpec) + (box.busy ? stopArea.width + page.sp(6) : 0)
      topPadding: Style.spacing.inputPaddingY + Border.top(box.borderSpec) + (box.replying ? replyBar.height + page.sp(6) : 0)
      bottomPadding: Style.spacing.inputPaddingY + Border.bottom(box.borderSpec)
      Keys.onPressed: function (event) { box.keyPressed(event) }
      background: BorderSurface {
        color: Style.controlFill(area.activeFocus, area.hovered, page.foreground, page.accent)
        borderSpec: box.borderSpec
        radius: Style.cornerRadius
      }
    }
  }

  // "↩ replying to ① “…”", inside the box, over what is typed.
  Item {
    id: replyBar
    visible: box.replying
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(box.borderSpec) - page.sp(4)
    anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(box.borderSpec)
    anchors.topMargin: Style.spacing.inputPaddingY + Border.top(box.borderSpec)
    height: barText.implicitHeight + page.sp(4)
    Rectangle { width: 2; height: parent.height; color: page.accent }
    Rectangle {
      id: barNumber
      x: page.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, barN.implicitWidth + page.sp(8))
      height: barN.implicitHeight + page.sp(2)
      radius: height / 2
      color: page.accent
      Text {
        id: barN
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(box.replyN)
        color: page.background
        font.family: page.fontFamily
        font.pixelSize: Math.round(page.textSize * 0.68)
      }
    }
    Text {
      id: barText
      anchors.left: barNumber.right
      anchors.leftMargin: page.sp(6)
      anchors.right: barCancel.left
      anchors.rightMargin: page.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: "↩ replying to “" + box.replyQuote + "”"
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
    Text {
      id: barCancel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "× esc"
      color: cancelArea.containsMouse && page.handOn ? page.accent : page.faint
      font.family: page.fontFamily
      font.pixelSize: page.fs(Style.font.caption)
      MouseArea {
        id: cancelArea
        anchors.fill: parent
        anchors.margins: -page.sp(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: box.cancelReply()
      }
    }
  }

  // At the end of the box's last line, where the eye is after sending.
  MouseArea {
    id: stopArea
    visible: box.busy
    width: Math.round(lineMetrics.height * 1.3)
    height: width
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX - Math.round((width - stopSquare.width) / 2) + Border.right(box.borderSpec)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: area.bottomPadding + Math.round((lineMetrics.lineSpacing - height) / 2)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: box.stop()
    Rectangle {
      id: stopSquare
      anchors.centerIn: parent
      width: Math.round(lineMetrics.height * 0.55)
      height: width
      radius: Math.min(Style.cornerRadius, Math.round(width / 4))
      color: stopArea.containsMouse && page.handOn ? page.accent : page.dim
    }
    Tip { host: box.page; shown: stopArea.containsMouse; text: box.page.tip("Stop it: what you wrote goes back in the box", "marginBack") }
  }
}
