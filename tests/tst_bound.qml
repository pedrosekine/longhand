import QtQuick
import QtTest
import "../plugin-page/Bound.js" as Bound

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
}
