import QtQuick
import QtTest
import "../plugin-page/Next.js" as Next

// What's next: the dashboard's rows, in the order they ask something of
// you (Next.js, moved out of Page.qml on 2026-10-30).
// "Now" is fixed: Tuesday 13 October 2026, 08:57.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_next.qml
TestCase {
  name: "Next"
  readonly property var now: new Date(2026, 9, 13, 8, 57, 30)
  readonly property var projects: [{ tag: "intsem", name: "Interdisciplinary Seminar" }]

  function sec(m, d, hh, mm) { return new Date(2026, m - 1, d, hh || 23, mm === undefined ? 59 : mm).getTime() / 1000 }
  function deadline(id, status, due, extra) {
    var d = { id: id, status: status, due: due, link: "[[2026.10.09#^d" + id + "]]", doneAt: 0, grade: "", title: "d" + id, project: "" }
    for (var k in extra) d[k] = extra[k]
    return d
  }
  function task(title, extra) {
    var t = { title: title, text: title, anchor: 0, away: "", when: "", due: "", kind: "task", priority: 0, age: 0, project: "", path: [], key: "" }
    for (var k in extra) t[k] = extra[k]
    return t
  }
  // A row as one word: what the eye reads down the list.
  function said(rows) {
    return rows.map(function (r) {
      return r.kind === "head" || r.kind === "month" ? r.kind + ":" + r.text
        : r.kind === "band" ? "band:" + r.text + (r.open ? "" : " ▸") + " " + r.count
        : r.kind === "deadline" ? "d" + r.deadline.id
        : r.kind === "task" ? r.task.title
        : r.kind === "shelf" || r.kind === "grading" ? r.kind + ":" + r.count
        : r.kind + ":" + r.item.id
    })
  }
  function state(extra) {
    var s = { deadlines: [], tasks: [], projects: projects, raised: [], proposals: [], showShelf: false, showGrading: false, now: now }
    for (var k in extra) s[k] = extra[k]
    return s
  }

  function test_nothing_is_nothing() {
    compare(Next.rows(state({})), [])
  }

  function test_due_late_first_closed_today_after() {
    var rows = Next.rows(state({ deadlines: [
      deadline(1, "open", sec(10, 16)),
      deadline(2, "open", sec(10, 10)),                                   // late: leads
      deadline(3, "done", sec(10, 12), { doneAt: sec(10, 13, 8, 0) }),     // closed today: stays, after
      deadline(4, "done", sec(10, 11), { doneAt: sec(10, 12, 9, 0) }),     // closed before today: owed a grade
      deadline(5, "open", sec(10, 20), { link: "" }),                      // no line yet
      deadline(6, "open", sec(11, 2)),
      deadline(7, "cancelled", sec(10, 9), { doneAt: sec(10, 13, 7, 0) }),
    ] }))
    compare(said(rows), ["head:DUE", "month:" + Qt.formatDate(new Date(2026, 9, 10), "MMMM"), "d2", "d1",
                         "month:" + Qt.formatDate(new Date(2026, 10, 2), "MMMM"), "d6",
                         "month:" + Qt.formatDate(new Date(2026, 9, 10), "MMMM"), "d7", "d3",
                         "head:NOT IN A NOTE YET", "d5", "grading:1"])
  }

  function test_boxes_by_what_they_ask() {
    var rows = Next.rows(state({ tasks: [
      task("bound one", { anchor: 9 }),                                    // listed as its deadline, never here
      task("read ch 3", { due: "2026-10-20" }),
      task("outline", { when: "2026-10-14" }),
      task("low, new", { priority: 0, age: 1 }),
      task("high, older", { priority: 2, age: 3 }),
      task("high, new", { priority: 2, age: 1 }),
      task("a seminar thought", { kind: "bullet", project: "intsem" }),
      task("a bike thought", { kind: "bullet", project: "bikes", path: ["Bikes, the long list"] }),
      task("loose", { kind: "bullet" }),
      task("gone quiet", { away: "quiet" }),
    ] }))
    compare(said(rows), ["head:DOING", "month:" + Qt.formatDate(new Date(2026, 9, 14), "MMMM"), "outline", "read ch 3",
                         "head:TO SCHEDULE", "high, new", "high, older", "low, new",
                         "head:Interdisciplinary Seminar", "a seminar thought",
                         "head:Bikes, the long list", "a bike thought",   // a tag the list does not know: its heading's name
                         "head:No project", "loose",
                         "shelf:1"])
    var band = rows.filter(function (r) { return r.kind === "head" && r.text === "Interdisciplinary Seminar" })[0]
    compare(band.tag, "#intsem")
    compare(rows.filter(function (r) { return r.kind === "task" && r.task.title === "a seminar thought" })[0].under, "Interdisciplinary Seminar")
  }

  function test_folded_bands_unfold() {
    var s = state({ tasks: [task("gone quiet", { away: "quiet" })],
                    deadlines: [deadline(4, "done", sec(10, 11), { doneAt: sec(10, 12, 9, 0) }),
                                deadline(8, "done", sec(10, 10), { doneAt: sec(10, 11, 9, 0), grade: "1" })],
                    showShelf: true, showGrading: true })
    compare(said(Next.rows(s)), ["head:SET ASIDE", "gone quiet", "head:WAITING FOR A GRADE", "d4"])
  }

  function test_proposals_where_the_box_is() {
    var tasks = [task("outline", { when: "2026-10-14", key: "k1" }), task("essay", { anchor: 6, key: "k6" })]
    var rows = Next.rows(state({
      tasks: tasks,
      deadlines: [deadline(6, "open", sec(10, 16))],
      raised: [{ id: "r1" }],
      proposals: [
        { id: "p1", key: "k1", kind: "do-date" },
        { id: "p2", key: "k6", kind: "priority", told: true },          // under the deadline its box is
        { id: "p3", key: "", kind: "question" },                        // about no box: from the agent
      ],
    }))
    compare(said(rows), ["head:DUE", "month:" + Qt.formatDate(new Date(2026, 9, 16), "MMMM"), "d6", "told:p2",
                         "head:DOING", "month:" + Qt.formatDate(new Date(2026, 9, 14), "MMMM"), "outline", "proposal:p1",
                         "head:FROM THE AGENT", "question:p3", "raised:r1"])
    compare(rows[3].task.key, "k6")
  }

  // A document to file goes in its course's band. Until 2026-10-30 the
  // band's "#intsem" was compared with the proposal's "intsem", and it
  // never did.
  function test_a_document_in_its_course_s_band() {
    var rows = Next.rows(state({
      tasks: [task("a seminar thought", { kind: "bullet", project: "intsem" })],
      proposals: [{ id: "f1", key: "", kind: "file", project: "intsem", name: "syllabus.pdf" },
                  { id: "f2", key: "", kind: "file", project: "bikes", name: "map.pdf" }],   // no band: from the agent
    }))
    compare(said(rows), ["head:Interdisciplinary Seminar", "proposal:f1", "a seminar thought",
                         "head:FROM THE AGENT", "proposal:f2"])
  }

  function test_tasks_by_anchor_and_key() {
    var tasks = [task("a", { anchor: 3, key: "ka" }), task("b", { key: "kb" })]
    compare(Next.taskOfAnchor(tasks, 3).title, "a")
    compare(Next.taskOfAnchor(tasks, 4), null)
    compare(Next.taskOfKey(tasks, "kb").title, "b")
    compare(Next.taskOfKey(tasks, ""), null)
  }

  // The course strip (2026-11-03): a lens on the courses picked, words
  // typed into its ⌕, and two more orders.
  function strip_state(extra) {
    return state(Object.assign({
      tasks: [task("outline the talk", { project: "intsem", when: "2026-10-20", path: ["Talk"] }),
              task("read for the seminar", { project: "intsem" }),
              task("ask Bernd about scope", { project: "respro", path: ["Themenvorschlag"] }),
              task("call my sister"),
              task("gone quiet", { project: "respro", away: "quiet" }),
              task("essay", { anchor: 6, key: "k6", project: "respro" })],
      deadlines: [deadline(6, "open", sec(10, 16), { project: "respro", title: "essay" }),
                  deadline(7, "open", sec(11, 2), { project: "intsem", title: "review" })],
      proposals: [{ id: "p1", key: "k6", kind: "priority" }, { id: "p2", key: "", kind: "question", question: "when is the talk?" }],
      raised: [{ id: "r1", text: "the seminar is busy" }],
    }, extra))
  }

  function test_a_lens_keeps_its_courses_in_every_band() {
    var rows = Next.rows(strip_state({ lens: ["respro"] }))
    compare(said(rows), ["head:DUE", "month:" + Qt.formatDate(new Date(2026, 9, 16), "MMMM"), "d6", "proposal:p1",
                         "head:TO SCHEDULE", "ask Bernd about scope", "shelf:1"])
    // No project is a course of its own, and so is a question about no box.
    compare(said(Next.rows(strip_state({ lens: [""] }))), ["head:TO SCHEDULE", "call my sister", "head:FROM THE AGENT", "question:p2"])
    compare(said(Next.rows(strip_state({ lens: ["respro", "intsem"] }))).filter(function (x) { return x.charAt(0) === "d" }),
            ["d6", "d7"])
  }

  function test_words_and_tags_typed() {
    // Words are in the row's words, its section or its course's name:
    // "seminar" is the whole Interdisciplinary Seminar.
    compare(said(Next.rows(strip_state({ query: "seminar" }))),
            ["head:DUE", "month:" + Qt.formatDate(new Date(2026, 10, 2), "MMMM"), "d7",
             "head:DOING", "month:" + Qt.formatDate(new Date(2026, 9, 20), "MMMM"), "outline the talk",
             "head:TO SCHEDULE", "read for the seminar", "head:FROM THE AGENT", "raised:r1"])
    compare(said(Next.rows(strip_state({ query: "bernd scope" }))), ["head:TO SCHEDULE", "ask Bernd about scope"])
    compare(said(Next.rows(strip_state({ query: "talk" }))),
            ["head:DOING", "month:" + Qt.formatDate(new Date(2026, 9, 20), "MMMM"), "outline the talk",
             "head:FROM THE AGENT", "question:p2"])
    compare(said(Next.rows(strip_state({ query: "#int talk" }))),
            ["head:DOING", "month:" + Qt.formatDate(new Date(2026, 9, 20), "MMMM"), "outline the talk"])
    compare(said(Next.rows(strip_state({ query: "#nosuch" }))), [])
  }

  function test_by_course_and_by_date() {
    compare(said(Next.rows(strip_state({ order: "course" }))),
            ["head:Interdisciplinary Seminar", "month:DUE", "d7", "month:DOING", "outline the talk", "month:TO SCHEDULE", "read for the seminar",
             "head:Themenvorschlag", "month:DUE", "d6", "proposal:p1", "month:TO SCHEDULE", "ask Bernd about scope",
             "head:No project", "month:TO SCHEDULE", "call my sister",
             "shelf:1", "head:FROM THE AGENT", "question:p2", "raised:r1"])
    // By date, the bands narrow as they come near: today (nothing due,
    // said), this week, next week open; November and what has no day
    // yet folded, each with how much it holds.
    compare(said(Next.rows(strip_state({ order: "date" }))),
            ["band:TODAY 0", "band:THIS WEEK 1", "d6", "proposal:p1", "band:NEXT WEEK 1", "outline the talk",
             "band:" + Qt.formatDate(new Date(2026, 10, 2), "MMMM").toUpperCase() + " ▸ 1", "band:NO DAY YET ▸ 3",
             "shelf:1", "head:FROM THE AGENT", "question:p2", "raised:r1"])
  }

  // The date bands (2026-11-03), on Tuesday 13 October: late, today, the
  // rest of this week to Sunday, next week, the rest of October, then a
  // band a month.
  function date_state(extra) {
    return state(Object.assign({
      order: "date",
      deadlines: [deadline(1, "open", sec(10, 10)),                                   // late
                  deadline(2, "done", sec(10, 9), { doneAt: sec(10, 13, 8, 0) }),     // closed today: today's
                  deadline(3, "open", sec(10, 18)),                                   // Sunday: this week
                  deadline(4, "open", sec(10, 19)),                                   // Monday: next week
                  deadline(5, "open", sec(10, 26)),                                   // later in October
                  deadline(6, "open", sec(11, 2)),
                  deadline(7, "open", new Date(2027, 0, 15, 23, 59).getTime() / 1000)],
      tasks: [task("today's", { when: "2026-10-13" }), task("Sunday's too", { when: "2026-10-25" }), task("someday")],
    }, extra))
  }

  function test_date_bands_narrow_as_they_come_near() {
    var oct = Qt.formatDate(now, "MMMM").toUpperCase(), nov = Qt.formatDate(new Date(2026, 10, 2), "MMMM").toUpperCase()
    var jan = Qt.formatDate(new Date(2027, 0, 15), "MMMM yyyy").toUpperCase()
    compare(said(Next.rows(date_state({}))),
            ["band:LATE 1", "d1", "band:TODAY 2", "today's", "d2", "band:THIS WEEK 1", "d3",
             "band:NEXT WEEK 2", "d4", "Sunday's too", "band:LATER IN " + oct + " ▸ 1",
             "band:" + nov + " ▸ 1", "band:" + jan + " ▸ 1", "band:NO DAY YET ▸ 1"])
    // A folded band says what comes first in it.
    var later = Next.rows(date_state({})).filter(function (r) { return r.kind === "band" && r.id === "rest" })[0]
    compare([later.next.title, later.next.ms], ["d5", sec(10, 26) * 1000])
  }

  function test_date_bands_fold_and_unfold() {
    function bandsSaid(folds) {
      return said(Next.rows(date_state({ folds: folds }))).filter(function (x) { return x.indexOf("band:") === 0 })
    }
    // Unfold all, then fold one: the one wins. What is late never folds.
    var all = bandsSaid({ "*": true, week: false })
    compare(all.filter(function (x) { return x.indexOf("▸") >= 0 }), ["band:THIS WEEK ▸ 1"])
    var none = bandsSaid({ "*": false })
    compare(none.filter(function (x) { return x.indexOf("▸") < 0 }), ["band:LATE 1"])
    compare(said(Next.rows(date_state({ folds: { "*": false, "m2026-11": true } }))).indexOf("d6") >= 0, true)
    // Words typed are looked for everywhere: every band open.
    compare(said(Next.rows(date_state({ folds: { "*": false }, query: "d" }))).filter(function (x) { return x.indexOf("▸") >= 0 }), [])
  }

  function test_date_bands_at_the_turn_of_a_month_and_on_a_sunday() {
    // Thursday 26 November: next week runs into December, so there is no
    // rest of November, and December starts after next week.
    var thu = new Date(2026, 10, 26, 9, 0)
    var rows = Next.rows(state({ now: thu, order: "date", folds: { "*": true },
                                 deadlines: [deadline(1, "open", sec(11, 28)), deadline(2, "open", sec(12, 3)), deadline(3, "open", sec(12, 10))] }))
    compare(said(rows), ["band:TODAY 0", "band:THIS WEEK 1", "d1", "band:NEXT WEEK 1", "d2",
                         "band:" + Qt.formatDate(new Date(2026, 11, 10), "MMMM").toUpperCase() + " 1", "d3"])
    // On a Sunday this week is over: Monday is next week's.
    var sun = new Date(2026, 9, 18, 9, 0)
    compare(said(Next.rows(state({ now: sun, order: "date", deadlines: [deadline(1, "open", sec(10, 19))] }))),
            ["band:TODAY 0", "band:NEXT WEEK 1", "d1"])
  }

  function test_the_strip_s_chips() {
    var c = Next.courses(strip_state({ lens: ["respro"] }))
    compare(c.chips.map(function (x) { return x.label + " " + x.count }), ["intsem 3", "respro 2", "none 1"])
    var respro = c.chips[1]
    compare([respro.due, respro.doing, respro.later, respro.next.title], [1, 0, 1, "essay"])
    compare([c.shown, c.total, c.outside], [2, 6, 1])
    // Words change the counts, not the chips; a #tag typed is a lens, not a count.
    var w = Next.courses(strip_state({ query: "#res seminar" }))
    compare(w.chips.map(function (x) { return x.label + " " + x.count }), ["intsem 3", "respro 0", "none 0"])
    compare(w.shown, 0)
  }

  // A band for a tag the curriculum does not name takes its heading from a
  // box under its own course — never from one written inside another's.
  function test_a_band_named_by_its_own_heading() {
    var stray = task("confirm the scope", { project: "thesis", claimed: "dtm", path: ["Speculative Environments"] })
    var own = task("read Martin's thesis", { project: "thesis", claimed: "thesis", path: ["Master Thesis"] })
    compare(Next.bandName("thesis", [stray, own], projects), "Master Thesis")
    compare(Next.bandName("thesis", [stray], projects), "thesis")
    compare(Next.bandName("intsem", [stray], projects), "Interdisciplinary Seminar")
  }
}
