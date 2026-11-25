import QtQuick
import qs.Commons
import qs.Commons as Commons

// omarchy-shell's ToggleSwitch: a track and a knob that says on or off.
// It never changes `checked` itself: a click says `toggled`, and whoever
// owns the state sets it. `interactive: false` leaves the click to the row
// it sits in.
Item {
  id: root

  property bool checked: false
  property bool busy: false
  property bool interactive: true
  property bool hasCursor: false
  property bool cursorRing: interactive
  property int cursorPad: Style.space(6)
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  property int trackHeight: Math.max(18, Math.round(Style.spacing.controlHeight * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)
  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
  readonly property int pad: cursorRing ? cursorPad : 0

  implicitWidth: trackWidth + pad * 2
  implicitHeight: trackHeight + pad * 2
  opacity: busy ? 0.6 : 1

  Rectangle {
    id: track
    anchors.centerIn: parent
    width: root.trackWidth
    height: root.trackHeight
    radius: root.rounded ? height / 2 : 0
    color: root.checked ? root.accent : "transparent"
    border.width: 1
    border.color: root.checked ? root.accent : Commons.Util.alpha(root.foreground, root.hot ? 0.7 : 0.45)
    Behavior on color { ColorAnimation { duration: Style.duration(90) } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? height / 2 : 0
      y: root.knobInset
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      color: root.checked ? Commons.Color.background : root.foreground
      Behavior on x { NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutQuad } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: root.interactive
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: root.toggled()
  }
}
