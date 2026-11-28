import QtQuick
import QtTest
import "../plugin-page/ProjectView.js" as PV

// A project's view: its page, open loops, then this week under its page
// (writing and reading together), the days before folded, then the shelf
// and the files folded (2026-11-16; this week, 2026-11-21).
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_projectview.qml
TestCase {
  name: "ProjectView"

  readonly property var sections: [
    { date: "2026-11-14", line: 2, heading: "", title: "Finish the Themenvorschlag",
      boxes: [{ line: 2, text: "Finish the Themenvorschlag #thesis 📅 2026-11-16 ^d61", state: " " }] },
    { date: "2026-11-10", line: 2, heading: "", title: "Revise it",
      boxes: [{ line: 2, text: "Revise it #thesis ✅ 2026-11-14", state: "x" }] },
    { date: "2026-11-05", line: 4, heading: "# Bernd Meeting #thesis", title: "Bernd Meeting", boxes: [] }
  ]
  readonly property var papers: [
    { pdf: "lit/moser2026.pdf", title: "moser2026", kind: "paper",
      cite: { authors: "Moser et al.", year: "2026", title: "Identifying environmental stress" },
      days: { "2026-11-15": { h: 10, q: 6 }, "2026-11-16": { h: 2, q: 0 } },
      questions: [{ id: "h3", page: 1, text: "urban cycling", note: "" }, { id: "h13", page: 2, text: "Getis-Ord Gi", note: "what?" }] },
    { pdf: "lit/zeile2016.pdf", title: "zeile2016", kind: "paper", cite: { authors: "Zeile et al.", year: "2016", title: "Urban emotions" }, days: {}, questions: [] },
    { pdf: "lit/fox2011.pdf", title: "fox2011", kind: "paper", cite: {}, days: {}, questions: [] },
    { pdf: "proposal/proposal.pdf", title: "proposal", kind: "document", days: {}, questions: [] },
    { pdf: "lit/gone.pdf", title: "gone", kind: "paper", missing: true, days: { "2026-11-01": { h: 1, q: 0 } }, questions: [] }
  ]

  // A Saturday: its week is Monday 16 to Sunday 22 November.
  readonly property var at: ({ today: "2026-11-21", name: "Master Thesis" })
  function at2(extra) { return Object.assign({}, at, extra || {}) }
  function kinds(rows) { return rows.map(function (r) { return r.kind }) }

  function test_page_open_this_week_then_folds() {
    var r = PV.rows(sections, papers, [], at)
    compare(kinds(r), ["page", "cap", "box", "question", "question", "cap", "page", "read", "fold", "fold", "fold"])
    compare([r[0].key, r[0].act], ["page:project", "listPage"])
    compare(r[1].text, "OPEN · 3")
    compare(r[2].text, "Finish the Themenvorschlag #thesis")
    compare(r[3].label, "Moser et al. 2026")
    compare(r[5].text, "THIS WEEK · 16–22 NOV")
    compare([r[6].key, r[6].act], ["page:week", "listWeek"])
  }

  function test_the_week_page_says_what_is_in_it() {
    var r = PV.rows(sections, papers, [], at)
    compare(r[6].said, "1 paper read · 2 questions to bring")
    // A section of the week with boxes ticked: counted as done.
    var done = [{ date: "2026-11-17", line: 2, heading: "", title: "Ask Bernd", done: 2, open: 0,
                  boxes: [{ line: 2, text: "Ask Bernd #thesis", state: "x" }, { line: 3, text: "Book the room #thesis", state: "x" }] }]
    compare(PV.rows(done, [], [], at)[2].said, "2 done")
    compare(PV.rows([sections[2]], [], [], at)[2].said, "nothing written or read yet")
  }

  function test_only_this_week_shows_the_rest_folds_by_name() {
    var r = PV.rows(sections, papers, [], at)
    var week = r.filter(function (x) { return x.kind === "read" || x.kind === "section" })
    compare(week.map(function (x) { return x.day }), ["2026-11-16"])
    compare(week[0].said, "2 highlights")
    var fold = r.filter(function (x) { return x.fold === "earlier" })[0]
    compare(fold.text, "Earlier · 3 days · Bernd Meeting")
    r = PV.rows(sections, papers, [], at2({ earlier: true }))
    var all = r.filter(function (x) { return x.kind === "read" || x.kind === "section" })
    // 14 Nov holds only an open box, already in OPEN: not twice.
    compare(all.map(function (x) { return x.day }), ["2026-11-16", "2026-11-15", "2026-11-10", "2026-11-05"])
    compare(all[1].said, "10 highlights, 6 questions")
    compare(r.filter(function (x) { return x.fold === "earlier" })[0].text, "Earlier · 3 days")
  }

  function test_the_week_runs_monday_to_sunday() {
    compare(PV.weekOf("2026-11-21"), { from: "2026-11-16", to: "2026-11-22", said: "16–22 Nov" })
    compare(PV.weekOf("2026-11-16").from, "2026-11-16")
    compare(PV.weekOf("2026-11-22").to, "2026-11-22")
    compare(PV.weekOf("2026-12-02"), { from: "2026-11-30", to: "2026-12-06", said: "30 Nov – 6 Dec" })
    compare(PV.weekOf("2027-01-01").from, "2026-12-28")
  }

  function test_a_missing_paper_is_left_out() {
    var r = PV.rows(sections, papers, [], at2({ earlier: true }))
    verify(!r.some(function (x) { return x.paper && x.paper.pdf === "lit/gone.pdf" }))
  }

  function test_folds_open_with_their_rows() {
    var r = PV.rows(sections, papers, [{ name: "Syllabus", path: "/v/projects/x/docs/Syllabus.pdf" }], at2({ shelf: true, files: true }))
    var shelf = r.filter(function (x) { return x.kind === "paper" })
    compare(shelf.map(function (x) { return x.label }), ["fox2011", "Zeile et al. 2016"])
    compare(r.filter(function (x) { return x.kind === "doc" }).map(function (x) { return x.name }), ["proposal", "Syllabus"])
    compare(r.filter(function (x) { return x.kind === "fold" }).map(function (x) { return x.text }),
            ["Earlier · 3 days · Bernd Meeting", "Shelf · 2 not begun", "Files · 2"])
  }

  function test_a_long_open_band_folds() {
    var many = []
    for (var i = 0; i < 9; i++) many.push({ id: "h" + i, page: 1, text: "q" + i, note: "" })
    var ps = [{ pdf: "a.pdf", title: "a", kind: "paper", cite: {}, days: { "2026-11-15": { h: 0, q: 9 } }, questions: many }]
    var r = PV.rows([], ps, [], at)
    compare(r.filter(function (x) { return x.kind === "question" }).length, 5)
    compare(r[7].text, "4 more open")
    r = PV.rows([], ps, [], at2({ open: true }))
    compare(r.filter(function (x) { return x.kind === "question" }).length, 9)
    compare(r[11].text, "fewer")
    compare(PV.rows([], [{ pdf: "b.pdf", kind: "paper", cite: {}, days: { "2026-11-15": { h: 0, q: 6 } },
                           questions: many.slice(0, 6) }], [], at).filter(function (x) { return x.kind === "question" }).length, 6)
  }

  function test_papers_read_the_same_day_the_last_read_first() {
    // Listed Z to A by file, as they come; saved Fox last, Resch first.
    var ps = [
      { pdf: "resch.pdf", kind: "paper", cite: { authors: "Resch et al.", year: "2020" }, last: "2026-11-20", saved: 100,
        days: { "2026-11-20": { h: 6, q: 0 } }, questions: [] },
      { pdf: "moser.pdf", kind: "paper", cite: { authors: "Moser et al.", year: "2023" }, last: "2026-11-20", saved: 200,
        days: { "2026-11-19": { h: 1, q: 0 }, "2026-11-20": { h: 6, q: 0 } }, questions: [] },
      { pdf: "fox.pdf", kind: "paper", cite: { authors: "Fox et al.", year: "2011" }, last: "2026-11-20", saved: 300,
        days: { "2026-11-20": { h: 5, q: 0 } }, questions: [] },
      { pdf: "zeile.pdf", kind: "paper", cite: { authors: "Zeile et al.", year: "2016" }, last: "2026-11-19", saved: 50,
        days: { "2026-11-19": { h: 4, q: 0 } }, questions: [] }]
    var read = PV.rows([], ps, [], at).filter(function (x) { return x.kind === "read" })
    compare(read.map(function (x) { return x.day + " " + x.label }),
            ["2026-11-20 Fox et al. 2011", "2026-11-20 Moser et al. 2023", "2026-11-20 Resch et al. 2020",
             // Moser's earlier day has no time of its own: after the one known.
             "2026-11-19 Zeile et al. 2016", "2026-11-19 Moser et al. 2023"])
  }

  function test_nothing_open_the_week_and_its_page_still() {
    compare(kinds(PV.rows([sections[2]], [], [], at)), ["page", "cap", "page", "fold"])
  }

  function test_nothing_at_all_only_its_pages() {
    var kinds = function (r) { return r.map(function (x) { return x.kind + (x.page ? ":" + x.page : "") }).join(" ") }
    compare(kinds(PV.rows([], [], [], at)), "page:project cap page:week")
    compare(kinds(PV.rows([], [papers[4]], [], at)), "page:project cap page:week")     // a missing paper is nothing
  }

  // A section's own boxes are in OPEN, each with its box, so Enter lands
  // on that line and not the first (2026-11-28).
  function test_a_sections_own_boxes_are_open_each_its_own() {
    var sec = { date: "2026-11-15", line: 2, heading: "# Seminar #thesis", title: "Seminar",
                tasks: [{ line: 3, text: "first", state: "x" }, { line: 4, text: "second", state: " " }, { line: 5, text: "third", state: " " }] }
    var open = PV.rows([sec], [], [], at).filter(function (x) { return x.kind === "box" })
    compare(open.map(function (x) { return x.box.text }), ["second", "third"])
    compare(open[1].key, "b:2026-11-15:5")
  }
  function test_the_same_heading_twice_a_day_two_rows() {
    var a = { date: "2026-11-18", line: 2, heading: "# Meeting #thesis", title: "Meeting" }
    var b = { date: "2026-11-18", line: 9, heading: "# Meeting #thesis", title: "Meeting" }
    var keys = PV.rows([a, b], [], [], at).filter(function (x) { return x.kind === "section" }).map(function (x) { return x.key })
    compare(keys.length, 2)
    verify(keys[0] !== keys[1])
  }
  function test_steps_skip_captions_and_hold_their_row() {
    var r = PV.rows(sections, papers, [], at)
    compare(PV.step(r, "", 1), r[2].key)              // opens on what is open, not on the page
    compare(PV.find(r, "nope").key, r[2].key)
    compare(PV.step(r, r[2].key, -1), "page:project") // its page one key up
    compare(PV.step(r, "page:project", -1), "page:project")   // the top holds
    compare(PV.step(r, r[4].key, 1), "page:week")     // over the "THIS WEEK" caption
    compare(PV.find(r, r[7].key).kind, "read")
    compare(PV.find([r[0]], "").key, "page:project")  // a page when there is nothing else
  }
}
