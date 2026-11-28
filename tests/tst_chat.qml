import QtQuick
import QtTest
import "../plugin-page/Chat.js" as Chat

// The chat's markdown, drawn as rich text (Chat.js, 2026-11-19): what Qt's
// markdown drew, with a line height and space between paragraphs.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_chat.qml
Item {
  TestCase {
    name: "Chat"
    readonly property var style: ({ fg: "#eeeeee", dim: "#999999", accent: "#ff8800", code: "Mono", leading: 132, gap: 11 })

    // What the reader sees: the text with the tags taken away. Qt draws one
    // character per character of this, which the passage marks rely on.
    function seen(h) {
      return h.replace(/<br\/>/g, "\n").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&amp;/g, "&")
    }

    function test_paragraphs_get_leading_and_a_gap() {
      var h = Chat.html("One line\nstill the first.\n\nThe second.", style)
      compare((h.match(/<p /g) || []).length, 2, h)
      verify(h.indexOf("line-height:132%") >= 0, "the leading is asked for: " + h)
      verify(h.indexOf("margin-bottom:11px") >= 0, "a gap after the first: " + h)
      verify(/margin-bottom:0px[^>]*>The second\.<\/p>$/.test(h), "none after the last: " + h)
      compare(seen(h), "One line still the first.The second.", "a soft break is a space")
    }

    function test_inline_emphasis_and_code() {
      var h = Chat.html("**bold**, *it*, _also_, `a*b*c` and ~~gone~~; snake_case_name stays", style)
      verify(h.indexOf("<b>bold</b>") >= 0, h)
      verify(h.indexOf("<i>it</i>") >= 0 && h.indexOf("<i>also</i>") >= 0, h)
      verify(h.indexOf("<code style=\"font-family:'Mono'\">a*b*c</code>") >= 0, "code keeps its stars: " + h)
      verify(h.indexOf("<s>gone</s>") >= 0, h)
      verify(h.indexOf("snake_case_name") >= 0, "underscores inside a word are not italic: " + h)
    }

    // A quote of the paper reads as prose: the words in the text's colour,
    // no underline, the page alone in the accent.
    function test_a_quote_link_is_prose_with_its_page_in_the_accent() {
      var h = Chat.html("They say [“were instructed to cycle” (p. 6)](quote:6:were%20instructed), but.", style)
      verify(h.indexOf("<a href=\"quote:6:were%20instructed\" style=\"color:#eeeeee;text-decoration:none\">“were instructed to cycle”") >= 0, h)
      verify(h.indexOf("<span style=\"color:#ff8800\">(p.&nbsp;6)</span></a>") >= 0, h)
      compare(seen(h), "They say “were instructed to cycle” (p. 6), but.")
    }

    function test_other_links_keep_the_accent() {
      var h = Chat.html("See [2026-11-18 · line 4](cite:human%2FDaily%2F2026-11-18.md#4) and <https://example.org/x>.", style)
      verify(h.indexOf("<a href=\"cite:human%2FDaily%2F2026-11-18.md#4\" style=\"color:#ff8800\">2026-11-18 · line 4</a>") >= 0, h)
      verify(h.indexOf("<a href=\"https://example.org/x\" style=\"color:#ff8800\">https://example.org/x</a>") >= 0, h)
    }

    function test_html_in_an_answer_is_only_text() {
      var h = Chat.html("a <b>tag</b> & 3 < 4", style)
      compare(seen(h), "a <b>tag</b> & 3 < 4")
      verify(h.indexOf("<b>tag") < 0, h)
    }

    function test_lists_nested_and_ordered() {
      var h = Chat.html("Steps:\n\n1. first\n2. second\n   - inner\n- after", style)
      verify(h.indexOf("<ol") >= 0 && h.indexOf("<ul") >= 0, h)
      compare((h.match(/<li /g) || []).length, 4, h)
      verify(/<li[^>]*>second<ul/.test(h.replace(/<\/li>/g, "")), "the inner list sits under its item: " + h)
    }

    function test_a_list_right_under_a_paragraph() {
      var h = Chat.html("Two things:\n- one\n- two", style)
      verify(/<p [^>]*>Two things:<\/p><ul/.test(h), h)
    }

    function test_code_fence_heading_quote_rule() {
      var h = Chat.html("## Head\n\n```\nx = *1*\n```\n\n> said\n> twice\n\n---\n\nend", style)
      verify(h.indexOf("<b>Head</b>") >= 0, h)
      verify(h.indexOf("<p style=\"font-family:'Mono';white-space:pre-wrap;margin-top:0;margin-bottom:11px\">x = *1*</p>") >= 0, h)
      verify(/margin-left:14px;color:#999999">said twice<\/p>/.test(h), h)
      verify(h.indexOf("<hr/>") >= 0, h)
    }

    function test_a_hard_break_stays() {
      compare(seen(Chat.html("one  \ntwo\\\nthree", style)), "one\ntwo\nthree")
    }

    // A table is drawn here too (2026-11-28): the answer around it keeps
    // its leading and its links, the cells their words' markdown.
    function test_a_table_is_drawn_in_the_chat() {
      var h = Chat.html("Before.\n\n| a | **b** |\n|:---|---:|\n| 1 | `x|y` |\n| 2 |\n\nAfter.", style)
      verify(h.indexOf("<table") >= 0, h)
      compare((h.match(/<th /g) || []).length, 2, h)
      compare((h.match(/<td /g) || []).length, 4, "a short row is filled to the head's width: " + h)
      verify(h.indexOf("<b>b</b>") >= 0 && h.indexOf("align=\"right\"") >= 0, h)
      verify(h.indexOf("x|y</code>") >= 0, "a bar in code is not a cell's edge: " + h)
      verify(/<p [^>]*>Before\.<\/p><table/.test(h) && /<\/table><p [^>]*>After\.<\/p>$/.test(h), h)
    }

    function test_a_table_right_under_a_paragraph() {
      var h = Chat.html("The plan:\n| day | what |\n|---|---|\n| Mon | read |", style)
      verify(/<p [^>]*>The plan:<\/p><table/.test(h), h)
    }

    function test_bullets_then_numbers_switch_lists() {
      var h = Chat.html("- a\n- b\n1. one\n2. two", style)
      verify(/<\/ul><ol/.test(h), "the bullets closed before the numbers: " + h)
      compare((h.match(/<ul/g) || []).length, 1, h)
      compare((h.match(/<ol/g) || []).length, 1, h)
    }

    function test_plain_words_keep_their_lines() {
      var h = Chat.plain("my <question>\nsecond line\n\nnew para", style)
      compare((h.match(/<p /g) || []).length, 2, h)
      verify(h.indexOf("my &lt;question&gt;<br/>second line") >= 0, h)
    }
  }
}
