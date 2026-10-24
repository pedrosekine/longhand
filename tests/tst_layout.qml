import QtQuick
import QtTest
import "../plugin-page/Layout.js" as Layout

// Where the note sits beside the panes (docs/navigation.md): one rule for
// both sides, and the note moves only when it has to.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_layout.qml
TestCase {
  name: "Layout"

  // A wide window: 1900 across, a 740 note, panes of 254 and 318.
  function test_room_for_both_moves_nothing() {
    var alone = Layout.note(1900, 740, 0, 0, 0)
    compare(alone.x, 580)
    compare(Layout.note(1900, 740, 0, 254, 0).x, alone.x)     // the sidebar opens
    compare(Layout.note(1900, 740, 0, 0, 318).x, alone.x)     // the right pane opens
    compare(Layout.note(1900, 740, 0, 254, 318).x, alone.x)   // both
    compare(Layout.note(1900, 740, 0, 254, 318).width, 740)
  }

  function test_steps_aside_as_far_as_it_has_to() {
    // 1300 across: centred at 280, the sidebar needs 300, the right pane
    // needs the note to end by 1300 - 340 = 960.
    compare(Layout.note(1300, 740, 0, 0, 0).x, 280)
    compare(Layout.note(1300, 740, 0, 300, 0).x, 300)
    compare(Layout.note(1300, 740, 0, 0, 340).x, 220)
    // The same distance either way: the rule has no favourite side.
    compare(280 - Layout.note(1300, 740, 0, 0, 340).x, 60)
    compare(Layout.note(1300, 740, 0, 340, 0).x - 280, 60)
  }

  function test_narrows_last() {
    var both = Layout.note(1200, 740, 0, 300, 340)
    compare(both.width, 560)
    compare(both.x, 300)
    // The overlay keeps its margin at the screen's edges.
    var over = Layout.note(1200, 740, 28, 300, 340)
    compare(over.width, 504)
    compare(over.x, 328)
    compare(Layout.note(500, 740, 0, 300, 340).width, 0)
  }
}
