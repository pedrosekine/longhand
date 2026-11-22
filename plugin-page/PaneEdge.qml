import QtQuick

// The agent's pane's left edge, dragged (2026-11-22, as Omarchy's window
// borders): under the mouse it lights and the pointer turns; dragged, the
// pane follows, as far as it may go (Layout.drag), and the split you are in
// keeps the width when let go. While dragging, a small label says the width
// and where the middle's least is.
Item {
  id: edge
  required property Item page
  readonly property bool on: page.paneSizable && !page.paneAlone
  visible: on
  anchors.left: parent.left
  anchors.leftMargin: -page.sp(4)
  anchors.top: parent.top
  anchors.bottom: parent.bottom
  width: page.sp(9)
  z: 40

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: page.sp(3)
    color: page.accent
    opacity: area.pressed ? 0.9 : area.containsMouse && page.handOn ? 0.6 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.SizeHorCursor
    preventStealing: true
    onPositionChanged: function (mouse) {
      if (!pressed) return
      var p = mapToItem(edge.page.contentItem, mouse.x, mouse.y)
      edge.page.dragPane(p.x)
    }
    onReleased: edge.page.endPaneDrag()
    onCanceled: edge.page.endPaneDrag()
    // A double click: back to where the split starts (today's width when
    // reading, the middle at its least when discussing).
    onDoubleClicked: edge.page.resetPane()
  }
  // The width, while dragged.
  Rectangle {
    visible: area.pressed && edge.page.paneLive > 0
    x: -width - edge.page.sp(10)
    y: Math.max(0, Math.min(edge.height - height, area.mouseY + edge.page.sp(16)))
    width: dragLabel.implicitWidth + edge.page.sp(20)
    height: dragLabel.implicitHeight + edge.page.sp(12)
    color: edge.page.sunk
    border.width: 1
    border.color: Qt.rgba(edge.page.foreground.r, edge.page.foreground.g, edge.page.foreground.b, 0.16)
    Text {
      id: dragLabel
      anchors.centerIn: parent
      textFormat: Text.StyledText
      text: edge.page.paneSplit + ": the chat " + edge.page.paneLive + " px"
        + "<font color=\"" + edge.page.dim + "\"> · the " + (edge.page.paneKind === "paper" ? "paper's" : "note's")
        + " least at " + edge.page.paneOpts.floor + "</font>"
      color: edge.page.foreground
      font.family: edge.page.fontFamily
      font.styleName: edge.page.fontStyle
      font.pixelSize: edge.page.fs(13)
    }
  }
}
