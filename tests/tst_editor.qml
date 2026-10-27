import QtQuick
import QtTest
import "../plugin-page"
import "../plugin-page/Rows.js" as Rows

// The page's editor, driven by keys, offscreen.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_editor.qml
Item {
  id: top
  width: 600
  height: 800

  NoteEditor {
    id: ed
    width: 560
    height: implicitHeight
    textSize: 16
    fontFamily: "monospace"   // so "the same place on the next line" is a column
  }

  SignalSpy { id: kept; target: ed; signalName: "cueDismissed" }

  TestCase {
    name: "NoteEditor"
    when: windowShown

    function focused() { return ed.rowItem(ed.focusedRow).field }

    function start(t, pos) {
      ed.load(t)
      ed.setCursor(pos === undefined ? t.length : pos, true)
      verify(ed.hasFocus, "note has focus")
    }

    function type(s) {
      for (var i = 0; i < s.length; i++) keyClick(s.charAt(i))
    }

    function test_rows_lift_markdown() {
      var r = Rows.derive("\n# Title\n- [ ] read ch.7\n\t- [x] sub\n1. one\n> [!private] secret\n> more\npara")
      compare(r[0].lead, true)
      compare(r[1].kind, "heading"); compare(r[1].body, "Title"); compare(r[1].headingLevel, 1)
      compare(r[2].kind, "task"); compare(r[2].body, "read ch.7"); compare(r[2].checked, false)
      compare(r[3].kind, "task"); compare(r[3].checked, true); compare(r[3].level, 1)
      compare(r[4].kind, "ordered"); compare(r[4].ordinal, "1.")
      compare(r[5].kind, "calloutHead"); compare(r[5].callout, "private"); compare(r[5].body, "secret"); compare(r[5].priv, true)
      compare(r[6].kind, "quote"); compare(r[6].priv, true); compare(r[6].body, "more")
      compare(r[7].kind, "plain")
      compare(r[1].space, 0)      // the first text, under the leading blank
      compare(r[2].space, 0.35)   // under a heading
      compare(r[4].space, 0.25)   // the next item of a list
      compare(r[6].space, 0)      // a callout's next line
      compare(r[7].space, 0.5)    // a paragraph after it
    }

    function test_vertical_rhythm() {
      var r = Rows.derive("para one\npara two\n\n\n## Section\n- a\n\n# Top\ntext")
      compare(r[1].space, 0.25)                    // the next line of text
      compare(r[2].space, 0.75); compare(r[3].space, 0)   // blank lines: one paragraph's space
      compare(r[4].space, 1.4 - 0.75)              // a heading: its own space, the blank counted
      compare(r[5].space, 0.35)                    // under it
      compare(r[7].space, 2.0 - 0.75)              // H1 after a list and a blank
      compare(r[8].space, 0.35)
    }

    function test_fence_keeps_markdown() {
      var r = Rows.derive("```\n# not a heading\n```\n# heading")
      compare(r[1].kind, "code"); compare(r[1].body, "# not a heading")
      compare(r[3].kind, "heading")
    }

    function test_load_shows_bodies_only() {
      start("\n- [ ] read ch.7")
      compare(ed.rowItem(1).field.text, "read ch.7")
      compare(focused().cursorPosition, 9)
    }

    // Opening a shorter note must not leave the focused row pointing past
    // the end: everything that reads it (the drawn cursor, paste and Enter
    // over a selection) would quietly stop working.
    function test_a_shorter_note_drops_a_dangling_focus() {
      start("\nline one\nline two\nline three\nline four")
      verify(ed.focusedRow >= 3, "the cursor is on a late row (" + ed.focusedRow + ")")
      ed.load("\nshort")
      verify(ed.focusedRow < ed.rows.length, "focused row is inside the note (" + ed.focusedRow + "/" + ed.rows.length + ")")
      ed.setCursor(ed.length, true)
      compare(ed.rowItem(ed.focusedRow).field.text, "short")
    }

    // Emphasis writes the markers the file keeps; nothing is drawn styled.
    function test_bold_wraps_the_selection() {
      start("\nread chapter seven")
      ed.selectSpan(6, 13)                       // "chapter"
      ed.emphasise("**")
      compare(ed.text, "\nread **chapter** seven")
      compare(ed.selStart, 8); compare(ed.selEnd, 15)
    }

    function test_bold_takes_the_word_under_the_cursor() {
      start("\nread chapter seven", 9)          // inside "chapter"
      ed.emphasise("**")
      compare(ed.text, "\nread **chapter** seven")
    }

    function test_bold_again_takes_it_off() {
      start("\nread **chapter** seven", 11)     // inside the bold word
      ed.emphasise("**")
      compare(ed.text, "\nread chapter seven")
    }

    function test_markers_around_a_selection_come_off() {
      start("\nread **chapter** seven")
      ed.selectSpan(8, 15)                       // just the word, markers outside
      ed.emphasise("**")
      compare(ed.text, "\nread chapter seven")
    }

    function test_italic_on_a_bold_word_adds_a_pair() {
      start("\nread **chapter** seven", 11)
      ed.emphasise("*")
      compare(ed.text, "\nread ***chapter*** seven")
    }

    function test_emphasis_on_nothing_stands_inside_the_pair() {
      start("\n")
      ed.emphasise("**")
      compare(ed.text, "\n****")
      compare(ed.cursorPosition, 3)
    }

    function test_code_and_strike_use_their_own_markers() {
      start("\npomo status today", 8)          // inside "status"
      ed.emphasise("`")
      compare(ed.text, "\npomo `status` today")
      ed.selectSpan(17, 17)                    // the cursor inside "today", nothing selected
      ed.emphasise("~~")
      compare(ed.text, "\npomo `status` ~~today~~")
    }

    // Wrapping leaves the words selected, so a second marker nests around
    // the first — the same keystrokes a writer would use for bold italic.
    function test_a_second_marker_nests_around_the_selection() {
      start("\nread chapter seven", 9)
      ed.emphasise("*")
      compare(ed.text, "\nread *chapter* seven")
      ed.emphasise("**")
      compare(ed.text, "\nread ***chapter*** seven")
    }

    // Emphasis is drawn, not shown: the row becomes rich text whose plain
    // text is still the line's body, so every offset the editor counts on
    // stays where it was.
    function test_an_emphasised_row_is_drawn_rich() {
      start("\nread **chapter** seven", 1)
      var item = ed.rowItem(1)
      compare(item.rich, true)
      compare(item.field.textFormat, TextEdit.RichText)
      compare(item.plain(), "read **chapter** seven")
      compare(item.field.length, 22)
    }

    function test_a_row_without_emphasis_stays_plain() {
      start("\nread chapter seven", 1)
      var item = ed.rowItem(1)
      compare(item.rich, false)
      compare(item.field.textFormat, TextEdit.PlainText)
    }

    // What is drawn: a pair holding nothing is markers with no job, and
    // markers with no job are shown. The keys never leave one — see the
    // deletion tests below — but a note written elsewhere can.
    function test_breaking_a_pair_shows_it_again() {
      start("\nread **chapter** seven")
      compare(ed.rowItem(1).rich, true)
      ed.remove(ed.text.length - 7, ed.text.length - 6)   // one star of the closer
      compare(ed.text, "\nread **chapter* seven")
      compare(ed.rowItem(1).rich, false)
    }

    function test_typing_into_a_drawn_row_writes_through() {
      start("\nread **chapter** seven")
      type(" twice")
      compare(ed.text, "\nread **chapter** seven twice")
      compare(ed.rowItem(1).plain(), "read **chapter** seven twice")
    }

    // Ctrl+B on a word and the row turns rich under the cursor, which must
    // stay where the student left it.
    function test_the_cursor_holds_while_the_row_turns_rich() {
      start("\nread chapter seven", 9)
      ed.emphasise("**")
      compare(ed.text, "\nread **chapter** seven")
      compare(ed.rowItem(1).rich, true)
      ed.clearSelection()                        // wrapping left the words selected
      ed.setCursor(ed.text.length, true)
      type("!")
      compare(ed.text, "\nread **chapter** seven!")
    }

    // ---------------------------------------------------------- the cursor
    //
    // A pair of markers drawn to nothing is one thing to the cursor: it
    // never stands inside one, crosses a whole run in one press, and
    // Backspace takes the letter beyond it rather than the marker.

    function test_backspace_takes_the_letter_not_the_marker_data() {
      return [
        { body: "a **bold**", after: "a **bol**" },
        { body: "a *it*", after: "a *i*" },
        { body: "a ~~gone~~", after: "a ~~gon~~" },
        { body: "a ***both***", after: "a ***bot***" }
      ]
    }

    function test_backspace_takes_the_letter_not_the_marker(row) {
      start("\n" + row.body)
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n" + row.after)
      compare(ed.rowItem(1).rich, true, "and it is still drawn")
    }

    // Emptying an emphasis takes the emphasis with it, so the student is
    // never left looking at a `**` they did not type. It cascades through
    // bold italic.
    function test_emptying_an_emphasis_takes_the_pair_data() {
      return [
        { body: "a **b** c", after: "a  c" },
        { body: "a *i* c", after: "a  c" },
        { body: "a `x` c", after: "a  c" },
        { body: "a ~~z~~ c", after: "a  c" },
        { body: "a ***b*** c", after: "a  c" }
      ]
    }

    function test_emptying_an_emphasis_takes_the_pair(row) {
      start("\n" + row.body, 1 + row.body.indexOf(" c"))
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n" + row.after)
    }

    // Deleting forward from inside the words takes what is past the
    // markers, never one of them.
    function test_delete_forward_steps_over_the_markers() {
      start("\na **bold** c", 1 + 8)        // after the "d", inside the bold
      keyClick(Qt.Key_Delete)
      compare(ed.text, "\na **bold**c")
    }

    function test_the_cursor_crosses_a_run_in_one_press() {
      start("\na **b** c", 1 + 1)           // after the "a"
      var seen = []
      for (var i = 0; i < 4; i++) { keyClick(Qt.Key_Right); seen.push(ed.cursorPosition) }
      compare(JSON.stringify(seen), "[5,6,9,10]")   // 3,4 and 7,8 are markers
      for (var j = 0; j < 4; j++) keyClick(Qt.Key_Left)
      compare(ed.cursorPosition, 2)
    }

    // Shift+Right out of the words selects the word, not half a marker, so
    // the key takes the emphasis off what it drew.
    function test_selecting_the_drawn_word_then_the_key_unwraps_it() {
      start("\na **bold** c", 1 + 4)        // before the "b"
      for (var i = 0; i < 4; i++) keyClick(Qt.Key_Right, Qt.ShiftModifier)
      compare(focused().selectedText, "bold")
      ed.emphasise("**")
      compare(ed.text, "\na bold c")
    }

    // …and deleting that selection takes the markers with it.
    function test_deleting_the_drawn_word_takes_the_markers() {
      start("\na **bold** c", 1 + 4)
      for (var i = 0; i < 4; i++) keyClick(Qt.Key_Right, Qt.ShiftModifier)
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\na  c")
    }

    // Ctrl+Backspace takes the word, and with it the emphasis that held
    // only that word — never the markers on their own. A space left against
    // a marker goes too: `**two **` is not emphasis to markdown, so the
    // pair would come back for a space nobody can see.
    function test_ctrl_backspace_takes_the_word_and_its_emphasis() {
      start("\na **bold** c", 1 + 10)      // the end of the bold word
      keyClick(Qt.Key_Backspace, Qt.ControlModifier)
      compare(ed.text, "\na  c")
    }

    function test_ctrl_backspace_leaves_a_longer_emphasis_standing() {
      start("\na **two words** c", 1 + 15)
      keyClick(Qt.Key_Backspace, Qt.ControlModifier)
      compare(ed.text, "\na **two** c")
      compare(ed.rowItem(1).rich, true)
    }

    function test_deleting_the_last_word_of_an_emphasis_by_selection() {
      start("\na **two words** c", 1 + 8)     // before "words"
      for (var i = 0; i < 5; i++) keyClick(Qt.Key_Right, Qt.ShiftModifier)
      compare(focused().selectedText, "words")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\na **two** c")
    }

    // The one pair you do see: the key pressed with nothing to wrap writes
    // an empty one and stands inside it, which is the only signal that the
    // next letters will be bold. The first letter takes it away.
    function test_the_empty_pair_is_visible_until_it_holds_something() {
      start("\nwrite here ")
      ed.emphasise("**")
      compare(ed.text, "\nwrite here ****")
      compare(ed.rowItem(1).rich, false, "nothing to draw yet")
      compare(ed.cursorPosition, 14)
      type("x")
      compare(ed.text, "\nwrite here **x**")
      compare(ed.rowItem(1).rich, true)
    }

    // A line that begins with emphasis can still be written before, and
    // Backspace there still drops the line's kind rather than a marker.
    function test_a_line_that_begins_with_emphasis() {
      start("\n- **bold** item", 1 + 0)     // the body's own start
      compare(ed.rows[1].kind, "bullet")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n**bold** item")
      compare(ed.rows[1].kind, "plain")
    }

    function test_a_code_line_keeps_its_markdown() {
      start("\n```\na **b** c\n```")
      compare(ed.rows[2].kind, "code")
      compare(ed.rowItem(2).rich, false)
    }

    function test_typing_writes_through() {
      start("\nhello")
      type(" world")
      compare(ed.text, "\nhello world")
    }

    function test_typing_markdown_lifts_it() {
      start("\n")
      type("# Plan")
      compare(ed.text, "\n# Plan")
      compare(ed.rows[1].kind, "heading")
      compare(focused().text, "Plan")
      compare(focused().cursorPosition, 4)
    }

    function test_checkbox_shorthand() {
      start("\n")
      type("- [] read")   // the space after the box is already there
      compare(ed.text, "\n- [ ] read")
      compare(focused().text, "read")
      start("\n")
      type("[] go")
      compare(ed.text, "\n- [ ] go")
    }

    function test_enter_continues_list_and_leaves_it() {
      var left = -1
      var conn = function (i) { left = i }
      ed.listLeft.connect(conn)
      start("\n- [x] one")
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- [x] one\n- [ ] ")
      compare(ed.rows[2].kind, "task")
      compare(ed.focusedRow, 2)
      type("two")
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- [x] one\n- [ ] two\n")
      compare(left, 3)
      ed.listLeft.disconnect(conn)
    }

    // Formatting inside a quote or a callout (2026-10-27): a line read in
    // layers — the quote's `> `, then a line of its own.
    function test_a_box_inside_a_callout_is_a_box() {
      start("> [!private]\n> - [ ] call mum\n> - a bullet\n> ## Tonight\n> > deeper")
      compare(ed.rows[1].kind, "task")
      compare(ed.rows[1].body, "call mum")
      compare(ed.rows[2].kind, "bullet")
      compare(ed.rows[3].kind, "heading")
      compare(ed.rows[4].kind, "quote")
      compare(ed.rows[4].quoteDepth, 2)
      compare(ed.rows[4].body, "deeper")
    }

    function test_enter_inside_a_callout_carries_the_quote_and_the_box() {
      start("> [!private]\n> - [ ] one")
      keyClick(Qt.Key_Return)
      compare(ed.text, "> [!private]\n> - [ ] one\n> - [ ] ")
      keyClick(Qt.Key_Return)
      compare(ed.text, "> [!private]\n> - [ ] one\n> ", "an empty item leaves the list, not the quote")
      keyClick(Qt.Key_Return)
      compare(ed.text, "> [!private]\n> - [ ] one\n", "then an empty quote line leaves the quote")
    }

    function test_backspace_inside_a_quote_peels_a_layer_at_a_time() {
      start("> > - [ ] x", 6)          // before "x"
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "> > x", "the box first")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "> x", "then one quote")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "x", "then the other")
    }

    function test_tab_inside_a_callout_nests_inside_it() {
      start("> - a\n> - b")
      keyClick(Qt.Key_Tab)
      compare(JSON.stringify(ed.text), JSON.stringify("> - a\n> \t- b"))
      compare(ed.rows[1].level, 1)
      keyClick(Qt.Key_Backtab)              // what Shift+Tab arrives as
      compare(ed.text, "> - a\n> - b")
    }

    function test_a_box_inside_a_callout_ticks() {
      start("> - [ ] call mum")
      ed.toggleCheckbox(0)
      verify(/^> - \[x\] call mum ✅ \d{4}-\d{2}-\d{2}$/.test(ed.text), ed.text)
    }

    function test_enter_reports_finished_line() {
      var got = null
      var conn = function (i, t) { got = [i, t] }
      ed.returnFinished.connect(conn)
      start("\nwhat now?")
      keyClick(Qt.Key_Return)
      compare(got[0], 1); compare(got[1], "what now?")
      compare(ed.text, "\nwhat now?\n")
      ed.returnFinished.disconnect(conn)
    }

    function test_enter_mid_line_splits() {
      start("\n- [ ] alpha beta", 9)   // after "al"
      compare(focused().cursorPosition, 2)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- [ ] al\n- [ ] pha beta")
      compare(ed.focusedRow, 2)
      compare(focused().cursorPosition, 0)
    }

    function test_two_enters_make_a_new_block() {
      start("\nfirst")
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Return)
      type("second")
      compare(ed.text, "\nfirst\n\nsecond")
      compare(ed.rows[2].blank, true)
      verify(ed.rowItem(2).height > 0 && ed.rowItem(2).height < ed.rowItem(3).height)
    }

    // Enter on an empty nested item steps out a level, as Shift+Tab does;
    // only at the outermost level does it leave the list.
    function test_enter_on_an_empty_nested_item_steps_out_a_level() {
      var left = -1
      var conn = function (i) { left = i }
      ed.listLeft.connect(conn)
      start("\n- a\n\t- b\n\t\t- ")
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- a\n\t- b\n\t- ")
      compare(ed.focusedRow, 3)
      compare(left, -1)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- a\n\t- b\n- ")
      compare(left, -1)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- a\n\t- b\n")
      compare(left, 3)
      ed.listLeft.disconnect(conn)
    }

    function test_stepping_out_keeps_the_kind_and_the_writing_goes_on() {
      start("\n- [ ] a\n\t- [ ] ")
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- [ ] a\n- [ ] ")
      type("b")
      compare(ed.text, "\n- [ ] a\n- [ ] b")
      start("\n- a\n    - ")
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- a\n  - ")
    }

    function test_stepping_out_of_a_numbered_level_numbers_on() {
      start("\n1. a\n\t1. ")
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n1. a\n2. ")
    }

    // In the middle of a list, the list stays one block: no blank line.
    function test_stepping_out_mid_list_keeps_the_list_whole() {
      start("\n- a\n\t- \n- c", 8)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- a\n- \n- c")
      compare(ed.focusedRow, 2)
    }

    function test_stepping_out_is_one_undo() {
      start("\n- a\n\t- ")
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\n- a\n\t- ")
    }

    // Backspace: the kind first, then the indentation a level at a time.
    function test_backspace_takes_the_indent_a_level_at_a_time() {
      start("\n- a\n\t\t- b", 9)   // start of "b"
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- a\n\t\tb")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- a\n\tb")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- a\nb")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- ab")
    }

    function test_backspace_takes_kind_then_joins() {
      start("\npara\n- [ ] item", 9)   // start of "item"
      compare(focused().cursorPosition, 0)
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\npara\nitem")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\nparaitem")
      compare(ed.focusedRow, 1)
      compare(focused().cursorPosition, 4)
    }

    function test_delete_pulls_words_up() {
      start("\nfoo\n- [ ] bar", 4)
      keyClick(Qt.Key_Delete)
      compare(ed.text, "\nfoobar")
    }

    function test_arrows_skip_blank_lines() {
      start("\nabc\n\n\ndef", 2)
      keyClick(Qt.Key_Down)
      compare(ed.focusedRow, 4)
      keyClick(Qt.Key_Up)
      compare(ed.focusedRow, 1)
      keyClick(Qt.Key_Up)
      compare(ed.focusedRow, 1)   // the leading blank line is not a place
      keyClick(Qt.Key_End)
      keyClick(Qt.Key_Right)
      compare(ed.focusedRow, 4)
      compare(focused().cursorPosition, 0)
      keyClick(Qt.Key_Left)
      compare(ed.focusedRow, 1)
      compare(focused().cursorPosition, 3)
    }

    // A tick says the day it was done (✅, drawn quietly: the row's words
    // are still only the words), and an untick takes the day off again.
    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }

    function test_ctrl_l_ticks() {
      start("\n- [ ] read")
      var at = ed.cursorPosition
      keyClick(Qt.Key_L, Qt.ControlModifier)
      compare(ed.text, "\n- [x] read ✅ " + today())
      compare(ed.rows[1].checked, true)
      compare(ed.rows[1].body, "read")
      compare(ed.cursorPosition, at)
      keyClick(Qt.Key_L, Qt.ControlModifier)
      compare(ed.text, "\n- [ ] read")
      start("\nplain")
      keyClick(Qt.Key_L, Qt.ControlModifier)
      compare(ed.text, "\n- [ ] plain")
    }

    function test_click_ticks() {
      start("\n- [ ] read\n\nother")
      ed.clickCheckbox(1)
      compare(ed.text, "\n- [x] read ✅ " + today() + "\n\nother")
      compare(ed.focusedRow, 1)
    }

    function test_tab_nests_items() {
      start("\n- one\n- two")
      keyClick(Qt.Key_Tab)
      compare(ed.text, "\n- one\n\t- two")
      compare(ed.rows[2].level, 1)
      compare(focused().text, "two")
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      compare(ed.text, "\n- one\n- two")
    }

    function test_numbered_lists_nest() {
      // Tab under a number: a list of its own, starting at 1; the rest count on.
      start("\n1. one\n2. two\n3. three", 9)
      keyClick(Qt.Key_Tab)
      compare(ed.text, "\n1. one\n\t1. two\n2. three")
      compare(focused().text, "two")
      // Back out: it counts on from the item above.
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      compare(ed.text, "\n1. one\n2. two\n3. three")
    }

    function test_nesting_takes_the_level_kind() {
      // A bullet moved out under "1." continues the count; one moved in
      // under bullets becomes a bullet.
      start("\n1. what problem\n\t- agentic AI\n\t- steer")
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      compare(ed.text, "\n1. what problem\n\t- agentic AI\n2. steer")
      keyClick(Qt.Key_Tab)
      compare(ed.text, "\n1. what problem\n\t- agentic AI\n\t- steer")
      start("\n- [ ] task\n1. num", 13)
      keyClick(Qt.Key_Tab)
      compare(ed.text, "\n- [ ] task\n\t1. num")   // a checkbox lends no kind
    }

    function test_marker_typed_in_empty_item_replaces_it() {
      start("\n1. one\n\t1. ", 11)
      type("- ")
      compare(ed.text, "\n1. one\n\t- ")
      compare(ed.rows[2].kind, "bullet")
      type("sub")
      compare(ed.text, "\n1. one\n\t- sub")
      start("\n- ", 3)
      type("1. ")
      compare(ed.text, "\n1. ")
      start("\n1. ", 4)
      type("x - y")
      compare(ed.text, "\n1. x - y")   // only when the item has nothing else
    }

    function test_a_date_lights_up_as_it_is_typed() {
      start("\n- [ ] essay")
      type(" by fr")
      verify(!ed.rowItem(1).pending, "not a date yet")
      type("i")
      verify(ed.rowItem(1).pending, "the date is lit up, its pill pending")
      compare(ed.rows[1].cueAt, "essay ".length)
      verify(ed.rows[1].cueLabel.indexOf("Fri") === 0, ed.rows[1].cueLabel)
      start("\n- [ ] call mum")
      type(" by phone")
      verify(!ed.rowItem(1).pending, "by phone is no date")
      start("\n- [ ] old line by friday")
      verify(!ed.rowItem(1).pending, "only the line being written lights up")
    }

    function test_backspace_right_away_keeps_the_date_as_words() {
      kept.clear()
      start("\n- [ ] essay by fr")
      type("i")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- [ ] essay by fri", "nothing deleted")
      compare(kept.count, 1)
      compare(kept.signalArguments[0][0], "- [ ] essay by fri")
      // Later, Backspace is Backspace.
      kept.clear()
      start("\n- [ ] essay by fr")
      type("id")
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- [ ] essay by fri")
      compare(kept.count, 0)
    }

    function test_space_at_the_end_of_a_bound_lines_words() {
      var t = "\n- [ ] Initial paper 📅 2026-11-30 ^d9"
      start(t, 1 + "- [ ] Initial paper".length)
      type(" ")
      compare(focused().text, "Initial paper ", "the space stays with the words")
      type("v2")
      compare(ed.text, "\n- [ ] Initial paper v2 📅 2026-11-30 ^d9")
      compare(ed.rows[1].deadline, 9)
    }

    function test_undo_and_redo() {
      start("\nhello")
      type("!")
      keyClick(Qt.Key_Return)
      type("x")
      compare(ed.text, "\nhello!\nx")
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\nhello!\n")
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\nhello!")
      keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
      compare(ed.text, "\nhello!\n")
    }

    // A line the page catches up with the store (Page.catchUp) is written
    // into the saved states too: undoing the student's own edits around it
    // never takes it back, and redo keeps it as well.
    function test_rebase_is_never_undone() {
      var was = "- [ ] read 📅 2026-11-30 ^d9", now = "- [x] read 📅 2026-11-30 ^d9"
      start("\n" + was + "\nnotes")
      type("!")
      keyClick(Qt.Key_Return)
      type("x")
      ed.rebase(was, now)
      ed.replace(1, 1 + was.length, now)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\n" + now + "\nnotes!\n")
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\n" + now + "\nnotes!")
      keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
      compare(ed.text, "\n" + now + "\nnotes!\n")
      // A state where the line differs keeps its own: undoing to it is
      // the student's own words coming back, with the facts they had.
      ed.load("\n" + was + "\nnotes")
      ed.setCursor(1 + "- [ ] read".length, true)
      type("ing")
      var was2 = "- [ ] reading 📅 2026-11-30 ^d9", now2 = "- [x] reading 📅 2026-11-30 ^d9"
      ed.rebase(was2, now2)
      ed.replace(1, 1 + was2.length, now2)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\n" + was + "\nnotes")
    }

    function test_quote_continues_and_ends() {
      start("\n> [!private]")
      keyClick(Qt.Key_Return)
      type("mine")
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n> [!private]\n> mine\n")
      compare(ed.rows[2].priv, true)
    }

    function test_typed_callout_session() {
      start("\nq?\n")
      type("> [!private]")
      keyClick(Qt.Key_Return)
      type("secret")
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Return)
      type("after")
      compare(ed.text, "\nq?\n> [!private]\n> secret\nafter")
    }

    function test_soft_break_stays_in_item() {
      start("\n- [ ] read")
      keyClick(Qt.Key_Return, Qt.ShiftModifier)
      type("notes")
      compare(ed.text, "\n- [ ] read\n  notes")
      compare(ed.rows[2].kind, "plain")
      compare(ed.rows[2].level, 1)
    }

    function test_programmatic_edit_keeps_cursor() {
      start("\n- [ ] a\nzzz")
      ed.remove(4, 5)
      ed.insert(4, "x")
      compare(ed.text, "\n- [x] a\nzzz")
      compare(ed.cursorPosition, ed.text.length)
      compare(focused().cursorPosition, 3)
    }

    function test_paste_splits_into_rows() {
      start("\n")
      focused().insert(0, "one\n# two")   // what a paste does to the field
      compare(ed.text, "\none\n# two")
      compare(ed.rows[2].kind, "heading")
      compare(ed.focusedRow, 2)
    }

    // Paste goes through the note's own plain clipboard, so a drawn row —
    // which is rich text, and would read what it is handed as html — takes
    // the same characters a plain one would.
    function test_paste_into_a_drawn_row() {
      start("\nread **chapter** seven", 1)
      compare(ed.rowItem(1).rich, true)
      ed.copyText("  a < b  ")
      ed.setCursor(ed.text.length, true)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(ed.text, "\nread **chapter** seven  a < b  ")
    }

    // Offsets across a drawn row are the body's, so a selection that crosses
    // it carries the markdown, not what is drawn.
    function test_a_selection_across_a_drawn_row_is_the_markdown() {
      start("\nread **chapter** seven\nnext line")
      ed.selectSpan(1, ed.text.length)
      compare(ed.text.slice(ed.selStart, ed.selEnd), "read **chapter** seven\nnext line")
    }

    function test_cursor_rect_follows_new_line() {
      start("\nalpha\nbeta\n\ngamma")
      keyClick(Qt.Key_Return)
      var item = ed.rowItem(ed.focusedRow)
      compare(ed.focusedRow, 5)
      compare(ed.cursorRect.y, item.y + item.field.y + item.field.cursorRectangle.y)
      verify(ed.cursorRect.y > ed.rowItem(4).y)
    }

    function test_marks_map_to_bodies() {
      start("\n- [ ] read ch.7\nread more")
      var marks = [{ start: 7, end: 11 }, { start: 16, end: 20 }]   // the two "read"s
      var a = ed.marksIn(1, marks, 1, ed.rows)
      compare(a.length, 1); compare(a[0].a, 0); compare(a[0].b, 4); compare(a[0].kind, "match")
      var b = ed.marksIn(2, marks, 1, ed.rows)
      compare(b[0].a, 0); compare(b[0].kind, "current")
    }

    function test_select_lands_on_match() {
      start("\n- [ ] read ch.7\nnext", 1)
      ed.select(12, 14)   // "ch"
      compare(ed.focusedRow, 1)
      compare(focused().selectedText, "ch")
      compare(ed.cursorPosition, 14)
      type("X")
      compare(ed.text, "\n- [ ] read X.7\nnext")
    }

    function test_rect_at() {
      start("\nalpha\nbeta")
      var r = ed.rectAt(8)
      verify(r !== null)
      compare(r.y, ed.rowItem(2).y + ed.rowItem(2).field.y)
    }

    function test_shift_down_selects_across_lines() {
      start("\n- [ ] alpha\n- [ ] beta\ngamma", 9)   // after "al"
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      verify(ed.spanning)
      compare(ed.selStart, 9)
      compare(ed.text.slice(ed.selStart, ed.selEnd), "pha\n- [ ] be")
      keyClick(Qt.Key_Right, Qt.ShiftModifier)
      compare(ed.text.slice(ed.selStart, ed.selEnd), "pha\n- [ ] bet")
      type("X")
      compare(ed.text, "\n- [ ] alXa\ngamma")
      verify(!ed.spanning)
    }

    function test_selection_grows_from_a_line_selection() {
      start("\none two\nthree", 5)   // after "one "
      keyClick(Qt.Key_End, Qt.ShiftModifier)        // the field's own: "two"
      compare(focused().selectedText, "two")
      keyClick(Qt.Key_Down, Qt.ShiftModifier)       // carries on into "three"
      verify(ed.spanning)
      compare(ed.selAnchor, 5)
    }

    function test_backspace_and_escape_on_span() {
      start("\nabc\ndef\nghi", 2)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Escape)
      verify(!ed.spanning)
      compare(ed.text, "\nabc\ndef\nghi")
      ed.setCursor(2, true)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\nahi")
      compare(ed.cursorPosition, 2)
    }

    function test_plain_arrow_collapses_span() {
      start("\nabc\ndef", 2)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Left)
      verify(!ed.spanning)
      compare(ed.cursorPosition, 2)
    }

    function test_tab_nests_every_selected_item() {
      start("\n- one\n- two\n- three", 3)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Tab)
      compare(ed.text, "\n\t- one\n\t- two\n\t- three")
      verify(ed.spanning)
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      compare(ed.text, "\n- one\n- two\n- three")
    }

    function test_cut_and_paste_carry_markdown() {
      start("\n- [ ] alpha\n# head\ntail", 7)
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_End, Qt.ShiftModifier)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(ed.text, "\n- [ ] \ntail")
      keyClick(Qt.Key_End, Qt.ControlModifier)
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(ed.text, "\n- [ ] \ntail\nalpha\n# head")
      compare(ed.rows[4].kind, "heading")
    }

    function test_ctrl_a_selects_everything() {
      start("\none\ntwo", 2)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_A, Qt.ControlModifier)             // line, block, then everything
      compare(ed.selStart, 0); compare(ed.selEnd, ed.text.length)
    }

    function test_mouse_drag_selects_across_lines() {
      start("\nalpha\nbeta\ngamma", 1)
      var a = ed.rowItem(1), c = ed.rowItem(3)
      mousePress(ed, a.field.x + 2, a.y + a.height / 2)
      mouseMove(ed, c.field.x + c.field.width - 2, c.y + c.height / 2)
      mouseRelease(ed, c.field.x + c.field.width - 2, c.y + c.height / 2)
      verify(ed.spanning)
      compare(ed.text.slice(ed.selStart, ed.selEnd), "alpha\nbeta\ngamma")
    }

    // Where column `col` of row i is drawn, in editor coordinates.
    function spot(i, col) {
      var it = ed.rowItem(i), f = it.field
      var r = f.positionToRectangle(col)
      return { x: f.x + r.x + 1, y: it.y + f.y + r.y + r.height / 2 }
    }
    function picked() {
      if (ed.spanning) return ed.text.slice(ed.selStart, ed.selEnd)
      var it = ed.rowItem(ed.focusedRow)
      return it ? it.field.selectedText : ""
    }

    // A paragraph that wraps onto three lines, selected whole: its middle
    // line is painted too, not only the first and the last.
    function test_a_wrapped_selection_paints_every_line() {
      var long = "a long paragraph that wraps across several lines on the page, the way prose does when a thought is written down by hand and goes on for longer than one line"
      start("\nshort\n" + long + "\nafter", 1)
      var f = ed.rowItem(2).field
      var lineH = f.positionToRectangle(0).height
      verify(f.contentHeight > lineH * 2.5, "the paragraph wraps onto three lines or more")
      mousePress(ed, spot(1, 0).x, spot(1, 0).y)
      mouseMove(ed, spot(3, 3).x, spot(3, 3).y)
      mouseRelease(ed, spot(3, 3).x, spot(3, 3).y)
      compare(picked(), "short\n" + long + "\naft")
      var it = ed.rowItem(2)
      var img = grabImage(ed)
      // The middle line's right edge, past where its words stop.
      verify(Qt.colorEqual(img.pixel(f.x + f.width - 1, it.y + f.y + lineH * 1.5), ed.selectionColor),
             "the middle line is painted")
    }

    // A drag passing over blank lines never moves the lines below: a blank
    // line opens to a full line only for a cursor, not for a selection.
    function test_a_drag_over_blank_lines_holds_the_page_still() {
      start("\nalpha one\n\nbeta two\n\n\ngamma three", 1)
      var x = spot(1, 3).x, y0 = spot(1, 3).y, y1 = spot(6, 3).y
      var gammaY = ed.rowItem(6).y
      mousePress(ed, x, y0)
      for (var y = y0; y <= y1; y++) {
        mouseMove(ed, x, y)
        compare(ed.rowItem(6).y, gammaY, "still at y " + y)
      }
      mouseRelease(ed, x, y1)
      compare(picked(), "ha one\n\nbeta two\n\n\ngam")
      compare(ed.rowItem(6).y, gammaY)
    }

    function test_a_click_on_a_blank_line_still_opens_it() {
      start("\nalpha\n\nbeta", 1)
      var it = ed.rowItem(2)
      var h = it.height
      mouseClick(ed, 20, it.y + it.height / 2)
      compare(ed.focusedRow, 2)
      verify(ed.rowItem(2).height > h, "opened to a line's height")
    }

    function test_triple_click_selects_the_line() {
      start("\n- [ ] one two three\nfour five six", 1)
      var p = spot(1, 5)
      mouseDoubleClickSequence(ed, p.x, p.y)
      compare(picked(), "two")
      mouseClick(ed, p.x, p.y)
      compare(picked(), "one two three")
      keyClick("X")
      compare(ed.text, "\n- [ ] X\nfour five six")
    }

    // Held after a double-click, the selection grows a word at a time,
    // keeping the first word whichever way it goes.
    function test_double_click_drag_grows_by_words() {
      start("\none two three\nfour five six", 1)
      var p = spot(1, 5)
      // Pressed twice, quickly: the second press is a double-click, held.
      mousePress(ed, p.x, p.y); mouseRelease(ed, p.x, p.y, Qt.LeftButton, Qt.NoModifier, 1)
      mousePress(ed, p.x, p.y, Qt.LeftButton, Qt.NoModifier, 1)
      compare(picked(), "two")
      mouseMove(ed, spot(2, 6).x, spot(2, 6).y)
      compare(picked(), "two three\nfour five")
      mouseMove(ed, spot(1, 1).x, spot(1, 1).y)
      compare(picked(), "one two")
      mouseMove(ed, p.x + 3, p.y)
      compare(picked(), "two")
      mouseRelease(ed, p.x + 3, p.y)
    }

    function test_triple_click_drag_grows_by_lines() {
      start("\nalpha one\nbeta two\ngamma three", 1)
      var p = spot(2, 2)
      mouseDoubleClickSequence(ed, p.x, p.y)
      mousePress(ed, p.x, p.y)
      compare(picked(), "beta two")
      mouseMove(ed, spot(3, 1).x, spot(3, 1).y)
      compare(picked(), "beta two\ngamma three")
      mouseMove(ed, spot(1, 4).x, spot(1, 4).y)
      compare(picked(), "alpha one\nbeta two")
      mouseRelease(ed, spot(1, 4).x, spot(1, 4).y)
    }

    function test_shift_click_carries_on_from_a_double_clicked_word() {
      start("\none two three\nfour five six", 1)
      mouseDoubleClickSequence(ed, spot(1, 5).x, spot(1, 5).y)
      mouseClick(ed, spot(2, 9).x, spot(2, 9).y, Qt.LeftButton, Qt.ShiftModifier)
      compare(picked(), "two three\nfour five")
    }

    function test_click_still_ticks_through_pointer() {
      start("\n- [ ] read\nother")
      var r = ed.rowItem(1)
      mouseClick(ed, r.box.x + r.box.width / 2, r.y + r.box.y + r.box.height / 2)
      compare(ed.text, "\n- [x] read ✅ " + today() + "\nother")
    }

    function test_bound_tail_is_lifted() {
      var r = Rows.derive("- [ ] chapter 2 draft #thesis 📅 2026-10-16 17:00 ^d6")
      compare(r[0].body, "chapter 2 draft #thesis")
      compare(r[0].deadline, 6)
      compare(r[0].dueLabel.indexOf("16 Oct · 17:00") >= 0, true)
      var u = Rows.derive("- [ ] old 📅 2026-10-16")[0]
      compare(u.body, "old"); compare(u.deadline, 0); verify(u.dueLabel !== "")
      compare(Rows.derive("- [ ] typing ")[0].body, "typing ")   // trailing space stays
      compare(Rows.derive("plain 📅 2026-10-16")[0].body, "plain 📅 2026-10-16")
    }

    function test_typing_keeps_the_tail() {
      start("\n- [ ] draft 📅 2026-10-16 ^d6", 12)   // end of "draft"
      compare(focused().text, "draft")
      type("s")
      compare(ed.text, "\n- [ ] drafts 📅 2026-10-16 ^d6")
    }

    function test_enter_at_end_of_bound_line_starts_after_tail() {
      start("\n- [ ] draft 📅 2026-10-16 ^d6", 12)
      keyClick(Qt.Key_Return)
      compare(ed.text, "\n- [ ] draft 📅 2026-10-16 ^d6\n- [ ] ")
    }

    function test_backspace_on_bound_box_drops_the_tail() {
      start("\n- [ ] draft 📅 2026-10-16 ^d6", 7)   // start of "draft"
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\ndraft")
    }

    function test_joins_keep_the_tail_at_the_end() {
      start("\n- [ ] draft 📅 2026-10-16 ^d6\nmore", 12)
      keyClick(Qt.Key_Delete)
      compare(ed.text, "\n- [ ] draftmore 📅 2026-10-16 ^d6")
      start("\n- [ ] draft 📅 2026-10-16 ^d6\nmore", 31)   // start of "more" (📅 is two UTF-16 units)
      keyClick(Qt.Key_Backspace)
      compare(ed.text, "\n- [ ] draftmore 📅 2026-10-16 ^d6")
      compare(ed.cursorPosition, 12)
    }

    function test_word_steps() {
      compare(Rows.wordStep("one two  three", 0, 1), 4)
      compare(Rows.wordStep("one two  three", 5, 1), 9)
      compare(Rows.wordStep("one two  three", 9, -1), 4)
      compare(Rows.wordStep("one two", 7, -1), 4)
      compare(Rows.wordStep("ação e año", 0, 1), 5)        // accents stay inside a word
      compare(Rows.wordStep("end.", 0, 1), 4)
    }

    function test_ctrl_shift_right_selects_a_word() {
      start("\nalpha beta gamma\nnext line", 1)
      keyClick(Qt.Key_Right, Qt.ControlModifier | Qt.ShiftModifier)
      verify(!ed.spanning)
      compare(focused().selectedText.trim(), "alpha")
      keyClick(Qt.Key_Right, Qt.ControlModifier | Qt.ShiftModifier)
      compare(focused().selectedText.trim(), "alpha beta")
    }

    function test_ctrl_shift_left_selects_a_word_back() {
      start("\nalpha beta gamma", 17)   // end of the line
      keyClick(Qt.Key_Left, Qt.ControlModifier | Qt.ShiftModifier)
      compare(focused().selectedText, "gamma")
    }

    function test_ctrl_shift_right_carries_on_by_word_across_lines() {
      start("\nalpha\nnext line", 6)   // end of "alpha"
      keyClick(Qt.Key_Right, Qt.ControlModifier | Qt.ShiftModifier)   // the line break
      verify(ed.spanning)
      keyClick(Qt.Key_Right, Qt.ControlModifier | Qt.ShiftModifier)   // "next "
      compare(ed.text.slice(ed.selStart, ed.selEnd), "\nnext ")
    }

    function test_ctrl_right_at_line_end_goes_on() {
      start("\nalpha\nnext", 6)
      keyClick(Qt.Key_Right, Qt.ControlModifier)
      compare(ed.focusedRow, 2)
      compare(focused().cursorPosition, 0)
    }

    function test_ctrl_shift_end_still_reaches_the_note_end() {
      start("\nalpha\nnext", 2)
      keyClick(Qt.Key_End, Qt.ControlModifier | Qt.ShiftModifier)
      verify(ed.spanning)
      compare(ed.selEnd, ed.text.length)
    }

    function test_ctrl_shift_up_selects_to_block_start() {
      // One paragraph of three lines, then a blank, then another block.
      start("\nfirst line\nsecond line\nthird line\n\nnext block", 20)   // "second l|ine"
      keyClick(Qt.Key_Up, Qt.ControlModifier | Qt.ShiftModifier)
      verify(ed.spanning)
      compare(ed.text.slice(ed.selStart, ed.selEnd), "first line\nsecond l")
    }

    function test_ctrl_shift_down_selects_to_block_end() {
      start("\nfirst line\nsecond line\nthird line\n\nnext block", 18)   // after "first l" + "ine\ns"
      keyClick(Qt.Key_Down, Qt.ControlModifier | Qt.ShiftModifier)
      compare(ed.text.slice(ed.selStart, ed.selEnd), ed.text.slice(18, ed.text.indexOf("\n\nnext")))
    }

    function test_ctrl_shift_again_takes_the_next_block() {
      start("\nfirst block\n\nsecond block\nstill second\n\nthird", 2)
      keyClick(Qt.Key_Down, Qt.ControlModifier | Qt.ShiftModifier)   // to the end of "first block"
      compare(ed.selEnd, ed.text.indexOf("\n\nsecond"))
      keyClick(Qt.Key_Down, Qt.ControlModifier | Qt.ShiftModifier)   // on through the second block
      compare(ed.selStart, 2)
      compare(ed.selEnd, ed.text.indexOf("\n\nthird"))
      keyClick(Qt.Key_Up, Qt.ControlModifier | Qt.ShiftModifier)     // back to the second block's start
      compare(ed.selEnd, ed.text.indexOf("second block"))
    }

    function test_ctrl_shift_up_on_a_list_item_stops_at_its_text() {
      start("\n- [ ] read ch.7 carefully", 17)   // "read ch.7 |carefully"
      keyClick(Qt.Key_Up, Qt.ControlModifier | Qt.ShiftModifier)
      compare(ed.text.slice(ed.selStart, ed.selEnd), "read ch.7 ")   // the box is not part of the words
    }

    function test_alt_up_down_move_the_line() {
      start("\none\n- [ ] two\nthree", 12)             // "t|wo"
      keyClick(Qt.Key_Up, Qt.AltModifier)
      compare(ed.text, "\n- [ ] two\none\nthree")
      compare(ed.cursorPosition, 8)                        // still "t|wo"
      keyClick(Qt.Key_Down, Qt.AltModifier)
      keyClick(Qt.Key_Down, Qt.AltModifier)
      compare(ed.text, "\none\nthree\n- [ ] two")
      keyClick(Qt.Key_Down, Qt.AltModifier)                // the last line stays last
      compare(ed.text, "\none\nthree\n- [ ] two")
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      compare(ed.text, "\none\n- [ ] two\nthree")       // each move is one undo
    }

    function test_alt_up_moves_every_line_selected() {
      start("\na\nb\nc\nd", 3)                          // in "b"
      ed.selectSpan(3, 6)                                  // "b" through "c"
      keyClick(Qt.Key_Up, Qt.AltModifier)
      compare(ed.text, "\nb\nc\na\nd")
      compare(ed.text.slice(ed.selStart, ed.selEnd), "b\nc")
    }

    function test_ctrl_a_climbs_line_block_note() {
      var t = "\nfirst one\nfirst two\n\n- [ ] solo\n\nlast"
      start(t, t.indexOf("irst two"))
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), "first two")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), "first one\nfirst two")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), t)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), t)
    }

    function test_ctrl_a_passes_a_step_that_changes_nothing() {
      var t = "\nfirst\n\n- [ ] solo\n\nlast"
      start(t, t.indexOf("olo"))
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), "solo")
      keyClick(Qt.Key_A, Qt.ControlModifier)          // the block is the line: on to the note
      compare(picked(), t)
      start(t, t.indexOf("\n\n- ") + 1)               // a blank line holds nothing of its own
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), t)
    }

    function test_ctrl_a_climbs_from_a_selection_made_by_hand() {
      var t = "\nfirst one\nfirst two\n\nlast"
      start(t, t.indexOf("first two"))
      for (var i = 0; i < 5; i++) keyClick(Qt.Key_Right, Qt.ShiftModifier)
      compare(picked(), "first")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), "first two")
      ed.selectSpan(t.indexOf("first two"), t.length - 1)   // across the blank line: the block is not enough
      keyClick(Qt.Key_A, Qt.ControlModifier)
      compare(picked(), t)
    }

    function test_ctrl_a_then_typing_replaces_what_the_step_took() {
      var t = "\nfirst one\nfirst two\n\nlast"
      start(t, t.indexOf("irst two"))
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      type("x")
      compare(ed.text, "\nx\n\nlast")
    }

    function test_escape_lets_go_and_the_cursor_comes_back() {
      var t = "\nfirst one\nfirst two\n\nlast"
      var at = t.indexOf("irst two")
      start(t, at)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_Escape)
      verify(!ed.spanning)
      compare(ed.cursorPosition, at)
      compare(ed.text, t)
      // by hand, the cursor stays at the end that moved
      start(t, t.indexOf("first one"))
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      keyClick(Qt.Key_Escape)
      verify(!ed.spanning)
      compare(ed.cursorPosition, t.indexOf("first two"))
    }

    function test_escape_on_words_picked_in_a_line_only_lets_go() {
      var filtered = []
      ed.keyFilter = function (e) { if (e.key === Qt.Key_Escape) filtered.push(e.key); return e.key === Qt.Key_Escape }
      start("\nfirst one", 1)
      for (var i = 0; i < 5; i++) keyClick(Qt.Key_Right, Qt.ShiftModifier)
      var seen = picked()
      keyClick(Qt.Key_Escape)
      var after = picked(), asked = filtered.length
      keyClick(Qt.Key_Escape)
      var next = filtered.length
      ed.keyFilter = null
      compare(seen, "first")
      compare(after, "")
      compare(asked, 0)                                  // the page was not asked
      compare(next, 1)                                   // the next one is the page's
    }

    function test_block_rect() {
      start("\nalpha\nbeta\n\ngamma")
      var r = ed.blockRect(1, 3)
      verify(r !== null)
      compare(r.y, ed.rowItem(1).y)
      compare(r.h, ed.rowItem(2).y + ed.rowItem(2).height - ed.rowItem(1).y)
    }
  }
}
