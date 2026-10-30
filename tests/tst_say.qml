import QtQuick
import QtTest
import "../plugin-page/Say.js" as Say

// What a dashboard row says (Say.js, moved out of Page.qml on 2026-10-30).
// "Now" is fixed: Tuesday 13 October 2026, 08:57.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_say.qml
TestCase {
  name: "Say"
  readonly property var now: new Date(2026, 9, 13, 8, 57, 30)
  readonly property var projects: [{ tag: "intsem", name: "Interdisciplinary Seminar" }, { tag: "dtm", name: "" }]

  function test_a_date_as_a_row_says_it() {
    compare(Say.sayDate("2026-10-13", now), "today")
    compare(Say.sayDate("2026-10-14", now), "tomorrow")
    compare(Say.sayDate("2026-10-12", now), "yesterday")
    compare(Say.sayDate("2026-10-10", now), "3 days late")
    compare(Say.sayDate("2026-10-20", now), Qt.formatDate(new Date(2026, 9, 20), "ddd d MMM"))
    compare(Say.sayDate("2026-10-14 17:00", now), "tomorrow 17:00")   // a time, said
    compare(Say.sayDate("2026-10-14 23:59", now), "tomorrow")         // the day's end, not
    compare(Say.sayDate("", now), "")
  }

  function test_age_and_life() {
    compare(Say.sayAge(0), "written today")
    compare(Say.sayAge(1), "written yesterday")
    compare(Say.sayAge(5), "written 5 days ago")
    compare(Say.sayLife({ away: "shelved" }), "put aside")
    compare(Say.sayLife({ away: "quiet" }), "gone quiet")
    compare(Say.sayLife({ warn: false }), "")
    compare(Say.sayLife({ warn: true, left: 1 }), "goes quiet tomorrow")
    compare(Say.sayLife({ warn: true, left: 4 }), "goes quiet in 4 days")
  }

  function test_title_and_mark() {
    compare(Say.taskTitle({ title: "read the paper", text: "read the paper ⏫" }), "read the paper")
    compare(Say.taskTitle({ title: "", text: "loose thought" }), "loose thought")
    compare(Say.taskMark({ priority: 2 }), "▲")
    compare(Say.taskMark({ priority: -1 }), "▽")
    compare(Say.taskMark({ priority: 0 }), "")
    compare(Say.taskMark(null), "")
  }

  function test_courses_by_their_names() {
    compare(Say.courseName("intsem", projects), "Interdisciplinary Seminar")
    compare(Say.courseName("dtm", projects), "dtm")          // a project with no name keeps its tag
    compare(Say.courseName("bikes", projects), "bikes")
    compare(Say.courseLabel("intsem", projects), "Interdisciplinary Seminar")
    compare(Say.courseLabel("bikes", projects), "#bikes")
    compare(Say.courseLabel("", projects), "")
  }

  function test_where_a_task_came_from() {
    var t = { path: ["Interdisciplinary Seminar", "Essay 2"], project: "intsem", age: 2 }
    compare(Say.taskWhere(t, undefined, projects), "Interdisciplinary Seminar › Essay 2   ·   written 2 days ago")
    compare(Say.taskWhere(t, "Interdisciplinary Seminar", projects), "Essay 2   ·   written 2 days ago")
    // A heading written as the tag takes the course's full name.
    compare(Say.taskWhere({ path: ["#intsem"], project: "intsem", age: 0 }, undefined, projects), "Interdisciplinary Seminar   ·   written today")
    compare(Say.taskWhere({ path: [], project: "bikes", age: 0, details: 1 }, undefined, projects), "#bikes   ·   written today   ·   1 line of detail")
    compare(Say.taskWhere({ age: 3, details: 2, warn: true, left: 2 }, undefined, projects),
            "written 3 days ago   ·   2 lines of detail   ·   goes quiet in 2 days")
  }

  function test_months_and_order() {
    compare(Say.monthLabel(new Date(2026, 10, 2).getTime(), now), Qt.formatDate(new Date(2026, 10, 2), "MMMM"))
    compare(Say.monthLabel(new Date(2027, 0, 5).getTime(), now), Qt.formatDate(new Date(2027, 0, 5), "MMMM yyyy"))
    compare(Say.taskMs({ when: "2026-10-20", due: "2026-10-30 17:00" }), new Date(2026, 9, 20).getTime())
    compare(Say.taskMs({ due: "2026-10-30 17:00" }), new Date(2026, 9, 30).getTime())
    compare(Say.taskMs({}), 0)
  }

  function test_a_deadline_stepping_aside() {
    var day = 86400, at = Math.floor(now.getTime() / 1000)
    compare(Say.asideIn({ status: "open", due: at - 11 * day }, now), 3)
    compare(Say.asideIn({ status: "open", due: at - 1 * day }, now), 0)    // not yet near
    compare(Say.asideIn({ status: "open", due: at - 15 * day }, now), 0)   // already gone
    compare(Say.asideIn({ status: "done", due: at - 11 * day }, now), 0)
  }

  function test_what_the_agent_s_row_says() {
    compare(Say.askKind({ told: true, kind: "priority" }), "told")
    compare(Say.askKind({ kind: "question" }), "question")
    compare(Say.askKind({ kind: "do-date" }), "proposal")
    compare(Say.sayAsk({ kind: "do-date", date: "2026-10-14", title: "read the paper" }, false, now), "do tomorrow · read the paper")
    compare(Say.sayAsk({ kind: "do-date", date: "2026-10-14", title: "read the paper" }, true, now), "do tomorrow")
    compare(Say.sayAsk({ kind: "priority", priority: 2, title: "essay", told: true }, false, now), "done: priority ▲ high · essay")
    compare(Say.sayAsk({ kind: "file", name: "syllabus.pdf", project: "intsem" }, false, now), "file “syllabus” in intsem")
    compare(Say.sayAsk({ kind: "steps", steps: ["outline it", "draft the intro"] }, false, now), "steps: outline it · draft the intro")
  }
}
