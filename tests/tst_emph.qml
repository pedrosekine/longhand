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

    // A link inside emphasis (2026-10-27): the bold holds the link, the
    // link is drawn as one, and the plain text is still the body.
    function test_a_link_inside_bold() {
      var body = "**bold with [[Nesting|a link]] inside** and [[x]] `[[code]]`"
      var style = { color: "#0000ff", missing: "#888888", source: "#999999", reveal: -1, known: function (l) { return true } }
      var h = Emph.html(body, "monospace", style)
      compare(strip(h), body, "the plain text is the body")
      verify(/<b>bold with .*a link.* inside<\/b>/.test(h), "the bold holds the link: " + h)
      verify(h.indexOf("**") < 0 || /color:transparent[^>]*>\*\*/.test(h), "no ** drawn: " + h)
      verify(h.indexOf("color:#0000ff;text-decoration:underline\">a link") >= 0, "the link is drawn as one")
      verify(h.indexOf("color:#0000ff;text-decoration:underline\">code") < 0, "a link inside code is code")
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

    // Arrows (2026-10-27): the glyph over the first character, the rest to
    // nothing, and the field read back through `unarrow` is the body.
    function test_arrows_are_drawn_data() {
      return [
        { body: "a -> b", shows: "a \u2192 b" },
        { body: "a <- b", shows: "a \u2190 b" },
        { body: "a <-> b", shows: "a \u2194 b" },
        { body: "**x -> y** and `p->q`", shows: "x \u2192 y and p->q" },
        { body: "see [[a->b]] then ->", shows: "see [[a->b]] then \u2192" },
        { body: "x<-1 and -->", shows: "x\u21901 and -\u2192" }
      ]
    }

    function test_arrows_are_drawn(row) {
      verify(Emph.has(row.body))
      var h = Emph.html(row.body, "mono")
      var seen = strip(h.replace(/<span style="font-size:1px[^>]*>[^<]*<\/span>/g, "").replace(/<span style="font-family[^>]*>|<\/span>/g, "")).replace(/`/g, "")
      compare(seen, row.shows.replace(/`/g, ""))
      compare(Emph.unarrow(strip(h)), row.body, "read back, the field is the body")
      compare(strip(h).length, row.body.length, "one position per character")
    }

    // A body holding what a drawn arrow leaves behind would not read back
    // as itself, so it is left as written.
    function test_a_drawn_arrow_written_out_is_left_alone() {
      verify(!Emph.has("already \u2192> here ->"))
      compare(Emph.arrowsIn("already \u2192> here ->").length, 0)
    }

    // The cursor never stands inside an arrow; a click there lands after it.
    function test_an_arrow_is_one_place_to_the_cursor() {
      var stops = Emph.stops("a <-> b")
      compare(Emph.validCol(stops, 3, 7, 0), 5)
      compare(Emph.validCol(stops, 4, 7, 0), 5)
      compare(Emph.validCol(stops, 3, 7, -1), 2)
      compare(Emph.validCol(stops, 2, 7, 0), 2)
    }
  }
}
