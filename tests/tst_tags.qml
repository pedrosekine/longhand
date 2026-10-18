import QtQuick
import QtTest
import "../plugin-page/Tags.js" as Tags

// `#` offers the tags that exist (Tags.js).
TestCase {
  name: "Tags"

  property var projects: [{ tag: "intsem", name: "Interdisciplinary Seminar" }, { tag: "dtm", name: "Design Theory & Methods" }]
  property var tasks: [{ tags: ["thesis"] }, { tags: ["thesis", "intsem"] }, { tags: ["admin"] }]

  function test_projects_first_then_by_use() {
    var k = Tags.known(projects, tasks, "A note #thesis and #Move")
    compare(k.map(function (t) { return t.tag }), ["intsem", "dtm", "thesis", "admin", "Move"])
    verify(k[0].project && !k[2].project)
  }

  function test_suggest_starts_first_and_by_project_name() {
    var k = Tags.known(projects, tasks, "")
    compare(Tags.suggest(k, "t").map(function (t) { return t.tag }), ["thesis", "intsem", "dtm"])
    compare(Tags.suggest(k, "semi").map(function (t) { return t.tag }), ["intsem"])
    compare(Tags.suggest(k, "design").map(function (t) { return t.tag }), ["dtm"])
  }

  function test_nothing_to_offer() {
    var k = Tags.known(projects, tasks, "")
    compare(Tags.suggest(k, ""), [])                // a heading's `# ` never flashes a list
    compare(Tags.suggest(k, "thesis"), [])          // already a tag: Enter is a new line
    compare(Tags.suggest(k, "INTSEM"), [])
    compare(Tags.suggest(k, "zzz"), [])             // a new tag is fine, nothing to offer
  }

  function test_tags_in_text() {
    compare(Tags.inText("#a b #c/d e#f #g-h"), ["a", "c/d", "g-h"])
  }
}
