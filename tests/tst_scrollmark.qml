import QtQuick
import QtQuick.Controls as QC
import QtTest
import "../plugin-page"

// The bar at a list's edge (ScrollMark.qml): it loads as a Flickable's own
// (a property clashing with ScrollBar's kept the whole page from loading,
// 2026-11-25), follows the list, and shows only when there is more than
// fits. A mouse drag never pans the list (acceptedButtons: Qt.NoButton).
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_scrollmark.qml
Item {
  id: top
  width: 300
  height: 300

  // What the bar reads from the page.
  Item {
    id: stubPage
    property bool handOn: true
    property color faint: "gray"
    property color foreground: "black"
    function sp(n) { return n }
  }

  Flickable {
    id: f
    width: 300
    height: 300
    contentWidth: 300
    contentHeight: 3000
    acceptedButtons: Qt.NoButton
    boundsBehavior: Flickable.StopAtBounds
    QC.ScrollBar.vertical: ScrollMark { id: bar; page: stubPage }
    Rectangle { width: 300; height: 3000; color: "white" }
  }

  TestCase {
    name: "ScrollMark"
    when: windowShown

    function test_it_follows_the_list() {
      verify(bar.upright)
      f.contentY = 0
      compare(bar.position, 0)
      f.contentY = 1350
      fuzzyCompare(bar.position, 0.45, 0.001)
      fuzzyCompare(bar.size, 0.1, 0.001)
    }

    function test_nothing_at_rest() {
      f.contentY = 0
      wait(250)
      verify(!bar.shown)
    }

    function test_a_mouse_drag_does_not_pan() {
      f.contentY = 0
      mouseDrag(f, 150, 250, 0, -200)
      compare(f.contentY, 0)
    }
  }
}
