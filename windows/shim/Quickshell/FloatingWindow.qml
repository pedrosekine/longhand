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
}
