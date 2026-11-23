import QtQuick

// The overlay, off Wayland: where the shell gives a layer above everything
// with the keyboard, Windows gets a frameless window that stays on top and
// covers the screen it opens on.
Window {
  id: panel

  readonly property PanelAnchors anchors: PanelAnchors {}
  property int exclusionMode: 0

  flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
  transientParent: null   // see FloatingWindow

  onVisibleChanged: {
    if (!visible) return
    x = Screen.virtualX
    y = Screen.virtualY
    width = Screen.width
    height = Screen.height
    raise()
    requestActivate()
  }
}
