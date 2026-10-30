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
}
