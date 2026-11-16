import QtQuick
import QtTest
import "../plugin-page/ProjectView.js" as PV

// A project's view: open loops, then the days (writing and reading
// together), then the shelf and the files folded (2026-11-16).
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

  function kinds(rows) { return rows.map(function (r) { return r.kind }) }

  function test_open_first_then_the_days_then_folds() {
    var r = PV.rows(sections, papers, [], {})
    compare(kinds(r), ["cap", "box", "question", "question", "cap", "read", "read", "section", "section", "fold", "fold"])
    compare(r[0].text, "OPEN · 3")
    compare(r[1].text, "Finish the Themenvorschlag #thesis")
    compare(r[2].label, "Moser et al. 2026")
  }

  function test_reading_stands_by_its_day() {
    var days = PV.rows(sections, papers, [], {}).filter(function (x) { return x.kind === "read" || x.kind === "section" })
    // 14 Nov holds only an open box, already in OPEN: not twice.
    compare(days.map(function (x) { return x.day }), ["2026-11-16", "2026-11-15", "2026-11-10", "2026-11-05"])
    compare(days[1].said, "10 highlights, 6 questions")
    compare(days[0].said, "2 highlights")
    compare([days[0].title, days[1].title], ["Identifying environmental stress", ""])   // the title once
  }

  function test_a_missing_paper_is_left_out() {
    var r = PV.rows(sections, papers, [], {})
    verify(!r.some(function (x) { return x.paper && x.paper.pdf === "lit/gone.pdf" }))
  }

  function test_folds_open_with_their_rows() {
    var r = PV.rows(sections, papers, [{ name: "Syllabus", path: "/v/projects/x/docs/Syllabus.pdf" }], { shelf: true, files: true })
    var shelf = r.filter(function (x) { return x.kind === "paper" })
    compare(shelf.map(function (x) { return x.label }), ["fox2011", "Zeile et al. 2016"])
    compare(r.filter(function (x) { return x.kind === "doc" }).map(function (x) { return x.name }), ["proposal", "Syllabus"])
    compare(r.filter(function (x) { return x.kind === "fold" }).map(function (x) { return x.text }), ["Shelf · 2 not begun", "Files · 2"])
  }

  function test_a_long_open_band_folds() {
    var many = []
    for (var i = 0; i < 9; i++) many.push({ id: "h" + i, page: 1, text: "q" + i, note: "" })
    var ps = [{ pdf: "a.pdf", title: "a", kind: "paper", cite: {}, days: { "2026-11-15": { h: 0, q: 9 } }, questions: many }]
    var r = PV.rows([], ps, [], {})
    compare(r.filter(function (x) { return x.kind === "question" }).length, 5)
    compare(r[6].text, "4 more open")
    r = PV.rows([], ps, [], { open: true })
    compare(r.filter(function (x) { return x.kind === "question" }).length, 9)
    compare(r[10].text, "fewer")
    compare(PV.rows([], [{ pdf: "b.pdf", kind: "paper", cite: {}, days: { "2026-11-15": { h: 0, q: 6 } },
                           questions: many.slice(0, 6) }], [], {}).filter(function (x) { return x.kind === "question" }).length, 6)
  }

  function test_nothing_open_no_caps() {
    var r = PV.rows([sections[2]], [], [], {})
    compare(kinds(r), ["section"])
  }

  function test_steps_skip_captions_and_hold_their_row() {
    var r = PV.rows(sections, papers, [], {})
    compare(PV.step(r, "", 1), r[1].key)
    compare(PV.step(r, r[3].key, 1), r[5].key)        // over the "BY DAY" caption
    compare(PV.step(r, r[1].key, -1), r[1].key)       // the top holds
    compare(PV.find(r, "nope").key, r[1].key)
    compare(PV.find(r, r[7].key).kind, "section")
  }
}
