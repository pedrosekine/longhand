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

  function cover(s) {
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
  }

  onVisibleChanged: {
    if (!visible) return
    var s = panel.screenNamed(Host.screenHere())
    panel.cover(s)
    // Moved onto a screen scaled otherwise than the one it opened on,
    // Windows shifts the window as the scale changes under it (2026-11-24:
    // 282 px to the right on a monitor at 150% beside a laptop at 125%,
    // the left of the screen uncovered); placed again once it is there, it
    // covers the screen.
    reCover.target = s
    reCover.restart()
    raise()
    requestActivate()
  }
  Timer {
    id: reCover
    property var target: null
    interval: 60
    onTriggered: if (panel.visible) panel.cover(target)
  }
}
