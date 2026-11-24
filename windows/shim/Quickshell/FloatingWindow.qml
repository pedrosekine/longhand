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
  onVisibleChanged: {
    if (!visible || placed) return
    placed = true
    var kept = Host.savedPlace(win.placeName)
    if (kept) {
      x = kept.x; y = kept.y; width = kept.width; height = kept.height
      return
    }
    var s = win.screenNamed(Host.screenHere())
    if (s) win.screen = s
    var room = Host.workArea()              // that screen's, the taskbar left out
    if (room.width <= 0) room = { x: Screen.virtualX, y: Screen.virtualY, width: Screen.desktopAvailableWidth, height: Screen.desktopAvailableHeight }
    height = Math.min(win.implicitHeight, room.height - 80)
    x = room.x + Math.max(0, Math.round((room.width - width) / 2))
    y = room.y + Math.max(0, Math.round((room.height - height) / 2))
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
