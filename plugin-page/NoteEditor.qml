import QtQuick
import "Rows.js" as Rows
import "Blocks.js" as Blocks
import "Emph.js" as Emph
import "Links.js" as Links
import "Shortcuts.js" as Sc
import "Task.js" as Task

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
  // Drawn while the mouse is on a checkbox: the page's hint, naming the
  // key that does the same (an Item; the editor knows nothing of tooltips).
  property Component boxTip: null
  // Who made each box and bullet (docs/agent.md): line index -> "agent" or
  // "together"; a line not in it is the person's. Drawn in the box or dot
  // itself — ◇ the agent's, the seal made together — so nothing is added
  // to the line.
  property var authors: ({})

  // The line being written: its text after the last keystroke in it. A
  // checkbox there that ends in a date has it lit up and its pill shown,
  // pending, as typed (Rows.readCue); the page binds it when the line is
  // left and clears this. `declined`: lines (raw) whose date stays words.
  property string typedRaw: ""
  // The agent's files are opened to read (docs/files.md): nothing typed,
  // pasted, ticked or moved changes them; selecting, copying and find still
  // work. `cues`: a date at a checkbox's end is lit as typed only in a day,
  // where it can become a deadline.
  property bool readOnly: false
  property bool cues: true
  property var declined: ({})
  // The row whose date lit up with the last keystroke: a Backspace right
  // then keeps the date as words (as Todoist does), instead of deleting.
  property int freshCue: -1
  signal cueDismissed(string raw)
  // A box ticked (done) or unticked by the person, in the note.
  signal boxTicked(int lineIndex, bool done)

  property string fontFamily: "sans-serif"
  property string fontStyle: ""        // the cut of the prose face (Page.qml)
  property string codeFamily: "monospace"
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
  property color cueColor: Qt.rgba(accent.r, accent.g, accent.b, 0.2)   // a date being recognised
  property color boxColor: dim                                  // an open checkbox
  property color checkColor: dim                                // a ticked one
  property color bulletColor: dim                               // dots and numbers
  property color quoteColor: faint                              // a quote's bar
  property color privateColor: dim                              // a private callout's bar and label
  property color codeColor: dim                                 // fenced code
  property real tabStop: textSize * 2

  // Space: within a block nothing, between blocks without a blank line a
  // little, across a blank line clearly more.
  readonly property int markerWidth: Math.round(textSize * 1.5)
  readonly property int quoteWidth: Math.round(textSize * 0.9)

  // Which row holds the keyboard focus (-1: none), and the cursor in
  // editor coordinates, for the page to keep in view and to hang the send
  // prompt under.
  property int focusedRow: -1
  readonly property bool hasFocus: focusedRow >= 0
  property rect cursorRect: Qt.rect(0, 0, 0, 0)

  // Room under a line for something the page shows there (Ctrl+D's "when?",
  // the `@` list): row `roomRow` grows by `roomHeight` below its words, so
  // the lines after it move down instead of being drawn over (2026-10-17).
  // `roomTop` is where that room starts, in editor coordinates.
  property int roomRow: -1
  // Images (docs/files.md, 2026-10-27). The page resolves a target to a
  // file url ("" when the vault has no such file); `resolveVersion` moves
  // when its index of the vault arrives, so rows ask again. Only rows within
  // a screen of the view load their picture, decoded at the size drawn, and
  // a picture scrolled further away is let go of.
  property var resolveImage: null
  property int resolveVersion: 0
  property real viewTop: 0
  property real viewBottom: 100000
  property real pixelRatio: 1
  // A picture's own size, { w, h } in pixels, read from its file's header by
  // the page (`imageSize(source)`, null until known; `sizesVersion` moves
  // when sizes arrive): its room is kept before it loads, it is never drawn
  // larger than it is, and it is decoded no larger than it is drawn.
  property var imageSize: null
  property int sizesVersion: 0
  // True once the page has tried and could not read a size (an svg, a
  // file `file` does not know): the picture loads anyway, at the column.
  property var sizeUnknown: function (src) { return false }

  // Tables (docs/files.md, 2026-10-27): drawn as one block while the cursor
  // is outside it — a bold header, hairlines across, no rules down, each
  // column as wide as its widest cell until the row would not fit, then the
  // widest ones give way and wrap — and as written while it is inside.
  FontMetrics { id: cellMetrics; font.family: ed.fontFamily; font.styleName: ed.fontStyle; font.pixelSize: ed.textSize }
  readonly property real cellGap: Math.round(ed.textSize * 1.2)
  property var tableCache: ({})
  function tableInfo(start, width) {
    var rows = ed.rows
    var head = rows[start]
    if (!head || head.kind !== "table") return null
    var lines = []
    for (var i = start; i < start + head.tableLen; i++) lines.push(rows[i].raw)
    var key = start + "\u0000" + Math.round(width) + "\u0000" + ed.textSize + "\u0000" + lines.join("\n")
    if (ed.tableCache.key === key) return ed.tableCache.info
    var align = Rows.aligns(lines[1])
    var n = align.length
    var natural = []
    for (var c = 0; c < n; c++) natural.push(0)
    for (var k = 0; k < lines.length; k++) {
      if (k === 1) continue
      var cs = Rows.cells(lines[k])
      for (var j = 0; j < n; j++)
        natural[j] = Math.max(natural[j], cellMetrics.advanceWidth(cs[j] || "") * (k === 0 ? 1.06 : 1) + 2)
    }
    var room = Math.max(n * 40, width - ed.cellGap * (n - 1))
    var widths = natural.slice()
    var total = widths.reduce(function (a, b) { return a + b }, 0)
    // Too wide: the narrow columns keep their width, the rest share what is left.
    for (var guard = 0; total > room && guard < n; guard++) {
      var fair = room / n, keep = 0, wide = 0
      for (var w = 0; w < n; w++) { if (natural[w] <= fair) keep += natural[w]; else wide++ }
      var share = wide > 0 ? Math.max(40, (room - keep) / wide) : fair
      widths = natural.map(function (x) { return Math.min(x, share) })
      total = widths.reduce(function (a, b) { return a + b }, 0)
      if (total <= room + 1) break
    }
    var info = { align: align, widths: widths, width: widths.reduce(function (a, b) { return a + b }, 0) + ed.cellGap * (n - 1) }
    ed.tableCache.key = key           // mutated, not reassigned: a cache tells no binding
    ed.tableCache.info = info
    return info
  }
  // Links: their colour, and whether the vault has what one points at
  // (`linkKnown(link)`, the page's; resolveVersion moves when it can tell).
  property color linkColor: accent
  property var linkKnown: null
  property bool linkHover: false

  // The link under a hit, unless it is drawn as written (being edited).
  function linkAtHit(h) {
    var item = ed.rowItem(h.i)
    if (!item || item.links.length === 0) return null
    var l = Links.at(item.links, h.col)
    return l && l.at !== item.revealLink ? l : null
  }
  // The link the cursor is in, for the key that follows it.
  function linkAtCursor() {
    var i = ed.focusedRow >= 0 ? ed.focusedRow : Rows.rowAt(ed.rows, ed.cursorPosition)
    var item = ed.rowItem(i), r = ed.rows[i]
    if (!item || !r || item.links.length === 0) return null
    return Links.at(item.links, ed.cursorPosition - r.start - r.prefixLen)
  }
  property real roomHeight: 0
  property real roomTop: 0

  // The row whose checkbox the mouse is over (-1: none): the box answers
  // in the accent, and the pointer over the lines shows a hand there
  // instead of a text cursor (2026-10-19).
  property int boxHover: -1

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
  // A link clicked (docs/files.md): the page follows it.
  signal linkActivated(int lineIndex, var link)

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
    pointer.clicks = 0
    ed.typedRaw = ""
    ed.freshCue = -1
    ed.undoStack = []
    ed.redoStack = []
    ed.commit(t, t.length)
    ed.placeCursor(false)
  }

  // Programmatic edits, with the cursor carried along the way TextEdit
  // carries it: text inserted at or before the cursor pushes it forward.
  function replace(a, b, s) {
    if (ed.readOnly) return
    var cur = ed.cursorPosition
    if (cur >= b) cur += s.length - (b - a)
    else if (cur > a) cur = a + s.length
    ed.commit(ed.text.slice(0, a) + s + ed.text.slice(b), cur)
    ed.placeCursor(false)
  }
  function insert(pos, s) { ed.replace(pos, pos, s) }

  // A line rewritten by changing only what differs (a box, a date at its
  // end), so a cursor in its words stays exactly where it was.
  function replaceLine(r, next) {
    var old = r.raw
    var p = 0
    while (p < old.length && p < next.length && old.charAt(p) === next.charAt(p)) p++
    var q = 0
    while (q < old.length - p && q < next.length - p
           && old.charAt(old.length - 1 - q) === next.charAt(next.length - 1 - q)) q++
    if (p === old.length && p === next.length) return
    ed.replace(r.start + p, r.start + old.length - q, next.slice(p, next.length - q))
  }
  function remove(a, b) { ed.replace(a, b, "") }

  // Emphasis: wrap the selection — or the word the cursor is in — in a
  // marker, and take it off again when it is already there. The markers are
  // written into the note as they are (`**`, `*`, `` ` ``, `~~`), because
  // the file stays plain markdown and Obsidian reads the same ones; the row
  // draws them to nothing and the words emphasised (Emph.js).
  function emphasise(marker) {
    if (ed.readOnly) return
    var t = ed.text
    var n = marker.length
    var a, b
    if (ed.spanning) { a = ed.selStart; b = ed.selEnd }
    else {
      // The word under the cursor; `\s` stops at the line's edges too.
      a = b = ed.cursorPosition
      while (a > 0 && !/\s/.test(t.charAt(a - 1))) a--
      while (b < t.length && !/\s/.test(t.charAt(b))) b++
    }
    // A one-character marker must not be half of a two-character one: the
    // `*` either side of `**bold**` belongs to the bold, so asking for
    // italic there adds a pair rather than eating one.
    var lone = function (i) { return n > 1 || (t.charAt(i - 1) !== marker && t.charAt(i + n) !== marker) }
    if (t.substring(a - n, a) === marker && t.substring(b, b + n) === marker && lone(a - n) && lone(b)) {
      ed.remove(b, b + n)              // the far end first: the near offsets hold
      ed.remove(a - n, a)
      ed.selectSpan(a - n, b - n)
    } else if (b - a >= 2 * n && t.substring(a, a + n) === marker && t.substring(b - n, b) === marker
               && lone(a) && lone(b - n)) {
      ed.remove(b - n, b)
      ed.remove(a, a + n)
      ed.selectSpan(a, b - 2 * n)
    } else {
      ed.insert(b, marker)
      ed.insert(a, marker)
      if (a === b) ed.setCursor(a + n, true)   // nothing to wrap: write the pair, stand inside it
      else ed.selectSpan(a + n, b + n)
    }
  }

  // Alt+Up / Alt+Down: the line the cursor is on — or every line a
  // selection touches — trades places with the line above or below, as in
  // VS Code; the cursor and the selection go with it. A bound line carries
  // its anchor along, so its deadline follows the words.
  function moveLines(dir) {
    if (ed.readOnly) return
    var t = ed.text
    var spanning = ed.spanning
    var anchor = ed.selAnchor
    var cur = ed.cursorPosition
    var a = spanning ? ed.selStart : cur
    var b = spanning ? ed.selEnd : cur
    if (spanning && t.charAt(b - 1) === "\n") b--      // ending at a line's start does not take that line
    var first = t.lastIndexOf("\n", a - 1) + 1
    var end = t.indexOf("\n", b)
    if (end < 0) end = t.length
    var lines = t.slice(first, end)
    var out, shift
    if (dir < 0) {
      if (first === 0) return
      var prevStart = t.lastIndexOf("\n", first - 2) + 1
      var prev = t.slice(prevStart, first - 1)
      out = t.slice(0, prevStart) + lines + "\n" + prev + t.slice(end)
      shift = -(prev.length + 1)
    } else {
      if (end >= t.length) return
      var nextEnd = t.indexOf("\n", end + 1)
      if (nextEnd < 0) nextEnd = t.length
      var next = t.slice(end + 1, nextEnd)
      out = t.slice(0, first) + next + "\n" + lines + t.slice(nextEnd)
      shift = next.length + 1
    }
    ed.snapshot(true)
    ed.commit(out, cur + shift)
    if (spanning) ed.selectSpan(anchor + shift, cur + shift)
    else ed.placeCursor(true)
  }

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
  // structural (Enter, merging lines, ticking, a line the page writes
  // because it was asked to) is a step of its own.
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
    if (ed.undoStack.length === 0 || ed.readOnly) return
    var s = ed.undoStack[ed.undoStack.length - 1]
    ed.undoStack = ed.undoStack.slice(0, -1)
    ed.redoStack = ed.redoStack.concat([{ text: ed.text, cursor: ed.cursorPosition }])
    ed.lastSnapshot = 0
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  // A line the page changed that no undo should take back (caught up with
  // the store): every saved state holding the line as it was (`was`) gets
  // it as it is now (`now`). A state where the line differs keeps it: the
  // facts there are the student's own, and undoing to it brings them back.
  function rebase(was, now) {
    var redone = function (s) {
      var lines = s.text.split("\n")
      var cur = s.cursor, pos = 0, hit = false
      for (var i = 0; i < lines.length; i++) {
        var end = pos + lines[i].length
        if (lines[i] === was) {
          if (cur >= end) cur += now.length - was.length
          else if (cur > pos) cur = Math.min(cur, pos + now.length)
          lines[i] = now
          end = pos + now.length
          hit = true
        }
        pos = end + 1
      }
      return hit ? { text: lines.join("\n"), cursor: cur } : s
    }
    ed.undoStack = ed.undoStack.map(redone)
    ed.redoStack = ed.redoStack.map(redone)
  }

  function redo() {
    if (ed.redoStack.length === 0 || ed.readOnly) return
    var s = ed.redoStack[ed.redoStack.length - 1]
    ed.redoStack = ed.redoStack.slice(0, -1)
    ed.undoStack = ed.undoStack.concat([{ text: ed.text, cursor: ed.cursorPosition }])
    ed.lastSnapshot = 0
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  // ------------------------------------------------------------ rows

  readonly property var roles: ["kind", "body", "level", "checked", "cancelled", "ordinal", "headingLevel", "callout", "priv", "blank", "lead", "space", "deadline", "dueLabel", "dueAt", "raw", "cueAt", "cueLabel", "tableRow", "tableStart", "tableLen"]

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
    // A row that no longer exists cannot be the focused one. When the rows
    // shrink — a shorter note opened, lines deleted — the old index would
    // dangle, and everything that reads it quietly stops: the drawn cursor
    // (updateCursorRect), paste over a selection, Enter over a selection.
    if (ed.focusedRow >= next.length) ed.focusedRow = -1
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
      if (item) item.show()
    }
    ed.syncing = false
  }

  function rowItem(i) { return i >= 0 ? rep.itemAt(i) : null }

  // Where row i draws its markers to nothing, and the column the cursor may
  // rest at there. A row with no emphasis has no runs and every column is
  // its own, exactly as before.
  function hiddenIn(i) {
    var r = ed.rows[i]
    if (!r || r.kind === "code" || r.kind === "front") return []
    return Emph.hidden(r.body)
  }

  function restCol(i, col, dir) {
    var r = ed.rows[i]
    if (!r) return col
    return Emph.validCol(ed.hiddenIn(i), col, r.body.length, dir)
  }

  // Inline code is drawn in the code face, so a change of face is a redraw.
  onCodeFamilyChanged: {
    for (var i = 0; i < ed.rows.length; i++) {
      var it = ed.rowItem(i)
      if (it) it.show()
    }
  }

  // The field follows `cursorPosition`.
  function placeCursor(focus) {
    if (ed.rows.length === 0) return
    var i = Rows.rowAt(ed.rows, ed.cursorPosition)
    var r = ed.rows[i]
    var col = ed.restCol(i, Rows.columnIn(r, ed.cursorPosition), 0)
    ed.cursorPosition = r.start + r.prefixLen + col
    var item = ed.rowItem(i)
    if (!item) return
    if (focus || ed.hasFocus) item.field.forceActiveFocus()
    if (item.field.cursorPosition !== col) item.field.cursorPosition = col
    ed.updateCursorRect()
  }

  function placeAt(i, col) {
    var r = ed.rows[i]
    ed.setCursor(r.start + r.prefixLen + ed.restCol(i, Math.max(0, Math.min(r.body.length, col)), 0), true)
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
    ed.ladderFrom = -1
  }

  // Where the cursor was when Ctrl+A began to climb (-1: not climbing), so
  // Esc can hand it back instead of leaving it at the end of what was taken.
  property int ladderFrom: -1

  // Ctrl+A climbs a step at a time: the line's words, then the block (the
  // one the agent answers), then the whole note. Each press takes the
  // nearest step that holds more than what is selected now, so a step that
  // would change nothing (a one-line block, an empty line) is passed over,
  // and a selection made by hand starts the climb from where it is.
  function selectAllStep(item) {
    var a = ed.cursorPosition, b = a
    if (ed.spanning) { a = ed.selStart; b = ed.selEnd }
    else if (item && item.field.selectedText !== "") {
      var f = item.field
      a = ed.absOf(item.index, Math.min(f.selectionStart, f.selectionEnd))
      b = ed.absOf(item.index, Math.max(f.selectionStart, f.selectionEnd))
    }
    var i = Rows.rowAt(ed.rows, a)
    var r = ed.rows[i]
    var steps = [[r.start + r.prefixLen, r.bodyEnd]]
    var blocks = Blocks.split(ed.text)
    for (var x = 0; x < blocks.length; x++) {
      if (i < blocks[x].start || i >= blocks[x].end) continue
      var first = ed.rows[blocks[x].start]
      var last = ed.rows[blocks[x].end - 1]
      if (first && last) steps.push([first.start + first.prefixLen, last.bodyEnd])
    }
    steps.push([0, ed.text.length])
    for (var s = 0; s < steps.length; s++) {
      var lo = steps[s][0], hi = steps[s][1]
      if (lo > a || hi < b || hi - lo <= b - a) continue
      var from = ed.spanning ? ed.ladderFrom : ed.cursorPosition
      ed.selectSpan(lo, hi)
      ed.ladderFrom = from
      return
    }
  }

  // Esc with something selected lets go of it and nothing more; the next
  // Esc is the page's. After a Ctrl+A climb the cursor goes back to where
  // it was.
  function letGo(item) {
    if (!ed.spanning) { item.field.deselect(); return }
    var back = ed.ladderFrom
    ed.clearSelection()
    if (back >= 0 && back <= ed.text.length) ed.cursorPosition = back
    ed.placeCursor(true)
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
    if (k === Qt.Key_Left) return col > 0 ? ed.absOf(i, ed.restCol(i, ctrl ? Rows.wordStep(r.body, col, -1) : col - 1, -1))
      : (i > 0 ? ed.absOf(i - 1, ed.rows[i - 1].body.length) : pos)
    if (k === Qt.Key_Right) return col < r.body.length ? ed.absOf(i, ed.restCol(i, ctrl ? Rows.wordStep(r.body, col, 1) : col + 1, 1))
      : (i + 1 < n ? ed.absOf(i + 1, 0) : pos)
    if (k === Qt.Key_Home) return ed.absOf(i, 0)
    if (k === Qt.Key_End) return ed.absOf(i, r.body.length)
    var dir = k === Qt.Key_Up ? -1 : 1
    var item = ed.rowItem(i)
    var f = item.field
    var c = f.positionToRectangle(col)
    // A wrapped line first moves within itself.
    if (dir > 0 && c.y < f.positionToRectangle(f.length).y - 1) return ed.absOf(i, ed.restCol(i, f.positionAt(c.x, c.y + c.height * 1.5), 0))
    if (dir < 0 && c.y > f.positionToRectangle(0).y + 1) return ed.absOf(i, ed.restCol(i, f.positionAt(c.x, c.y - c.height * 0.5), 0))
    var j = Rows.nextTextRow(ed.rows, i, dir)
    if (j < 0) return dir < 0 ? ed.absOf(i, 0) : ed.absOf(i, r.body.length)
    var t = ed.rowItem(j).field
    return ed.absOf(j, ed.restCol(j, t.positionAt(f.x + c.x - t.x, dir > 0 ? 1 : t.contentHeight - 1), 0))
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

  // Paste through the hidden plain field, never into the row's own. A row
  // with emphasis in it is rich text, and a rich field reads what is handed
  // to it as html: a pasted `<` would be markup and a run of spaces would
  // collapse. What arrives is the clipboard's plain text, the same on every
  // line, and `insert` puts it through the note the way typing does.
  function pasteText() {
    clip.text = ""
    clip.paste()
    var t = clip.text
    clip.text = ""
    return t
  }

  function pasteAt(pos) {
    if (ed.readOnly) return
    var t = ed.pasteText().replace(/\r/g, "")
    if (t === "") return
    ed.snapshot(true)
    ed.insert(pos, t)
    ed.placeCursor(true)
  }

  function removeSpan() {
    if (ed.readOnly) return
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
    var moved = []
    for (var m = i; m <= j; m++) if (!ed.rows[m].blank) moved.push(m)
    ed.relist(moved)
    ed.selectSpan(ed.absOf(i, 0), ed.absOf(j, ed.rows[j].body.length))
  }

  // Lines moved to another level: their list's markers follow (Rows.relist).
  function relist(lines) {
    var ch = Rows.relist(ed.rows, lines)
    for (var k = ch.length - 1; k >= 0; k--) {
      var r = ed.rows[ch[k].line]
      ed.replace(r.start + r.indent.length, r.start + r.prefixLen, ch[k].marker)
    }
  }

  // Ctrl+Shift+Up / Down: select from the cursor to the start / end of its
  // block — the same block the agent answers. Again at the edge, the
  // selection takes the block before / after too. A selection already
  // there keeps its anchor.
  function selectToBlockEdge(dir, item) {
    var blocks = Blocks.split(ed.text)
    var cur = ed.spanning ? ed.selCursor : ed.cursorPosition
    var anchor = ed.spanning ? ed.selAnchor : (item ? ed.nativeAnchor(item) : ed.cursorPosition)
    var to = -1
    for (var b = 0; b < blocks.length; b++) {
      var first = ed.rows[blocks[b].start]
      var last = ed.rows[blocks[b].end - 1]
      if (!first || !last) continue
      var startAt = first.start + first.prefixLen
      var endAt = last.bodyEnd
      if (dir < 0 && startAt < cur) to = startAt                    // the nearest start before
      if (dir > 0 && endAt > cur && to < 0) to = endAt              // the nearest end after
    }
    if (to < 0 || to === anchor) return
    ed.selectSpan(anchor, to)
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
    if (ctrl && k === Qt.Key_A) { ed.selectAllStep(ed.rowItem(ed.focusedRow)); return true }
    if (ctrl && k === Qt.Key_V) {
      var at = ed.selStart
      ed.removeSpan()
      ed.pasteAt(at)
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
    return { i: i, col: ed.restCol(i, f.positionAt(x - f.x, ly - f.y), 0), box: box }
  }

  function updateCursorRect() {
    var item = ed.rowItem(ed.focusedRow)
    if (!item) return
    column.forceLayout()
    var c = item.field.cursorRectangle
    var p = item.field.mapToItem(ed, c.x, c.y)
    ed.cursorRect = Qt.rect(p.x, p.y, c.width, c.height)
  }

  // A run of lines in editor coordinates — what the page marks.
  function blockRect(startLine, endLine) {
    column.forceLayout()
    var a = ed.rowItem(startLine)
    var b = ed.rowItem(endLine - 1)
    if (!a || !b) return null
    var y = a.y + a.gapTop
    return { y: y, h: b.y + b.height - b.room - y }
  }

  // ------------------------------------------------------------ editing

  // A field changed under the student's fingers.
  function typed(i, body, col) {
    if (ed.readOnly) return
    var r = ed.rows[i]
    if (!r) return
    ed.clearSelection()
    body = body.replace(/\r/g, "")
    // A list marker typed into an empty item takes the item's place: "2. "
    // then "- " is a bullet, not "2. - ".
    var swap = (r.kind === "bullet" || r.kind === "ordered" || r.kind === "task") && /^([-*+]|\d+[.)]) $/.test(body)
    var line = (swap ? r.indent : r.raw.substring(0, r.prefixLen)) + body + r.suffix
    ed.snapshot(/\n/.test(body))
    var lineEnd = r.start + r.raw.length
    var before = ed.rows.length
    ed.commit(ed.text.slice(0, r.start) + line + ed.text.slice(lineEnd), r.start + (swap ? r.indent.length : r.prefixLen) + col)
    // The line changed kind (markdown typed or broken) or a paste brought
    // new lines: the field's text moved, so put the cursor back.
    var now = ed.rows[i]
    ed.typedRaw = now ? now.raw : ""
    ed.freshCue = r.cueAt < 0 && now && now.cueAt >= 0 ? i : -1
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
      // Enter on an empty item steps out one level, as Shift+Tab does
      // (and Notion); at the outermost level it leaves the list (or the
      // quote). 2026-10-19.
      if (r.kind !== "quote" && r.indent !== "") {
        ed.outdent(i)
        ed.relist([i])
        ed.placeCursor(true)
        return
      }
      ed.remove(r.start, lineEnd)
      if (r.kind !== "quote") ed.listLeft(i)
      return
    }
    ed.insert(pos, "\n" + carry)
    ed.returnFinished(i, lineText)
  }

  // Backspace at the start of a line: first the kind goes, then the
  // indentation a level at a time, then the line joins the one above.
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
      ed.outdent(i)
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

  // One level of indentation off line i: a tab, or two spaces.
  function outdent(i) {
    var r = ed.rows[i]
    if (r.indent.charAt(0) === "\t") ed.remove(r.start, r.start + 1)
    else if (r.indent !== "") ed.remove(r.start, r.start + Math.min(2, r.indent.length))
  }

  function indent(i, out) {
    var r = ed.rows[i]
    var listy = r.kind === "task" || r.kind === "bullet" || r.kind === "ordered"
    var was = ed.text
    ed.snapshot(true)
    if (out) {
      ed.outdent(i)
    } else if (listy || r.indent !== "") {
      ed.insert(r.start, "\t")
    } else {
      ed.insert(ed.cursorPosition, "\t")
    }
    if (listy && ed.text !== was) ed.relist([i])
    ed.placeCursor(true)
  }

  // Ctrl+L or a click: tick or untick a checkbox; on a bullet or a plain
  // line, make it a checkbox.
  function toggleCheckbox(i) {
    if (ed.readOnly) return
    var r = ed.rows[i]
    if (!r) return
    ed.snapshot(true)
    if (r.kind === "task") {
      // Ticked, the line says the day it was done (`✅`, as Obsidian Tasks
      // writes it; drawn quietly, as the cancel date is), which keeps it in
      // the dashboard for the rest of the day; unticked, the day comes off.
      // A cancelled box clicked is open again, as a ticked one is.
      var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
      var next = r.checked
        ? Task.setField(Task.setField(Task.setState(r.raw, " "), "✅", ""), "❌", "")
        : Task.setField(Task.setState(r.raw, "x"), "✅", today)
      ed.replaceLine(r, next)
      ed.boxTicked(i, !r.checked)
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

  // A pair of markers drawn to nothing is one thing to the cursor: it never
  // stands inside one, Left and Right cross a whole run in one press, and
  // Backspace and Delete take the letter beyond it rather than the marker
  // itself. A deletion that would leave a pair holding nothing takes the
  // pair with it, because markers with no job are drawn — which is the one
  // way a `**` the student never typed could appear.
  //
  // Before this, a character that is not drawn was still a character: the
  // Backspace that should have taken a letter took a marker, and the
  // markdown came back (2026-10-15, the evening emphasis landed).
  // True when the key was used.
  function emphKey(event, item) {
    var i = item.index
    var runs = ed.hiddenIn(i)
    if (runs.length === 0) return false
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    if (alt) return false
    var f = item.field
    var r = ed.rows[i]
    var len = r.body.length
    var col = f.cursorPosition
    var sel = f.selectedText !== ""
    var k = event.key

    if ((k === Qt.Key_Left || k === Qt.Key_Right) && !(sel && !shift)) {
      var dir = k === Qt.Key_Right ? 1 : -1
      var to = ctrl ? Rows.wordStep(r.body, col, dir) : col + dir
      if (to < 0 || to > len) return false          // the next line's business
      to = ed.restCol(i, to, dir)
      if (!shift) { f.cursorPosition = to; return true }
      var anchor = sel ? (col === f.selectionEnd ? f.selectionStart : f.selectionEnd) : col
      if (to === anchor) f.deselect()
      else f.select(anchor, to)
      return true
    }

    if (k === Qt.Key_Backspace || k === Qt.Key_Delete) {
      var a, b, x
      if (sel) {
        a = Math.min(f.selectionStart, f.selectionEnd)
        b = Math.max(f.selectionStart, f.selectionEnd)
      } else if (k === Qt.Key_Backspace) {
        b = col
        for (x = 0; x < runs.length; x++) if (b > runs[x].a && b <= runs[x].b) b = runs[x].a
        if (b <= 0) return false                    // the line's own start, as before
        a = ctrl ? Rows.wordStep(r.body, b, -1) : b - 1
      } else {
        a = col
        for (x = 0; x < runs.length; x++) if (a >= runs[x].a && a < runs[x].b) a = runs[x].b
        if (a >= len) return false                  // the line's own end, as before
        b = ctrl ? Rows.wordStep(r.body, a, 1) : a + 1
      }
      var span = Emph.collapse(r.body, a, b)
      var base = r.start + r.prefixLen
      ed.snapshot(true)
      ed.replace(base + span.a, base + span.b, "")
      ed.placeCursor(true)
      return true
    }
    return false
  }

  function key(event, item) {
    var f = item.field
    var i = item.index
    var fresh = ed.freshCue
    ed.freshCue = -1
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    var noSel = f.selectedText === ""

    if (k === Qt.Key_Escape && !ctrl && !alt && (ed.spanning || !noSel)) { ed.letGo(item); event.accepted = true; return }
    if (ed.keyFilter && ed.keyFilter(event)) { event.accepted = true; return }
    // Which keys do what comes from Shortcuts.js; the student can move them.
    var toStart = Sc.hit(event, "selectBlockStart")
    if (toStart || Sc.hit(event, "selectBlockEnd")) {
      ed.selectToBlockEdge(toStart ? -1 : 1, item)
      event.accepted = true
      return
    }
    // Before a selection's own keys, which would take Alt+Up as an arrow.
    if (Sc.hit(event, "lineUp") || Sc.hit(event, "lineDown")) {
      ed.moveLines(Sc.hit(event, "lineUp") ? -1 : 1)
      event.accepted = true
      return
    }
    if (ed.spanning) {
      if (ed.spanKey(event)) { event.accepted = true; return }
    }

    // Shift+arrows past the edge of a line: the selection carries on into
    // the next one (by word with Ctrl). Inside a line the field selects on
    // its own, Ctrl+Shift+arrows by word. Ctrl+Shift+Home/End reach the
    // note's ends; Ctrl+A climbs to the whole note (selectAllStep).
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
    if (ctrl && k === Qt.Key_A) { ed.selectAllStep(item); event.accepted = true; return }
    // Paste is the note's, not the field's: see `pasteText`.
    if (ctrl && !shift && !alt && k === Qt.Key_V) {
      var from = noSel ? ed.cursorPosition : ed.absOf(i, Math.min(f.selectionStart, f.selectionEnd))
      if (!noSel) ed.replace(from, ed.absOf(i, Math.max(f.selectionStart, f.selectionEnd)), "")
      ed.pasteAt(from)
      event.accepted = true
      return
    }

    if (ed.emphKey(event, item)) { event.accepted = true; return }

    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !ctrl && !alt) {
      ed.returnKey(item, shift)
    } else if (k === Qt.Key_Backspace && noSel && fresh === i && f.cursorPosition === f.length) {
      ed.cueDismissed(ed.rows[i].raw)
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
    } else if (Sc.hit(event, "undo")) {
      ed.undo()
    } else if (Sc.hit(event, "redo")) {
      ed.redo()
    } else if (Sc.hit(event, "checkbox")) {
      ed.toggleCheckbox(i)
    } else if (Sc.hit(event, "noteStart")) {
      ed.setCursor(0, true)
    } else if (Sc.hit(event, "noteEnd")) {
      ed.setCursor(ed.text.length, true)
    } else if (Sc.fieldWouldTake(event)) {
      // Moved to other keys: the field's own undo or jump must not take
      // the old ones back.
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
        required property bool cancelled
        required property string ordinal
        required property int headingLevel
        required property string callout
        required property bool priv
        required property bool blank
        required property bool lead
        required property real space
        required property int deadline
        required property string dueLabel
        required property real dueAt
        required property string raw
        required property int cueAt
        required property string cueLabel
        required property int tableRow
        required property int tableStart
        required property int tableLen

        property alias field: field
        property alias box: box
        readonly property string author: ed.authors[row.index] || ""
        readonly property bool listy: kind === "task" || kind === "bullet" || kind === "ordered"
        readonly property bool quoted: kind === "quote" || kind === "calloutHead"
        // A date being written at the end of this checkbox: lit up, its
        // pill pending (accent) until the line is left and it is bound.
        readonly property bool pending: ed.cues && kind === "task" && cueAt >= 0 && ed.typedRaw !== "" && raw === ed.typedRaw && !ed.declined[raw]
        readonly property int gapTop: blank ? 0 : Math.round(space * ed.textSize)
        readonly property real indentX: level * ed.markerWidth
        readonly property real labelWidth: kind === "calloutHead" ? label.implicitWidth + Math.round(ed.textSize * 0.4) : 0
        readonly property real fieldX: indentX + (listy ? ed.markerWidth : (quoted ? ed.quoteWidth : 0)) + labelWidth
        readonly property real firstLine: fm.height

        width: column.width
        readonly property real room: index === ed.roomRow ? ed.roomHeight : 0
        // A blank line opens to a line's height when the cursor is on it —
        // but not under a selection or a press: a drag passing over it
        // would move every line below by that much and back (2026-10-19).
        readonly property bool opened: !blank || field.activeFocus && !ed.spanning && !pointer.pressed
        height: (tableDrawn ? (tableRow === 1 ? Math.round(ed.textSize * 0.5) : gapTop + cellRow.height + Math.round(ed.textSize * 0.5))
                 : img ? gapTop + (reveal ? field.height + imgGap : 0) + picture.height
                 : opened ? gapTop + field.height : Math.round(space * ed.textSize)) + room
        Binding { when: row.index === ed.roomRow; target: ed; property: "roomTop"; value: row.y + row.height - row.room }

        // What the field holds, read and written as the body: with emphasis
        // in it the field is rich text (Emph.js), and then its `text` is
        // html — `plain` is the body, character for character, and the only
        // thing the editor ever looks at.
        readonly property bool rich: kind !== "code" && kind !== "front" && kind !== "image" && Emph.has(body)
        // Its links (Emph.linksIn), and the one being edited — the cursor in
        // it — which is drawn as written.
        readonly property var links: kind !== "code" && kind !== "front" && kind !== "image" && body.indexOf("[") >= 0 ? Emph.linksIn(body) : []
        readonly property int revealLink: {
          if (links.length === 0 || ed.focusedRow !== index || !ed.rows[index]) return -1
          var l = Links.at(links, ed.cursorPosition - ed.rows[index].start - ed.rows[index].prefixLen)
          return l ? l.at : -1
        }
        onRevealLinkChanged: row.show()
        Connections {
          target: ed
          enabled: row.links.length > 0
          function onResolveVersionChanged() { row.show() }
        }
        function linkStyle() {
          return { color: String(ed.linkColor), missing: String(ed.faint), source: String(ed.dim), reveal: row.revealLink,
                   known: function (l) { return !ed.linkKnown || ed.linkKnown(l) } }
        }

        // A picture: its source shown above it while the cursor is on the
        // line, else the picture alone.
        readonly property var img: kind === "image" ? Links.imageLine(body) : null
        readonly property bool reveal: !img || field.activeFocus
        readonly property string imgSource: img && ed.resolveImage ? ed.resolveImage(img.target, img.wiki, ed.resolveVersion) : ""
        readonly property var natural: img && row.imgSource !== "" && row.imgSource !== "?" && ed.imageSize
          ? ed.imageSize(row.imgSource, ed.sizesVersion) : null
        readonly property real imgWidth: !img ? 0 : Math.max(0, Math.min(row.width - row.fieldX,
          img.width > 0 ? img.width : natural ? natural.w : row.width - row.fieldX))
        readonly property bool near: !!img && row.y + row.height > ed.viewTop - (ed.viewBottom - ed.viewTop)
          && row.y < ed.viewBottom + (ed.viewBottom - ed.viewTop)
        readonly property real imgGap: Math.round(ed.textSize * 0.4)

        // A table's row, drawn (`tableDrawn`) unless the cursor is in its
        // table, where every line of it shows as written.
        readonly property bool tableDrawn: kind === "table" && !(ed.focusedRow >= tableStart && ed.focusedRow < tableStart + tableLen)
        readonly property var tinfo: kind === "table" ? ed.tableInfo(tableStart, row.width - row.fieldX) : null
        readonly property var tcells: kind === "table" && tableRow !== 1 ? Rows.cells(raw) : []
        property bool rendering: false

        function plain() {
          return field.textFormat === TextEdit.RichText
            ? field.getText(0, field.length).replace(/[\u2028\u2029]/g, "\n")
            : field.text
        }

        function show() {
          var want = row.rich ? Emph.html(row.body, ed.codeFamily, row.links.length ? row.linkStyle() : null) : row.body
          if (field.shown === want && row.plain() === row.body) return
          var col = field.cursorPosition
          row.rendering = true
          field.textFormat = row.rich ? TextEdit.RichText : TextEdit.PlainText
          field.shown = want
          field.text = want
          row.rendering = false
          if (field.cursorPosition !== col) field.cursorPosition = Math.max(0, Math.min(col, field.length))
        }

        onBodyChanged: row.show()
        Component.onCompleted: row.show()

        FontMetrics { id: fm; font: field.font }

        Row {
          id: cellRow
          visible: row.tableDrawn && row.tableRow !== 1 && !!row.tinfo
          x: row.fieldX
          y: row.gapTop + Math.round(ed.textSize * 0.25)
          spacing: ed.cellGap
          Repeater {
            model: cellRow.visible ? row.tinfo.widths.length : 0
            Text {
              required property int index
              width: row.tinfo.widths[index]
              wrapMode: Text.Wrap
              textFormat: Text.RichText
              text: Emph.html(row.tcells[index] || "", ed.codeFamily, { color: String(ed.linkColor), missing: String(ed.faint),
                                source: String(ed.dim), reveal: -1, known: function (l) { return !ed.linkKnown || ed.linkKnown(l) } })
              horizontalAlignment: row.tinfo.align[index] === "right" ? Text.AlignRight : row.tinfo.align[index] === "center" ? Text.AlignHCenter : Text.AlignLeft
              color: ed.foreground
              font.family: ed.fontFamily
              font.styleName: row.tableRow === 0 ? "" : ed.fontStyle
              font.weight: row.tableRow === 0 ? Font.DemiBold : Font.Normal
              font.pixelSize: ed.textSize
            }
          }
        }
        // The hairlines: under the header strong, between the rows faint.
        Rectangle {
          visible: row.tableDrawn && !!row.tinfo && row.tableRow !== 0 && row.tableRow < row.tableLen - 1
          x: row.fieldX
          y: row.tableRow === 1 ? Math.round(row.height / 2) : row.height - 1
          width: row.tinfo ? row.tinfo.width : 0
          height: 1
          color: row.tableRow === 1 ? ed.dim : Qt.rgba(ed.faint.r, ed.faint.g, ed.faint.b, 0.35)
        }

        Item {
          id: picture
          visible: !!row.img
          x: row.fieldX
          y: row.gapTop + (row.reveal ? field.height + row.imgGap : 0)
          width: row.imgWidth
          height: !row.img ? 0
            : row.imgSource === "" ? missing.implicitHeight
            : row.natural ? Math.round(row.imgWidth * row.natural.h / Math.max(1, row.natural.w))
            : loader.item && loader.item.status === Image.Ready ? loader.item.paintedHeight
            : Math.round(row.imgWidth * 0.4)
          Loader {
            id: loader
            active: row.near && row.imgSource !== "" && row.imgSource !== "?" && (!!row.natural || ed.sizeUnknown(row.imgSource, ed.sizesVersion))
            // No size of its own: a sized Loader would stretch the picture.
            // A picture smaller than the column keeps its own size: Qt only
            // ever scales a bitmap down to `sourceSize`, so `implicitWidth`
            // is the smaller of the two.
            sourceComponent: Image {
              width: picture.width
              height: row.natural ? picture.height : status === Image.Ready ? Math.round(width * implicitHeight / Math.max(1, implicitWidth)) : 0
              asynchronous: true
              cache: false
              fillMode: Image.PreserveAspectFit
              sourceSize.width: Math.round(Math.min(row.natural ? row.natural.w : 1e9, picture.width * ed.pixelRatio))
              source: row.imgSource
              smooth: true
              mipmap: true

            }
          }
          Text {
            id: missing
            visible: !!row.img && row.imgSource === ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: row.img ? row.img.target + " · not found in the vault" : ""
            color: ed.faint
            font.family: ed.fontFamily
            font.styleName: ed.fontStyle
            font.pixelSize: Math.round(ed.textSize * 0.8)
          }
        }

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
          font.styleName: ed.fontStyle
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
          // The person's box is this square; the agent's and the shared one
          // draw their own shape inside it, and the square gives way.
          readonly property color edge: boxArea.containsMouse ? ed.accent : ed.boxColor
          color: row.checked && row.author === "" ? (boxArea.containsMouse ? ed.accent : ed.checkColor) : "transparent"
          border.width: row.checked || row.author !== "" ? 0 : Math.max(1, Math.round(ed.textSize * 0.08))
          border.color: box.edge

          // The agent's: a diamond, outlined while open, filled when done.
          Rectangle {
            visible: row.author === "agent"
            anchors.centerIn: parent
            width: Math.round(box.size * 0.74)
            height: width
            rotation: 45
            radius: Math.max(1, Math.round(width * 0.12))
            color: row.checked ? (boxArea.containsMouse ? ed.accent : ed.checkColor) : "transparent"
            border.width: row.checked ? 0 : Math.max(1, Math.round(ed.textSize * 0.08))
            border.color: box.edge
          }

          // Made together: the seal, quiet while open, the tick's colour
          // when done.
          LogoMark {
            visible: row.author === "together"
            anchors.centerIn: parent
            width: Math.round(box.size * 1.12)
            height: width
            outline: !row.checked
            strokePx: Math.max(1, Math.round(ed.textSize * 0.08))
            color: row.checked ? (boxArea.containsMouse ? ed.accent : ed.checkColor) : box.edge
          }

          Text {
            anchors.centerIn: parent
            visible: row.checked
            textFormat: Text.PlainText
            text: row.cancelled ? "–" : "✓"
            color: ed.background
            font.family: ed.fontFamily
            // Smaller in the agent's diamond and the seal, which hold less
            // than the square.
            font.pixelSize: Math.round(box.size * (row.author === "" ? 0.85 : 0.62))
            font.bold: true
          }

          MouseArea {
            id: boxArea
            anchors.fill: parent
            anchors.margins: -Math.round(ed.textSize * 0.25)
            enabled: box.visible
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
              if (containsMouse) ed.boxHover = row.index
              else if (ed.boxHover === row.index) ed.boxHover = -1
            }
            Component.onDestruction: if (ed.boxHover === row.index) ed.boxHover = -1
            onClicked: ed.clickCheckbox(row.index)
            Loader { anchors.fill: parent; active: !!ed.boxTip && parent.containsMouse; sourceComponent: ed.boxTip }
          }
        }

        Rectangle {
          id: dot
          readonly property int size: Math.max(4, Math.round(ed.textSize * 0.26))
          visible: row.kind === "bullet"
          x: row.indentX + Math.round((ed.markerWidth - size) / 2) - Math.round(ed.textSize * 0.15)
          y: row.gapTop + Math.round((row.firstLine - size) / 2)
          width: size
          height: size
          radius: size / 2
          // The person's dot; the agent's and the shared one draw their own.
          color: row.author === "" ? ed.bulletColor : "transparent"

          Rectangle {
            visible: row.author === "agent"
            anchors.centerIn: parent
            width: Math.round(dot.size * 0.9)
            height: width
            rotation: 45
            color: ed.bulletColor
          }

          LogoMark {
            visible: row.author === "together"
            anchors.centerIn: parent
            width: Math.round(dot.size * 1.9)
            height: width
            color: ed.bulletColor
          }
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
        // the urgent colour. A date being written: the pill to be, accent.
        Rectangle {
          id: due
          readonly property bool late: !row.checked && row.dueAt > 0 && row.dueAt < Date.now()
          visible: row.dueLabel !== "" || row.pending
          anchors.right: parent.right
          y: row.gapTop + Math.round((row.firstLine - height) / 2)
          width: dueText.implicitWidth + (row.deadline > 0 || row.pending ? Math.round(ed.textSize * 0.9) : 0)
          height: dueText.implicitHeight + Math.round(ed.textSize * 0.2)
          radius: height / 2
          color: "transparent"
          border.width: row.deadline > 0 || row.pending ? 1 : 0
          border.color: row.pending ? ed.accent : late ? ed.urgent : ed.faint
          Text {
            id: dueText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: row.pending ? row.cueLabel : row.dueLabel
            color: row.pending ? ed.accent : due.late ? ed.urgent : ed.dim
            font.family: ed.fontFamily
            font.styleName: ed.fontStyle
            font.pixelSize: Math.round(ed.textSize * 0.78)
          }
        }

        // Under the words: search matches (faint, the current one
        // stronger) and a selection across lines. A piece that wraps is
        // drawn as its first line, the whole lines between, and its last.
        Repeater {
          model: ed.paintIn(row.index, ed.marks, ed.currentMark, ed.selAnchor, ed.selCursor, ed.rows)
            .concat(row.pending ? [{ a: row.cueAt, b: row.body.length, kind: "cue" }] : [])
          Item {
            id: mark
            required property var modelData
            readonly property var pieces: {
              field.width; field.contentHeight; field.text
              var r1 = field.positionToRectangle(modelData.a)
              var r2 = field.positionToRectangle(modelData.b)
              if (modelData.sliver) return [{ x: r1.x, y: r1.y, w: Math.round(ed.textSize * 0.4), h: r1.height }]
              if (Math.abs(r1.y - r2.y) < 1) return [{ x: r1.x, y: r1.y, w: r2.x - r1.x, h: r1.height }]
              var out = [{ x: r1.x, y: r1.y, w: field.width - r1.x, h: r1.height }]
              var mid = r1.y + r1.height
              if (r2.y - mid >= 1) out.push({ x: 0, y: mid, w: field.width, h: r2.y - mid })
              out.push({ x: 0, y: r2.y, w: r2.x, h: r2.height })
              return out
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
                color: mark.modelData.kind === "selection" ? ed.selectionColor : mark.modelData.kind === "current" ? ed.currentMarkColor
                  : mark.modelData.kind === "cue" ? ed.cueColor : ed.markColor
                opacity: 1
              }
            }
          }
        }

        TextEdit {
          id: field
          readOnly: ed.readOnly
          x: row.fieldX
          y: row.gapTop
          width: Math.max(0, row.width - row.fieldX - (due.visible ? due.width + Math.round(ed.textSize * 0.6) : 0))
          // Set by `row.show()`, never bound: the row decides whether this
          // line is drawn plain or rich, and `shown` is what it last gave.
          property string shown: ""
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          selectByKeyboard: true
          persistentSelection: false
          opacity: row.reveal && !row.tableDrawn ? 1 : 0
          color: row.checked || row.kind === "front" || row.img ? ed.dim
            : row.kind === "heading" ? ed.headingColors[Math.max(0, Math.min(row.headingLevel, ed.headingColors.length) - 1)]
            : row.kind === "code" ? ed.codeColor : ed.foreground
          selectionColor: ed.selectionColor
          selectedTextColor: ed.foreground
          font.family: row.kind === "code" || row.kind === "front" ? ed.codeFamily : ed.fontFamily
          font.pixelSize: row.kind === "heading"
            ? Math.round(ed.textSize * (row.headingLevel === 1 ? 1.7 : row.headingLevel === 2 ? 1.4 : row.headingLevel === 3 ? 1.15 : 1))
            : (row.kind === "code" || row.kind === "front" || row.img ? Math.round(ed.textSize * 0.85) : ed.textSize)
          font.styleName: row.kind === "heading" || row.kind === "code" || row.kind === "front" ? "" : ed.fontStyle
          // Rank, in the three channels that have an order: size, weight and
          // the colour's distance from the prose (ThemeColors `headings`).
          // Only the title is Bold — below it the page is one weight, so H2
          // reads as a section and not as a second title.
          font.weight: row.kind === "heading" ? (row.headingLevel === 1 ? Font.Bold : Font.DemiBold) : Font.Normal
          cursorVisible: activeFocus && row.opened
          tabStopDistance: ed.tabStop

          onTextChanged: {
            if (ed.syncing || row.rendering) return
            var p = row.plain()
            if (p !== row.body) ed.typed(row.index, p, cursorPosition)
          }
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
  // A double-click takes the word and a triple-click the line; held and
  // dragged after either, the selection grows a word or a line at a time,
  // and Shift+click carries on from the far end of what is selected.
  MouseArea {
    id: pointer
    anchors.fill: column
    // Over the lines it is on top, so its cursor is the one shown: a
    // hand on a checkbox (which takes the click), a text cursor elsewhere.
    cursorShape: ed.boxHover >= 0 || ed.linkHover ? Qt.PointingHandCursor : Qt.IBeamCursor
    hoverEnabled: true
    // A press on a link follows it on release, unless it became a drag.
    property var linkDown: null
    preventStealing: true
    property int downAt: -1
    // What a drag grows by (1 a character, 2 a word, 3 a line), and the
    // word or line it began on, as text offsets.
    property int unit: 1
    property int unitA: -1
    property int unitB: -1
    // Presses in quick succession at one spot: 2 a double-click, 3 a
    // triple. Counted here, so a press held after either is a drag of it.
    property int clicks: 0
    property double pressAt: 0
    property point pressPt: Qt.point(0, 0)

    // The word or the line under a hit, as text offsets.
    function unitAt(h, unit) {
      var r = ed.rows[h.i]
      if (unit === 3) return { a: ed.absOf(h.i, 0), b: ed.absOf(h.i, r.body.length) }
      var w = Rows.wordAt(r.body, h.col)
      return { a: ed.absOf(h.i, ed.restCol(h.i, w.a, -1)), b: ed.absOf(h.i, ed.restCol(h.i, w.b, 1)) }
    }

    // The word or line the press began on, selected in its own line.
    function selectFirst() {
      ed.clearSelection()
      var i = Rows.rowAt(ed.rows, pointer.unitA)
      var r = ed.rows[i]
      ed.setCursor(pointer.unitA, true)
      var item = ed.rowItem(i)
      if (item && pointer.unitB > pointer.unitA)
        item.field.select(pointer.unitA - r.start - r.prefixLen, pointer.unitB - r.start - r.prefixLen)
    }

    function begin(h, unit) {
      var u = pointer.unitAt(h, unit)
      pointer.unit = unit
      pointer.unitA = u.a
      pointer.unitB = u.b
      pointer.selectFirst()
    }

    onPressed: function (mouse) {
      var h = ed.hitTest(mouse.x, mouse.y)
      if (h.box) { mouse.accepted = false; return }
      var pos = ed.absOf(h.i, h.col)
      var now = Date.now()
      var again = now - pointer.pressAt < Qt.styleHints.mouseDoubleClickInterval
        && Math.abs(mouse.x - pointer.pressPt.x) < 8 && Math.abs(mouse.y - pointer.pressPt.y) < 8
      pointer.clicks = again && pointer.clicks < 3 ? pointer.clicks + 1 : 1
      pointer.pressAt = now
      pointer.pressPt = Qt.point(mouse.x, mouse.y)
      pointer.unit = 1
      if (mouse.modifiers & Qt.ShiftModifier) {
        var item = ed.rowItem(ed.focusedRow)
        var anchor = ed.spanning ? ed.selAnchor : item ? ed.nativeAnchor(item) : ed.cursorPosition
        pointer.downAt = anchor
        if (pos !== anchor) ed.selectSpan(anchor, pos)
        else { ed.clearSelection(); ed.setCursor(pos, true) }
        return
      }
      pointer.downAt = pos
      if (pointer.clicks > 1) { pointer.linkDown = null; pointer.begin(h, pointer.clicks); return }
      var link = ed.linkAtHit(h)
      if (link) { pointer.linkDown = { i: h.i, link: link }; return }
      ed.clearSelection()
      ed.setCursor(pos, true)
    }
    onPositionChanged: function (mouse) {
      if (!pressed) {
        // Hovering is this area's now (for links), so a box's hand is
        // decided here too: the box's own area no longer hears the hover.
        var hv = ed.hitTest(mouse.x, mouse.y)
        ed.linkHover = !hv.box && !!ed.linkAtHit(hv)
        if (hv.box) ed.boxHover = hv.i
        else if (ed.boxHover >= 0) ed.boxHover = -1
        return
      }
      if (pointer.downAt < 0) return
      var h = ed.hitTest(mouse.x, mouse.y)
      if (pointer.linkDown) {
        if (Math.abs(mouse.x - pointer.pressPt.x) < 6 && Math.abs(mouse.y - pointer.pressPt.y) < 6) return
        pointer.linkDown = null
      }
      if (pointer.unit > 1) {
        var u = pointer.unitAt(h, pointer.unit)
        if (u.a < pointer.unitA) ed.selectSpan(pointer.unitB, u.a)
        else if (u.b > pointer.unitB) ed.selectSpan(pointer.unitA, u.b)
        else if (ed.spanning) pointer.selectFirst()
        return
      }
      var pos = ed.absOf(h.i, h.col)
      if (pos !== pointer.downAt) ed.selectSpan(pointer.downAt, pos)
      else if (ed.spanning) { ed.clearSelection(); ed.setCursor(pos, true) }
    }
    onReleased: {
      pointer.downAt = -1
      if (pointer.linkDown) { var d = pointer.linkDown; pointer.linkDown = null; ed.linkActivated(d.i, d.link) }
    }
    onExited: { ed.linkHover = false; ed.boxHover = -1 }
  }
}
