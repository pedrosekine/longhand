import QtQuick
import QtTest
import "../plugin-page/Outside.js" as Outside

// Outside: a note changed on disk while the page has it open, taken in as
// one edit, beside the words still waiting to be saved.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_outside.qml
Item {
  TestCase {
    name: "Outside"

    function result(base, ours, theirs) {
      var t = Outside.take(base, ours, theirs)
      return { text: Outside.applied(ours, t.edit), kept: t.kept, clash: t.clash, edit: t.edit }
    }

    function test_the_span() {
      compare(Outside.span("abc", "abc"), null)
      compare(Outside.span("abc", "abXc"), { a: 2, b: 2, s: "X" })
      compare(Outside.span("abc", "ac"), { a: 1, b: 2, s: "" })
      compare(Outside.span("one\ntwo\n", "zero\none\ntwo\n"), { a: 0, b: 0, s: "zero\n" })
    }

    function test_nothing_waiting_takes_theirs_as_one_span() {
      var r = result("one\ntwo\n", "one\ntwo\n", "one\ntwo\nthree\n")
      compare(r.text, "one\ntwo\nthree\n")
      compare(r.edit, { a: 8, b: 8, s: "three\n" }, "only what changed, so the cursor is carried, not reset")
      verify(!r.kept && !r.clash)
    }

    function test_the_same_text_is_no_news() {
      var r = result("a\n", "a\nb", "a\nb")
      compare(r.edit, null, "theirs is ours already (the other machine had the same words)")
    }

    function test_words_waiting_are_kept_beside_a_change_elsewhere() {
      // Typed at the end, not yet saved; a line added at the top elsewhere.
      var r = result("one\ntwo\n", "one\ntwo\nmine", "zero\none\ntwo\n")
      compare(r.text, "zero\none\ntwo\nmine")
      verify(r.kept && !r.clash)
      // And the other way: typed at the top, theirs at the end.
      r = result("one\ntwo\n", "mine one\ntwo\n", "one\ntwo\nthree\n")
      compare(r.text, "mine one\ntwo\nthree\n", "theirs moved by what ours added before it")
      verify(r.kept)
    }

    function test_spans_that_only_touch_are_apart() {
      // Ours typed at the end of "one"; theirs changed "two" right after.
      var r = result("one\ntwo", "one!\ntwo", "one\nTWO")
      compare(r.text, "one!\nTWO")
      verify(r.kept)
    }

    function test_the_same_place_is_a_clash() {
      // Both wrote at the end: whose words come first is not known.
      var r = result("one\n", "one\nmine", "one\ntheirs")
      verify(r.clash)
      compare(r.text, "one\ntheirs", "theirs shown; one undo gives ours back")
      // Both changed one word.
      r = result("a cat sat", "a dog sat", "a bat sat")
      verify(r.clash)
      compare(r.text, "a bat sat")
    }

    function test_theirs_unchanged_from_base_changes_nothing() {
      var r = result("one", "one more", "one")
      compare(r.edit, null, "the disk still has what we wrote: our words wait for their save")
    }
  }
}
