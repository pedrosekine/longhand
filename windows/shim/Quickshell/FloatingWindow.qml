import QtQuick
import LonghandHost

// The pinned shape: an ordinary window, Snap's and the taskbar's to place.
Window {
  id: win

  property real implicitWidth: 680
  property real implicitHeight: 900
  property size minimumSize: Qt.size(0, 0)

  // The page declares its windows inside an Item that is in no window; Qt
  // would wait for that Item to get one before showing this. Saying there is
  // no transient parent is what lets `visible` mean visible.
  transientParent: null

  width: implicitWidth
  height: Math.min(implicitHeight, Screen.desktopAvailableHeight - 80)
  minimumWidth: minimumSize.width
  minimumHeight: minimumSize.height

  // Hyprland gives a window its place, the same each time. Windows would
  // put this one in a screen's corner and forget it: so the first time it
  // is shown, where it was left last time Longhand ran (the state folder,
  // while that is still on a screen), else the middle of the screen the
  // pointer is on; after that, wherever it was left.
  property bool placed: false
  readonly property string placeName: win.title !== "" ? win.title : "window"
  function screenNamed(name) {
    var all = Qt.application.screens
    for (var i = 0; i < all.length; i++) if (all[i].name === name) return all[i]
    return null
  }
  function place(g) {
    x = g.x; y = g.y; width = g.width; height = g.height
  }
  onVisibleChanged: {
    if (!visible || placed) return
    placed = true
    var g = Host.savedPlace(win.placeName)
    var s = win.screenNamed(g ? g.screen : Host.screenHere())
    if (s) win.screen = s
    if (!g) {
      var room = Host.workArea()            // the pointer's screen's, the taskbar left out
      if (room.width <= 0) room = { x: Screen.virtualX, y: Screen.virtualY, width: Screen.desktopAvailableWidth, height: Screen.desktopAvailableHeight }
      var h = Math.min(win.implicitHeight, room.height - 80)
      g = { x: room.x + Math.max(0, Math.round((room.width - width) / 2)),
            y: room.y + Math.max(0, Math.round((room.height - h) / 2)), width: width, height: h }
    }
    win.place(g)
    // Put on a screen scaled otherwise than the one Windows first gave it,
    // the window is shifted and resized as the scale changes under it, as
    // the overlay was (PanelWindow.qml); placed again once it is there, it
    // is where it was left.
    rePlace.target = g
    rePlace.restart()
  }
  Timer {
    id: rePlace
    property var target: null
    interval: 60
    onTriggered: if (win.visible && target) win.place(target)
  }

  // Kept a moment after it was last moved or sized, and when it is put away.
  function keep() {
    if (!win.placed || win.visibility === Window.Minimized || win.visibility === Window.Maximized
        || win.visibility === Window.FullScreen || win.width < 200 || win.height < 150) return
    Host.keepPlace(win.placeName, { x: win.x, y: win.y, width: win.width, height: win.height })
  }
  Timer { id: keeping; interval: 800; onTriggered: win.keep() }
  onXChanged: if (visible && placed) keeping.restart()
  onYChanged: if (visible && placed) keeping.restart()
  onWidthChanged: if (visible && placed) keeping.restart()
  onHeightChanged: if (visible && placed) keeping.restart()
  onClosing: win.keep()
}
