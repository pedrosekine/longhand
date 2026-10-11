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
      compare(r[2].gapAbove, true)
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

    function test_ctrl_l_ticks() {
      start("\n- [ ] read")
      keyClick(Qt.Key_L, Qt.ControlModifier)
      compare(ed.text, "\n- [x] read")
      compare(ed.rows[1].checked, true)
      keyClick(Qt.Key_L, Qt.ControlModifier)
      compare(ed.text, "\n- [ ] read")
      start("\nplain")
      keyClick(Qt.Key_L, Qt.ControlModifier)
      compare(ed.text, "\n- [ ] plain")
    }

    function test_click_ticks() {
      start("\n- [ ] read\n\nother")
      ed.clickCheckbox(1)
      compare(ed.text, "\n- [x] read\n\nother")
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

    function test_click_still_ticks_through_pointer() {
      start("\n- [ ] read\nother")
      var r = ed.rowItem(1)
      mouseClick(ed, r.box.x + r.box.width / 2, r.y + r.box.y + r.box.height / 2)
      compare(ed.text, "\n- [x] read\nother")
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

    function test_block_rect() {
      start("\nalpha\nbeta\n\ngamma")
      var r = ed.blockRect(1, 3)
      verify(r !== null)
      compare(r.y, ed.rowItem(1).y)
      compare(r.h, ed.rowItem(2).y + ed.rowItem(2).height - ed.rowItem(1).y)
    }
  }
}
