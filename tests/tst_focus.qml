import QtQuick
import QtTest
import "../plugin-page/Focus.js" as Focus

// One project's part of the day (Focus.js, 2026-11-11): which lines a tag
// claims, by the runner's rule, and how the view carries them over edits.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_focus.qml
TestCase {
  name: "Focus"

  readonly property string day: [
    "Morning notes.",                          // 0
    "",                                        // 1
    "# Design Studio #studio",                 // 2
    "the crit went well",                      // 3
    "## Next steps",                           // 4
    "- [ ] sketch the radio",                  // 5
    "",                                        // 6
    "# Thesis #thesis",                        // 7
    "- [ ] ask Chris about diaries #studio",   // 8
    "  he said fridays",                       // 9
    "- [ ] read ch.2",                         // 10
    "# Team meeting #studio",                  // 11
    "notes",                                   // 12
    "",                                        // 13
    ""].join("\n")                             // 14

  function test_a_tag_claims_its_sections_and_its_boxes() {
    // Each heading until the next of its level or higher; the box written
    // in another course's section with its detail; no blank lines at ends.
    compare(Focus.claims(day, "studio"), [[2, 6], [8, 10], [11, 13]])
    compare(Focus.claims(day, "#Studio"), [[2, 6], [8, 10], [11, 13]])
    // The thesis's section does not include the studio's box, by the
    // rule the list follows (the box is the studio's).
    compare(Focus.claims(day, "thesis"), [[7, 11]])
    compare(Focus.claims(day, "nothing"), [])
    compare(Focus.claims(day, ""), [])
  }

  function test_an_h2_inside_is_part_of_it_and_an_h2_does_not_end_an_h1() {
    var t = "# Course #c\nintro\n## Week 2 #c\nmore\n## Other\nstill c\n# Next\nout"
    compare(Focus.claims(t, "c"), [[0, 6]])
    // A tagged H2 alone claims until the next H2 or H1.
    compare(Focus.claims("# Day\n## Seminar #s\nx\n### deep\ny\n## Lunch\nz", "s"), [[1, 5]])
  }

  function test_fences_and_frontmatter_are_not_headings() {
    var t = "---\ntags: x\n---\n# A #a\n```\n# not a heading #b\n```\nafter"
    compare(Focus.claims(t, "a"), [[3, 8]])
    compare(Focus.claims(t, "b"), [])
  }

  function test_mask_and_folds() {
    var lines = day.split("\n")
    var m = Focus.mask(lines.length, Focus.claims(day, "studio"))
    compare(m[0], false); compare(m[2], true); compare(m[5], true); compare(m[6], false)
    compare(Focus.any(m), true)
    compare(Focus.any(Focus.mask(3, [])), false)
    var f = Focus.folds(m, lines)
    compare(f.above[2], 1)        // "Morning notes." (the blank line is not counted)
    compare(f.above[8], 1)        // "# Thesis #thesis"
    compare(f.above[11], 1)       // "- [ ] read ch.2"
    compare(f.above[3], 0)
    compare(f.below[12], 0)       // only blank lines after it: no fold
    var g = Focus.folds([false, true, false, false], ["a", "b", "c", "d"])
    compare(g.above[1], 1); compare(g.below[1], 2)
  }

  function test_what_is_shown_only_grows_while_typing() {
    var prev = [false, true, true, false]
    // A line changed in the view, and one added after it: both shown.
    compare(Focus.carry(prev, 2, 1, 2), [false, true, true, true, false])
    // A line only added under a shown one, or above one: shown.
    compare(Focus.carry(prev, 3, 0, 1), [false, true, true, true, false])
    compare(Focus.carry(prev, 1, 0, 1), [false, true, true, true, false])
    // Added between folded lines: stays folded (an edit made elsewhere).
    compare(Focus.carry([true, false, false], 2, 0, 1), [true, false, false, false])
    // A line removed: the rest keep theirs.
    compare(Focus.carry(prev, 2, 1, 0), [false, true, false])
  }

  function test_the_tag_a_line_is_in() {
    compare(Focus.tagAt(day, 3), "studio")
    compare(Focus.tagAt(day, 5), "studio")
    compare(Focus.tagAt(day, 8), "studio")      // a box's own tag first
    compare(Focus.tagAt(day, 10), "thesis")
    compare(Focus.tagAt(day, 12), "studio")
    compare(Focus.tagAt(day, 0), "")
  }
}
