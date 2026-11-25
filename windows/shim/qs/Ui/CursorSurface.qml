import QtQuick
import qs.Commons
import qs.Commons as Commons

// omarchy-shell's CursorSurface: the ground under one thing in a popup that
// the keys or the pointer can be on. `hasCursor` lights it; nothing in it
// looks at the pointer itself, so one thing is lit at a time.
BorderSurface {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool outline: false
  property bool bordered: false

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color fill: Style.hoverFillFor(foreground, accent)
  property color currentFill: Style.selectedFillFor(foreground, accent)

  radius: Style.cornerRadius
  color: hasCursor ? fill : (current ? currentFill : "transparent")
  borderSpec: hasCursor ? Border.controlSpec("hover", foreground, accent)
    : current ? Border.controlSpec("selected", foreground, accent)
    : bordered ? Border.controlSpec("normal", foreground, accent)
    : Border.none()

  Behavior on color { ColorAnimation { duration: Style.duration(60) } }
}
