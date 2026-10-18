import QtQuick
import QtTest
import "../plugin-page/Threads.js" as T

// A sent block keeps its conversation when its words change (Threads.js):
// the conversation rides on the block's lines through every edit in the
// page, any kind of line, and is kept by the lines' words.
TestCase {
  name: "Threads"

  function lines(s) { return s.split("\n") }

  function test_a_reworded_line_keeps_its_conversation() {
    var was = lines("Should I buy an e-scooter?\n\nOther prose.")
    var now = lines("Should I buy an e-scooter in Linz, or a bike?\n\nOther prose.")
    compare(T.carry(was, now, { 0: "abc" }), { 0: "abc" })
  }

  function test_lines_added_above_move_it_with_its_block() {
    var was = lines("Should I buy one?\n\nMore.")
    var now = lines("A new first line.\n\nShould I buy one?\n\nMore.")
    compare(T.carry(was, now, { 0: "abc" }), { 2: "abc" })
  }

  function test_a_box_keeps_it_through_its_facts_and_its_words() {
    var was = lines("- [ ] read the paper")
    var now = lines("- [x] read the whole paper ✅ 2026-10-18")
    compare(T.carry(was, now, { 0: "abc" }), { 0: "abc" })
  }

  function test_a_deleted_block_lets_it_go() {
    var was = lines("Question?\n\nOther.")
    var now = lines("Other.")
    compare(T.carry(was, now, { 0: "abc" }), {})
  }

  function test_found_on_any_line_of_its_block() {
    var map = { 3: "abc" }
    compare(T.find(map, { start: 2, end: 5 }), "abc")
    compare(T.find(map, { start: 0, end: 2 }), "")
  }

  function test_pinned_once() {
    var map = {}
    verify(T.pin(map, { start: 4, end: 6 }, "abc"))
    verify(!T.pin(map, { start: 4, end: 6 }, "def"))
    compare(map, { 4: "abc" })
  }

  function test_kept_by_words_and_restored() {
    var ls = lines("- [ ] read the paper ⏳ 2026-10-20\n\nShould I go?")
    var recs = T.serialize({ 0: "abc", 2: "def" }, ls)
    compare(recs.length, 2)
    var back = lines("A line added in Obsidian.\n\n- [x] read the paper\n\nShould I go?")
    compare(T.restore(recs, back), { 2: "abc", 4: "def" })
    compare(T.restore(recs, lines("Reworded elsewhere?")), {})
  }
}
