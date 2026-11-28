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

  // Making a project (2026-10-22).
  function test_what_may_be_made() {
    verify(Tags.canMake("thesis") && Tags.canMake("msc/thesis"))
    verify(!Tags.canMake("1") && !Tags.canMake("") && !Tags.canMake("-x"))
    verify(Tags.isProject(projects, "DTM") && !Tags.isProject(projects, "thesis"))
  }

  function test_the_sidebar_field() {
    compare(Tags.fromField("Master Thesis #thesis", projects), { name: "Master Thesis", tag: "thesis", taken: false })
    compare(Tags.fromField("  Master   Thesis ", projects), { name: "Master Thesis", tag: "master-thesis", taken: false })
    compare(Tags.fromField("Design Theory & Methods", projects).tag, "design-theory-methods")
    compare(Tags.fromField("#dtm", projects), { name: "dtm", tag: "dtm", taken: true })
    compare(Tags.fromField("", projects).tag, "")
    compare(Tags.fromField("Über", projects).tag, "ber")
  }
  // Reaching a project by its letters (plan.md item 19).
  property var reachList: [{ tag: "respro", name: "Research Proficiency" }, { tag: "studio", name: "Design Studio" },
                           { tag: "dtm", name: "Design Theory & Methods" }, { tag: "intsem", name: "Interdisciplinary Seminar" },
                           { tag: "thesis", name: "Master Thesis" }]
  function tags(l) { return l.map(function (p) { return p.tag }) }

  function test_reach_tag_then_word_then_within() {
    compare(tags(Tags.reach(reachList, "th")), ["thesis", "dtm"])
    compare(tags(Tags.reach(reachList, "#TH")), ["thesis", "dtm"])     // the # that started it is no letter
    compare(tags(Tags.reach(reachList, "design")), ["studio", "dtm"])  // the list's order inside a group
    compare(tags(Tags.reach(reachList, "sem")), ["intsem"])
    compare(tags(Tags.reach(reachList, "")), tags(reachList))
    compare(Tags.reach(reachList, "zzz"), [])
    // Accents aside, both ways (2026-11-28).
    compare(tags(Tags.reach([{ tag: "fhoo", name: "FHOÖ Linz" }], "fhoö")), ["fhoo"])
    compare(tags(Tags.reach([{ tag: "uni", name: "Universität Wien" }], "universitat")), ["uni"])
  }

  function test_by_use_most_reached_first_ties_as_listed() {
    var now = 100 * 86400
    var uses = { thesis: [now - 10, now - 20, now - 30], dtm: [now - 40], studio: [now - 29 * 86400, now - 30 * 86400] }
    // studio's uses are older than four weeks: it keeps its place.
    compare(tags(Tags.byUse(reachList, uses, now)), ["thesis", "dtm", "respro", "studio", "intsem"])
    compare(tags(Tags.byUse(reachList, {}, now)), tags(reachList))
  }

  function test_used_counts_and_forgets() {
    var now = 100 * 86400
    var u = Tags.used({ old: [now - 40 * 86400], thesis: [now - 5] }, "thesis", now)
    compare(u.thesis, [now - 5, now])
    verify(u.old === undefined)
  }
}
