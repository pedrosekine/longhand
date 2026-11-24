import QtQuick
import LonghandHost

// The overlay, off Wayland: where the shell gives a layer above everything
// with the keyboard, Windows gets a frameless window that stays on top and
// covers a screen — the one the pointer is on, as Hyprland opens a layer on
// the focused monitor.
Window {
  id: panel

  readonly property PanelAnchors anchors: PanelAnchors {}
  property int exclusionMode: 0

  flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
  transientParent: null   // see FloatingWindow

  function screenNamed(name) {
    var all = Qt.application.screens
    for (var i = 0; i < all.length; i++) if (all[i].name === name) return all[i]
    return null
  }

  onVisibleChanged: {
    if (!visible) return
    var s = panel.screenNamed(Host.screenHere())
    if (s) {
      panel.screen = s
      x = s.virtualX
      y = s.virtualY
      width = s.width
      height = s.height
    } else {
      x = Screen.virtualX
      y = Screen.virtualY
      width = Screen.width
      height = Screen.height
    }
    raise()
    requestActivate()
  }
}
