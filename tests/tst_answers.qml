import QtQuick
import QtTest
import "../plugin-page/Answers.js" as Answers

// A question's answer, for hovering it in the PDF (Answers.js).
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_answers.qml
TestCase {
  name: "Answers"

  readonly property var turns: [
    { role: "student", text: "what is this?", marks: ["h2"] },
    { role: "agent", text: "It is the method's first step." },
    { role: "student", text: "and this one?", marks: ["h5"] },
    { role: "agent", text: "", error: "timeout" },
    { role: "student", text: "My waiting questions, one by one:\n- h5\n- h7", marks: ["h5", "h7"] },
    { role: "agent", text: "**h5:**\nCoding is reading closely.\n\nIt comes before themes.\n\nh7:\nA theme is a pattern of meaning." },
    { role: "student", text: "say more" },
    { role: "agent", text: "More words." }
  ]

  function test_the_answer_after_the_message_that_pointed_at_it() {
    var a = Answers.forMark(turns, "h2")
    compare(a.student, 0)
    compare(a.agent, 1)
    compare(a.text, "It is the method's first step.")
    compare(a.more, 0, "the next message asks about another mark: none of what follows is about this one")
    compare(Answers.forMark(turns, "h7").more, 1, "a message about no mark after it: the conversation went on")
  }

  function test_an_error_is_not_an_answer() {
    // h5's first asking failed; the next one answered it.
    var a = Answers.forMark(turns, "h5")
    compare(a.agent, 5)
    compare(a.text, "Coding is reading closely.\n\nIt comes before themes.")
  }

  function test_asked_together_each_gets_its_part() {
    compare(Answers.forMark(turns, "h7").text, "A theme is a pattern of meaning.")
    compare(Answers.part("h1: Yes, it does.\nh2: No.", "h1", ["h1", "h2"]), "Yes, it does.")
    compare(Answers.part("`h2`:\nNo.", "h2", ["h1", "h2"]), "No.")
    // Its name not in the answer: the whole answer.
    compare(Answers.part("Both are the same thing.", "h2", ["h1", "h2"]), "Both are the same thing.")
    // A name of another paper's mark is not a part.
    compare(Answers.part("h9: words\nmore", "h1", ["h1", "h2"]), "h9: words\nmore")
  }

  function test_what_was_asked() {
    compare(Answers.forMark(turns, "h2").asked, "what is this?")
    // Asked together: each its own line's note, or nothing (the passage is the question).
    compare(Answers.forMark(turns, "h5").asked, "")
    compare(Answers.asked("My waiting questions, one by one:\n- h5: why first?\n- h7", "h5"), "why first?")
    compare(Answers.asked("My question:\n- h3: and here?", "h3"), "and here?")
    compare(Answers.asked("My question is simple: why?", "h3"), "My question is simple: why?", "words of one's own stay")
  }

  function test_none_yet() {
    compare(Answers.forMark(turns, "h3"), null)
    compare(Answers.forMark([], "h1"), null)
    compare(Answers.forMark([{ role: "student", text: "q", marks: ["h1"] }], "h1"), null, "asked, not answered yet")
  }

  function test_a_tip_says_it_plainly() {
    compare(Answers.gist("**Coding** is `reading` closely, as [Braun](http://x) says.").text,
            "Coding is reading closely, as Braun says.")
    compare(Answers.gist("> “words quoted” (p. 3)\n\n- a point\n- another").text, "“words quoted” (p. 3) a point another")
    compare(Answers.gist("short").cut, false)
  }

  function test_a_long_answer_is_its_first_sentences() {
    var long = "Coding is reading closely. It comes before themes and after familiarisation. "
      + "Then the analyst names each passage with a code that says what it is about, and keeps going through every item of the data set until the end."
    var g = Answers.gist(long, 100)
    compare(g.text, "Coding is reading closely. It comes before themes and after familiarisation.")
    compare(g.cut, true)
    // One long sentence: cut at a word.
    var g2 = Answers.gist("word ".repeat(80), 60)
    verify(g2.text.length <= 61 && g2.text.slice(-1) === "…", g2.text)
  }
}
