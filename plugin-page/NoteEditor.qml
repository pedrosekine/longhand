import QtQuick
import "Rows.js" as Rows

// The sheet's editor: the note drawn, not shown as markdown.
//
// One text field per line, each holding only the words. A heading is set
// large, a checkbox is a box you can click (or Ctrl+L), a bullet is a dot, a
// number is a number, a quote or callout carries a bar, and a private callout
// says so. Blank lines are drawn as space between blocks — more than between
// the lines of one block — so the block the agent answers is the block you
// see. Typing the markdown (`# `, `- [ ] `, `> `) turns the line into that
// kind on the spot; Backspace at the start of a line takes the kind off.
//
// Underneath it is still one plain text: `text` is the note body exactly as
// it goes to disk, `cursorPosition` an offset into it, and `insert`/`remove`
// edit it like the TextEdit this replaced. Every edit goes through that text
// and the rows are re-derived from it, so nothing is ever written that the
// student did not type.
//
// Keys the page owns (Esc, the send prompt, block jumps, the margin) reach
// `keyFilter` first; whatever it does not take is editing.
//
// Selecting: inside one line the field's own selection does the work. A
// selection that crosses lines (Shift+arrows past a line's edge, a drag
// with the mouse, Ctrl+A) is held here as text offsets and painted;
// typing, Backspace/Delete, cut, copy, paste, Enter and Tab/Shift+Tab act
// on all of it. Copying it copies the markdown, so pasting brings the kinds
// back.
Item {
  id: ed

  property string text: ""
  property int cursorPosition: 0
  readonly property int length: text.length

  // function (event) -> bool; true when the page consumed the key.
  property var keyFilter: null

  property string fontFamily: "sans-serif"
  property int textSize: 16
  property color foreground: "black"
  property color background: "white"
  property color dim: "gray"
  property color faint: "lightgray"
  property color selectionColor: "lightblue"
  property color accent: "orange"
  property color urgent: "red"

  // What each kind of line is drawn in. The page fills these from the
  // Omarchy theme (ThemeColors.qml); the defaults only keep the editor usable
  // on its own (tests).
  property var headingColors: [foreground, foreground, foreground, foreground]   // h1, h2, h3, h4–h6
  property color markColor: Qt.rgba(1, 0.85, 0.2, 0.35)        // a search match
  property color currentMarkColor: Qt.rgba(1, 0.6, 0.1, 0.55)  // the current one
  property color boxColor: dim                                  // an open checkbox
  property color checkColor: dim                                // a ticked one
  property color bulletColor: dim                               // dots and numbers
  property color quoteColor: faint                              // a quote's bar
  property color privateColor: dim                              // a private callout's bar and label
  property color codeColor: dim                                 // fenced code
  property real tabStop: textSize * 2

  // Space: within a block nothing, between blocks without a blank line a
  // little, across a blank line clearly more.
  readonly property int blockGap: Math.round(textSize * 0.85)
  readonly property int smallGap: Math.round(textSize * 0.3)
  readonly property int markerWidth: Math.round(textSize * 1.5)
  readonly property int quoteWidth: Math.round(textSize * 0.9)

  // Which row holds the keyboard focus (-1: none), and the cursor in
  // editor coordinates, for the page to keep in view and to hang the send
  // prompt under.
  property int focusedRow: -1
  readonly property bool hasFocus: focusedRow >= 0
  property rect cursorRect: Qt.rect(0, 0, 0, 0)

  // Search matches to paint, as text offsets ({ start, end }), and which of
  // them is the current one. Painting only: they never touch the text.
  property var marks: []
  property int currentMark: -1

  // A selection across lines, as text offsets (-1: none).
  property int selAnchor: -1
  property int selCursor: -1
  readonly property bool spanning: selAnchor >= 0 && selCursor >= 0 && selAnchor !== selCursor
  readonly property int selStart: Math.min(selAnchor, selCursor)
  readonly property int selEnd: Math.max(selAnchor, selCursor)

  // True while a cut is being applied: what leaves the text is on the
  // clipboard, so a bound line going with it is moving, not being deleted.
  property bool cutting: false

  // Enter finished a line (the line as it was before the break), and Enter
  // on an empty item left a list. The page decides what they mean.
  signal returnFinished(int lineIndex, string lineText)
  signal listLeft(int lineIndex)

  implicitHeight: column.height

  property var rows: []          // Rows.derive(text), kept in step with the model
  property bool syncing: false
  property var undoStack: []
  property var redoStack: []
  property double lastSnapshot: 0

  // ------------------------------------------------------------ the text

  // Replace everything (a load from disk). The cursor goes to the end and
  // the undo history starts over.
  function load(t) {
    ed.clearSelection()
    ed.undoStack = []
    ed.redoStack = []
    ed.commit(t, t.length)
    ed.placeCursor(false)
  }

  // Programmatic edits, with the cursor carried along the way TextEdit
  // carries it: text inserted at or before the cursor pushes it forward.
  function replace(a, b, s) {
    var cur = ed.cursorPosition
    if (cur >= b) cur += s.length - (b - a)
    else if (cur > a) cur = a + s.length
    ed.commit(ed.text.slice(0, a) + s + ed.text.slice(b), cur)
    ed.placeCursor(false)
  }
  function insert(pos, s) { ed.replace(pos, pos, s) }
  function remove(a, b) { ed.replace(a, b, "") }

  // Move the cursor. With `focus`, the note takes the keyboard too;
  // otherwise the field only follows when the note already has it.
  function setCursor(pos, focus) {
    ed.cursorPosition = Math.max(0, Math.min(ed.text.length, pos))
    ed.placeCursor(focus === true)
  }

  function focusNote() { ed.placeCursor(true) }

  function commit(t, cur) {
    ed.cursorPosition = Math.max(0, Math.min(t.length, cur))
    if (t !== ed.text) {
      ed.text = t
      ed.syncRows()
    } else if (ed.rows.length === 0) {
      ed.syncRows()
    }
  }

  // ------------------------------------------------------------ undo

  // Typing within a moment of the last edit joins its undo step; anything
  // structural (Enter, merging lines, ticking) is a step of its own.
  function snapshot(force) {
    var now = Date.now()
    var join = !force && now - ed.lastSnapshot < 900
    ed.lastSnapshot = force ? 0 : now
    if (join && ed.undoStack.length > 0) return
    var s = ed.undoStack.slice(Math.max(0, ed.undoStack.length - 299))
    s.push({ text: ed.text, cursor: ed.cursorPosition })
    ed.undoStack = s
    ed.redoStack = []
  }

  function undo() {
    if (ed.undoStack.length === 0) return
    var s = ed.undoStack[ed.undoStack.length - 1]
    ed.undoStack = ed.undoStack.slice(0, -1)
    ed.redoStack = ed.redoStack.concat([{ text: ed.text, cursor: ed.cursorPosition }])
    ed.lastSnapshot = 0
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  function redo() {
    if (ed.redoStack.length === 0) return
    var s = ed.redoStack[ed.redoStack.length - 1]
    ed.redoStack = ed.redoStack.slice(0, -1)
    ed.undoStack = ed.undoStack.concat([{ text: ed.text, cursor: ed.cursorPosition }])
    ed.lastSnapshot = 0
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  // ------------------------------------------------------------ rows

  readonly property var roles: ["kind", "body", "level", "checked", "ordinal", "headingLevel", "callout", "priv", "blank", "lead", "gapAbove", "deadline", "dueLabel", "dueAt"]

  function roleValues(r) {
    var o = {}
    for (var k = 0; k < ed.roles.length; k++) o[ed.roles[k]] = r[ed.roles[k]]
    return o
  }

  // Bring the model in line with the text, touching only the rows that
  // changed, so the field being typed in is never rebuilt under the cursor.
  function syncRows() {
    var next = Rows.derive(ed.text)
    var prev = ed.rows
    var a = 0
    while (a < prev.length && a < next.length && prev[a].raw === next[a].raw) a++
    var b = 0
    while (b < prev.length - a && b < next.length - a
           && prev[prev.length - 1 - b].raw === next[next.length - 1 - b].raw) b++
    var oldMid = prev.length - a - b
    var newMid = next.length - a - b
    ed.syncing = true
    ed.rows = next
    if (oldMid > newMid) rowModel.remove(a + newMid, oldMid - newMid)
    for (var k = oldMid; k < newMid; k++) rowModel.insert(a + k, ed.roleValues(next[a + k]))
    for (var i = 0; i < next.length; i++) {
      var cur = rowModel.get(i)
      for (var r = 0; r < ed.roles.length; r++) {
        var role = ed.roles[r]
        if (cur[role] !== next[i][role]) rowModel.setProperty(i, role, next[i][role])
      }
      // Typing `>` into an empty line leaves the body empty, as it was:
      // the role does not change, but the field still shows the `>`.
      var item = rep.itemAt(i)
      if (item && item.field.text !== next[i].body) item.field.text = next[i].body
    }
    ed.syncing = false
  }

  function rowItem(i) { return i >= 0 ? rep.itemAt(i) : null }

  // The field follows `cursorPosition`.
  function placeCursor(focus) {
    if (ed.rows.length === 0) return
    var i = Rows.rowAt(ed.rows, ed.cursorPosition)
    var r = ed.rows[i]
    var col = Rows.columnIn(r, ed.cursorPosition)
    ed.cursorPosition = r.start + r.prefixLen + col
    var item = ed.rowItem(i)
    if (!item) return
    if (focus || ed.hasFocus) item.field.forceActiveFocus()
    if (item.field.cursorPosition !== col) item.field.cursorPosition = col
    ed.updateCursorRect()
  }

  function placeAt(i, col) {
    var r = ed.rows[i]
    ed.setCursor(r.start + r.prefixLen + Math.max(0, Math.min(r.body.length, col)), true)
  }

  // Rows just inserted have no place in the column until it lays out, so
  // lay out first; and whenever the column moves, the cursor moved too.
  // Select [a, b) and put the cursor at b, as if the student had dragged
  // over it. Both ends in one line (search matches never cross lines).
  function select(a, b) {
    ed.clearSelection()
    var i = Rows.rowAt(ed.rows, a)
    var r = ed.rows[i]
    var ca = Rows.columnIn(r, a)
    var cb = Rows.columnIn(r, b)
    ed.placeAt(i, cb)
    var item = ed.rowItem(i)
    if (item) item.field.select(ca, cb)
  }

  // Where a text offset is drawn, in editor coordinates.
  function rectAt(pos) {
    column.forceLayout()
    var i = Rows.rowAt(ed.rows, pos)
    var item = ed.rowItem(i)
    if (!item) return null
    var c = item.field.positionToRectangle(Rows.columnIn(ed.rows[i], pos))
    var p = item.field.mapToItem(ed, c.x, c.y)
    return Qt.rect(p.x, p.y, c.width, c.height)
  }

  // The marks that fall in row i, as columns of its body.
  function marksIn(i, marks, current, rows) {
    var r = rows[i]
    if (!r || !marks || marks.length === 0) return []
    var a0 = r.start + r.prefixLen
    var a1 = r.bodyEnd
    var out = []
    for (var k = 0; k < marks.length; k++) {
      var m = marks[k]
      if (m.end <= a0 || m.start >= a1) continue
      out.push({ a: Math.max(m.start, a0) - a0, b: Math.min(m.end, a1) - a0, kind: k === current ? "current" : "match" })
    }
    return out
  }

  // What to paint under row i: search marks, and the part of a selection
  // across lines that falls in it (an empty line inside one gets a sliver,
  // so the selection reads as continuous).
  function paintIn(i, marks, current, anchor, cursor, rows) {
    var out = ed.marksIn(i, marks, current, rows)
    var r = rows[i]
    if (!r || anchor < 0 || cursor < 0 || anchor === cursor) return out
    var a = Math.min(anchor, cursor), b = Math.max(anchor, cursor)
    var a0 = r.start + r.prefixLen
    var a1 = r.bodyEnd
    if (b < a0 || a > a1) return out
    if (b === a0 && a < a0 && r.body.length > 0) return out
    var ca = Math.max(a, a0) - a0, cb = Math.min(b, a1) - a0
    out.push({ a: ca, b: cb, kind: "selection", sliver: cb === ca })
    return out
  }

  // ------------------------------------------------------------ selection across lines

  function clearSelection() {
    ed.selAnchor = -1
    ed.selCursor = -1
  }

  function absOf(i, col) {
    var r = ed.rows[i]
    return r.start + r.prefixLen + Math.max(0, Math.min(r.body.length, col))
  }

  // Select from `anchor` to `pos`, the cursor (and keyboard) at `pos`.
  function selectSpan(anchor, pos) {
    pos = Math.max(0, Math.min(ed.text.length, pos))
    ed.setCursor(pos, true)
    ed.selAnchor = anchor
    ed.selCursor = ed.cursorPosition
    var item = ed.rowItem(ed.focusedRow)
    if (item) item.field.deselect()
  }

  // Where a selection's moving end goes for a navigation key.
  function stepPos(pos, k, ctrl) {
    if (ctrl && k === Qt.Key_Home) return 0
    if (ctrl && k === Qt.Key_End) return ed.text.length
    var i = Rows.rowAt(ed.rows, pos)
    var r = ed.rows[i]
    var col = Rows.columnIn(r, pos)
    var n = ed.rows.length
    // With Ctrl, a word at a time; at a line's edge, into the next line.
    if (k === Qt.Key_Left) return col > 0 ? ed.absOf(i, ctrl ? Rows.wordStep(r.body, col, -1) : col - 1)
      : (i > 0 ? ed.absOf(i - 1, ed.rows[i - 1].body.length) : pos)
    if (k === Qt.Key_Right) return col < r.body.length ? ed.absOf(i, ctrl ? Rows.wordStep(r.body, col, 1) : col + 1)
      : (i + 1 < n ? ed.absOf(i + 1, 0) : pos)
    if (k === Qt.Key_Home) return ed.absOf(i, 0)
    if (k === Qt.Key_End) return ed.absOf(i, r.body.length)
    var dir = k === Qt.Key_Up ? -1 : 1
    var item = ed.rowItem(i)
    var f = item.field
    var c = f.positionToRectangle(col)
    // A wrapped line first moves within itself.
    if (dir > 0 && c.y < f.positionToRectangle(f.length).y - 1) return ed.absOf(i, f.positionAt(c.x, c.y + c.height * 1.5))
    if (dir < 0 && c.y > f.positionToRectangle(0).y + 1) return ed.absOf(i, f.positionAt(c.x, c.y - c.height * 0.5))
    var j = Rows.nextTextRow(ed.rows, i, dir)
    if (j < 0) return dir < 0 ? ed.absOf(i, 0) : ed.absOf(i, r.body.length)
    var t = ed.rowItem(j).field
    return ed.absOf(j, t.positionAt(f.x + c.x - t.x, dir > 0 ? 1 : t.contentHeight - 1))
  }

  // The field's own selection as text offsets: where it started, so a
  // selection that grows past the line keeps its anchor.
  function nativeAnchor(item) {
    var f = item.field
    if (f.selectedText === "") return ed.cursorPosition
    var col = f.cursorPosition === f.selectionEnd ? f.selectionStart : f.selectionEnd
    return ed.absOf(item.index, col)
  }

  function copyText(t) {
    clip.text = t
    clip.selectAll()
    clip.copy()
    clip.text = ""
  }

  function removeSpan() {
    var a = ed.selStart, b = ed.selEnd
    ed.snapshot(true)
    ed.clearSelection()
    ed.replace(a, b, "")
    ed.placeCursor(true)
  }

  // Tab / Shift+Tab on a selection: every line in it nests or un-nests,
  // and the selection stays on those lines.
  function indentSpan(out) {
    var i = Rows.rowAt(ed.rows, ed.selStart)
    var j = Rows.rowAt(ed.rows, ed.selEnd)
    ed.snapshot(true)
    ed.clearSelection()
    for (var k = j; k >= i; k--) {
      var r = ed.rows[k]
      if (r.blank) continue
      if (!out) ed.replace(r.start, r.start, "\t")
      else if (r.indent.charAt(0) === "\t") ed.replace(r.start, r.start + 1, "")
      else if (r.indent !== "") ed.replace(r.start, r.start + Math.min(2, r.indent.length), "")
    }
    ed.selectSpan(ed.absOf(i, 0), ed.absOf(j, ed.rows[j].body.length))
  }

  // Keys while a selection crosses lines. True when the key was used.
  function spanKey(event) {
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    var nav = k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down
      || k === Qt.Key_Home || k === Qt.Key_End
    if (nav && shift && !alt) {
      var anchor = ed.selAnchor
      var to = ed.stepPos(ed.selCursor, k, ctrl)
      if (to === anchor) { ed.clearSelection(); ed.setCursor(to, true) }
      else ed.selectSpan(anchor, to)
      return true
    }
    if (nav && !alt && !ctrl) {
      var back = k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Home
      var at = back ? ed.selStart : ed.selEnd
      ed.clearSelection()
      ed.setCursor(at, true)
      return true
    }
    if (ctrl && k === Qt.Key_C) { ed.copyText(ed.text.slice(ed.selStart, ed.selEnd)); return true }
    if (ctrl && k === Qt.Key_X) {
      ed.copyText(ed.text.slice(ed.selStart, ed.selEnd))
      ed.cutting = true
      ed.removeSpan()
      ed.cutting = false
      return true
    }
    if (ctrl && k === Qt.Key_A) { ed.selectSpan(0, ed.text.length); return true }
    if (ctrl && k === Qt.Key_V) {
      ed.removeSpan()
      var it = ed.rowItem(ed.focusedRow)
      if (it) it.field.paste()
      return true
    }
    if (k === Qt.Key_Backspace || k === Qt.Key_Delete) { ed.removeSpan(); return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !ctrl && !alt) {
      ed.removeSpan()
      var r = ed.rowItem(ed.focusedRow)
      if (r) ed.returnKey(r, shift)
      return true
    }
    if (k === Qt.Key_Tab && !ctrl && !alt) { ed.indentSpan(false); return true }
    if (k === Qt.Key_Backtab) { ed.indentSpan(true); return true }
    if (event.text !== "" && !ctrl && !alt && event.text.charCodeAt(0) >= 32) {
      var a = ed.selStart, b = ed.selEnd
      ed.snapshot(true)
      ed.clearSelection()
      ed.replace(a, b, event.text)
      ed.placeCursor(true)
      return true
    }
    // Anything else (undo, Ctrl+L, …) acts on the cursor: the selection
    // goes first.
    if (k !== Qt.Key_Shift && k !== Qt.Key_Control && k !== Qt.Key_Alt && k !== Qt.Key_Meta) ed.clearSelection()
    return false
  }

  // Where a point in the editor lands: row, column, and whether it is on a
  // checkbox (which handles its own clicks).
  function hitTest(x, y) {
    column.forceLayout()
    var n = ed.rows.length
    var i = 0
    while (i < n - 1 && y >= ed.rowItem(i).y + ed.rowItem(i).height) i++
    var item = ed.rowItem(i)
    var r = ed.rows[i]
    if (!item || !r) return { i: 0, col: 0, box: false }
    if (y >= item.y + item.height) return { i: i, col: r.body.length, box: false }
    if (r.blank) return { i: i, col: 0, box: false }
    var b = item.box
    var pad = Math.round(ed.textSize * 0.25)
    var ly = y - item.y
    var box = r.kind === "task" && x >= b.x - pad && x <= b.x + b.width + pad && ly >= b.y - pad && ly <= b.y + b.height + pad
    var f = item.field
    return { i: i, col: f.positionAt(x - f.x, ly - f.y), box: box }
  }

  function updateCursorRect() {
    var item = ed.rowItem(ed.focusedRow)
    if (!item) return
    column.forceLayout()
    var c = item.field.cursorRectangle
    var p = item.field.mapToItem(ed, c.x, c.y)
    ed.cursorRect = Qt.rect(p.x, p.y, c.width, c.height)
  }

  // A run of lines in editor coordinates — what the page veils and marks.
  function blockRect(startLine, endLine) {
    column.forceLayout()
    var a = ed.rowItem(startLine)
    var b = ed.rowItem(endLine - 1)
    if (!a || !b) return null
    var y = a.y + a.gapTop
    return { y: y, h: b.y + b.height - y }
  }

  // ------------------------------------------------------------ editing

  // A field changed under the student's fingers.
  function typed(i, body, col) {
    var r = ed.rows[i]
    if (!r) return
    ed.clearSelection()
    body = body.replace(/\r/g, "")
    var line = r.raw.substring(0, r.prefixLen) + body + r.suffix
    ed.snapshot(/\n/.test(body))
    var lineEnd = r.start + r.raw.length
    var before = ed.rows.length
    ed.commit(ed.text.slice(0, r.start) + line + ed.text.slice(lineEnd), r.start + r.prefixLen + col)
    // The line changed kind (markdown typed or broken) or a paste brought
    // new lines: the field's text moved, so put the cursor back.
    var now = ed.rows[i]
    if (ed.rows.length !== before || !now || now.body !== body) ed.placeCursor(true)
    else ed.updateCursorRect()
  }

  function fieldCursor(i, col) {
    var r = ed.rows[i]
    if (!r) return
    ed.cursorPosition = r.start + r.prefixLen + col
    ed.updateCursorRect()
  }

  function selectionRange(item) {
    var r = ed.rows[item.index]
    var f = item.field
    return { a: r.start + r.prefixLen + f.selectionStart, b: r.start + r.prefixLen + f.selectionEnd }
  }

  function returnKey(item, soft) {
    var i = item.index
    ed.snapshot(true)
    if (item.field.selectedText !== "") {
      var sel = ed.selectionRange(item)
      ed.remove(sel.a, sel.b)
    }
    var r = ed.rows[i]
    var pos = ed.cursorPosition
    var lineText = r.raw
    var lineEnd = r.start + r.raw.length
    // At the end of a bound line's words, the new line starts after its
    // date, so the line keeps its deadline.
    if (r.suffix !== "" && pos >= r.bodyEnd) pos = lineEnd
    var carry = (r.kind === "code" || r.kind === "front") ? "" : Rows.continuation(r)
    if (soft) {
      // A new line in the same block: under a list item, indented to stay
      // part of it; in a quote, still quoted.
      var under = (r.kind === "task" || r.kind === "bullet" || r.kind === "ordered") ? r.indent + "  "
        : (carry === "> " ? "> " : r.indent)
      ed.insert(pos, "\n" + under)
      return
    }
    if (carry !== "" && r.body === "" && r.suffix === "" && pos >= lineEnd && r.kind !== "calloutHead") {
      // Enter on an empty item leaves the list (or the quote).
      ed.remove(r.start, lineEnd)
      if (r.kind !== "quote") ed.listLeft(i)
      return
    }
    ed.insert(pos, "\n" + carry)
    ed.returnFinished(i, lineText)
  }

  // Backspace at the start of a line: first the kind goes, then the
  // indentation, then the line joins the one above.
  // A bound line that stops being a checkbox stops being a deadline: its
  // date goes with the box (and the page asks about the deadline). Joining
  // onto a bound line slips the words in before that line's date.
  function backspaceAtStart(i) {
    var r = ed.rows[i]
    ed.snapshot(true)
    if (r.marker !== "") {
      if (r.suffix !== "") ed.remove(r.bodyEnd, r.start + r.raw.length)
      ed.remove(r.start + r.indent.length, r.start + r.prefixLen)
    } else if (r.indent !== "") {
      ed.remove(r.start, r.start + r.indent.length)
    } else if (i > 0) {
      var p = ed.rows[i - 1]
      if (p.suffix !== "") {
        var at = p.bodyEnd
        ed.replace(p.start, r.start + r.raw.length, p.raw.slice(0, p.raw.length - p.suffix.length) + r.raw + p.suffix)
        ed.setCursor(at, true)
      } else {
        ed.remove(r.start - 1, r.start)
      }
    }
    ed.placeCursor(true)
  }

  // Delete at the end of a line pulls the next line's words up, without
  // its markdown.
  function deleteAtEnd(i) {
    if (i + 1 >= ed.rows.length) return
    var r = ed.rows[i]
    var n = ed.rows[i + 1]
    ed.snapshot(true)
    if (r.suffix !== "") {
      var at = r.bodyEnd
      ed.replace(r.start, n.start + n.raw.length, r.raw.slice(0, r.raw.length - r.suffix.length) + n.body + r.suffix)
      ed.setCursor(at, true)
    } else {
      ed.remove(r.start + r.raw.length, n.start + n.prefixLen)
    }
    ed.placeCursor(true)
  }

  function indent(i, out) {
    var r = ed.rows[i]
    var listy = r.kind === "task" || r.kind === "bullet" || r.kind === "ordered"
    ed.snapshot(true)
    if (out) {
      if (r.indent.charAt(0) === "\t") ed.remove(r.start, r.start + 1)
      else if (r.indent !== "") ed.remove(r.start, r.start + Math.min(2, r.indent.length))
    } else if (listy || r.indent !== "") {
      ed.insert(r.start, "\t")
    } else {
      ed.insert(ed.cursorPosition, "\t")
    }
    ed.placeCursor(true)
  }

  // Ctrl+L or a click: tick or untick a checkbox; on a bullet or a plain
  // line, make it a checkbox.
  function toggleCheckbox(i) {
    var r = ed.rows[i]
    if (!r) return
    ed.snapshot(true)
    if (r.kind === "task") {
      var at = r.start + r.indent.length + 3
      ed.replace(at, at + 1, r.checked ? " " : "x")
    } else if (r.kind === "bullet") {
      ed.insert(r.start + r.prefixLen, "[ ] ")
    } else if (r.kind === "plain" || r.kind === "blank") {
      ed.insert(r.start + r.indent.length, "- [ ] ")
    }
    ed.placeCursor(false)
  }

  function clickCheckbox(i) {
    ed.placeAt(i, ed.rows[i].body.length)
    ed.toggleCheckbox(i)
  }

  function atFirstLine(f) { return f.cursorRectangle.y <= f.positionToRectangle(0).y + 1 }
  function atLastLine(f) { return f.cursorRectangle.y >= f.positionToRectangle(f.length).y - 1 }

  // Up / Down past the edge of a field: the neighbouring line, at the same
  // horizontal place.
  function moveVertical(item, dir) {
    var j = Rows.nextTextRow(ed.rows, item.index, dir)
    if (j < 0) {
      ed.placeAt(item.index, dir < 0 ? 0 : ed.rows[item.index].body.length)
      return
    }
    var x = item.field.x + item.field.cursorRectangle.x
    var target = ed.rowItem(j)
    var f = target.field
    var col = f.positionAt(x - f.x, dir > 0 ? 1 : f.contentHeight - 1)
    ed.placeAt(j, col)
  }

  function key(event, item) {
    var f = item.field
    var i = item.index
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    var noSel = f.selectedText === ""

    if (ed.spanning && k === Qt.Key_Escape) { ed.clearSelection(); ed.placeCursor(true); event.accepted = true; return }
    if (ed.keyFilter && ed.keyFilter(event)) { event.accepted = true; return }
    if (ed.spanning) {
      if (ed.spanKey(event)) { event.accepted = true; return }
    }

    // Shift+arrows past the edge of a line: the selection carries on into
    // the next one (by word with Ctrl). Inside a line the field selects on
    // its own, Ctrl+Shift+arrows by word. Ctrl+Shift+Home/End reach the
    // note's ends; Ctrl+A takes the whole note.
    if (shift && !alt && (k === Qt.Key_Down || k === Qt.Key_Up || k === Qt.Key_Left || k === Qt.Key_Right
        || ((k === Qt.Key_Home || k === Qt.Key_End) && ctrl))) {
      var edge = (k === Qt.Key_Down && ed.atLastLine(f)) || (k === Qt.Key_Up && ed.atFirstLine(f))
        || (k === Qt.Key_Right && f.cursorPosition === f.length && i + 1 < ed.rows.length)
        || (k === Qt.Key_Left && f.cursorPosition === 0 && i > 0)
        || ((k === Qt.Key_Home || k === Qt.Key_End) && ctrl)
      if (edge) {
        var anchor = ed.nativeAnchor(item)
        var to = ed.stepPos(ed.cursorPosition, k, ctrl)
        if (to !== anchor) ed.selectSpan(anchor, to)
        event.accepted = true
        return
      }
    }
    if (ctrl && k === Qt.Key_A) { ed.selectSpan(0, ed.text.length); event.accepted = true; return }

    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !ctrl && !alt) {
      ed.returnKey(item, shift)
    } else if (k === Qt.Key_Backspace && noSel && f.cursorPosition === 0) {
      ed.backspaceAtStart(i)
    } else if (k === Qt.Key_Delete && noSel && f.cursorPosition === f.length && !ctrl) {
      ed.deleteAtEnd(i)
    } else if (k === Qt.Key_Up && !ctrl && !alt && !shift && ed.atFirstLine(f)) {
      ed.moveVertical(item, -1)
    } else if (k === Qt.Key_Down && !ctrl && !alt && !shift && ed.atLastLine(f)) {
      ed.moveVertical(item, 1)
    } else if (k === Qt.Key_Left && !alt && !shift && noSel && f.cursorPosition === 0) {
      var p = Rows.nextTextRow(ed.rows, i, -1)
      if (p >= 0) ed.placeAt(p, ed.rows[p].body.length)
    } else if (k === Qt.Key_Right && !alt && !shift && noSel && f.cursorPosition === f.length) {
      var n = Rows.nextTextRow(ed.rows, i, 1)
      if (n >= 0) ed.placeAt(n, 0)
    } else if (k === Qt.Key_Tab && !ctrl && !alt) {
      ed.indent(i, false)
    } else if (k === Qt.Key_Backtab) {
      ed.indent(i, true)
    } else if (k === Qt.Key_Z && ctrl) {
      if (shift) ed.redo()
      else ed.undo()
    } else if (k === Qt.Key_Y && ctrl) {
      ed.redo()
    } else if (k === Qt.Key_L && ctrl) {
      ed.toggleCheckbox(i)
    } else if (k === Qt.Key_Home && ctrl) {
      ed.setCursor(0, true)
    } else if (k === Qt.Key_End && ctrl) {
      ed.setCursor(ed.text.length, true)
    } else if (event.text === " " && noSel && f.length === 0 && /\s$/.test(ed.rows[i].marker)) {
      // The marker already ends in a space; "- [] " should not leave two.
    } else if (event.text === "]" && noSel) {
      // "- []" or a bare "[]" at the start of a line is what fingers
      // type; "- [ ] " is what markdown wants.
      var r = ed.rows[i]
      var before = r.raw.substring(0, ed.cursorPosition - r.start)
      if (/^\s*[-*+] \[$/.test(before)) {
        ed.snapshot(true)
        ed.insert(ed.cursorPosition, " ] ")
      } else if (/^\s*\[$/.test(before)) {
        ed.snapshot(true)
        ed.replace(r.start, ed.cursorPosition, before.replace("[", "- [ ] "))
      } else {
        return
      }
    } else {
      return
    }
    event.accepted = true
  }

  // ------------------------------------------------------------ drawing

  ListModel { id: rowModel }

  // The clipboard, reached through a field nobody sees.
  TextEdit { id: clip; visible: false; textFormat: TextEdit.PlainText }

  Column {
    id: column
    width: ed.width
    onHeightChanged: Qt.callLater(ed.updateCursorRect)

    Repeater {
      id: rep
      model: rowModel

      Item {
        id: row
        required property int index
        required property string kind
        required property string body
        required property int level
        required property bool checked
        required property string ordinal
        required property int headingLevel
        required property string callout
        required property bool priv
        required property bool blank
        required property bool lead
        required property bool gapAbove
        required property int deadline
        required property string dueLabel
        required property real dueAt

        property alias field: field
        property alias box: box
        readonly property bool listy: kind === "task" || kind === "bullet" || kind === "ordered"
        readonly property bool quoted: kind === "quote" || kind === "calloutHead"
        readonly property int gapTop: gapAbove ? ed.smallGap : 0
        readonly property real indentX: level * ed.markerWidth
        readonly property real labelWidth: kind === "calloutHead" ? label.implicitWidth + Math.round(ed.textSize * 0.4) : 0
        readonly property real fieldX: indentX + (listy ? ed.markerWidth : (quoted ? ed.quoteWidth : 0)) + labelWidth
        readonly property real firstLine: fm.height

        width: column.width
        height: blank && !field.activeFocus ? (lead ? 0 : ed.blockGap) : gapTop + field.height

        onBodyChanged: if (field.text !== body) field.text = body
        Component.onCompleted: field.text = body

        FontMetrics { id: fm; font: field.font }

        // A click beside the words (the indent, the space of a blank line)
        // lands on this line; on a blank line it opens a line to write on.
        MouseArea {
          anchors.fill: parent
          onClicked: function (mouse) {
            ed.placeAt(row.index, row.blank ? 0 : field.positionAt(mouse.x - field.x, mouse.y - field.y))
          }
        }

        Rectangle {
          visible: row.quoted
          x: row.indentX + Math.round(ed.textSize * 0.15)
          width: Math.max(2, Math.round(ed.textSize * 0.12))
          height: row.height
          radius: width / 2
          color: row.priv ? ed.privateColor : ed.quoteColor
        }

        Text {
          id: label
          visible: row.kind === "calloutHead"
          x: row.indentX + ed.quoteWidth
          y: row.gapTop + (row.firstLine - height) / 2
          textFormat: Text.PlainText
          text: row.callout === "private" ? "private · never sent" : row.callout
          color: row.priv ? ed.privateColor : ed.dim
          font.family: ed.fontFamily
          font.pixelSize: Math.round(ed.textSize * 0.72)
          font.letterSpacing: 0.4
        }

        Rectangle {
          id: box
          readonly property int size: Math.round(ed.textSize * 0.72)
          visible: row.kind === "task"
          x: row.indentX + Math.round((ed.markerWidth - size) / 2) - Math.round(ed.textSize * 0.15)
          y: row.gapTop + Math.round((row.firstLine - size) / 2)
          width: size
          height: size
          radius: Math.max(2, Math.round(size * 0.22))
          color: row.checked ? ed.checkColor : "transparent"
          border.width: row.checked ? 0 : Math.max(1, Math.round(ed.textSize * 0.08))
          border.color: ed.boxColor

          Text {
            anchors.centerIn: parent
            visible: row.checked
            textFormat: Text.PlainText
            text: "✓"
            color: ed.background
            font.family: ed.fontFamily
            font.pixelSize: Math.round(box.size * 0.85)
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Math.round(ed.textSize * 0.25)
            cursorShape: Qt.PointingHandCursor
            onClicked: ed.clickCheckbox(row.index)
          }
        }

        Rectangle {
          readonly property int size: Math.max(4, Math.round(ed.textSize * 0.26))
          visible: row.kind === "bullet"
          x: row.indentX + Math.round((ed.markerWidth - size) / 2) - Math.round(ed.textSize * 0.15)
          y: row.gapTop + Math.round((row.firstLine - size) / 2)
          width: size
          height: size
          radius: size / 2
          color: ed.bulletColor
        }

        Text {
          visible: row.kind === "ordered"
          x: row.indentX
          width: ed.markerWidth - Math.round(ed.textSize * 0.35)
          y: row.gapTop
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: row.ordinal
          color: ed.bulletColor
          font: field.font
        }

        // A bound line's date, at the line's end: a pill while it names a
        // deadline, plain once the deadline is gone. Late and still open:
        // the urgent colour.
        Rectangle {
          id: due
          readonly property bool late: !row.checked && row.dueAt > 0 && row.dueAt < Date.now()
          visible: row.dueLabel !== ""
          anchors.right: parent.right
          y: row.gapTop + Math.round((row.firstLine - height) / 2)
          width: dueText.implicitWidth + (row.deadline > 0 ? Math.round(ed.textSize * 0.9) : 0)
          height: dueText.implicitHeight + Math.round(ed.textSize * 0.2)
          radius: height / 2
          color: "transparent"
          border.width: row.deadline > 0 ? 1 : 0
          border.color: late ? ed.urgent : ed.faint
          Text {
            id: dueText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: row.dueLabel
            color: due.late ? ed.urgent : ed.dim
            font.family: ed.fontFamily
            font.pixelSize: Math.round(ed.textSize * 0.78)
          }
        }

        // Under the words: search matches (faint, the current one
        // stronger) and a selection across lines. A piece that wraps is
        // drawn in two.
        Repeater {
          model: ed.paintIn(row.index, ed.marks, ed.currentMark, ed.selAnchor, ed.selCursor, ed.rows)
          Item {
            id: mark
            required property var modelData
            readonly property var pieces: {
              field.width; field.contentHeight; field.text
              var r1 = field.positionToRectangle(modelData.a)
              var r2 = field.positionToRectangle(modelData.b)
              if (modelData.sliver) return [{ x: r1.x, y: r1.y, w: Math.round(ed.textSize * 0.4), h: r1.height }]
              if (Math.abs(r1.y - r2.y) < 1) return [{ x: r1.x, y: r1.y, w: r2.x - r1.x, h: r1.height }]
              return [{ x: r1.x, y: r1.y, w: field.width - r1.x, h: r1.height },
                      { x: 0, y: r2.y, w: r2.x, h: r2.height }]
            }
            Repeater {
              model: mark.pieces
              Rectangle {
                required property var modelData
                x: field.x + modelData.x - 1
                y: field.y + modelData.y
                width: modelData.w + 2
                height: modelData.h
                radius: mark.modelData.kind === "selection" ? 0 : Math.max(2, Math.round(ed.textSize * 0.15))
                color: mark.modelData.kind === "selection" ? ed.selectionColor : (mark.modelData.kind === "current" ? ed.currentMarkColor : ed.markColor)
                opacity: 1
              }
            }
          }
        }

        TextEdit {
          id: field
          x: row.fieldX
          y: row.gapTop
          width: Math.max(0, row.width - row.fieldX - (due.visible ? due.width + Math.round(ed.textSize * 0.6) : 0))
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          selectByKeyboard: true
          persistentSelection: false
          color: row.checked || row.kind === "front" ? ed.dim
            : row.kind === "heading" ? ed.headingColors[Math.max(0, Math.min(row.headingLevel, ed.headingColors.length) - 1)]
            : row.kind === "code" ? ed.codeColor : ed.foreground
          selectionColor: ed.selectionColor
          selectedTextColor: ed.foreground
          font.family: row.kind === "code" || row.kind === "front" ? "monospace" : ed.fontFamily
          font.pixelSize: row.kind === "heading"
            ? Math.round(ed.textSize * (row.headingLevel === 1 ? 1.5 : row.headingLevel === 2 ? 1.3 : row.headingLevel === 3 ? 1.15 : 1))
            : (row.kind === "code" || row.kind === "front" ? Math.round(ed.textSize * 0.85) : ed.textSize)
          font.weight: row.kind === "heading" ? Font.DemiBold : Font.Normal
          cursorVisible: activeFocus
          tabStopDistance: ed.tabStop

          onTextChanged: if (!ed.syncing && text !== row.body) ed.typed(row.index, text, cursorPosition)
          onCursorPositionChanged: if (activeFocus && !ed.syncing) ed.fieldCursor(row.index, cursorPosition)
          onCursorRectangleChanged: if (activeFocus) ed.updateCursorRect()
          onActiveFocusChanged: {
            if (activeFocus) {
              ed.focusedRow = row.index
              ed.fieldCursor(row.index, cursorPosition)
            } else if (ed.focusedRow === row.index) {
              ed.focusedRow = -1
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) { ed.key(event, row) }
        }
      }
    }
  }

  // The mouse, over every line at once, so a drag can cross from one
  // line's field into the next. A press on a checkbox goes through to it.
  MouseArea {
    id: pointer
    anchors.fill: column
    cursorShape: Qt.IBeamCursor
    preventStealing: true
    property int downAt: -1

    onPressed: function (mouse) {
      var h = ed.hitTest(mouse.x, mouse.y)
      if (h.box) { mouse.accepted = false; return }
      var pos = ed.absOf(h.i, h.col)
      if (mouse.modifiers & Qt.ShiftModifier) {
        var anchor = ed.spanning ? ed.selAnchor : ed.cursorPosition
        pointer.downAt = anchor
        if (pos !== anchor) ed.selectSpan(anchor, pos)
        return
      }
      ed.clearSelection()
      pointer.downAt = pos
      ed.setCursor(pos, true)
    }
    onPositionChanged: function (mouse) {
      if (!pressed || pointer.downAt < 0) return
      var h = ed.hitTest(mouse.x, mouse.y)
      var pos = ed.absOf(h.i, h.col)
      if (pos !== pointer.downAt) ed.selectSpan(pointer.downAt, pos)
      else if (ed.spanning) { ed.clearSelection(); ed.setCursor(pos, true) }
    }
    onReleased: pointer.downAt = -1
    onDoubleClicked: function (mouse) {
      var h = ed.hitTest(mouse.x, mouse.y)
      if (h.box) return
      ed.clearSelection()
      ed.placeAt(h.i, h.col)
      var item = ed.rowItem(h.i)
      if (item) item.field.selectWord()
    }
  }
}
