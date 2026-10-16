import QtQuick
import QtTest
import "../plugin-page/Task.js" as Task

// A line is found again by its words, whatever facts it now carries — the
// one way every surface looks for it (docs/tasks.md). Ticking from the
// dashboard used to match the exact words, so a line that ended in a space
// could be dropped but never ticked.
TestCase {
  name: "Tasks"

  function test_found_where_it_was() {
    compare(Task.findWords(["a", "- [ ] read ch.7", "b"], 1, "read ch.7"), 1)
  }

  function test_found_after_lines_moved() {
    var lines = ["new line", "a", "- [ ] other", "- [ ] read ch.7"]
    compare(Task.findWords(lines, 2, "read ch.7"), 3)   // line 2 is now a different task
  }

  function test_found_whatever_its_state_or_facts() {
    compare(Task.findWords(["- [x] read ch.7"], 0, "read ch.7"), 0)
    compare(Task.findWords(["- [-] read ch.7 ❌ 2026-10-17"], 0, "read ch.7"), 0)
    compare(Task.findWords(["- [ ] read ch.7 ⏳ 2026-10-18"], 0, "read ch.7"), 0)
    compare(Task.findWords(["- [ ] read ch.7 again"], 0, "read ch.7"), -1)
  }

  function test_a_line_that_ends_in_a_space() {
    // The list reads the words trimmed; the line on disk keeps its space.
    compare(Task.findWords(["- [ ] this is a checkbox "], 0, "this is a checkbox"), 0)
    compare(Task.setState("- [ ] this is a checkbox ", "x"), "- [x] this is a checkbox ")
  }

  function test_text_with_regex_and_dollar_signs() {
    var t = "pay $5 (cash) for [x]"
    compare(Task.findWords(["- [ ] " + t], 0, t), 0)
    compare(Task.setState("- [ ] " + t, "x"), "- [x] " + t)
  }
}
