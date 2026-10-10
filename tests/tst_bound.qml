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

  function test_links() {
    compare(Bound.link("2026.10.09", 6), "[[2026.10.09#^d6]]")
    compare(Bound.parseLink("[[2026.10.09#^d6]]").id, 6)
    compare(Bound.parseLink("https://x"), null)
  }
}
