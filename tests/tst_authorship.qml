import QtQuick
import QtTest
import "../plugin-page/Authorship.js" as A

// Who made a line (docs/agent.md, "Who made it"): kept through every edit
// the page sees, by line, for boxes and bullets.
TestCase {
  name: "Authorship"

  function lines(s) { return s.split("\n") }

  function test_only_boxes_and_bullets_carry_it() {
    verify(A.isListLine("- [ ] a box"))
    verify(A.isListLine("  - a bullet under it"))
    verify(!A.isListLine("A line of prose."))
    verify(!A.isListLine("# A heading"))
  }

  function test_key_is_the_words_alone() {
    compare(A.key("- [ ] draft the intro"), A.key("- [x] draft the intro ✅ 2026-10-17"))
    compare(A.key("- [ ] draft the intro ⏳ 2026-10-20 🔼"), A.key("- [ ] draft the intro"))
    compare(A.key("\t- [ ] draft the intro"), A.key("- [ ] draft the intro"))
    verify(A.key("- [ ] draft the intro") !== A.key("- [ ] draft the outro"))
  }

  function test_facts_do_not_change_who_made_it() {
    var was = lines("# Essay\n- [ ] draft the intro\nprose")
    var now = lines("# Essay\n- [x] draft the intro ✅ 2026-10-17\nprose")
    compare(A.carry(was, now, { 1: "agent" }), { 1: "agent" })
    now = lines("# Essay\n- [ ] draft the intro ⏳ 2026-10-20\nprose")
    compare(A.carry(was, now, { 1: "agent" }), { 1: "agent" })
  }

  function test_the_persons_words_make_it_together() {
    var was = lines("- [ ] draft the intro\n- [ ] mine")
    var now = lines("- [ ] draft the introduction\n- [ ] mine")
    compare(A.carry(was, now, { 0: "agent" }), { 0: "together" })
    // and together stays together
    compare(A.carry(now, lines("- [ ] draft the full introduction\n- [ ] mine"), { 0: "together" }), { 0: "together" })
  }

  function test_lines_above_and_below_move_it_along() {
    var was = lines("- [ ] the agent's\n- [ ] mine")
    var now = lines("A new first line.\n\n- [ ] the agent's\n- [ ] mine")
    compare(A.carry(was, now, { 0: "agent" }), { 2: "agent" })
    compare(A.carry(now, was, { 2: "agent" }), { 0: "agent" })
  }

  function test_a_moved_line_keeps_who_made_it() {
    var was = lines("- [ ] the agent's\n- [ ] mine\n- [ ] also mine")
    var now = lines("- [ ] mine\n- [ ] the agent's\n- [ ] also mine")
    compare(A.carry(was, now, { 0: "agent" }), { 1: "agent" })
  }

  function test_split_and_join() {
    // Enter in the middle of the agent's line: the first half was edited,
    // the second half is new, and the person's.
    var was = lines("- [ ] read the paper and write notes")
    var now = lines("- [ ] read the paper\n- [ ] and write notes")
    compare(A.carry(was, now, { 0: "agent" }), { 0: "together" })
    // Two lines joined into one: the joined line was edited.
    compare(A.carry(now, lines("- [ ] read the paper and write notes"), { 1: "agent" }), { 0: "together" })
  }

  function test_deleted_is_gone() {
    var was = lines("- [ ] mine\n- [ ] the agent's\n- [ ] also mine")
    compare(A.carry(was, lines("- [ ] mine\n- [ ] also mine"), { 1: "agent" }), {})
  }

  function test_turned_into_prose_is_the_persons() {
    var was = lines("- [ ] the agent's")
    compare(A.carry(was, lines("the agent's"), { 0: "agent" }), {})
  }

  function test_kept_and_found_again() {
    var text = lines("# Essay\n- [ ] draft the intro\n  - find the quote\n- [ ] mine")
    var map = { 1: "agent", 2: "together" }
    var recs = A.serialize(map, text)
    compare(recs.length, 2)
    // the note read again, facts changed meanwhile: found again by words
    var again = lines("# Essay\n- [x] draft the intro ✅ 2026-10-17\n  - find the quote\n- [ ] mine")
    compare(A.restore(recs, again), { 1: "agent", 2: "together" })
    // edited elsewhere (Obsidian): not found, so the person's
    compare(A.restore(recs, lines("# Essay\n- [ ] draft a better intro\n  - find the quote\n- [ ] mine")), { 2: "together" })
  }

  function test_the_same_words_twice() {
    var text = lines("- [ ] read\n- [ ] read")
    var recs = A.serialize({ 1: "agent" }, text)
    // one record claims one line, not both
    var got = A.restore(recs, text)
    compare(Object.keys(got).length, 1)
  }
}
