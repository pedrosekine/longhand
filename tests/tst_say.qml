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
    // Written inside another course's section (2026-11-03): the course,
    // then the headings it is really under — never its name over theirs.
    var stray = { path: ["Speculative Environments", "Watch and read list"], project: "intsem", claimed: "dtm", age: 0 }
    compare(Say.taskWhere(stray, undefined, projects),
            "Interdisciplinary Seminar   ·   in Speculative Environments › Watch and read list   ·   written today")
    compare(Say.taskWhere(stray, "Interdisciplinary Seminar", projects), "Speculative Environments › Watch and read list   ·   written today")
    compare(Say.taskWhere({ path: ["Speculative Environments"], project: "bikes", claimed: "dtm", age: 0 }, "bikes", projects),
            "Speculative Environments   ·   written today")      // a band named by the tag alone
    // Claimed by its own course, whatever the case of the tag: as before.
    compare(Say.taskWhere({ path: ["IntSem", "Essay 2"], project: "intsem", claimed: "INTSEM", age: 0 }, undefined, projects),
            "Interdisciplinary Seminar › Essay 2   ·   written today")
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

  function test_a_deadline_row_s_second_line() {
    var at = Math.floor(now.getTime() / 1000), day = 86400
    var d = { id: 6, status: "open", project: "intsem", due: at + 3 * day, grade: "" }
    var t = { path: ["#intsem", "Essay 2"], details: 2 }
    compare(Say.deadlineWhere(d, t, projects, null, null, now), "Interdisciplinary Seminar › Essay 2   ·   2 lines of detail")
    // No line holds it: the course alone.
    compare(Say.deadlineWhere(d, null, projects, null, null, now), "Interdisciplinary Seminar")
    compare(Say.deadlineWhere({ id: 7, status: "open", project: "bikes", due: at, grade: "" }, null, projects, null, null, now), "#bikes")
    compare(Say.deadlineWhere({ id: 8, status: "cancelled", project: "", due: at, grade: "" }, null, projects, null, null, now), "cancelled")
    compare(Say.deadlineWhere({ id: 9, status: "done", project: "", due: at, grade: "1.3" }, null, projects, null, null, now), "graded 1.3")
    // A fortnight past its date, an open one steps aside.
    compare(Say.deadlineWhere({ id: 10, status: "open", project: "", due: at - 12 * day, grade: "" }, null, projects, null, null, now),
            "steps aside in 2 days")
    compare(Say.deadlineWhere(d, null, projects, { origin: "agent", rewritten: true }, null, now),
            "Interdisciplinary Seminar   ·   from the agent · rewritten by you")
    compare(Say.deadlineWhere(d, null, projects, { origin: "you" }, { moves: 2, firstDue: at }, now),
            "Interdisciplinary Seminar   ·   moved twice, first due " + Qt.formatDate(now, "d MMM"))
    compare(Say.deadlineWhere(d, null, projects, null, { moves: 3 }, now), "Interdisciplinary Seminar   ·   moved 3 times")
    // Its line inside another course's section: the course, then where.
    var stray = { path: ["Speculative Environments", "Watch and read list"], claimed: "dtm", details: 0 }
    compare(Say.deadlineWhere(d, stray, projects, { origin: "agent" }, null, now),
            "Interdisciplinary Seminar   ·   in Speculative Environments › Watch and read list   ·   from the agent")
  }

  function test_what_a_section_says_under_it() {
    compare(Say.sectionUnder({ sub: [{ text: "Essay #intsem" }, { text: "Reading" }] }), "Essay · Reading")
    compare(Say.sectionUnder({ sub: [{ text: "a" }, { text: "b" }, { text: "c" }, { text: "d" }, { text: "e" }, { text: "f" }] }), "a · b · c · d · +2")
    compare(Say.sectionUnder({ sub: [], preview: ["first line", "second"] }), "first line · second")
    compare(Say.sectionUnder({}), "")
  }

  // A project's list says what each section's tagged line says, and its
  // lines as words, not markdown (2026-11-11).
  function test_a_section_says_its_tagged_line() {
    compare(Say.sectionTitle({ heading: "Team meeting #studio", tag: "studio" }, "Design Studio"), "Team meeting #studio")
    compare(Say.sectionTitle({ heading: "Ideation solo for #studio", tag: "studio" }, "Design Studio"), "Ideation solo for #studio")
    // Only the project again: nothing to add to the list's own header.
    compare(Say.sectionTitle({ heading: "Design Studio #studio", tag: "studio" }, "Design Studio"), "")
    compare(Say.sectionTitle({ heading: "design studio #Studio", tag: "studio" }, "Design Studio"), "")
    compare(Say.sectionTitle({ heading: "#studio", tag: "studio" }, "Design Studio"), "")
    compare(Say.sectionTitle({ heading: "", tag: "studio", level: 0 }, "Design Studio"), "")
    compare(Say.sectionTitle({ heading: "**Crit** with [[Chris|Chris F.]] #studio", tag: "studio" }, "Design Studio"),
            "Crit with Chris F. #studio")
    // The project's tag drawn quiet, another tag and the words as they are.
    compare(Say.quietTag("Team meeting #studio <draft>", "studio", "#777"),
            'Team meeting <font color="#777">#studio</font> &lt;draft&gt;')
    compare(Say.quietTag("#studio at start, #studios not", "studio", "#777"),
            '<font color="#777">#studio</font> at start, #studios not')
  }

  function test_a_line_as_words() {
    compare(Say.plainLine("- [x] Innovation and Market of AI Agents and hardware - Pedro ✅ 2026-10-30"),
            "✓ Innovation and Market of AI Agents and hardware - Pedro")
    compare(Say.plainLine("- [ ] Reflective Research Diary 2 #studio ⏳ 2026-11-12 📅 2026-11-13 ^d58"),
            "○ Reflective Research Diary 2 #studio")
    compare(Say.plainLine("- [-] dropped ⏫ [est:: 1h]"), "✗ dropped")
    compare(Say.plainLine("- Candlelight AI: light signals it is on"), "Candlelight AI: light signals it is on")
    compare(Say.plainLine("  2. the *second* `step`"), "the second step")
    compare(Say.plainLine("> quoted ==bright== words"), "quoted bright words")
    compare(Say.plainLine("see [the brief](https://x.y) and ~~old~~"), "see the brief and old")
  }

  function test_what_a_section_holds() {
    compare(Say.sectionUnder({ preview: ["- [x] Ask Chris ✅ 2026-11-04", "- [x] More research #studio ✅ 2026-11-04"] }),
            "✓ Ask Chris · ✓ More research #studio")
    // The day's boxes outside the section: each with its own state.
    compare(Say.sectionUnder({ level: 0, preview: ["Diary 2"],
                               boxes: [{ text: "Diary 2 #studio 📅 2026-11-13 ^d58", state: " " }, { text: "Sent it", state: "x" }] }),
            "○ Diary 2 #studio · ✓ Sent it")
    compare(Say.sectionCounts({ open: 1, done: 2 }), "1 open · 2 done")
    compare(Say.sectionCounts({ open: 0, done: 0 }), "")
    compare(Say.projectSummary([]), "")
    compare(Say.projectSummary([{ date: "a", open: 1 }]), "1 section · 1 open")
    compare(Say.projectSummary([{ date: "a", open: 1 }, { date: "a", open: 0 }, { date: "b", open: 2 }]),
            "3 sections on 2 days · 3 open")
    compare(Say.projectSummary([{ date: "a", open: 0 }, { date: "b", open: 0 }]), "2 sections")
  }
}
