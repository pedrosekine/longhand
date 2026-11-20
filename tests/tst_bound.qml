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
    // Trailing #tags after a date cue are kept in head and excluded from the cue span.
    var ct = Bound.cue("submit essay by friday #respro")
    compare(ct.phrase, "friday"); compare(ct.head, "submit essay #respro")
    compare(ct.title, "submit essay"); compare(ct.project, "respro")
    compare(ct.cueFrom, 12); compare(ct.cueEnd, 22)
    var cb = Bound.cue("submit essay friday #respro #draft")
    compare(cb.phrase, "friday"); compare(cb.head, "submit essay #respro #draft")
    compare(cb.title, "submit essay"); compare(cb.project, "respro")
    compare(cb.cueFrom, 12); compare(cb.cueEnd, 19)
  }

  function test_on_cues_a_date_only_when_one_follows() {
    var c = Bound.cue("conference on the 8th of Feb")
    compare(c.phrase, "the 8th of Feb"); compare(c.title, "conference")
    compare(Bound.cue("call the dean on friday 10:00").phrase, "friday 10:00")
    compare(Bound.cue("hand in on 12.11").phrase, "12.11")               // a dotted day
    compare(Bound.cue("work on 2.3"), null)                              // …but an exercise is not one
    compare(Bound.cue("defence on March 3").phrase, "March 3")
    compare(Bound.cue("essay on Kant by monday").phrase, "monday")      // the last cue counts
    compare(Bound.cue("read on friday by the 9th of Nov").phrase, "the 9th of Nov")
    compare(Bound.cue("work on part 3"), null)
    compare(Bound.cue("focus on today"), null)
    compare(Bound.cue("comment on 3 papers"), null)
    compare(Bound.cue("notes on monday's lecture").phrase, "monday's lecture")  // lights up only if it parses
    compare(Bound.cue("on friday"), null)                                // nothing to name the deadline
  }

  // No cue word (decided 2026-11-15): a date at the end is the deadline.
  function test_a_bare_date_at_the_end() {
    function bare(body) { var c = Bound.cue(body); return c ? [c.head, c.phrase] : null }
    compare(bare("essay monday"), ["essay", "monday"])
    compare(bare("essay next monday 10:00"), ["essay", "next monday 10:00"])   // the date as long as it reads
    compare(bare("send it tomorrow at 5pm"), ["send it", "tomorrow at 5pm"])
    compare(bare("hand in 12.11"), ["hand in", "12.11"])
    compare(bare("hand in 1.5."), ["hand in", "1.5."])
    compare(bare("essay 12.11.2026 17:00"), ["essay", "12.11.2026 17:00"])
    compare(bare("read pages 20 oct"), ["read pages", "20 oct"])
    compare(bare("defence March 3"), ["defence", "March 3"])
    compare(bare("conference the 8th of Feb"), ["conference", "the 8th of Feb"])
    compare(bare("call Anna this sat"), ["call Anna", "this sat"])
    compare(bare("plan the trip next week"), ["plan the trip", "next week"])
    compare(bare("slides for monday"), ["slides", "monday"])                    // "for" goes with the date
    compare(Bound.cue("chapter 2 #thesis fri").project, "thesis")
    compare(Bound.cue("chapter 2 #thesis fri").title, "chapter 2")
  }

  function test_a_bare_date_only_when_it_is_one() {
    var no = ["monday",                  // nothing to name the deadline
              "exercise 2.3", "upgrade to python 3.12", "read chapter 3", "write 2h",
              "lie in the sun", "the cat sat", "get 10 marks", "go to may",
              "essay friday 3",          // a time has a colon or am/pm
              "notes from monday", "focus on today", "gym every friday", "recap of tuesday",
              "since last thursday", "read ⏳ 2026-11-16", "reread friday's lecture"]
    for (var i = 0; i < no.length; i++) compare(Bound.cue(no[i]), null, no[i])
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
    // A priority and the day to work on it are kept, in front of the date
    // (2026-11-17: they are drawn in the pill, and a catch-up dropped them).
    var marked = Rows.derive("- [ ] the lab notes [est:: 2h] 🔽 ⏳ 2030-01-03 📅 2030-01-08 ^d87")[0]
    compare(marked.marks, " 🔽 ⏳ 2030-01-03")
    compare(marked.dateTail, " 📅 2030-01-08 ^d87")
    compare(Bound.caughtUp(marked, { id: 87, status: "done", due: sec(2030, 1, 9, 23, 59), doneAt: sec(2030, 1, 7, 9, 0) }),
            "- [x] the lab notes [est:: 2h] 🔽 ⏳ 2030-01-03 📅 2030-01-09 ✅ 2030-01-07 ^d87")
    compare(Bound.caughtUp(marked, undefined), "- [ ] the lab notes [est:: 2h] 🔽 ⏳ 2030-01-03 📅 2030-01-08")
  }

  // Where a line the page writes goes (2026-11-03): its course's section,
  // else the top — never the end, inside the last section.
  function test_where_a_written_line_goes() {
    var day = ["[[agents/longhand/daily/2026-11-03|agent]]", "", "- [x] the cup club ^d48",
               "# Own your Strength #coach", "a question", "",
               "# Speculative Environments #dtm", "## Watch and read list", "- [ ] Our Friends Electric", ""]
    compare(Bound.placeAt(day, "thesis"), 3)          // no #thesis section: after the loose box, above the first heading
    compare(Bound.placeAt(day, "coach"), 5)           // the end of its section, before the blank line
    compare(Bound.placeAt(day, "dtm"), 9)             // an H2 does not end the H1
    compare(Bound.placeAt(day, "DTM"), 9)             // a tag is a tag whatever its case
    compare(Bound.placeAt(day, ""), 3)
    compare(Bound.placeAt(["# Notes #dtm-old", "x"], "dtm"), 0)   // another tag that starts the same is not it
    compare(Bound.placeAt(["# Only a heading", "words"], "thesis"), 0)
    compare(Bound.placeAt(["just words", "more", ""], "thesis"), 2)  // no heading: loose throughout, so the end
    compare(Bound.placeAt([""], "thesis"), 0)
    compare(Bound.placeAt(["---", "agent: false", "---", "# Day #dtm"], "thesis"), 3)  // after the frontmatter
    compare(Bound.placeAt(["- [ ] loose", "```", "# not a heading", "```", "# Real #dtm"], "thesis"), 4)
  }
}
