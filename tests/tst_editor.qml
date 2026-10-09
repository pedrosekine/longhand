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

    function test_block_rect() {
      start("\nalpha\nbeta\n\ngamma")
      var r = ed.blockRect(1, 3)
      verify(r !== null)
      compare(r.y, ed.rowItem(1).y)
      compare(r.h, ed.rowItem(2).y + ed.rowItem(2).height - ed.rowItem(1).y)
    }
  }
}
