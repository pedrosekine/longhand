import QtQuick
import QtTest
import "../plugin-page/Switch.js" as Switch

// The switcher's matching (Switch.js, the switcher pass, 2026-11-28): every
// word somewhere, accents aside, as the sidebar's find; days by their
// names; the matched letters marked.
TestCase {
  name: "Switch"

  property var paths: [
    "projects/thesis/meeting-notes.md", "projects/thesis/Methods.md", "human/Daily/2026-11-02.md",
    "human/Daily/2026-11-20.md", "human/Daily/README.md", "human/Reading/moser2026identifying.pdf",
    "agents/longhand/thesis.md", "human/Über alles.md", "zeta/thesis.md", "alfa/thesis.md", "human/shot.png"
  ]
  function opts(extra) {
    var o = { daily: "human/Daily", agentRoot: "agents/longhand", isDay: function (s) { return /^\d{4}-\d\d-\d\d$/.test(s) } }
    for (var k in extra) o[k] = extra[k]
    return o
  }
  function rels(items) { return items.map(function (i) { return i.path }) }

  function test_every_word_somewhere() {
    compare(rels(Switch.files(paths, "thesis notes", opts({}))), ["projects/thesis/meeting-notes.md"])
  }

  function test_accents_aside_both_ways() {
    compare(rels(Switch.files(paths, "uber", opts({}))), ["human/Über alles.md"])
    compare(rels(Switch.files(paths, "ÜBER", opts({}))), ["human/Über alles.md"])
  }

  function test_name_first_then_shorter_then_a_to_z() {
    // "thesis" in the name beats "thesis" only in the folder; equal names A to Z; never the agent's.
    var got = rels(Switch.files(paths, "thesis", opts({})))
    compare(got.slice(0, 2), ["alfa/thesis.md", "zeta/thesis.md"])
    verify(got.indexOf("agents/longhand/thesis.md") < 0)
    verify(got.indexOf("projects/thesis/Methods.md") > 1)
  }

  function test_days_newest_first_and_only_by_name() {
    var got = Switch.files(paths, "daily", opts({}))
    var days = got.filter(function (i) { return i.date !== "" }).map(function (i) { return i.date })
    compare(days, ["2026-11-20", "2026-11-02"])
    var readme = got.filter(function (i) { return i.path === "human/Daily/README.md" })[0]
    compare(readme.date, "")
    compare(readme.hint, "note")
  }

  function test_a_paper_by_its_name() {
    var names = { "human/Reading/moser2026identifying.pdf": { name: "Moser et al. 2026", title: "Identifying what matters" } }
    var got = Switch.files(paths, "matters", opts({ names: names }))
    compare(rels(got), ["human/Reading/moser2026identifying.pdf"])
    compare(got[0].title, "Moser et al. 2026")
    compare(got[0].sub, "Identifying what matters")
    compare(got[0].hint, "pdf")
  }

  function test_at_most_six() {
    var many = []
    for (var i = 0; i < 20; i++) many.push("n/note" + i + ".md")
    compare(Switch.files(many, "note", opts({})).length, 6)
  }

  function test_views_by_any_word() {
    var v = { title: "export as a PDF", sub: "this section", keywords: "export pdf print hand in" }
    verify(Switch.viewMatches(v, "print"))
    verify(Switch.viewMatches(v, "pdf section"))
    verify(!Switch.viewMatches(v, "pdf calendar"))
  }

  function test_marked_and_escaped() {
    compare(Switch.marked("Über <alles>", "uber"), "<b>Über</b> &lt;alles&gt;")
    compare(Switch.marked("read the chapter", "chap read"), "<b>read</b> the <b>chap</b>ter")
    compare(Switch.marked("nothing", ""), "nothing")
    compare(Switch.firstSpan("so - [ ] read **chapter**", "chapter"), { a: 16, b: 23 })
    compare(Switch.firstSpan("plain", "zzz"), null)
  }
}
