import QtQuick

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

  // Hyprland gives a new window its place; Windows would put this one in
  // the screen's corner. The first time it is shown, the middle; after
  // that, wherever it was left.
  property bool placed: false
  onVisibleChanged: {
    if (!visible || placed) return
    placed = true
    x = Screen.virtualX + Math.max(0, Math.round((Screen.desktopAvailableWidth - width) / 2))
    y = Screen.virtualY + Math.max(0, Math.round((Screen.desktopAvailableHeight - height) / 2))
  }
}
