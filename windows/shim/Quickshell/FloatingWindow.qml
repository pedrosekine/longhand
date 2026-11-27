import QtQuick
import LonghandHost
import qs.Commons as Commons

// The window shape: an ordinary window, Snap's and the taskbar's to place.
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
  // while that is still on a screen; maximized, if it was), else the middle
  // of the screen the pointer is on; after that, wherever it was left —
  // unless it is shown again from another screen, where it opens on that
  // one (2026-11-27: the overlay kept as a window on the second monitor
  // opened the window back on the first).
  property bool placed: false
  // Its last place while neither maximized nor full screen: what is kept,
  // maximized or not, and what it comes back to from maximized.
  property var normalPlace: null
  readonly property string placeName: win.title !== "" ? win.title : "window"
  function screenNamed(name) {
    var all = Qt.application.screens
    for (var i = 0; i < all.length; i++) if (all[i].name === name) return all[i]
    return null
  }
  function place(g) {
    x = g.x; y = g.y; width = g.width; height = g.height
  }
  // The middle of a screen's room, at the size the page asks for, or less
  // where the screen is smaller.
  function middleOf(room, w, h) {
    if (room.width <= 0) room = { x: Screen.virtualX, y: Screen.virtualY, width: Screen.desktopAvailableWidth, height: Screen.desktopAvailableHeight }
    w = Math.min(w, room.width - 80)
    h = Math.min(h, room.height - 80)
    return { x: room.x + Math.max(0, Math.round((room.width - w) / 2)),
             y: room.y + Math.max(0, Math.round((room.height - h) / 2)), width: w, height: h }
  }
  // Windows' title bar stays — Snap, the taskbar, a frame to drag and size
  // by — painted the page's paper and words, so it reads as the top of the
  // page and not as a second header over it; the private paper sinks it
  // too (windows/dwm.py). Hyprland draws no title bar at all.
  function paintTitleBar() {
    if (win.visible) Host.paintTitleBar(win, String(win.color), String(Commons.Color.foreground))
  }
  onColorChanged: win.paintTitleBar()
  Connections {
    target: Commons.Color
    function onForegroundChanged() { win.paintTitleBar() }
  }

  onVisibleChanged: {
    if (visible) win.paintTitleBar()
    if (!visible) return
    if (placed) { win.toScreenHere(); return }
    placed = true
    var g = Host.savedPlace(win.placeName)
    var s = win.screenNamed(g ? g.screen : Host.screenHere())
    if (s) win.screen = s
    if (!g) g = win.middleOf(Host.workArea(), win.implicitWidth, win.implicitHeight)
    win.normalPlace = { x: g.x, y: g.y, width: g.width, height: g.height }
    win.place(g)
    // Put on a screen scaled otherwise than the one Windows first gave it,
    // the window is shifted and resized as the scale changes under it, as
    // the overlay was (PanelWindow.qml); placed again once it is there, it
    // is where it was left.
    rePlace.target = g
    rePlace.maximize = !!g.maximized
    rePlace.restart()
  }
  // Shown again with the pointer on another screen: there, at its size, in
  // the middle — maximized again if it was.
  function toScreenHere() {
    var here = Host.screenHere()
    if (here === "" || !win.screen || win.screen.name === here) return
    var room = Host.workArea()
    var s = win.screenNamed(here)
    if (!s || room.screen !== here) return
    var maxed = win.visibility === Window.Maximized || win.visibility === Window.FullScreen
    var size = win.normalPlace || { width: win.width, height: win.height }
    if (maxed) win.visibility = Window.Windowed
    win.screen = s
    var g = win.middleOf(room, size.width, size.height)
    win.place(g)
    rePlace.target = g
    rePlace.maximize = maxed
    rePlace.restart()
  }
  Timer {
    id: rePlace
    property var target: null
    property bool maximize: false
    interval: 60
    onTriggered: {
      if (!win.visible || !target) return
      win.place(target)
      if (maximize) win.visibility = Window.Maximized
      maximize = false
    }
  }

  // Kept a moment after it was last moved, sized, maximized or put back,
  // and when it is put away. Full screen keeps what it had before.
  function keep() {
    if (!win.placed || win.width < 200 || win.height < 150) return
    var v = win.visibility
    if (v === Window.Windowed || v === Window.AutomaticVisibility) {
      win.normalPlace = { x: win.x, y: win.y, width: win.width, height: win.height }
      Host.keepPlace(win.placeName, win.normalPlace)
    } else if (v === Window.Maximized && win.normalPlace) {
      var g = win.normalPlace
      Host.keepPlace(win.placeName, { x: g.x, y: g.y, width: g.width, height: g.height, maximized: true })
    }
  }
  Timer { id: keeping; interval: 800; onTriggered: win.keep() }
  onXChanged: if (visible && placed) keeping.restart()
  onYChanged: if (visible && placed) keeping.restart()
  onWidthChanged: if (visible && placed) keeping.restart()
  onHeightChanged: if (visible && placed) keeping.restart()
  onVisibilityChanged: if (visible && placed) keeping.restart()
  onClosing: win.keep()
}
