import QtQuick
import QtTest
import "../plugin-page/Layout.js" as Layout

// Where the note sits beside the panes (docs/navigation.md): one rule for
// both sides, the note centred in the room the panes leave.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_layout.qml
TestCase {
  name: "Layout"

  // A wide window: 1900 across, a 740 note, panes of 254 and 318.
  function test_centred_in_the_room_the_panes_leave() {
    var alone = Layout.note(1900, 740, 0, 0, 0)
    compare(alone.x, 580)
    compare(Layout.note(1900, 740, 0, 254, 0).x, 707)         // the sidebar opens: 254 + (1646 - 740) / 2
    compare(Layout.note(1900, 740, 0, 0, 318).x, 421)         // the right pane opens: (1582 - 740) / 2
    compare(Layout.note(1900, 740, 0, 254, 318).x, 548)       // both: 254 + (1328 - 740) / 2
    compare(Layout.note(1900, 740, 0, 254, 318).width, 740)
  }

  function test_even_margins_either_side() {
    // Whatever is open, the room left of the note and the room right of it
    // are the same (to the pixel a rounding gives).
    var cases = [[1900, 0, 0, 0], [1900, 0, 254, 0], [1900, 0, 0, 458], [1440, 28, 254, 318], [1300, 0, 300, 340]]
    for (var i = 0; i < cases.length; i++) {
      var c = cases[i], n = Layout.note(c[0], 740, c[1], c[2], c[3])
      var before = n.x - c[1] - c[2]
      var after = c[0] - c[1] - c[3] - (n.x + n.width)
      verify(Math.abs(before - after) <= 1, JSON.stringify(c) + ": " + before + " vs " + after)
    }
    // A pane moves the note by half its room, the same distance either way.
    var mid = Layout.note(1300, 740, 0, 0, 0).x
    compare(mid - Layout.note(1300, 740, 0, 0, 340).x, 170)
    compare(Layout.note(1300, 740, 0, 340, 0).x - mid, 170)
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

  function test_narrow_windows_and_mutual_exclusion() {
    // 1900 and 1200 fit both side panes beside a >= 420 px note.
    verify(Layout.bothFit(1900, 0, 254, 318, 420))
    verify(Layout.bothFit(1200, 0, 254, 318, 420))
    // Half-screen 1080p split (960 px) and default floating window (680 px) do not.
    verify(!Layout.bothFit(960, 0, 254, 318, 420))
    verify(!Layout.bothFit(680, 0, 254, 318, 420))
    // Right pane fits cleanly alone at 960 and 680, and returns 0 when too narrow.
    compare(Layout.rightPane(1900, 0, 740, 254, 18, 300, 440, 340), 440)
    compare(Layout.rightPane(960, 0, 740, 0, 18, 300, 440, 340), 300)
    compare(Layout.rightPane(680, 0, 740, 0, 18, 300, 440, 340), 300)
    compare(Layout.rightPane(500, 0, 740, 0, 18, 300, 440, 340), 0)
  }

  // ---------------------------------------------- the pane sized by hand
  // The laptop (1440 across, 18 gap): a paper whose floor is 600, the
  // chat's ceiling 918 with the rail.
  readonly property var lap: ({ room: 1422, min: 300, ceiling: 918, floor: 600, hardFloor: 360, reading: 440 })

  function test_reading_starts_as_today_and_discussing_at_the_floor() {
    compare(Layout.paneWidth(lap, "reading", 0), 440)
    compare(Layout.paneWidth(lap, "discussing", 0), 822)        // the paper at 600
    // The big screen: the chat stops at its ceiling, the rest is the paper's.
    var big = { room: 1902, min: 300, ceiling: 918, floor: 600, hardFloor: 360, reading: 440 }
    compare(Layout.paneWidth(big, "discussing", 0), 918)
  }

  function test_remembered_widths_are_kept_within_reach() {
    compare(Layout.paneWidth(lap, "reading", 520), 520)
    compare(Layout.paneWidth(lap, "reading", 120), 300)          // never under the pane's least
    // A drag may take the paper under its floor, down to the chat's ceiling.
    compare(Layout.paneWidth(lap, "discussing", 5000), 918)
  }

  function test_nudges_stop_at_the_floor_drags_go_past() {
    compare(Layout.nudge(lap, 440, 100), 540)
    compare(Layout.nudge(lap, 800, 100), 822)                    // the paper's floor
    compare(Layout.nudge(lap, 822, 100), 822)
    compare(Layout.nudge(lap, 900, 100), 900)                    // a drag took it further: stays
    compare(Layout.nudge(lap, 900, -100), 800)
    compare(Layout.nudge(lap, 340, -100), 300)
    compare(Layout.drag(lap, 1000), 918)                         // the chat's ceiling comes first
    var roomy = { room: 1422, min: 300, ceiling: 2000, floor: 600, hardFloor: 360, reading: 440 }
    compare(Layout.drag(roomy, 1300), 1062)                      // the paper's least for a drag
    compare(Layout.drag(lap, 100), 300)
  }

  function test_one_at_a_time_when_both_do_not_fit() {
    // Half the laptop: 710 less the gap.
    var half = { room: 692, min: 300, ceiling: 918, floor: 600, hardFloor: 360, reading: 440 }
    verify(Layout.paneRange(half).alone)
    compare(Layout.paneWidth(half, "reading", 0), 0)
    verify(!Layout.paneRange(lap).alone)
  }

  function test_a_papers_floor_follows_its_type() {
    // A letter page (612 pt), text from 72 to 540: reach 234 + 14 = 248.
    // 10 pt type (words 12 pt high) at 11 px wants 1.1 px a point: 546.
    compare(Layout.paperFloor({ x0: 72, x1: 540, w: 612, h: 12 }, 612, 11, 0), 546)
    // Smaller type wants a wider column; the sheet's padding is added.
    compare(Layout.paperFloor({ x0: 72, x1: 540, w: 612, h: 10.8 }, 612, 11, 56), 663)
    // No words: the page's width at 10 pt.
    compare(Layout.paperFloor(null, 612, 11, 0), 674)
  }
}

