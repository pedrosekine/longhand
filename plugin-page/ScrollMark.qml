import QtQuick
import QtQuick.Controls

// The bar at a list's edge (2026-11-25, the mouse pass): how long the list
// is and where in it you are, and a handle the mouse can drag. It stays
// out of the way: a thin line while the list moves, a little wider under
// the hand, a faint line at rest so a long list says it goes on (the
// second pass: at rest it was nothing, and nothing said there was more),
// and nothing when everything fits. Attach it
// as `QC.ScrollBar.vertical: ScrollMark { page: … }` (the Flickable's own
// `acceptedButtons: Qt.NoButton` keeps a mouse drag from panning the list
// as a finger would; the wheel, the touchpad and this bar scroll it).
ScrollBar {
  id: bar
  required property Item page
  readonly property bool upright: orientation === Qt.Vertical
  readonly property bool shown: size < 1 && (active || hovered && page.handOn)

  policy: ScrollBar.AsNeeded
  minimumSize: 0.06
  padding: page.sp(2)
  // The hit area, wider than what is drawn.
  implicitWidth: upright ? page.sp(10) : 0
  implicitHeight: upright ? 0 : page.sp(10)

  contentItem: Item {
    implicitWidth: bar.page.sp(6)
    implicitHeight: bar.page.sp(6)
    Rectangle {
      readonly property real thick: bar.page.sp(bar.hovered || bar.pressed ? 6 : 3)
      anchors.right: bar.upright ? parent.right : undefined
      anchors.bottom: bar.upright ? undefined : parent.bottom
      width: bar.upright ? thick : parent.width
      height: bar.upright ? parent.height : thick
      radius: thick / 2
      color: bar.pressed ? bar.page.foreground : bar.page.faint
      // At rest only when there is clearly more: a fitted page a pixel or two
      // wider than its view (a PDF's rounding) drew a line with nowhere to go.
      opacity: bar.size >= 1 ? 0 : bar.shown ? (bar.hovered || bar.pressed ? 0.7 : 0.45) : bar.size < 0.98 ? 0.18 : 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      Behavior on width { NumberAnimation { duration: 120 } }
      Behavior on height { NumberAnimation { duration: 120 } }
    }
  }
  background: Item {}
}
