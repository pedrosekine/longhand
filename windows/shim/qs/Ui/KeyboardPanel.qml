import QtQuick
import QtQuick.Window
import LonghandHost
import qs.Commons
import qs.Commons as Commons

// omarchy-shell's KeyboardPanel is the card a bar widget opens under its
// label. On Windows it is a small window of its own in the corner by the
// clock, where the tray's own flyouts open: no title bar, no taskbar button,
// above the other windows, the keys given to `focusTarget` when it opens.
// It goes when Esc is pressed in it (the widget's own key catcher asks) or
// when another window is clicked: a flyout, not a place to stay.
//
// The names are the shell's: `open` shows it, `contentWidth` and
// `contentHeight` are the card's own size (the padding inside them, as
// `fittedContentHeight` counts it), and what is declared inside goes into
// the padded middle.
Window {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property int margin: Style.space(12)
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property real drawnHeight: contentHeight
  property var borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, 1)
  property bool centerOnBar: false
  property bool open: false
  property Item focusTarget: null
  // (The shell calls this alias contentItem; a Window has one of its own.)
  default property alias cardItems: holder.data

  // The screen's own room, the taskbar left out, as the host says it.
  property var area: ({ x: 0, y: 0, width: 0, height: 0 })
  readonly property real availableCardWidth: Math.max(0, area.width - margin * 2)
  readonly property real availableCardHeight: Math.max(0, area.height - margin * 2)
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var wanted = Math.max(1, Number(width) || 1)
    var most = root.availableCardWidth > 0 ? root.availableCardWidth : wanted
    if (cap !== undefined && Number(cap) > 0) most = Math.min(most, Number(cap))
    return Math.round(Math.min(wanted, most))
  }
  function fittedContentHeight(implicitHeight, cap) {
    var wanted = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var most = root.availableCardHeight > 0 ? root.availableCardHeight : wanted
    if (cap !== undefined && Number(cap) > 0) most = Math.min(most, Number(cap))
    return Math.round(Math.min(wanted, most))
  }
  function cappedContentHeight(height) {
    var wanted = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    return Math.round(root.availableCardHeight > 0 ? Math.min(wanted, root.availableCardHeight) : wanted)
  }

  function close() {
    if (root.owner && typeof root.owner.close === "function") root.owner.close()
    else root.open = false
  }

  // The corner by the clock: the work area's bottom right, wherever the
  // taskbar is.
  function place() {
    root.x = Math.round(root.area.x + root.area.width - root.width - root.margin)
    root.y = Math.round(root.area.y + root.area.height - root.height - root.margin)
  }
  function screenNamed(name) {
    var all = Qt.application.screens
    for (var i = 0; i < all.length; i++) if (all[i].name === name) return all[i]
    return null
  }
  // Opened on a screen scaled otherwise than the one it was last on, the
  // window is shifted as the scale changes under it, as the overlay was
  // (Quickshell/PanelWindow.qml): placed again once it is there, it is in
  // the corner.
  Timer { id: rePlace; interval: 60; onTriggered: if (root.visible) root.place() }

  transientParent: null
  // Never drawn (no title bar): the widget's name, for whoever lists windows.
  title: owner && owner.moduleName ? owner.moduleName : "longhand.popup"
  flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
  color: "transparent"
  width: Math.max(1, contentWidth)
  height: Math.max(1, contentHeight)
  onWidthChanged: if (visible) place()
  onHeightChanged: if (visible) place()

  onOpenChanged: {
    if (root.open) {
      root.area = Host.workArea()
      var s = root.screenNamed(root.area.screen)
      if (s) root.screen = s
      root.place()
      root.show()
      // Windows 11's corners, and with them the shadow and hairline edge
      // its own flyouts have (windows/dwm.py): the card stands off what is
      // behind it, as the clock's own flyout does beside it.
      Host.roundCorners(root)
      rePlace.restart()
      root.raise()
      root.requestActivate()
      // The keys to the widget's key catcher, unless the widget has already
      // given them to something inside it (the timer's digits, when idle).
      // Asked of the items themselves: the window may not be the active one
      // yet, and until it is it names no item as having the keys.
      Qt.callLater(function () { if (root.focusTarget && !root.holdsFocus(root.focusTarget)) root.focusTarget.forceActiveFocus() })
    } else root.hide()
  }
  function holdsFocus(item) {
    if (item.focus) return true
    for (var i = 0; i < item.children.length; i++) if (root.holdsFocus(item.children[i])) return true
    return false
  }
  // Another window was clicked. Not while it is still coming up: a window
  // is not the active one for a moment after it is first shown.
  onActiveChanged: if (!root.active && root.open) leaving.restart(); else leaving.stop()
  // Nor the second click of a double click on its tray icon (2026-11-25,
  // tested on the ThinkPad): that click makes the taskbar the active
  // window just after the first opened this one, which then put itself
  // away. The tray says so (windows/Main.qml, on its DoubleClick), and for
  // a moment a loss takes the keys back instead. Only then: another window
  // clicked a moment after opening still puts it away.
  property real keepUntil: 0
  function keepThroughLoss() {
    root.keepUntil = Date.now() + 600
    if (root.open && !root.active) { root.raise(); root.requestActivate() }
  }
  // When it last put itself away so: a click on its own tray icon does
  // that on the press, and the host (windows/Main.qml, popup) does not open
  // it again on the release.
  property real lostAt: 0
  Timer {
    id: leaving
    interval: 120
    onTriggered: {
      if (root.active || !root.open) return
      if (Date.now() < root.keepUntil) { root.raise(); root.requestActivate() }
      else { root.lostAt = Date.now(); root.close() }
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.overlayRadius               // Windows rounds the window itself at 8 (dwm.py)
    color: Commons.Color.popups.background
    border.color: Border.color(root.borderSpec)
    border.width: Border.top(root.borderSpec)
  }

  Item {
    id: holder
    anchors.fill: parent
    anchors.margins: root.padding + Border.top(root.borderSpec)
  }
}
