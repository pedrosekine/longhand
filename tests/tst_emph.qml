import QtQuick
import QtTest
import "../plugin-page/Emph.js" as Emph

// Inline emphasis: what counts as emphasis, and what the row draws for it.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_emph.qml
Item {
  TestCase {
    name: "Emph"

    // The whole point: whatever is drawn, the plain text underneath is the
    // body as it is on disk. Qt gives one document position per character,
    // so stripping the tags has to give the body back.
    function strip(h) {
      return h.replace(/<[^>]*>/g, "")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    }

    function test_the_plain_text_is_the_body_data() {
      return [
        { body: "plain words" },
        { body: "**bold** here" },
        { body: "*it* and **bold** and `code` and ~~gone~~" },
        { body: "**bold *and* italic**" },
        { body: "two  spaces and a trailing one " },
        { body: "a < b & c > d" },
        { body: "`a < b`" },
        { body: "\tindented code-ish" },
        { body: "2 * 3 * 4" },
        { body: "snake_case_name" },
        { body: "unclosed **bold" },
        { body: "****" }
      ]
    }

    function test_the_plain_text_is_the_body(row) {
      compare(strip(Emph.html(row.body, "mono")), row.body)
    }

    function test_bold_and_italic_are_read() {
      verify(Emph.has("a **b** c"))
      verify(Emph.has("a *b* c"))
      verify(Emph.has("a __b__ c"))
      verify(Emph.has("a `b` c"))
      verify(Emph.has("a ~~b~~ c"))
      verify(Emph.html("a **b** c", "mono").indexOf("<b>b</b>") >= 0)
      verify(Emph.html("a *b* c", "mono").indexOf("<i>b</i>") >= 0)
      verify(Emph.html("a ~~b~~ c", "mono").indexOf("<s>b</s>") >= 0)
      verify(Emph.html("a `b` c", "mono").indexOf("font-family:'mono'") >= 0)
    }

    function test_a_line_without_markers_is_never_emphasis() {
      verify(!Emph.has(""))
      verify(!Emph.has("just some words"))
      verify(!Emph.has("- [ ] a task"))
    }

    // Arithmetic, paths and identifiers are not markup.
    function test_what_is_not_emphasis() {
      verify(!Emph.has("2 * 3 * 4"), "spaces inside")
      verify(!Emph.has("snake_case_name"), "underscores inside a word")
      verify(!Emph.has("a ** b **"), "content starts with a space")
      verify(!Emph.has("****"), "nothing to emphasise")
      verify(!Emph.has("unclosed **bold"), "no closer")
      verify(!Emph.has("5 ~ 6"), "a single tilde is nothing")
    }

    // The markers are kept, in a span that draws to nothing.
    function test_the_markers_are_drawn_to_nothing() {
      var h = Emph.html("a **b** c", "mono")
      compare(h.split("font-size:1px").length - 1, 2)
      verify(h.indexOf("color:transparent") >= 0)
    }

    // Break one and it stops being emphasis — which is how you see it.
    function test_a_broken_pair_shows_its_markers() {
      verify(Emph.has("**bold**"))
      verify(!Emph.has("**bold*"))
      verify(!Emph.has("*bold**"), "the lone star is half of the pair after it")
    }

    // `***word***` is what the two keys write when you press both: the
    // outer pair takes the ends of the run, the inner pair what is left.
    function test_bold_and_italic_together() {
      var h = Emph.html("***word***", "mono")
      verify(h.indexOf("<b>") >= 0 && h.indexOf("<i>") >= 0)
      compare(strip(h), "***word***")
      compare(h.split("font-size:1px").length - 1, 4)
    }

    function test_emphasis_nests() {
      var h = Emph.html("**bold *and* italic**", "mono")
      verify(h.indexOf("<b>") >= 0 && h.indexOf("<i>") >= 0)
      compare(strip(h), "**bold *and* italic**")
    }

    // Markdown inside a code span is content.
    function test_code_holds_its_content_as_written() {
      var h = Emph.html("`a **b** c`", "mono")
      verify(h.indexOf("<b>") < 0)
      compare(strip(h), "`a **b** c`")
    }

    // `pre-wrap` is what keeps the spaces real; without it every offset
    // after a double space would be off by one.
    function test_spaces_are_kept() {
      verify(Emph.html("**a**  b ", "mono").indexOf("white-space:pre-wrap") >= 0)
    }

    function test_underscores_work_at_the_edges_of_words() {
      verify(Emph.has("an _italic_ word"))
      verify(Emph.has("an __bold__ word"))
      verify(!Emph.has("an_italic_word"))
    }
  }
}
