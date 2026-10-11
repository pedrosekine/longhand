import QtQuick
import QtTest
import "../plugin-page/Tasks.js" as Tasks

// Ticking from the what's-next list lands on the right line even after the
// note changed.
TestCase {
  name: "Tasks"

  function test_found_where_it_was() {
    compare(Tasks.find(["a", "- [ ] read ch.7", "b"], 1, "read ch.7", false), 1)
  }

  function test_found_after_lines_moved() {
    var lines = ["new line", "a", "- [ ] other", "- [ ] read ch.7"]
    compare(Tasks.find(lines, 2, "read ch.7", false), 3)   // line 2 is now a different task
  }

  function test_gone_or_already_ticked() {
    compare(Tasks.find(["- [x] read ch.7"], 0, "read ch.7", false), -1)
    compare(Tasks.find(["- [x] read ch.7"], 0, "read ch.7", true), 0)
    compare(Tasks.find(["- [ ] read ch.7 again"], 0, "read ch.7", false), -1)
  }

  function test_text_with_regex_and_dollar_signs() {
    var t = "pay $5 (cash) for [x]"
    var i = Tasks.find(["- [ ] " + t], 0, t, false)
    compare(i, 0)
    compare(Tasks.flip("- [ ] " + t, true), "- [x] " + t)
  }
}
