import QtQuick
import QtTest
import "../plugin-page"

// Touchpad scrolling: travel times the gain while the fingers move, a glide
// after they lift, a mouse wheel left to the Flickable.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_touchscroll.qml
Item {
  width: 300
  height: 300

  Flickable {
    id: f
    width: 300
    height: 300
    contentWidth: 300
    contentHeight: 6000
    boundsBehavior: Flickable.StopAtBounds
    Rectangle { width: 300; height: 6000; color: "white" }
    TouchScroll { id: ts; flickable: f }
  }

  TestCase {
    name: "TouchScroll"
    when: windowShown

    function init() { f.cancelFlick(); f.contentY = 3000; ts.samples = [] }

    function test_fingers_move_the_content_by_the_gain() {
      ts.begin()
      ts.move(10, 1000)
      compare(f.contentY, 3000 - 10 * ts.gain)
      ts.move(-20, 1010)
      compare(f.contentY, 3000 + 10 * ts.gain)
    }

    function test_stops_at_the_ends() {
      ts.begin()
      f.contentY = 5
      ts.move(100, 1000)
      compare(f.contentY, 0)
      f.contentY = 5695
      ts.move(-100, 1010)
      compare(f.contentY, 5700)
    }

    function test_glides_on_after_a_quick_lift() {
      ts.begin()
      var t = Date.now()
      for (var i = 0; i < 6; i++) ts.move(-30, t + i * 10)
      var at = f.contentY
      ts.end(t + 60)
      verify(f.flicking, "a glide starts")
      tryVerify(function () { return f.contentY > at + 50 }, 1000, "and carries on the way the fingers went")
    }

    function test_resting_the_fingers_first_means_stop() {
      ts.begin()
      ts.move(-30, 1000)
      ts.move(-30, 1010)
      ts.end(1500)   // half a second still before lifting
      verify(!f.flicking)
    }

    function test_mouse_wheel_is_left_to_the_flickable() {
      mouseWheel(f, 150, 150, 0, -120)   // over the view, so through the TouchScroll first
      tryVerify(function () { return f.contentY > 3000 }, 1000, "the Flickable scrolled for the wheel")
    }
  }
}
