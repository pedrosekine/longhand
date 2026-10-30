import QtQuick
import QtTest
import "../plugin-page/Bound.js" as Bound
import "../plugin-page/Rows.js" as Rows

// The rules for lines that stand for deadlines.
TestCase {
  name: "Bound"

  function test_cue_words_and_calendar_mark() {
    var c = Bound.cue("chapter 2 draft #thesis due fri 17:00")
    compare(c.phrase, "fri 17:00"); compare(c.title, "chapter 2 draft"); compare(c.project, "thesis")
    compare(c.head, "chapter 2 draft #thesis")
    compare(Bound.cue("essay by monday").phrase, "monday")
    compare(Bound.cue("send it 📅 tomorrow").phrase, "tomorrow")
    compare(Bound.cue("read paper by Smith due friday").phrase, "friday")   // the last cue counts
  }

  function test_on_cues_a_date_only_when_one_follows() {
    var c = Bound.cue("conference on the 8th of Feb")
    compare(c.phrase, "the 8th of Feb"); compare(c.title, "conference")
    compare(Bound.cue("call the dean on friday 10:00").phrase, "friday 10:00")
    compare(Bound.cue("hand in on 12.11"), null)                         // the dates read no dotted days
    compare(Bound.cue("defence on March 3").phrase, "March 3")
    compare(Bound.cue("essay on Kant by monday").phrase, "monday")      // the last cue counts
    compare(Bound.cue("read on friday by the 9th of Nov").phrase, "the 9th of Nov")
    compare(Bound.cue("work on part 3"), null)
    compare(Bound.cue("focus on today"), null)
    compare(Bound.cue("comment on 3 papers"), null)
    compare(Bound.cue("notes on monday's lecture").phrase, "monday's lecture")  // lights up only if it parses
    compare(Bound.cue("on friday"), null)                                // nothing to name the deadline
  }

  function test_no_cue_no_deadline() {
    compare(Bound.cue("call mum by phone"), null)
    compare(Bound.cue("work until done"), null)
    compare(Bound.cue("reread friday's lecture"), null)
    compare(Bound.cue("due friday"), null)   // nothing to name the deadline
  }

  function test_tail_and_anchor() {
    compare(Bound.tail(new Date(2026, 9, 16, 17, 0).getTime(), 6), " 📅 2026-10-16 17:00 ^d6")
    compare(Bound.tail(new Date(2026, 9, 16, 23, 59).getTime(), 6), " 📅 2026-10-16 ^d6")
    var a = Bound.anchors("- [ ] a 📅 2026-10-16 ^d6\nplain ^d7\n\t- [x] b ^d8")
    compare(a["6"].line, 0); compare(a["6"].checked, false)
    compare(a["7"], undefined)
    compare(a["8"].checked, true)
  }

  function test_proposal_finds_its_line() {
    // 2026-10-12's IntSem list: each proposal is about one line, not the next free one.
    var lines = ["Roles Planned by 30 oct", "Initial paper by 30 nov", "individual reviews by 07 dec",
                 "author response by 14 dec", "final paper by 15 jan", "A0 poster by 20 jan"]
    var due = function (m, d) { return new Date(2026, m - 1, d, 23, 59).getTime() }
    compare(Bound.matchLine("Roles planned", due(10, 30), lines), 0)
    compare(Bound.matchLine("Individual reviews", due(12, 7), lines), 2)
    compare(Bound.matchLine("Final paper", due(1, 15), lines), 4)   // not "Initial paper", though it holds "paper"
    compare(Bound.matchLine("Conference", due(2, 3), lines), -1)
    compare(Bound.matchLine("one-pager", 0, ["draft the one-pager #DORO"]), 0)
    compare(Bound.matchLine("paper", 0, ["Initial paper", "final paper"]), -1)   // which one is not clear
    compare(Bound.matchLine("", due(10, 30), lines), -1)
    // The research-proposal list: the agent reworded every title.
    var rp = ["A registered topic and supervisor, and a peer group by 30 oct",
              "Proposal of version 1, read by supervisor and 2 fellow students by 18 dec",
              "Masthe's thesis conference on the 8th of Feb",
              "Proposal of version 2, graded by the supervisor by 19th of Feb"]
    compare(Bound.matchLine("Registered topic, supervisor and peer group", due(10, 30), rp), 0)
    compare(Bound.matchLine("Proposal v1 read by supervisor and 2 fellow students", due(12, 18), rp), 1)
    compare(Bound.matchLine("Master's thesis conference", due(2, 8), rp), 2)
    compare(Bound.matchLine("Proposal v2 graded by supervisor", due(2, 19), rp), 3)
    compare(Bound.matchLine("Proposal v2 graded by supervisor", 0, rp), 3)   // words alone, no date
  }

  function test_days_named() {
    compare(Bound.daysIn("by 30 oct"), ["10-30"])
    compare(Bound.daysIn("on the 8th of Feb"), ["2-8"])
    compare(Bound.daysIn("Oct 30"), ["10-30"])
    compare(Bound.daysIn("📅 2026-10-30 ^d7"), ["10-30"])
    compare(Bound.daysIn("version 2, graded"), [])
  }

  function test_links() {
    compare(Bound.link("2026.10.09", 6), "[[2026.10.09#^d6]]")
    compare(Bound.parseLink("[[2026.10.09#^d6]]").id, 6)
    compare(Bound.parseLink("https://x"), null)
  }

  // ---- the page's bound lines (moved out of Page.qml on 2026-10-30)

  function sec(y, m, d, hh, mm) { return new Date(y, m - 1, d, hh, mm).getTime() / 1000 }

  function test_a_line_for_a_deadline() {
    compare(Bound.lineFor({ status: "open", title: "essay draft", project: "intsem", due: sec(2026, 10, 16, 17, 0), id: 6 }),
            "- [ ] essay draft #intsem 📅 2026-10-16 17:00 ^d6")
    compare(Bound.lineFor({ status: "done", title: "read it", project: "", due: sec(2026, 10, 14, 23, 59), id: 7 }),
            "- [x] read it 📅 2026-10-14 ^d7")
    // A project that is no tag is not written as one.
    compare(Bound.lineFor({ status: "open", title: "talk", project: "Guest lecture", due: sec(2026, 10, 14, 23, 59), id: 8 }),
            "- [ ] talk 📅 2026-10-14 ^d8")
  }

  function test_ticked_with_its_day() {
    var raw = "- [ ] essay draft 📅 2026-10-16 17:00 ^d6"
    var done = Bound.ticked(raw, true, "2026-10-13")
    verify(/^- \[x\] /.test(done)); verify(done.indexOf("✅ 2026-10-13") > 0); verify(/\^d6$/.test(done))
    compare(Bound.ticked(done, false, "2026-10-13"), raw)
  }

  function test_what_an_edit_did_to_bound_lines() {
    var was = Bound.anchors("- [ ] a 📅 2026-10-16 ^d6\n- [ ] b 📅 2026-10-17 ^d7")
    var e = Bound.edits(was, Bound.anchors("- [ ] b 📅 2026-10-17 ^d7"))
    compare(e.gone, [6]); verify(!e.changed)
    e = Bound.edits(was, Bound.anchors("- [x] a 📅 2026-10-16 ^d6\n- [ ] b 📅 2026-10-17 ^d7"))
    compare(e.gone, []); verify(e.changed)                                // ticked
    e = Bound.edits(was, Bound.anchors("- [ ] b 📅 2026-10-17 ^d7\n\n- [ ] a 📅 2026-10-16 ^d6"))
    compare(e.gone, []); verify(!e.changed)                               // moved: nothing to tell
    e = Bound.edits(Bound.anchors(""), was)
    verify(e.changed)                                                     // back
  }

  function test_the_twin_a_proposal_left() {
    var items = [
      { id: 3, status: "done", link: "", title: "essay draft", due: sec(2026, 10, 16, 23, 59) },
      { id: 4, status: "open", link: "[[2026.10.12#^d4]]", title: "essay draft", due: sec(2026, 10, 16, 23, 59) },
      { id: 5, status: "open", link: "", title: "Essay draft, first version", due: sec(2026, 10, 16, 17, 0) },
    ]
    compare(Bound.twin(items, "essay draft #intsem", sec(2026, 10, 16, 23, 59) * 1000).id, 5)   // the same day, mostly the words
    compare(Bound.twin(items, "essay draft", sec(2026, 10, 17, 23, 59) * 1000), null)           // another day
    compare(Bound.twin(items, "poster", sec(2026, 10, 16, 23, 59) * 1000), null)                // other words
  }

  function test_the_line_tab_bound_and_its_number() {
    var rows = Rows.derive("- [ ] outline 📅 2026-10-20 \nwords\n- [ ] essay 📅 2026-10-20 ^d6\n- [ ] poster 📅 2026-10-20 ")
    var ms = new Date(2026, 9, 20, 23, 59).getTime()
    compare(Bound.tabBound(rows, { ms: ms, line: 3 }), 3)
    compare(Bound.tabBound(rows, { ms: ms, line: 1 }), 0)      // the nearer of two; a numbered one is not it
    compare(Bound.tabBound(rows, { ms: ms + 86400000, line: 0 }), -1)
    compare(Bound.numbered(rows[0], 9, false), "- [ ] outline 📅 2026-10-20 ^d9")
    var spaced = Rows.derive("- [ ] outline   📅 2026-10-20 ")[0]
    compare(Bound.numbered(spaced, 9, true), "- [ ] outline 📅 2026-10-20 ^d9")    // left: tidied
    compare(Bound.numbered(spaced, 9, false), "- [ ] outline   📅 2026-10-20 ^d9")  // still in it: as typed
  }

  function test_a_line_caught_up_with_the_store() {
    var r = Rows.derive("- [ ] essay draft #intsem 📅 2026-10-16 17:00 ^d6  ")[0]
    var d = { id: 6, status: "open", due: sec(2026, 10, 16, 17, 0), doneAt: 0 }
    compare(Bound.caughtUp(r, d), "- [ ] essay draft #intsem 📅 2026-10-16 17:00 ^d6")
    d.status = "done"; d.doneAt = sec(2026, 10, 15, 9, 0)
    compare(Bound.caughtUp(r, d), "- [x] essay draft #intsem 📅 2026-10-16 17:00 ✅ 2026-10-15 ^d6")
    d.status = "cancelled"
    compare(Bound.caughtUp(r, d), "- [-] essay draft #intsem 📅 2026-10-16 17:00 ❌ 2026-10-15 ^d6")
    // Closed with no day on record: today's.
    d.doneAt = 0
    compare(Bound.caughtUp(r, d, new Date(2026, 9, 13, 8, 0)), "- [-] essay draft #intsem 📅 2026-10-16 17:00 ❌ 2026-10-13 ^d6")
    // Open again: neither mark.
    var closed = Rows.derive("- [x] read it 📅 2026-10-14 ✅ 2026-10-13 ^d7")[0]
    compare(Bound.caughtUp(closed, { id: 7, status: "open", due: sec(2026, 10, 14, 23, 59), doneAt: 0 }), "- [ ] read it 📅 2026-10-14 ^d7")
    // The store has no such deadline: the date stays, the number goes.
    compare(Bound.caughtUp(r, undefined), "- [ ] essay draft #intsem 📅 2026-10-16 17:00")
  }
}
