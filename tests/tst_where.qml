import QtQuick
import QtTest
import "../plugin-page/Where.js" as Where

// The path Ctrl+Shift+C copies: the file's line, not the line drawn.
TestCase {
  name: "Where"

  function test_the_cursors_line() {
    compare(Where.at("/n.md", "", "one\ntwo\nthree", 0), "/n.md:1")
    compare(Where.at("/n.md", "", "one\ntwo\nthree", 4), "/n.md:2")
    compare(Where.at("/n.md", "", "one\ntwo\nthree", 13), "/n.md:3")   // at the very end
    compare(Where.at("/n.md", "", "", 0), "/n.md:1")
  }

  // The frontmatter and the agent link line never enter the editor, but
  // they are lines of the file: an agent opening it must land on the line.
  function test_counts_what_the_page_hides() {
    var before = "---\nagent: false\n---\n[[agents/longhand/daily/2026.11.03|agent]]\n\n"
    compare(Where.at("/n.md", before, "# Day\n- [ ] essay", 0), "/n.md:6")
    compare(Where.at("/n.md", before, "# Day\n- [ ] essay", 6), "/n.md:7")
  }

  function test_lines_selected() {
    var body = "a\nb\nc\nd"
    compare(Where.at("/n.md", "", body, 2, 5), "/n.md:2-3")
    compare(Where.at("/n.md", "", body, 0, 4), "/n.md:1-2")   // ends at c's start: c is not taken
    compare(Where.at("/n.md", "", body, 2, 3), "/n.md:2")     // inside one line
    compare(Where.at("/n.md", "", body, 3, 3), "/n.md:2")     // nothing selected
  }
}
