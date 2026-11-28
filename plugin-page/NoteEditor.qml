import QtQuick
import "Rows.js" as Rows
import "Blocks.js" as Blocks
import "Emph.js" as Emph
import "Links.js" as Links
import "Shortcuts.js" as Sc
import "Task.js" as Task
import "Focus.js" as Focus

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
  property var chatKey: null    // (event, hasOwnSelection) → taken: the chat's selection's keys
  property var firstKey: null   // (event) → taken: before anything else (the page's open menu)
  // Drawn while the mouse is on a checkbox: the page's hint, naming the
  // key that does the same (an Item; the editor knows nothing of tooltips).
  property Component boxTip: null
  // Drawn while the mouse is on a link (2026-11-25, the mouse pass): the
  // page's hint, saying where it goes, given the link as `link`.
  property Component linkTip: null
  property var hoverLink: null    // { i, link } under the mouse
  // A deadline's date pill under the mouse (its line), and its hint (an
  // Item from the page, as boxTip): lit and named as the dashboard's are.
  property int pillHover: -1
  // The pill under the mouse is a day to work on it, not a deadline.
  readonly property bool pillDoOnly: pillHover >= 0 && !!rows[pillHover] && rows[pillHover].deadline <= 0
  property Component pillTip: null
  // What shows of the note (the page's Flickable): a drag past its edge keeps selecting.
  property Item viewport: null
  // Drawn by the box on the cursor's line: the page's key for it while
  // Ctrl is held (an Item; the editor knows nothing of keys).
  property Component boxBadge: null
  // The hand is on the mouse (the page's `handOn`): a box under a still
  // pointer, as the lines move, is not lit.
  property bool handOn: true
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
  // Dates Tab made deadlines whose number the store has not given yet, by
  // the minute (Page.qml, acceptCue): a box carrying one draws it as the
  // pill to be, as while it was typed.
  property var bindingAt: ({})
  signal cueDismissed(string raw)
  // A box ticked (done) or unticked by the person, in the note.
  signal boxTicked(int lineIndex, bool done)
  // A box clicked with the mouse (the page may name the key, docs/hints.md).
  signal boxClicked()
  // A deadline's date pill clicked: the page asks for its new day, as Ctrl+D.
  signal datePillClicked(int lineIndex)
  // A right click on the lines (x, y in the editor's own coordinates): the
  // page's edit menu, its acts done by `editAct` as their keys do them.
  signal menuAsked(real x, real y)

  property string fontFamily: "sans-serif"
  property string fontStyle: ""        // the cut of the prose face (Page.qml)
  property string codeFamily: "monospace"
  property int textSize: 16
  // The leading of the note's prose, in ems (2026-11-19). A TextEdit has no
  // line height of its own, and plain text none at all, so a row of prose is
  // drawn as rich text with its paragraph's line-height: one block, one
  // document position per character, as an emphasised row already was.
  // 0 leaves the face's own (Adwaita Sans: 1.21). Headings keep tighter.
  property real leading: 0
  readonly property real headingLeading: 1.2
  property color foreground: "black"
  property color background: "white"
  property color dim: "gray"
  property color faint: "lightgray"
  property color selectionColor: "lightblue"
  // The shell's corners (Style.cornerRadius, Hyprland's rounding), from the
  // page: the editor reads no shell module of its own.
  property int cornerRadius: 0
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
  property color cancelColor: dim                               // a cancelled one: never the tick's
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
  // A column never gives way below about eight letters; a table too wide
  // even then scrolls sideways in its block (2026-11-14), every row of it
  // together, by a sideways swipe or Shift and the wheel.
  FontMetrics { id: cellMetrics; font.family: ed.fontFamily; font.styleName: ed.fontStyle; font.pixelSize: ed.textSize }
  readonly property real cellGap: Math.round(ed.textSize * 1.2)
  readonly property real cellMin: Math.max(40, Math.round(cellMetrics.advanceWidth("abcdefgh")))
  // How far each drawn table is scrolled sideways, by its first line.
  property var tableShifts: ({})
  function tableShift(start) { return ed.tableShifts[start] || 0 }
  function setTableShift(start, x) {
    var m = {}
    for (var k in ed.tableShifts) m[k] = ed.tableShifts[k]
    if (x > 0) m[start] = x
    else delete m[start]
    ed.tableShifts = m
  }
  property var tableCache: ({})
  function tableInfo(start, width) {
    var rows = ed.rows
    var head = rows[start]
    if (!head || head.kind !== "table") return null
    var lines = []
    for (var i = start; i < start + head.tableLen; i++) lines.push(rows[i].raw)
    // One entry per table, by its first line (2026-11-27): with one entry
    // for the whole note, two tables took turns throwing each other's out.
    var key = Math.round(width) + "\u0000" + ed.textSize + "\u0000" + lines.join("\n")
    var hit = ed.tableCache[start]
    if (hit && hit.key === key) return hit.info
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
    var room = Math.max(1, width - ed.cellGap * (n - 1))
    var widths = natural.slice()
    var total = widths.reduce(function (a, b) { return a + b }, 0)
    // Too wide: the narrow columns keep their width, the rest share what is left.
    for (var guard = 0; total > room && guard < n; guard++) {
      var fair = room / n, keep = 0, wide = 0
      for (var w = 0; w < n; w++) { if (natural[w] <= fair) keep += natural[w]; else wide++ }
      var share = Math.max(ed.cellMin, wide > 0 ? (room - keep) / wide : fair)
      widths = natural.map(function (x) { return Math.min(x, share) })
      total = widths.reduce(function (a, b) { return a + b }, 0)
      if (total <= room + 1) break
    }
    var whole = widths.reduce(function (a, b) { return a + b }, 0) + ed.cellGap * (n - 1)
    var info = { align: align, widths: widths, width: whole, reach: Math.max(0, Math.ceil(whole - width)) }
    ed.tableCache[start] = { key: key, info: info }   // mutated, not reassigned: a cache tells no binding
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
  // Backspace at the start of a private block's first line: the page takes
  // the block out of private (Page.togglePrivateBlock).
  signal privateUnwrap()
  // A link clicked (docs/files.md): the page follows it.
  signal linkActivated(int lineIndex, var link)

  // One project's part of the day (Focus.js, 2026-11-11): with a tag here
  // only the lines it claims are drawn, and the rest of the day is folded
  // to a line saying how much. The text is the whole note all the same;
  // only the drawing changes. `shown` has a flag per line (null: all of
  // them); a cursor sent into a folded line (a search, a link, an undo)
  // opens the whole day again rather than edit what cannot be seen.
  property string focusTag: ""
  property var shown: null
  property var foldAbove: []
  property var foldBelow: []
  property bool loading: false
  // Which fold mark the mouse is on: its row and "top" or "bottom" ("": none).
  property string foldHot: ""
  readonly property int foldSize: Math.round(textSize * 2.2)
  signal foldClicked()
  onFocusTagChanged: ed.refold(null)

  function isShown(i) { return ed.shown === null || !!ed.shown[i] }

  // The flags for the text as it is: carried from before an edit when
  // `carried` is given, and whatever the tag claims now added to them.
  function refold(carried) {
    if (ed.focusTag === "") {
      ed.shown = null
      ed.foldAbove = []
      ed.foldBelow = []
      return
    }
    var lines = ed.text.split("\n")
    var m = Focus.mask(lines.length, Focus.claims(ed.text, ed.focusTag))
    if (carried && carried.length === m.length) for (var i = 0; i < m.length; i++) m[i] = m[i] || carried[i]
    if (!Focus.any(m)) { ed.focusTag = ""; return }       // nothing of it left: the whole day
    var f = Focus.folds(m, lines)
    ed.shown = m
    ed.foldAbove = f.above
    ed.foldBelow = f.below
  }

  // The drawn line nearest to i (i itself when drawn), looking `dir` first.
  function nearestShown(i, dir) {
    if (ed.isShown(i)) return i
    for (var d = 1; d < ed.rows.length; d++) {
      var x = i + d * dir, y = i - d * dir
      if (x >= 0 && x < ed.rows.length && ed.isShown(x)) return x
      if (y >= 0 && y < ed.rows.length && ed.isShown(y)) return y
    }
    return i
  }

  // The next line the cursor may stand on: past blank lines and folded ones.
  function nextRow(i, dir) {
    var j = Rows.nextTextRow(ed.rows, i, dir, ed.shown)
    return j >= 0 && ed.isShown(j) ? j : -1
  }

  // The drawn run of lines around offset `pos`, as offsets: a selection
  // never reaches across a fold.
  function runAround(pos) {
    var i = Rows.rowAt(ed.rows, pos)
    var a = i, b = i
    while (a > 0 && ed.isShown(a - 1)) a--
    while (b + 1 < ed.rows.length && ed.isShown(b + 1)) b++
    return { a: ed.rows[a].start, b: ed.rows[b].start + ed.rows[b].raw.length }
  }

  implicitHeight: column.height

  property var rows: []          // Rows.derive(text), kept in step with the model
  property bool syncing: false
  property var undoStack: []
  property var redoStack: []
  property double lastSnapshot: 0
  // The typing the newest undo step holds while it may still grow: "ins"
  // or "del", where the cursor ended, and when the step began (snapshot).
  property var undoRun: null

  // Where Up and Down aim, in editor x, and the place the last one landed
  // (2026-11-27): a run of them keeps to one column, so a short line or a
  // heading on the way no longer pulls the cursor left for the rest of it.
  // Any other move leaves the cursor somewhere else, and the aim with it.
  property var goal: null

  // The last move of the cursor was the mouse's: the page keeps it in
  // view without the margin it keeps for the keys (a click near the bottom
  // must not scroll the line away from under the pointer).
  property bool mouseLed: false

  // The minute, for what the clock changes: a deadline's pill turns late,
  // and "today" becomes "yesterday" at midnight (Rows.doLabel), without
  // waiting for the line to be written on.
  property double now: Date.now()
  property string today: new Date().toDateString()
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var d = new Date()
      ed.now = d.getTime()
      if (d.toDateString() !== ed.today) {
        ed.today = d.toDateString()
        if (ed.rows.length > 0) ed.syncRows()
      }
    }
  }

  // A line's date the person kept as words, the line written on since:
  // the page keeps it words under its new text too (`declined`).
  signal declineCarried(string was, string now)
  property var keptCue: null    // { raw, phrase }: the line being written and the date it keeps as words
  // Alt+Up / Alt+Down stopped at a private block's edge: a line moved out
  // of it, or the block's mark from its top, would be read by the agent.
  signal privateKept()

  // ------------------------------------------------------------ the text

  // Whether a line holds the window's keys: `focus`, not `activeFocus`,
  // which every line gives up while the window is behind another.
  function holdsFocus() {
    for (var i = 0; i < rep.count; i++) {
      var it = rep.itemAt(i)
      if (it && it.field.focus) return true
    }
    return false
  }

  // Replace everything (a load from disk). The cursor goes to the end and
  // the undo history starts over. If a line held the keys, a line still
  // does: the one they were in may be rebuilt, and the keys would go with
  // it, leaving every shortcut deaf until a click (2026-11-17). Keys asked
  // for before there were lines (`focusNote`) come now, unless something
  // shown was given them meanwhile.
  function load(t) {
    var held = ed.holdsFocus() || (ed.focusOwed && ed.keysUnclaimed())
    ed.focusOwed = false
    ed.loading = true
    ed.shown = null
    ed.clearSelection()
    pointer.clicks = 0
    ed.typedRaw = ""
    ed.freshCue = -1
    ed.undoStack = []
    ed.redoStack = []
    ed.undoRun = null
    ed.goal = null
    ed.escapeAt = -1
    ed.keptCue = null
    ed.tableCache = ({})
    ed.commit(t, t.length)
    ed.placeCursor(held)
    ed.loading = false
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

  // Several edits as one (2026-11-27): [{ a, b, s }], offsets into the text
  // as it is, none overlapping. One commit, so the rows are derived and
  // drawn once, where a replace each did it again per marker or per line.
  function editsApplied(edits) {
    var es = edits.slice().sort(function (x, y) { return y.a - x.a })
    var t = ed.text
    for (var e = 0; e < es.length; e++) t = t.slice(0, es[e].a) + es[e].s + t.slice(es[e].b)
    return t
  }
  // Where offset p is once the edits are made. Something inserted exactly
  // at p goes before it when `bias` > 0 (p moves on), after it otherwise.
  function through(edits, p, bias) {
    var d = 0
    for (var e = 0; e < edits.length; e++) {
      var x = edits[e]
      if (x.b < p || (x.b === p && (x.a < p || bias > 0))) d += x.s.length - (x.b - x.a)
      else if (x.a < p) d += x.a + x.s.length - p
    }
    return p + d
  }
  // The edits made, the cursor carried as `replace` carries it.
  function applyEdits(edits) {
    if (ed.readOnly || edits.length === 0) return
    ed.commit(ed.editsApplied(edits), ed.through(edits, ed.cursorPosition, 1))
    ed.placeCursor(false)
  }

  // Lines gone from a numbered list, or joined: the items after count on
  // from the ones before (2026-11-27: deleting `2.` left `1.` and `3.`).
  function renumberAt(pos) {
    var i = Rows.rowAt(ed.rows, pos)
    var near = []
    for (var k = Math.max(0, i - 1); k <= Math.min(ed.rows.length - 1, i + 1); k++)
      if (ed.rows[k].kind === "ordered") near.push(k)
    if (near.length > 0) ed.relist(near, true)
  }

  // Which lines are private (Blocks.js, as the agent reads the note), by
  // their words, counted.
  function privateLines(text) {
    var lines = text.split("\n"), out = {}
    var bl = Blocks.split(text)
    for (var x = 0; x < bl.length; x++) {
      if (!bl[x].private) continue
      for (var k = bl[x].start; k < bl[x].end; k++) out[lines[k]] = (out[lines[k]] || 0) + 1
    }
    return out
  }
  function privateLost(was, now) {
    var p = ed.privateLines(was), q = ed.privateLines(now)
    for (var l in p) if ((q[l] || 0) < p[l]) return true
    return false
  }

  // Emphasis: wrap the selection — or the word the cursor is in — in a
  // marker, and take it off again when it is already there. The markers are
  // written into the note as they are (`**`, `*`, `` ` ``, `~~`), because
  // the file stays plain markdown and Obsidian reads the same ones; the row
  // draws them to nothing and the words emphasised (Emph.js).
  //
  // Since 2026-11-27: the word under the cursor leaves its punctuation out
  // (`world.` → `**world**.`); a link is taken whole; inside an emphasis of
  // the same kind the key takes it off what it is on, splitting the phrase
  // round it (`**one two three**`, Ctrl+B on "two": `**one** two
  // **three**`), where it wrote a second pair inside the first; and over
  // several lines each line's words are wrapped on their own, since an
  // emphasis never crosses a line (the markers went before `- ` and `# `,
  // and showed). All of it one edit and one undo step.
  function emphasise(marker) {
    if (ed.readOnly) return
    var t = ed.text
    var n = marker.length
    var a, b
    var sel = ed.selected()
    if (sel) {
      // Spaces at a selection's edges stay outside the markers: `**word **`
      // is no emphasis (Emph.js), and a drag easily takes the space.
      a = sel.a; b = sel.b
      while (a < b && /\s/.test(t.charAt(a))) a++
      while (b > a && /\s/.test(t.charAt(b - 1))) b--
      if (Rows.rowAt(ed.rows, a) !== Rows.rowAt(ed.rows, b)) { ed.emphasiseLines(marker, a, b); return }
    } else {
      // At a word's edge, not in it: nothing to wrap, and the key says what
      // the next letters are — out of the emphasis that ends here, into the
      // one that starts here (as Google Docs does), else a pair written to
      // be typed into.
      var er = ed.rows[Rows.rowAt(ed.rows, ed.cursorPosition)]
      var ebase = er.start + er.prefixLen
      var ecol = ed.cursorPosition - ebase
      var inLink = er.body.indexOf("[") >= 0 && !!Links.at(Emph.linksIn(er.body), ecol)
      if (!inLink && !ed.insideWord(er, ecol)) {
        var to = Emph.stepFor(er.body, ecol, Emph.KIND[marker])
        if (to >= 0) {
          ed.clearSelection()
          ed.escapeAt = ebase + to
          ed.setCursor(ebase + to, true)
          return
        }
        ed.snapshot(true)
        ed.clearSelection()
        ed.commit(t.slice(0, ed.cursorPosition) + marker + marker + t.slice(ed.cursorPosition), ed.cursorPosition + n)
        ed.setCursor(ed.cursorPosition, true)
        return
      }
      var w = ed.wordAtCursor()
      a = w.a; b = w.b
    }
    var r = ed.rows[Rows.rowAt(ed.rows, a)]
    var base = r.start + r.prefixLen
    var ca = Math.max(a, base) - base, cb = Math.max(ca, Math.min(b, r.bodyEnd) - base)
    var trimmed = Emph.trimRuns(r.body, ca, cb)
    ca = trimmed.a; cb = trimmed.b
    ed.snapshot(true)
    if (ca === cb) {
      // Nothing to wrap: write the pair, stand inside it.
      ed.clearSelection()
      ed.commit(t.slice(0, base + ca) + marker + marker + t.slice(base + ca), base + ca + n)
      ed.setCursor(base + ca + n, true)
      return
    }
    var edits = ed.emphasisEdits(r, ca, cb, marker)
    var sa = ed.through(edits, base + ca, 1), sb = ed.through(edits, base + cb, -1)
    ed.clearSelection()
    ed.commit(ed.editsApplied(edits), sb)
    ed.selectSpan(sa, sb)
  }

  // The word the cursor is in, for the emphasis keys: its punctuation and
  // the markers already round it left out; in a link, the whole link.
  function wordAtCursor() {
    var r = ed.rows[Rows.rowAt(ed.rows, ed.cursorPosition)]
    var base = r.start + r.prefixLen, body = r.body
    var col = Math.max(0, Math.min(body.length, ed.cursorPosition - base))
    var links = body.indexOf("[") >= 0 ? Emph.linksIn(body) : []
    var l = links.length > 0 ? Links.at(links, col) : null
    if (l) return { a: base + l.at, b: base + l.end }
    var a = col, b = col
    while (a > 0 && !/\s/.test(body.charAt(a - 1))) a--
    while (b < body.length && !/\s/.test(body.charAt(b))) b++
    var runs = Emph.hidden(body)
    var edge = /[.,;:!?()\[\]{}"'“”‘’…]/
    for (var guard = 0; guard < 8; guard++) {
      var a0 = a, b0 = b
      while (a < b && edge.test(body.charAt(a))) a++
      while (b > a && edge.test(body.charAt(b - 1))) b--
      for (var x = 0; x < runs.length; x++) {
        if (runs[x].open && runs[x].a === a && runs[x].b <= b) a = runs[x].b
        if (!runs[x].open && runs[x].b === b && runs[x].a >= a) b = runs[x].a
      }
      if (a === a0 && b === b0) break
    }
    return { a: base + a, b: base + b }
  }

  // The edits that put `marker` round [ca, cb) of row r's words, or take
  // it off them when an emphasis of its kind already holds them: the
  // phrase round them keeps its emphasis either side.
  function emphasisEdits(r, ca, cb, marker) {
    var base = r.start + r.prefixLen, body = r.body
    var node = Emph.ofKind(body, ca, cb, Emph.KIND[marker])
    if (!node) return [{ a: base + cb, b: base + cb, s: marker }, { a: base + ca, b: base + ca, s: marker }]
    if (ca === node.at && cb === node.end) { ca = node.inner[0]; cb = node.inner[1] }
    var w = Emph.widen(body, ca, cb, node.inner[0], node.inner[1])
    var m = node.marker
    var lcore = body.substring(node.inner[0], w.a).replace(/\s+$/, "")
    var rcore = body.substring(w.b, node.inner[1]).replace(/^\s+/, "")
    var out = []
    if (rcore === "") out.push({ a: base + node.inner[1], b: base + node.end, s: "" })
    else out.push({ a: base + node.inner[1] - rcore.length, b: base + node.inner[1] - rcore.length, s: m })
    if (lcore === "") out.push({ a: base + node.at, b: base + node.inner[0], s: "" })
    else out.push({ a: base + node.inner[0] + lcore.length, b: base + node.inner[0] + lcore.length, s: m })
    return out
  }

  // Emphasis over several lines: each line's words on their own. When every
  // line's already are, it comes off them all; otherwise it goes on the
  // lines without it. Code, front matter and a table's dashes are passed.
  function emphasiseLines(marker, a, b) {
    var i = Rows.rowAt(ed.rows, a), j = Rows.rowAt(ed.rows, b)
    var kind = Emph.KIND[marker]
    var segs = []
    for (var k = i; k <= j; k++) {
      var r = ed.rows[k]
      if (r.blank || !ed.isShown(k) || r.kind === "code" || r.kind === "front" || r.kind === "image"
          || (r.kind === "table" && r.tableRow === 1)) continue
      var base = r.start + r.prefixLen
      var ca = Math.max(a, base) - base, cb = Math.min(b, r.bodyEnd) - base
      while (ca < cb && /\s/.test(r.body.charAt(ca))) ca++
      while (cb > ca && /\s/.test(r.body.charAt(cb - 1))) cb--
      if (cb > ca) segs.push({ r: r, a: ca, b: cb, has: !!Emph.ofKind(r.body, ca, cb, kind) })
    }
    if (segs.length === 0) return
    var all = segs.every(function (g) { return g.has })
    var edits = []
    for (var s = 0; s < segs.length; s++)
      if (all || !segs[s].has) edits = edits.concat(ed.emphasisEdits(segs[s].r, segs[s].a, segs[s].b, marker))
    var from = ed.spanning ? ed.selAnchor : a, to = ed.spanning ? ed.selCursor : b
    var lo = ed.through(edits, Math.min(from, to), -1), hi = ed.through(edits, Math.max(from, to), 1)
    ed.snapshot(true)
    ed.clearSelection()
    ed.commit(ed.editsApplied(edits), to >= from ? hi : lo)
    if (to >= from) ed.selectSpan(lo, hi)
    else ed.selectSpan(hi, lo)
  }

  // Ctrl+K: a link, the way Obsidian writes one. Words selected become its
  // text and the cursor waits between the parentheses for the address;
  // with none, `[]()` and the cursor between the brackets for the words.
  function makeLink() {
    if (ed.readOnly) return
    ed.snapshot(true)
    var sel = ed.selected()
    if (sel) {
      var a = sel.a, b = sel.b
      ed.insert(b, "]()")              // the far end first: the near offset holds
      ed.insert(a, "[")
      ed.clearSelection()
      ed.setCursor(b + 3, true)
    } else {
      var c = ed.cursorPosition
      ed.insert(c, "[]()")
      ed.setCursor(c + 1, true)
    }
  }

  // Alt+Up / Alt+Down: the line the cursor is on — or every line a
  // selection touches — trades places with the line above or below, as in
  // VS Code; the cursor and the selection go with it. A bound line carries
  // its anchor along, so its deadline follows the words.
  //
  // Three things hold since 2026-11-27. Lines from outside a quote pass a
  // quote whole instead of landing inside it, which cut it in two: a
  // private block's lower half became a quote of its own, read by the
  // agent. A private line never leaves its block this way, nor its mark its
  // top (`privateKept`; cut and paste still move one out, on purpose). And
  // the numbers of a list stay where they stand, so moving `3.` up makes it
  // `2.` and the list still counts 1, 2, 3.
  function moveLines(dir) {
    if (ed.readOnly) return
    var t = ed.text
    var spanning = ed.spanning
    var anchor = ed.selAnchor
    var cur = ed.cursorPosition
    var a = spanning ? ed.selStart : cur
    var b = spanning ? ed.selEnd : cur
    if (spanning && t.charAt(b - 1) === "\n") b--      // ending at a line's start does not take that line
    var lines = t.split("\n")
    var ia = Rows.rowAt(ed.rows, a), ib = Rows.rowAt(ed.rows, b)
    var quoted = function (k) { return /^>/.test(lines[k]) }
    var moving = lines.slice(ia, ib + 1)
    var allQuoted = moving.every(function (l) { return /^>/.test(l) })
    // The lines passed over: the one beside them, or a whole quote.
    var pa, pb
    if (dir < 0) {
      if (ia === 0) return
      pa = pb = ia - 1
      if (!allQuoted && quoted(pb)) while (pa > 0 && quoted(pa - 1)) pa--
    } else {
      if (ib >= lines.length - 1) return
      pa = pb = ib + 1
      if (!allQuoted && quoted(pa)) while (pb < lines.length - 1 && quoted(pb + 1)) pb++
    }
    // A line never trades places with one folded away (Focus.js).
    for (var f = pa; f <= pb; f++) if (!ed.isShown(f)) return
    var passed = lines.slice(pa, pb + 1)
    var lo = Math.min(ia, pa), hi = Math.max(ib, pb)
    var was = lines.slice(lo, hi + 1)
    var moved = dir < 0 ? moving.concat(passed) : passed.concat(moving)
    var num = /^([ \t]*)(\d+)([.)] )/
    for (var k = 0; k < moved.length; k++) {
      var o = num.exec(was[k]), n = num.exec(moved[k])
      if (o && n && o[1] === n[1]) moved[k] = n[1] + o[2] + moved[k].substring(n[1].length + n[2].length)
    }
    var out = lines.slice(0, lo).concat(moved, lines.slice(hi + 1)).join("\n")
    if (ed.privateLost(t, out)) { ed.privateKept(); return }
    // The moving lines as they are now (their numbers may have changed),
    // and where they start: an offset in them is carried there.
    var own = dir < 0 ? moved.slice(0, moving.length) : moved.slice(passed.length)
    var oldStart = ed.rows[ia].start
    var newStart = ed.rows[lo].start + (dir < 0 ? 0 : passed.length === 0 ? 0 : moved.slice(0, passed.length).join("\n").length + 1)
    var carry = function (p) {
      var off = p - oldStart, at = newStart
      for (var x = 0; x < moving.length; x++) {
        if (off <= moving[x].length) {
          var grow = own[x].length - moving[x].length
          var head = (moving[x].match(/^[ \t]*\d+/) || [""])[0].length
          if (grow !== 0 && off >= head && head > 0) off += grow
          return at + Math.max(0, Math.min(own[x].length, off))
        }
        off -= moving[x].length + 1
        at += own[x].length + 1
      }
      return at      // the start of the line after them
    }
    ed.snapshot(true)
    var nc = carry(cur)
    var na = spanning ? carry(anchor) : nc
    ed.commit(out, nc)
    if (spanning) ed.selectSpan(na, nc)
    else ed.placeCursor(true)
  }

  // Move the cursor. With `focus`, the note takes the keyboard too;
  // otherwise the field only follows when the note already has it.
  function setCursor(pos, focus) {
    ed.cursorPosition = Math.max(0, Math.min(ed.text.length, pos))
    ed.placeCursor(focus === true)
  }

  // Asked for the keys before the note has a line to hold them: the page
  // opened before its note was read, as its first open after the shell
  // starts is. The note owes itself the keys until its lines come (`load`).
  // Until 2026-11-24 the ask was simply lost, and a closed sheet's key
  // catcher kept the keys: on Omarchy the overlay's first open typed into
  // hidden settings (the alongside window was saved by a second ask when
  // Wayland mapped it); Windows had a stand-in in its host.
  property bool focusOwed: false
  function focusNote() {
    if (ed.rows.length === 0) { ed.focusOwed = true; return }
    ed.placeCursor(true)
  }

  // Nothing shown was given the keys: nothing has them, or what has them
  // is hidden (a closed sheet's catcher) or something the note sits in.
  // Then an owed ask is still the last word on where they go.
  function keysUnclaimed() {
    var f = ed.Window.activeFocusItem
    if (!f || !f.visible) return true
    for (var p = ed.parent; p; p = p.parent) if (p === f) return true
    return false
  }

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
  //
  // `run` says what the typing was (typed, emphKey): { kind: "ins" or
  // "del", a, b: the span it touched, to: where the cursor ends, space:
  // it starts with a space, fresh: a step of its own that typing after it
  // may join }. Until 2026-11-27 a step joined anything within 900 ms of
  // the last keystroke, so a fast writer's whole paragraph was one Ctrl+Z,
  // and an edit on another line, or a word typed and taken back, went with
  // the typing before it. Now a step also ends where the cursor jumped,
  // where typing turns to deleting or back, and at a space once it has
  // run for three seconds.
  function snapshot(force, run) {
    if (ed.readOnly) return
    var now = Date.now()
    var u = ed.undoRun
    var join = !force && now - ed.lastSnapshot < 900
    if (join && run) join = !!u && !run.fresh && u.kind === run.kind && (u.end === run.a || u.end === run.b)
                             && !(run.space && now - u.since > 3000)
    ed.lastSnapshot = force ? 0 : now
    ed.undoRun = force || !run ? null : { kind: run.kind, end: run.to, since: join && u ? u.since : now }
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
    ed.undoRun = null
    ed.clearSelection()
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
    ed.undoRun = null
    ed.clearSelection()
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  // ------------------------------------------------------------ rows

  readonly property var roles: ["kind", "body", "level", "checked", "cancelled", "ordinal", "headingLevel", "callout", "priv", "blank", "lead", "space", "deadline", "dueLabel", "dueAt", "doDay", "raw", "cueAt", "cueEnd", "cueLabel", "cueBad", "tableRow", "tableStart", "tableLen", "quoteDepth", "outerLevel", "paperEnd", "paperAbove", "paperBelow", "extraBlank"]

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
    if (ed.focusTag !== "")
      ed.refold(ed.shown && ed.shown.length === prev.length ? Focus.carry(ed.shown, a, oldMid, newMid) : null)
    ed.rows = next
    // A row that no longer exists cannot be the focused one. When the rows
    // shrink — a shorter note opened, lines deleted — the old index would
    // dangle, and everything that reads it quietly stops: the drawn cursor
    // (updateCursorRect), paste over a selection, Enter over a selection.
    if (ed.focusedRow >= next.length) ed.focusedRow = -1
    if (oldMid > newMid) rowModel.remove(a + newMid, oldMid - newMid)
    for (var k = oldMid; k < newMid; k++) rowModel.insert(a + k, ed.roleValues(next[a + k]))
    // A row outside the lines that changed is compared with what it was
    // (`prev`, which the model holds), not read back from the model, and
    // redrawn only when something of it changed (2026-11-27). Until then
    // every keystroke read every row back and drew it again — its emphasis
    // parsed, its html made — so typing slowed as the note grew.
    for (var i = 0; i < next.length; i++) {
      var mid = i >= a && i < a + newMid
      var cur = mid ? rowModel.get(i) : prev[i < a ? i : i - newMid + oldMid]
      var touched = false
      for (var r = 0; r < ed.roles.length; r++) {
        var role = ed.roles[r]
        if (cur[role] !== next[i][role]) { rowModel.setProperty(i, role, next[i][role]); touched = true }
      }
      // Typing `>` into an empty line leaves the body empty, as it was:
      // the role does not change, but the field still shows the `>`. A
      // line that changed kind with the same words (a fence opened above
      // it) is drawn again too.
      if (!mid && !touched) continue
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

  // Row i's words as they are drawn — the markers drawn to nothing and a
  // link's hidden source left out — and the column of the body each drawn
  // character is (2026-11-27, for find: "read chapter" found nothing in
  // `read **chapter 3**`, and part of a link's hidden address was marked
  // as a sliver nobody could read).
  function drawnWords(i) {
    var r = ed.rows[i]
    var hide = ed.hiddenIn(i).slice()
    var prose = r.kind !== "code" && r.kind !== "front" && r.kind !== "image"
    if (prose && r.body.indexOf("[") >= 0) {
      var item = ed.rowItem(i)
      var reveal = item ? item.revealLink : -1
      var ls = Emph.linksIn(r.body)
      for (var k = 0; k < ls.length; k++) {
        if (ls[k].at === reveal) continue
        hide.push({ a: ls[k].at, b: ls[k].inner[0] }, { a: ls[k].inner[1], b: ls[k].end })
      }
    }
    if (hide.length === 0) return null       // drawn as written
    var text = "", at = []
    for (var c = 0; c < r.body.length; c++) {
      var gone = false
      for (var h = 0; h < hide.length && !gone; h++) gone = c >= hide[h].a && c < hide[h].b
      if (!gone) { text += r.body.charAt(c); at.push(c) }
    }
    return { text: text, at: at }
  }

  // Its arrows (Emph.arrowsIn), each one character to the cursor.
  function arrowsIn(i) {
    var r = ed.rows[i]
    if (!r || r.kind === "code" || r.kind === "front" || r.kind === "image") return []
    return Emph.arrowsIn(r.body)
  }

  function restCol(i, col, dir) {
    var r = ed.rows[i]
    if (!r) return col
    // The place Ctrl+B stepped to, out of an emphasis or into it, holds
    // until the cursor moves on (Emph.forbidden).
    if (ed.escapeAt >= 0 && r.start + r.prefixLen + col === ed.escapeAt) return col
    var stops = r.kind === "code" || r.kind === "front" ? [] : r.kind === "image" ? Emph.hidden(r.body) : Emph.stops(r.body)
    return Emph.validCol(stops, col, r.body.length, dir)
  }
  // Where Ctrl+B (or its kin) at a word's edge put the cursor: just past an
  // emphasis's markers, or just inside them, so what is typed next is out of
  // it or in it (Google Docs' way of turning bold off for the next letters).
  // -1: none.
  property int escapeAt: -1

  // Whether column `col` of row r is inside a word, its drawn letters on
  // both sides (the markers between them do not count).
  function insideWord(r, col) {
    var body = r.body, hid = Emph.hidden(body)
    var hiddenAt = function (c) { for (var h = 0; h < hid.length; h++) if (c >= hid[h].a && c < hid[h].b) return true; return false }
    var p = col - 1
    while (p >= 0 && hiddenAt(p)) p--
    var n = col
    while (n < body.length && hiddenAt(n)) n++
    var wordy = function (ch) { return ch !== "" && !/[\s.,;:!?()\[\]{}"'“”‘’…]/.test(ch) }
    return p >= 0 && n < body.length && wordy(body.charAt(p)) && wordy(body.charAt(n))
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
    if (!ed.isShown(i)) {
      if (ed.loading) {
        i = ed.nearestShown(i, -1)
        ed.cursorPosition = ed.rows[i].bodyEnd
      } else {
        ed.focusTag = ""
      }
    }
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

  // Ctrl+A climbs a step at a time, each step the next one out that holds
  // the cursor (2026-11-11): the line's words; a list item with what is
  // under it, then the item it hangs from, then the whole list; the block
  // (a paragraph, a quote, a table); the section under each heading above
  // it, the nearest first; the whole note. Each press takes the nearest
  // step that holds more than what is selected now, so a step that would
  // change nothing (a one-line item, a one-line paragraph) is passed over,
  // and a selection made by hand starts the climb from where it is. Until
  // then the steps were the line, the block and the note, and a list's
  // items are one block each: a bullet went from its line to the whole
  // note in one press. The wider steps take whole lines, their marks too,
  // so what is copied or cut is whole markdown.
  // An edit from the mouse's menu (2026-11-25, the mouse pass), done as
  // its key does it on the cursor's line: Ctrl and `k` (C, X, V, A).
  function editAct(k) {
    var item = ed.rowItem(ed.focusedRow)
    if (!item) return
    ed.key({ key: k, modifiers: Qt.ControlModifier, text: "", isAutoRepeat: false, accepted: false }, item)
  }
  function hasSelection() {
    var item = ed.rowItem(ed.focusedRow)
    return ed.spanning || (!!item && item.field.selectedText !== "")
  }
  // The selection as text offsets, or null.
  function selectedSpan() {
    if (ed.spanning) return { a: ed.selStart, b: ed.selEnd }
    var item = ed.rowItem(ed.focusedRow)
    if (!item || item.field.selectedText === "") return null
    var f = item.field
    return { a: ed.absOf(item.index, Math.min(f.selectionStart, f.selectionEnd)),
             b: ed.absOf(item.index, Math.max(f.selectionStart, f.selectionEnd)) }
  }

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
    var spans = ed.ladder(i)
    for (var x = 0; x < spans.length; x++) {
      var first = ed.rows[spans[x][0]], last = ed.rows[spans[x][1]]
      steps.push([first.start, last.start + last.raw.length])
    }
    if (ed.shown !== null) {
      var run = ed.runAround(a)
      steps = steps.filter(function (st) { return st[0] >= run.a && st[1] <= run.b })
      steps.push([run.a, run.b])
    } else steps.push([0, ed.text.length])
    for (var s = 0; s < steps.length; s++) {
      var lo = steps[s][0], hi = steps[s][1]
      if (lo > a || hi < b) continue
      if (ed.shownFrom(lo) === ed.shownFrom(a) && ed.shownTo(hi) === ed.shownTo(b)) continue
      var from = ed.spanning ? ed.ladderFrom : ed.cursorPosition
      ed.selectSpan(lo, hi)
      ed.ladderFrom = from
      return
    }
  }

  // The steps out from row i, as [first, last] rows, the smallest first;
  // only those of more than one line (the words' step holds one).
  function ladder(i) {
    var rows = ed.rows, n = rows.length
    var spans = []
    function blank(k) { return rows[k].kind === "blank" }
    // The list item the row is, or the one it is written under.
    var j = -1
    if (Rows.listy(rows[i])) j = i
    else if (Rows.inList(rows[i]))
      for (var u = i - 1; u >= 0 && !blank(u) && Rows.inList(rows[u]); u--)
        if (Rows.listy(rows[u]) && rows[u].level < rows[i].level) { j = u; break }
    var top = -1
    while (j >= 0) {
      var L = rows[j].level, e = j
      for (var d = j + 1; d < n && !blank(d) && Rows.inList(rows[d]) && rows[d].level > L; d++) e = d
      spans.push([j, e])
      top = j
      var p = -1
      for (var w = j - 1; w >= 0 && !blank(w) && Rows.inList(rows[w]); w--)
        if (Rows.listy(rows[w]) && rows[w].level < L) { p = w; break }
      j = p
    }
    if (top >= 0) {
      var l0 = top, l1 = top
      while (l0 > 0 && !blank(l0 - 1) && Rows.inList(rows[l0 - 1])) l0--
      while (l1 < n - 1 && !blank(l1 + 1) && Rows.inList(rows[l1 + 1])) l1++
      spans.push([l0, l1])
    }
    var blocks = Blocks.split(ed.text)
    for (var x = 0; x < blocks.length; x++)
      if (i >= blocks[x].start && i < blocks[x].end) spans.push([blocks[x].start, blocks[x].end - 1])
    // Sections: a heading's lines until the next heading of its level or
    // higher, without the blank lines at its end; the nearest first.
    var heads = Focus.headings(ed.text.split("\n"))
    var secs = []
    for (var h = 0; h < heads.length && heads[h].line <= i; h++) {
      var end = n
      for (var k = h + 1; k < heads.length; k++) if (heads[k].level <= heads[h].level) { end = heads[k].line; break }
      if (i >= end) continue
      var last = end - 1
      while (last > heads[h].line && blank(last)) last--
      secs.unshift([heads[h].line, last])
    }
    spans = spans.concat(secs).filter(function (sp) { return sp[1] > sp[0] })
    // Smallest first; each holds the ones before it.
    spans.sort(function (x1, x2) { return (x1[1] - x1[0]) - (x2[1] - x2[0]) || x2[0] - x1[0] })
    return spans
  }

  // A text offset as the selection is drawn: a line's hidden mark is not
  // drawn, so an end inside it is where its words start; a bound line's
  // date is not drawn either, so an end past its words is where they end.
  function shownFrom(pos) {
    var r = ed.rows[Rows.rowAt(ed.rows, pos)]
    return r ? Math.max(pos, r.start + r.prefixLen) : pos
  }
  function shownTo(pos) {
    var r = ed.rows[Rows.rowAt(ed.rows, pos)]
    return r ? Math.max(r.start + r.prefixLen, Math.min(pos, r.bodyEnd)) : pos
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
    if (ed.shown !== null) {
      var run = ed.runAround(anchor)
      pos = Math.max(run.a, Math.min(run.b, pos))
    }
    ed.setCursor(pos, true)
    ed.selAnchor = anchor
    // The cursor cannot stand in a line's hidden mark, so it is put where
    // the words start; the selection still starts at the line's start, so
    // what is copied or cut is the whole line, its mark too.
    // Nor past a bold word's closing markers (Emph.forbidden): the cursor
    // stands before them, the selection still takes them, so an emphasis
    // selected to its end is selected whole. Never a bound line's date.
    var landed = ed.cursorPosition
    var lr = Rows.rowAt(ed.rows, landed)
    ed.selCursor = Rows.rowAt(ed.rows, pos) === lr && (pos < landed || pos <= ed.rows[lr].bodyEnd) ? pos : landed
    var item = ed.rowItem(ed.focusedRow)
    if (item) item.field.deselect()
  }

  // Where a selection's moving end goes for a navigation key.
  function stepPos(pos, k, ctrl) {
    ed.aimNext = -1
    if (ctrl && k === Qt.Key_Home) return ed.shown !== null ? ed.runAround(pos).a : 0
    if (ctrl && k === Qt.Key_End) return ed.shown !== null ? ed.runAround(pos).b : ed.text.length
    var i = Rows.rowAt(ed.rows, pos)
    var r = ed.rows[i]
    var col = Rows.columnIn(r, pos)
    var n = ed.rows.length
    // With Ctrl, a word at a time; at a line's edge, into the next line.
    if (k === Qt.Key_Left) return col > 0 ? ed.absOf(i, ed.restCol(i, ctrl ? Rows.wordStep(r.body, col, -1) : col - 1, -1))
      : (i > 0 && ed.isShown(i - 1) ? ed.absOf(i - 1, ed.rows[i - 1].body.length) : pos)
    if (k === Qt.Key_Right) return col < r.body.length ? ed.absOf(i, ed.restCol(i, ctrl ? Rows.wordStep(r.body, col, 1) : col + 1, 1))
      : (i + 1 < n && ed.isShown(i + 1) ? ed.absOf(i + 1, 0) : pos)
    if (k === Qt.Key_Home) return ed.absOf(i, 0)
    if (k === Qt.Key_End) return ed.absOf(i, r.body.length)
    var dir = k === Qt.Key_Up ? -1 : 1
    var item = ed.rowItem(i)
    var f = item.field
    var c = f.positionToRectangle(col)
    // The column the run of Up and Down began at (`goal`).
    var x = ed.aimX(item, pos)
    ed.aimNext = x
    // A wrapped line first moves within itself.
    if (dir > 0 && c.y < f.positionToRectangle(f.length).y - 1) return ed.absOf(i, ed.restCol(i, f.positionAt(x - f.x, c.y + c.height * 1.5), 0))
    if (dir < 0 && c.y > f.positionToRectangle(0).y + 1) return ed.absOf(i, ed.restCol(i, f.positionAt(x - f.x, c.y - c.height * 0.5), 0))
    var j = ed.nextRow(i, dir)
    if (j < 0) { ed.aimNext = -1; return dir < 0 ? ed.absOf(i, 0) : ed.absOf(i, r.body.length) }
    var t = ed.rowItem(j).field
    return ed.absOf(j, ed.restCol(j, t.positionAt(x - t.x, dir > 0 ? 1 : t.contentHeight - 1), 0))
  }
  // The x stepPos aimed at for Up or Down (-1: none), for the caller to
  // keep as the goal once the selection has moved.
  property real aimNext: -1

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
    ed.insert(pos, ed.pasteShape(pos, t))
    ed.placeCursor(true)
  }

  // What a paste puts at `pos`. Inside a quote or a callout, every line of
  // it after the first carries the quote's marks, unless it has a quote of
  // its own (2026-11-27). Pasted bare, a second line ended the quote there
  // — and in a private block, every line below it became a quote of its
  // own: private no more, and the agent's to read (Blocks.js). Enter and
  // Backspace had been kept from splitting a private block; a paste was not.
  function pasteShape(pos, t) {
    if (t.indexOf("\n") < 0) return t
    var r = ed.rows[Rows.rowAt(ed.rows, pos)]
    var lead = !r ? "" : r.kind === "quote" ? r.indent + r.marker : r.kind === "calloutHead" ? r.indent + "> " : (r.quoteLead || "")
    if (lead === "") return t
    return t.split("\n").map(function (line, k) { return k === 0 || /^[ \t]*>/.test(line) ? line : lead + line }).join("\n")
  }

  function removeSpan() {
    if (ed.readOnly) return
    var a = ed.selStart, b = ed.selEnd
    var lines = ed.text.slice(a, b).indexOf("\n") >= 0
    ed.snapshot(true)
    ed.clearSelection()
    ed.replace(a, b, "")
    if (lines) ed.renumberAt(a)
    ed.placeCursor(true)
  }

  // Ctrl+L over lines (2026-11-27: it ticked only the line the cursor was
  // on, and let go of the rest). Lines that are not boxes yet become boxes,
  // and the boxes are left alone; when they are all boxes, the open ones
  // are ticked, and when every one is ticked, they all open again. One
  // step to undo, and the selection stays on them.
  function toggleLines(a, b) {
    if (ed.readOnly) return
    var i = Rows.rowAt(ed.rows, a), j = Rows.rowAt(ed.rows, b)
    if (j > i && b === ed.rows[j].start) j--
    var make = [], boxes = []
    for (var k = i; k <= j; k++) {
      var r = ed.rows[k]
      if (!ed.isShown(k) || r.blank) continue
      if (r.kind === "task") boxes.push(k)
      else if (r.kind === "bullet" || r.kind === "plain" || r.kind === "quote") make.push(k)
    }
    var edits = []
    var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
    var ticked = -1
    if (make.length > 0) {
      for (var m = 0; m < make.length; m++) {
        var p = ed.rows[make[m]]
        var at = p.kind === "plain" ? p.start + p.indent.length : p.start + p.prefixLen
        edits.push({ a: at, b: at, s: p.kind === "bullet" ? "[ ] " : "- [ ] " })
      }
    } else if (boxes.length > 0) {
      var open = boxes.some(function (x) { return !ed.rows[x].checked })
      for (var x = 0; x < boxes.length; x++) {
        var q = ed.rows[boxes[x]]
        if (open === q.checked) continue
        var next = open ? Task.setField(Task.setState(q.raw, "x"), "✅", today)
          : Task.setField(Task.setField(Task.setState(q.raw, " "), "✅", ""), "❌", "")
        edits.push({ a: q.start, b: q.start + q.raw.length, s: next })
        if (ticked < 0) ticked = boxes[x]
      }
    }
    if (edits.length === 0) return
    var from = ed.selAnchor, to = ed.selCursor
    ed.snapshot(true)
    var na = ed.through(edits, from, from <= to ? -1 : 1), nb = ed.through(edits, to, to < from ? -1 : 1)
    ed.clearSelection()
    ed.commit(ed.editsApplied(edits), nb)
    ed.selectSpan(na, nb)
    if (ticked >= 0) ed.boxTicked(ticked, open)
  }

  // A line's own indentation starts after its quote layers (Rows.js):
  // Tab and Shift+Tab nest inside the quote, never move the quote itself.
  function innerAt(r) { return r.start + (r.quoteLead || "").length }
  function innerIndent(r) { return r.indent.substring((r.quoteLead || "").length) }

  // Tab / Shift+Tab on a selection: every line in it nests or un-nests,
  // and the selection stays on those lines.
  function indentSpan(out) {
    var i = Rows.rowAt(ed.rows, ed.selStart)
    var j = Rows.rowAt(ed.rows, ed.selEnd)
    if (ed.readOnly) return
    ed.snapshot(true)
    ed.clearSelection()
    var edits = []
    for (var k = j; k >= i; k--) {
      var r = ed.rows[k]
      if (r.blank) continue
      var at = ed.innerAt(r), own = ed.innerIndent(r)
      if (!out) edits.push({ a: at, b: at, s: "\t" })
      else if (own.charAt(0) === "\t") edits.push({ a: at, b: at + 1, s: "" })
      else if (own !== "") edits.push({ a: at, b: at + Math.min(2, own.length), s: "" })
    }
    ed.applyEdits(edits)
    var moved = []
    for (var m = i; m <= j; m++) if (!ed.rows[m].blank) moved.push(m)
    ed.relist(moved)
    ed.selectSpan(ed.absOf(i, 0), ed.absOf(j, ed.rows[j].body.length))
  }

  // Lines moved to another level: their list's markers follow (Rows.relist).
  // `kept`: the lines stayed where they are, only the numbers count on.
  function relist(lines, kept) {
    var ch = Rows.relist(ed.rows, lines, kept)
    ed.applyEdits(ch.map(function (c) {
      var r = ed.rows[c.line]
      return { a: r.start + r.indent.length, b: r.start + r.prefixLen, s: c.marker }
    }))
  }

  // Ctrl+Shift+Up / Down (2026-11-11): from the cursor, select to the
  // start / end of its block — the same blocks the agent answers, a list
  // item each. With a selection, its top edge goes up to the block above
  // (Down: its bottom edge to the block below), so a block taken with
  // Ctrl+A grows a block at a time either way, whatever end the cursor
  // was at. Until then a selection's moving end went, and Ctrl+Shift+Up
  // after Ctrl+A shrank it to its last block. Shift+arrows still move the
  // cursor's end a line at a time, to take some back.
  function selectToBlockEdge(dir, item) {
    var a = ed.cursorPosition, b = a
    if (ed.spanning) { a = ed.selStart; b = ed.selEnd }
    else if (item && item.field.selectedText !== "") {
      var anc = ed.nativeAnchor(item)
      a = Math.min(anc, ed.cursorPosition); b = Math.max(anc, ed.cursorPosition)
    }
    var blocks = Blocks.split(ed.text)
    var to = -1
    for (var k = 0; k < blocks.length; k++) {
      var first = ed.rows[blocks[k].start]
      var last = ed.rows[blocks[k].end - 1]
      if (!first || !last) continue
      if (ed.shown !== null && !ed.isShown(blocks[k].start) && !ed.isShown(blocks[k].end - 1)) continue
      var startAt = first.start, endAt = last.start + last.raw.length
      if (dir < 0 && ed.shownFrom(startAt) < ed.shownFrom(a)) to = startAt          // the nearest start above
      if (dir > 0 && to < 0 && ed.shownTo(endAt) > ed.shownTo(b)) to = endAt        // the nearest end below
    }
    if (to < 0) return
    // Within one line the selection is its words, as the line's own step
    // is; across lines it takes them whole, their marks too.
    var keep = dir < 0 ? b : a
    var tr = ed.rows[Rows.rowAt(ed.rows, to)]
    if (Rows.rowAt(ed.rows, to) === Rows.rowAt(ed.rows, keep)) to = dir < 0 ? tr.start + tr.prefixLen : tr.bodyEnd
    var from = ed.spanning ? ed.ladderFrom : -1
    ed.selectSpan(keep, to)
    ed.ladderFrom = from
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
      var aim = ed.aimNext
      if (to === anchor) { ed.clearSelection(); ed.setCursor(to, true) }
      else ed.selectSpan(anchor, to)
      if (aim >= 0) ed.aimed(aim)
      return true
    }
    if (nav && !alt && !ctrl) {
      var back = k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Home
      var at = back ? ed.selStart : ed.selEnd
      ed.clearSelection()
      ed.setCursor(at, true)
      return true
    }
    // Ctrl alone with them: Ctrl+Shift+C is the path's, Ctrl+Alt the
    // AltGr of a Windows keyboard (2026-11-25).
    var only = ctrl && !alt && !shift
    if (only && k === Qt.Key_C) { ed.copyText(ed.text.slice(ed.selStart, ed.selEnd)); return true }
    if (only && k === Qt.Key_X) {
      ed.copyText(ed.text.slice(ed.selStart, ed.selEnd))
      ed.cutting = true
      ed.removeSpan()
      ed.cutting = false
      return true
    }
    if (only && k === Qt.Key_A) { ed.selectAllStep(ed.rowItem(ed.focusedRow)); return true }
    if (Sc.hit(event, "checkbox")) { ed.toggleLines(ed.selStart, ed.selEnd); return true }
    // An agent's file read: what would write keeps the selection, and
    // writes nothing (2026-11-27: a letter typed let go of it).
    var writes = k === Qt.Key_Backspace || k === Qt.Key_Delete || k === Qt.Key_Return || k === Qt.Key_Enter
      || k === Qt.Key_Tab || k === Qt.Key_Backtab || (only && k === Qt.Key_V)
      || (event.text !== "" && (!ctrl && !alt || ctrl && alt) && event.text.charCodeAt(0) >= 32)
    if (ed.readOnly && writes) return true
    if (only && k === Qt.Key_V) {
      var pasted = ed.pasteText().replace(/\r/g, "")
      if (pasted !== "" && !ed.readOnly) {
        var pa = ed.selStart, pb = ed.selEnd
        ed.snapshot(true)
        ed.clearSelection()
        ed.replace(pa, pb, ed.pasteShape(pa, pasted))
        ed.placeCursor(true)
      }
      return true
    }
    if (k === Qt.Key_Backspace || k === Qt.Key_Delete) { ed.removeSpan(); return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !ctrl && !alt) {
      ed.removeSpan()
      var r = ed.rowItem(ed.focusedRow)
      if (r) ed.returnKey(r, shift, true)
      return true
    }
    if (k === Qt.Key_Tab && !ctrl && !alt) { ed.indentSpan(false); return true }
    if (k === Qt.Key_Backtab) { ed.indentSpan(true); return true }
    // AltGr on Windows arrives as Ctrl+Alt with its letter (2026-11-25).
    if (event.text !== "" && (!ctrl && !alt || ctrl && alt) && event.text.charCodeAt(0) >= 32) {
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
    i = ed.nearestShown(i, -1)
    // The sliver at the top of a private block is the paper's edge, not a
    // line: a click there lands at the start of the block's words.
    if (ed.rows[i] && Rows.sunkHead(ed.rows[i]) && i + 1 < n && ed.isShown(i + 1)) return { i: i + 1, col: 0, box: false }
    var item = ed.rowItem(i)
    var r = ed.rows[i]
    if (!item || !r) return { i: 0, col: 0, box: false }
    if (item.foldTop > 0 && y < item.y + item.foldTop) return { i: i, col: 0, box: false, fold: true }
    if (item.foldBottom > 0 && y >= item.y + item.height - item.foldBottom) return { i: i, col: r.body.length, box: false, fold: true }
    if (y >= item.y + item.height) return { i: i, col: r.body.length, box: false }
    if (r.blank) return { i: i, col: 0, box: false }
    var b = item.box
    var pad = Math.round(ed.textSize * 0.25)
    var ly = y - item.y
    var box = r.kind === "task" && !ed.readOnly && x >= b.x - pad && x <= b.x + b.width + pad && ly >= b.y - pad && ly <= b.y + b.height + pad
    // A deadline's date pill takes its own click (its reschedule).
    var pl = item.pill
    var pill = (r.deadline > 0 || r.doDay !== "") && pl.visible && !ed.readOnly && x >= pl.x - pad && x <= pl.x + pl.width + pad && ly >= pl.y - pad && ly <= pl.y + pl.height + pad
    var f = item.field
    var col = item.tableDrawn ? item.tableCol(x, ly) : f.positionAt(x - f.x, ly - f.y)
    return { i: i, col: ed.restCol(i, col, 0), box: box, pill: pill }
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
    if (!a || !b || !ed.isShown(startLine) || !ed.isShown(endLine - 1)) return null
    var y = a.y + a.gapTop - a.padTop
    return { y: y, h: b.y + b.height - b.room - b.foldBottom - y }
  }

  // ------------------------------------------------------------ editing

  // A field changed under the student's fingers.
  function typed(i, body, col) {
    if (ed.readOnly) return
    var r = ed.rows[i]
    if (!r) return
    ed.clearSelection()
    ed.escapeAt = -1          // typed where it stepped to: the letter holds the place now
    body = body.replace(/\r/g, "")
    // A list marker typed into an empty item, or at the start of its words,
    // takes the item's place: "2. " then "- " is a bullet, not "2. - ".
    // A bound checkbox keeps its box: its deadline never goes by typing.
    var lead = /^([-*+]|\d+[.)]) /.exec(body)
    var swap = (r.kind === "bullet" || r.kind === "ordered" || r.kind === "task") && lead !== null
      && col === lead[0].length && (body === lead[0] || r.suffix === "")
    var line = (swap ? r.indent : r.raw.substring(0, r.prefixLen)) + body + r.suffix
    ed.snapshot(/\n/.test(body), ed.runOf(r, body))
    var lineEnd = r.start + r.raw.length
    var before = ed.rows.length
    ed.commit(ed.text.slice(0, r.start) + line + ed.text.slice(lineEnd), r.start + (swap ? r.indent.length : r.prefixLen) + col)
    if (swap) ed.relist([i], true)
    // The line changed kind (markdown typed or broken) or a paste brought
    // new lines: the field's text moved, so put the cursor back.
    var now = ed.rows[i]
    // A date kept as words stays words while the line is written on: a #tag
    // after it, or a space, made it a new line to the page's `declined`, and
    // the date lit up again and became a deadline as the line was left
    // (2026-11-27). Only a different date lights up anew.
    // (A line in between with no date at all, `fri #` on the way to
    // `fri #thesis`, carries it on.)
    var cueText = function (x) { return x.body.substring(x.cueAt, x.cueEnd >= 0 ? x.cueEnd : x.body.length).trim() }
    var kept = ed.keptCue && ed.keptCue.raw === r.raw ? ed.keptCue.phrase
      : ed.declined[r.raw] && r.cueAt >= 0 && !r.cueBad ? cueText(r) : ""
    ed.keptCue = null
    if (kept !== "" && now && now.raw !== r.raw && (now.cueAt < 0 || now.cueBad || cueText(now) === kept)) {
      if (!ed.declined[now.raw]) ed.declineCarried(r.raw, now.raw)
      ed.keptCue = { raw: now.raw, phrase: kept }
    }
    ed.typedRaw = now ? now.raw : ""
    // (A date meant but not read is none: Backspace there is a Backspace.)
    ed.freshCue = (r.cueAt < 0 || r.cueBad) && now && now.cueAt >= 0 && !now.cueBad ? i : -1
    if (ed.rows.length !== before || !now || now.body !== body) ed.placeCursor(true)
    else ed.updateCursorRect()
  }

  // What a keystroke did to row r's words (`body` as they are now), as
  // snapshot's `run`: the one span that differs, in text offsets.
  function runOf(r, body) {
    var old = r.body
    var p = 0
    while (p < old.length && p < body.length && old.charAt(p) === body.charAt(p)) p++
    var q = 0
    while (q < old.length - p && q < body.length - p
           && old.charAt(old.length - 1 - q) === body.charAt(body.length - 1 - q)) q++
    var gone = old.length - p - q, added = body.length - p - q
    var at = r.start + r.prefixLen + p
    if (gone === 0) return { kind: "ins", a: at, b: at, to: at + added, space: /^\s/.test(body.charAt(p)) }
    if (added === 0) return { kind: "del", a: at, b: at + gone, to: at }
    return { kind: "ins", a: at, b: at + gone, to: at + added, fresh: true }   // typed over a selection
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

  // What is selected, as text offsets ({ a, b }), however it was made: a
  // selection across lines is the editor's, one inside a line is its
  // field's own. null when nothing is.
  function selected() {
    if (ed.spanning) return { a: ed.selStart, b: ed.selEnd }
    var item = ed.rowItem(ed.focusedRow)
    return item && item.field.selectedText !== "" ? ed.selectionRange(item) : null
  }

  function returnKey(item, soft, noSnap) {
    // An agent's file read: Enter writes nothing, and says no line was
    // finished (2026-11-27: it pushed undo steps and told the page so).
    if (ed.readOnly) return
    var i = item.index
    if (!noSnap) ed.snapshot(true)
    if (item.field.selectedText !== "") {
      var sel = ed.selectionRange(item)
      ed.remove(sel.a, sel.b)
    }
    var r = ed.rows[i]
    var pos = ed.cursorPosition
    var lineText = r.raw
    var lineEnd = r.start + r.raw.length
    // At the end of a bound line's words, the new line starts after its
    // date, so the line keeps its deadline — and the cursor goes with it,
    // or it would stay behind on this line.
    if (r.suffix !== "" && pos >= r.bodyEnd) { pos = lineEnd; ed.cursorPosition = pos }
    // A fence inside a quote carries the quote; elsewhere code carries nothing.
    var carry = r.kind === "code" ? (r.quoteLead || "") : r.kind === "front" ? "" : Rows.continuation(r)
    if (soft) {
      // A new line in the same block: under a list item, indented to stay
      // part of it; in a quote, still quoted.
      var under = (r.kind === "task" || r.kind === "bullet" || r.kind === "ordered") ? r.indent + "  "
        : (r.kind === "quote" ? carry : r.indent)
      ed.insert(pos, "\n" + under)
      return
    }
    // Enter before a line's first word makes room above it, and the line
    // stays whole (2026-11-11). Split there, the hidden mark stayed behind
    // on an empty line and the words went down without it: a heading left
    // `## ` and became plain words, a ticked box came back unticked, a
    // callout's title became its body. What goes above is the line's own
    // kind emptied — an open box, a bullet, the next number, a quote's
    // marker — as Notion and Docs do for lists; for a heading, a callout
    // or plain words, an empty line, inside the quote it is in.
    if (r.body !== "" && pos === r.start + r.prefixLen && r.kind !== "code" && r.kind !== "front") {
      var above = r.kind === "task" ? r.indent + r.marker.replace(/\[[^\]]\]/, "[ ]")
        : (r.kind === "bullet" || r.kind === "ordered" || r.kind === "quote") ? r.indent + r.marker
        : (r.quoteLead || "")
      ed.insert(r.start, above + "\n")
      if (r.kind === "ordered") ed.relist([i + 1], true)
      ed.setCursor(ed.rows[i + 1].start + ed.rows[i + 1].prefixLen, true)
      return
    }
    // An empty line inside a quote, with more of the quote below it, is a
    // line of it like any other: Enter adds another (2026-11-13). Leaving
    // there split the quote, and a private block's lower half became a
    // quote of its own, private no more.
    var quoteGoesOn = r.kind === "quote" && i + 1 < ed.rows.length && /^[ \t]*>/.test(ed.rows[i + 1].raw)
    if (carry !== "" && r.body === ""&& r.suffix === "" && pos >= lineEnd && r.kind !== "calloutHead" && r.kind !== "code" && !quoteGoesOn) {
      // Enter on an empty item steps out one level, as Shift+Tab does
      // (and Notion); at the outermost level it leaves the list (or the
      // quote). 2026-10-19.
      if (r.kind !== "quote" && ed.innerIndent(r) !== "") {
        ed.outdent(i)
        ed.relist([i])
        ed.placeCursor(true)
        return
      }
      // An empty item inside a quote leaves the list, not the quote: what
      // is left is the quote's own line.
      if (r.kind !== "quote" && (r.quoteLead || "") !== "") {
        ed.remove(r.start + r.indent.length, r.start + r.prefixLen)
        ed.placeCursor(true)
        return
      }
      if (r.kind === "quote") { ed.leaveQuote(i); return }
      ed.remove(r.start, lineEnd)
      ed.listLeft(i)
      return
    }
    ed.insert(pos, "\n" + carry)
    // A new number in the middle of a list: the items below count on.
    if (r.kind === "ordered") ed.relist([i + 1], true)
    ed.returnFinished(i, lineText)
  }

  // Enter on a quote's empty last line leaves the quote for a line of its
  // own below it, a blank line between (2026-11-13). The cursor used to
  // stay where it was, on a line now outside: the private paper drew back
  // from under it and it blinked on the paper's edge. And a line written
  // straight under a quote is, in markdown, still the quote's (Obsidian
  // drew it inside the private block); the blank line keeps it apart. A
  // blank line or two already there is used, not added to.
  function leaveQuote(i) {
    var r = ed.rows[i]
    var n = ed.rows.length, k = 0, j = i + 1
    while (j < n && k < 2 && ed.rows[j].blank) { k++; j++ }
    var need = j >= n ? Math.max(0, 1 - k) : 2 - k
    ed.replace(r.start, r.start + r.raw.length, new Array(need + 1).join("\n"))
    ed.setCursor(r.start + 1, true)
  }

  // Backspace at the start of a line: first the kind goes, then the
  // indentation a level at a time, then the line joins the one above.
  // A bound line that stops being a checkbox stops being a deadline: its
  // date goes with the box (and the page asks about the deadline). Joining
  // onto a bound line slips the words in before that line's date.
  function backspaceAtStart(i) {
    if (ed.readOnly) return
    var r = ed.rows[i]
    // In a private block a line's `> ` is the block's, not the line's
    // (2026-11-13): taking it off split the block there, and every line
    // below became a quote of its own, private no more. The line joins the
    // one above instead. On the block's first line it is the block's
    // mark that goes — the whole block out of private, as Ctrl+P does it,
    // said by the page, and one undo puts it back.
    if (r.priv && r.kind === "quote" && r.quoteDepth === 1 && i > 0 && ed.rows[i - 1].priv) {
      var above = ed.rows[i - 1]
      if (Rows.sunkHead(above)) { ed.privateUnwrap(); return }
      ed.snapshot(true)
      var words = r.raw.substring(r.prefixLen)
      if (above.suffix !== "") {
        var at0 = above.bodyEnd
        ed.replace(above.start, r.start + r.raw.length, above.raw.slice(0, above.raw.length - above.suffix.length) + words + above.suffix)
        ed.setCursor(at0, true)
      } else {
        var at1 = above.start + above.raw.length
        ed.remove(at1, r.start + r.prefixLen)
        ed.setCursor(at1, true)
      }
      return
    }
    ed.snapshot(true)
    if (r.marker !== "") {
      if (r.suffix !== "") ed.remove(r.bodyEnd, r.start + r.raw.length)
      // A quote's markers go one layer at a time: `> > x` becomes `> x`.
      var from = r.kind === "quote" ? r.marker.lastIndexOf(">") : 0
      ed.remove(r.start + r.indent.length + Math.max(0, from), r.start + r.prefixLen)
    } else if (r.indent !== "") {
      ed.outdent(i)
    } else if (i > 0 && ed.isShown(i - 1)) {
      var p = ed.rows[i - 1]
      if (p.suffix !== "") {
        var at = p.bodyEnd
        ed.replace(p.start, r.start + r.raw.length, p.raw.slice(0, p.raw.length - p.suffix.length) + r.raw + p.suffix)
        ed.setCursor(at, true)
      } else {
        ed.remove(r.start - 1, r.start)
      }
      ed.renumberAt(ed.cursorPosition)
    }
    ed.placeCursor(true)
  }

  // Delete at the end of a line pulls the next line's words up, without
  // its markdown.
  function deleteAtEnd(i) {
    if (ed.readOnly) return
    if (i + 1 >= ed.rows.length || !ed.isShown(i + 1)) return
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
    ed.renumberAt(ed.cursorPosition)
    ed.placeCursor(true)
  }

  // One level of indentation off line i: a tab, or two spaces.
  function outdent(i) {
    var r = ed.rows[i]
    var at = ed.innerAt(r), own = ed.innerIndent(r)
    if (own.charAt(0) === "\t") ed.remove(at, at + 1)
    else if (own !== "") ed.remove(at, at + Math.min(2, own.length))
  }

  function indent(i, out) {
    if (ed.readOnly) return
    var r = ed.rows[i]
    var listy = r.kind === "task" || r.kind === "bullet" || r.kind === "ordered"
    var was = ed.text
    ed.snapshot(true)
    if (out) {
      ed.outdent(i)
    } else if (listy || ed.innerIndent(r) !== "") {
      ed.insert(ed.innerAt(r), "\t")
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
    } else if (r.kind === "quote") {
      ed.insert(r.start + r.prefixLen, "- [ ] ")
    }
    ed.placeCursor(false)
  }

  function clickCheckbox(i) {
    ed.placeAt(i, ed.rows[i].body.length)
    ed.toggleCheckbox(i)
    ed.boxClicked()
  }

  function atFirstLine(f) { return f.cursorRectangle.y <= f.positionToRectangle(0).y + 1 }
  function atLastLine(f) { return f.cursorRectangle.y >= f.positionToRectangle(f.length).y - 1 }

  // PgUp / PgDn (2026-11-25, the keyboard pass): a screen up or down, the
  // view and the cursor together, as every editor has them; with Shift,
  // selecting. The note is a column of one-line fields, so no field could
  // do it, and the keys did nothing. Past the first or last line: the
  // note's start or end, as Ctrl+Home and Ctrl+End.
  function pageStep(dir, select, item) {
    var view = ed.viewport
    var h = Math.max(ed.textSize * 3, (view ? view.height : ed.height) - ed.textSize * 2)
    var f = item.field
    var c = f.cursorRectangle
    var at = f.mapToItem(ed, c.x, c.y + c.height / 2)
    var x = ed.aimX(item, ed.spanning ? ed.selCursor : ed.cursorPosition)
    var y = at.y + dir * h
    column.forceLayout()
    var pos
    if (y < 0) pos = ed.shown !== null ? ed.runAround(ed.cursorPosition).a : 0
    else if (y >= column.height) pos = ed.shown !== null ? ed.runAround(ed.cursorPosition).b : ed.text.length
    else {
      var spot = ed.hitTest(x, y)
      pos = ed.absOf(spot.i, spot.col)
    }
    if (view) view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + dir * h))
    if (select) {
      var anchor = ed.spanning ? ed.selAnchor : ed.nativeAnchor(item)
      if (pos === anchor) { ed.clearSelection(); ed.setCursor(pos, true) }
      else ed.selectSpan(anchor, pos)
    } else {
      if (ed.spanning) ed.clearSelection()
      ed.setCursor(pos, true)
    }
    ed.aimed(x)
  }

  // The x Up and Down aim at from the cursor at `pos` (`goal`), else the
  // cursor's own, in editor x.
  function aimX(item, pos) {
    var g = ed.goal
    if (g && (g.pos === pos || g.sel === pos)) return g.x
    var f = item.field
    var c = f.positionToRectangle(Rows.columnIn(ed.rows[item.index], pos))
    return f.x + c.x
  }
  function aimed(x) { ed.goal = { x: x, pos: ed.cursorPosition, sel: ed.selCursor } }

  // Up / Down: the line above or below — within a wrapped line first, then
  // the neighbouring line — at the column the run of them began at.
  function moveVertical(item, dir) {
    var f = item.field
    var x = ed.aimX(item, ed.cursorPosition)
    var c = f.cursorRectangle
    if (dir < 0 ? !ed.atFirstLine(f) : !ed.atLastLine(f)) {
      ed.placeAt(item.index, f.positionAt(x - f.x, dir < 0 ? c.y - c.height * 0.5 : c.y + c.height * 1.5))
      ed.aimed(x)
      return
    }
    var j = ed.nextRow(item.index, dir)
    if (j < 0) {
      ed.placeAt(item.index, dir < 0 ? 0 : ed.rows[item.index].body.length)
      ed.goal = null
      return
    }
    var t = ed.rowItem(j).field
    ed.placeAt(j, t.positionAt(x - t.x, dir > 0 ? 1 : t.contentHeight - 1))
    ed.aimed(x)
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
  //
  // Words with Ctrl (Ctrl+arrows, Ctrl+Backspace, Ctrl+Delete) come here on
  // every line, emphasis or not (2026-11-27): a plain line left them to the
  // field, whose idea of a word is Qt's, so bolding one word in a line
  // moved where Ctrl+Left stopped on it. One rule now, Rows.wordStep.
  function emphKey(event, item) {
    var i = item.index
    var runs = ed.hiddenIn(i)
    var arrows = ed.arrowsIn(i)
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    var wordKey = ctrl && (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Backspace || k === Qt.Key_Delete)
    if (runs.length === 0 && arrows.length === 0 && !wordKey) return false
    if (alt) return false
    var f = item.field
    var r = ed.rows[i]
    var len = r.body.length
    var col = f.cursorPosition
    var sel = f.selectedText !== ""

    // Home / End on a line with markers: the line's (or the wrapped line's)
    // edge, at its place: a bold last word's End is inside the bold.
    if ((k === Qt.Key_Home || k === Qt.Key_End) && !ctrl && !shift && runs.length > 0) {
      var c = f.cursorRectangle
      var edgeCol = f.positionAt(k === Qt.Key_End ? f.width + 1000 : -1000, c.y + c.height / 2)
      f.cursorPosition = ed.restCol(i, edgeCol, 0)
      return true
    }

    if ((k === Qt.Key_Left || k === Qt.Key_Right) && !(sel && !shift)) {
      var dir = k === Qt.Key_Right ? 1 : -1
      var to = ctrl ? Rows.wordStep(r.body, col, dir) : col + dir
      if (to < 0 || to > len || (to === col && !shift)) return false          // the next line's business
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
        var st = Emph.trimRuns(r.body, Math.min(f.selectionStart, f.selectionEnd), Math.max(f.selectionStart, f.selectionEnd))
        a = st.a
        b = st.b
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
      // An arrow goes whole, as the one character it looks like.
      for (x = 0; x < arrows.length; x++) {
        var w = arrows[x]
        if (a > w.at && a < w.end) a = w.at
        if (b > w.at && b < w.end) b = w.end
      }
      if (ed.readOnly) return false
      var span = Emph.collapse(r.body, a, b)
      var base = r.start + r.prefixLen
      ed.snapshot(sel || ctrl, { kind: "del", a: base + span.a, b: base + span.b, to: base + span.a })
      ed.replace(base + span.a, base + span.b, "")
      ed.placeCursor(true)
      return true
    }
    return false
  }

  function key(event, item) {
    if (ed.firstKey && ed.firstKey(event)) { event.accepted = true; return }
    var f = item.field
    var i = item.index
    var fresh = ed.freshCue
    ed.freshCue = -1
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    var noSel = f.selectedText === ""
    ed.mouseLed = false
    if ((event.text === "" || ctrl || alt) && k !== Qt.Key_Shift && k !== Qt.Key_Control && k !== Qt.Key_Alt && k !== Qt.Key_Meta
        && !Sc.hit(event, "bold") && !Sc.hit(event, "italic") && !Sc.hit(event, "code") && !Sc.hit(event, "strike")) ed.escapeAt = -1

    if (k === Qt.Key_Escape && !ctrl && !alt && (ed.spanning || !noSel)) { ed.letGo(item); event.accepted = true; return }
    if (ed.keyFilter && ed.keyFilter(event)) { event.accepted = true; return }
    // Words dragged over in an agent's answer beside the note leave the
    // keys here (2026-11-25, the mouse pass): Ctrl+C copies them unless the
    // note has words of its own selected, and Ctrl+R answers them.
    if (ed.chatKey && ed.chatKey(event, ed.spanning || !noSel)) { event.accepted = true; return }
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
    if ((k === Qt.Key_PageUp || k === Qt.Key_PageDown) && !ctrl && !alt) {
      ed.pageStep(k === Qt.Key_PageUp ? -1 : 1, !!shift, item)
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
        var aim = ed.aimNext
        if (to !== anchor) ed.selectSpan(anchor, to)
        if (aim >= 0) ed.aimed(aim)
        event.accepted = true
        return
      }
    }
    if (ctrl && !alt && !shift && k === Qt.Key_A) { ed.selectAllStep(item); event.accepted = true; return }
    // Copy, cut and paste are the note's, not the field's: rich rows hold
    // 1px hidden spans and drawn arrows (`→>`) that must stay plain markdown
    // on the clipboard, and cutting inside emphasis collapses orphan markers.
    if (ctrl && !shift && !alt && (k === Qt.Key_C || k === Qt.Key_X)) {
      if (!noSel) {
        var rRow = ed.rows[i]
        var ca = Math.min(f.selectionStart, f.selectionEnd)
        var cb = Math.max(f.selectionStart, f.selectionEnd)
        // Markers whose partner is outside the selection are left out: a
        // drag from before a bold word into it is the word.
        var ct = Emph.trimRuns(rRow.body, ca, cb)
        ca = ct.a; cb = ct.b
        ed.copyText(rRow.body.slice(ca, cb))
        if (k === Qt.Key_X && !ed.readOnly) {
          var cSpan = Emph.collapse(rRow.body, ca, cb)
          var cBase = rRow.start + rRow.prefixLen
          ed.snapshot(true)
          ed.cutting = true
          ed.replace(cBase + cSpan.a, cBase + cSpan.b, "")
          ed.cutting = false
          ed.placeCursor(true)
        }
      }
      event.accepted = true
      return
    }
    if (ctrl && !shift && !alt && k === Qt.Key_V) {
      var pasted = ed.pasteText().replace(/\r/g, "")
      if (pasted !== "" && !ed.readOnly) {
        var from = noSel ? ed.cursorPosition : ed.absOf(i, Math.min(f.selectionStart, f.selectionEnd))
        var to = noSel ? from : ed.absOf(i, Math.max(f.selectionStart, f.selectionEnd))
        ed.snapshot(true)
        ed.replace(from, to, ed.pasteShape(from, pasted))
        ed.placeCursor(true)
      }
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
    } else if (k === Qt.Key_Delete && noSel && f.cursorPosition === f.length) {
      // Ctrl+Del too, as Ctrl+Backspace at a line's start joins it to the
      // one before (2026-11-25: it did nothing).
      ed.deleteAtEnd(i)
    } else if ((k === Qt.Key_Up || k === Qt.Key_Down) && !ctrl && !alt && !shift) {
      if (!noSel) f.deselect()
      ed.moveVertical(item, k === Qt.Key_Up ? -1 : 1)
    } else if (k === Qt.Key_Left && !alt && !shift && noSel && f.cursorPosition === 0) {
      var p = ed.nextRow(i, -1)
      if (p >= 0) ed.placeAt(p, ed.rows[p].body.length)
    } else if (k === Qt.Key_Right && !alt && !shift && noSel && f.cursorPosition === f.length) {
      var n = ed.nextRow(i, 1)
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
      ed.setCursor(ed.shown !== null ? ed.runAround(ed.cursorPosition).a : 0, true)
    } else if (Sc.hit(event, "noteEnd")) {
      ed.setCursor(ed.shown !== null ? ed.runAround(ed.cursorPosition).b : ed.text.length, true)
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
        required property string doDay
        required property string raw
        required property int cueAt
        required property bool cueBad
        required property int cueEnd
        required property string cueLabel
        required property int tableRow
        required property int tableStart
        required property int tableLen
        required property int quoteDepth
        required property int outerLevel
        required property bool paperEnd
        required property bool paperAbove
        required property bool paperBelow
        required property bool extraBlank

        property alias field: field
        property alias box: box
        property alias pill: due
        readonly property string author: ed.authors[row.index] || ""
        readonly property bool listy: kind === "task" || kind === "bullet" || kind === "ordered"
        // A private callout is not drawn as a quote (B · Paper, 2026-10-27):
        // no bar, no label, its words aligned with the prose; the page sinks
        // it into a darker paper and puts a lock in the gutter.
        readonly property bool quoted: (kind === "quote" || kind === "calloutHead") && !priv
        // Quote layers (Rows.js reads a line in layers, 2026-10-27): a bar
        // for each, at the line's outer indentation; a checkbox, bullet or
        // heading inside them is drawn after the bars as it is anywhere.
        readonly property int bars: priv ? 0 : quoteDepth
        readonly property real quoteSpace: bars * ed.quoteWidth
        readonly property bool quoteRow: kind === "quote" || kind === "calloutHead"
        // Its `> [!private]` line, empty and not being written on, is only
        // the top of the sunk paper.
        readonly property bool sunkHead: kind === "calloutHead" && priv && body.trim() === "" && !field.activeFocus
        // A date being written at the end of this checkbox: lit up, its
        // pill pending (accent) until the line is left and it is bound.
        readonly property bool pending: ed.cues && !priv && kind === "task" && cueAt >= 0 && ed.typedRaw !== "" && raw === ed.typedRaw && !ed.declined[raw]
        // Bound with Tab, its number on its way: the same pill, its date.
        readonly property bool binding: kind === "task" && deadline <= 0 && dueAt > 0 && !!ed.bindingAt[Math.floor(dueAt / 60000)]
        // Folded away (Focus.js): no room at all. A drawn line with folded
        // lines before it carries their mark above its words; the last
        // drawn line, the mark for those after it.
        readonly property bool folded: !ed.isShown(index)
        readonly property int foldTop: !folded && (ed.foldAbove[index] || 0) > 0 ? ed.foldSize : 0
        readonly property int foldBottom: !folded && (ed.foldBelow[index] || 0) > 0 ? ed.foldSize : 0
        visible: !folded
        // The sunk paper's margin is inside its first and last lines
        // (2026-11-13): the page draws the paper over exactly these rows,
        // so it never reaches over a neighbour — the cursor on the line
        // after a private block used to blink half on the paper. Its top is
        // the `> [!private]` line, a sliver when empty and the margin over
        // its words when written on; its bottom, room under the last line.
        // A blank line touching the paper keeps that much clear when the
        // cursor opens it.
        readonly property int paperPad: Math.round(ed.textSize * 0.4)
        readonly property int padTop: kind === "calloutHead" && priv && !sunkHead ? paperPad : 0
        readonly property int padBottom: paperEnd || (blank && opened && paperBelow) ? paperPad : 0
        readonly property int baseGap: blank ? (opened && paperAbove ? paperPad : 0) : Math.round(space * ed.textSize) + padTop
        readonly property int gapTop: foldTop + baseGap
        readonly property real indentX: outerLevel * ed.markerWidth + (quoteRow ? 0 : quoteSpace) + (level - outerLevel) * ed.markerWidth
        readonly property real labelWidth: kind === "calloutHead" && !priv ? label.implicitWidth + Math.round(ed.textSize * 0.4) : 0
        readonly property real fieldX: indentX + (listy ? ed.markerWidth : (quoteRow ? quoteSpace : 0)) + labelWidth
        readonly property real firstLine: fm.height

        width: column.width
        readonly property real room: index === ed.roomRow ? ed.roomHeight : 0
        // A blank line opens to a line's height when the cursor is on it —
        // but not under a selection or a press: a drag passing over it
        // would move every line below by that much and back (2026-10-19).
        readonly property bool opened: !blank || field.activeFocus && !ed.spanning && !pointer.pressed
        height: folded ? 0 : foldTop + foldBottom + room + padBottom
                 + (sunkHead ? baseGap + paperPad : (tableDrawn ? (tableRow === 1 ? Math.round(ed.textSize * 0.5) : baseGap + cellRow.height + Math.round(ed.textSize * 0.5))
                 : img ? baseGap + (reveal ? field.height + imgGap : 0) + picture.height
                 : opened || extraBlank ? baseGap + field.height : Math.round(space * ed.textSize)))
        Binding { when: row.index === ed.roomRow; target: ed; property: "roomTop"; value: row.y + row.height - row.room - row.foldBottom }

        // The folds' marks: how many written lines of the day are folded
        // there. A click (the pointer's, see hitTest) opens the whole day.
        Repeater {
          model: [{ at: "top", n: row.foldTop > 0 ? ed.foldAbove[row.index] : 0 },
                  { at: "bottom", n: row.foldBottom > 0 ? ed.foldBelow[row.index] : 0 }]
          Item {
            required property var modelData
            visible: modelData.n > 0
            width: row.width
            height: ed.foldSize
            y: modelData.at === "top" ? 0 : row.height - ed.foldSize
            readonly property bool hot: ed.foldHot === row.index + modelData.at
            readonly property color ink: hot ? ed.accent : ed.faint
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: foldWords.x - Math.round(ed.textSize * 0.6); height: 1; color: parent.ink; opacity: 0.6 }
            Text {
              id: foldWords
              anchors.verticalCenter: parent.verticalCenter
              x: Math.round(ed.textSize * 1.5)
              textFormat: Text.PlainText
              text: modelData.n === 1 ? "1 line of the day" : modelData.n + " lines of the day"
              color: parent.ink
              font.family: ed.fontFamily
              font.styleName: ed.fontStyle
              font.pixelSize: Math.round(ed.textSize * 0.75)
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              x: foldWords.x + foldWords.width + Math.round(ed.textSize * 0.6)
              width: Math.max(0, parent.width - x); height: 1; color: parent.ink; opacity: 0.6
            }
          }
        }

        // What the field holds, read and written as the body: with emphasis
        // in it the field is rich text (Emph.js), and then its `text` is
        // html — `plain` is the body, character for character, and the only
        // thing the editor ever looks at.
        readonly property bool prose: kind !== "code" && kind !== "front" && kind !== "image"
        readonly property bool rich: prose && Emph.has(body)          // drawn with its emphasis
        readonly property bool richText: rich || (prose && ed.leading > 0)   // drawn as rich text, for either
        // Qt's rich-text line-height is a share of the font's own line, so
        // the leading in ems is asked for in this row's face and size.
        readonly property int leadPct: ed.leading > 0 && fm.height > 0
          ? Math.round(100 * (kind === "heading" ? ed.headingLeading : ed.leading) * field.font.pixelSize / fm.height) : 0
        onLeadPctChanged: row.show()
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
        // How far this table is scrolled sideways, and how far it can be.
        readonly property real tableShiftNow: tableClip.shift
        readonly property real tableReach: tableClip.reach

        // A point on the drawn table (row coordinates) as a column of the
        // line's words: the cell it is in, the letter under it (2026-11-27).
        // It was read off the hidden line as written, whose letters stand
        // elsewhere, so a click opened the table with the cursor in another
        // cell, and a link in a cell could not be followed.
        function tableCol(x, y) {
          if (!row.tinfo || row.tableRow === 1) return 0
          var spans = Rows.cellSpans(row.raw)
          var lead = ed.rows[row.index] ? ed.rows[row.index].prefixLen : 0
          var cx = x - tableClip.x + tableClip.shift, left = 0
          var n = row.tinfo.widths.length
          for (var c = 0; c < n; c++) {
            var w = row.tinfo.widths[c]
            if (c === n - 1 || cx < left + w + ed.cellGap / 2) {
              var sp = spans[c]
              if (!sp) return row.body.length
              var cell = cellRep.itemAt(c)
              var k = cell ? cell.positionAt(cx - cell.x, y - cellRow.y) : 0
              return Math.max(0, Math.min(row.body.length, sp.a + Math.max(0, Math.min(sp.b - sp.a, k)) - lead))
            }
            left += w + ed.cellGap
          }
          return 0
        }
        // Where column `col` of the words is drawn in the table, in row
        // coordinates (null: not in a cell).
        function cellRect(col) {
          var spans = Rows.cellSpans(row.raw)
          var p = col + (ed.rows[row.index] ? ed.rows[row.index].prefixLen : 0)
          for (var c = 0; c < spans.length; c++) {
            if (p < spans[c].a || p > spans[c].b) continue
            var cell = cellRep.itemAt(c)
            if (!cell) return null
            var r = cell.positionToRectangle(p - spans[c].a)
            return Qt.rect(tableClip.x + cellRow.x + cell.x + r.x, cellRow.y + cell.y + r.y, r.width, r.height)
          }
          return null
        }
        property bool rendering: false

        // A drawn arrow is its glyph over its first character (Emph.js):
        // read back, it is the characters that were typed.
        readonly property bool arrowed: rich && Emph.arrowsIn(body).length > 0
        function plain() {
          if (field.textFormat !== TextEdit.RichText) return field.text
          var t = field.getText(0, field.length).replace(/[\u2028\u2029]/g, "\n")
          return row.arrowed ? Emph.unarrow(t) : t
        }

        function show() {
          var want = row.rich ? Emph.html(row.body, ed.codeFamily, row.links.length ? row.linkStyle() : null)
            : row.richText ? Emph.html(row.body, ed.codeFamily, null) : row.body
          if (row.richText && row.leadPct > 0) want = "<p style=\"line-height:" + row.leadPct + "%;margin:0\">" + want + "</p>"
          if (field.shown === want && row.plain() === row.body) return
          var col = field.cursorPosition
          row.rendering = true
          field.textFormat = row.richText ? TextEdit.RichText : TextEdit.PlainText
          field.shown = want
          field.text = want
          if (field.cursorPosition !== col) field.cursorPosition = Math.max(0, Math.min(col, field.length))
          row.rendering = false
        }

        onBodyChanged: row.show()
        Component.onCompleted: row.show()

        FontMetrics { id: fm; font: field.font }

        // The drawn table, clipped to the column: a table too wide for it
        // moves sideways under the clip, every row by the same shift.
        Item {
          id: tableClip
          visible: row.tableDrawn && !!row.tinfo
          x: row.fieldX
          width: Math.max(0, row.width - row.fieldX)
          height: row.height
          clip: reach > 0
          readonly property real reach: row.tinfo ? row.tinfo.reach : 0
          readonly property real shift: Math.min(reach, ed.tableShift(row.tableStart))
          // Under the words' field, so its text cursor still shows; the
          // wheel reaches it, since the field takes none. Only sideways
          // (or Shift and the wheel) moves the table; the rest scrolls the
          // note as ever.
          MouseArea {
            anchors.fill: parent
            z: -1
            enabled: tableClip.reach > 0
            acceptedButtons: Qt.NoButton
            onWheel: function (wheel) {
              var dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 2
              var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2
              if (wheel.modifiers & Qt.ShiftModifier) { if (dx === 0) dx = dy; dy = 0 }
              if (dx === 0 || Math.abs(dx) < Math.abs(dy)) { wheel.accepted = false; return }
              ed.setTableShift(row.tableStart, Math.max(0, Math.min(tableClip.reach, tableClip.shift - dx)))
            }
          }
          Row {
            id: cellRow
            visible: row.tableRow !== 1
            x: -tableClip.shift
            y: row.gapTop + Math.round(ed.textSize * 0.25)
            spacing: ed.cellGap
            Repeater {
              id: cellRep
              model: cellRow.visible && row.tinfo ? row.tinfo.widths.length : 0
              // A field that is never typed in, for its positions: where a
              // click lands in the cell, and where a link's hint goes.
              TextEdit {
                required property int index
                width: row.tinfo.widths[index]
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.RichText
                readOnly: true
                activeFocusOnPress: false
                selectByMouse: false
                text: Emph.html(row.tcells[index] || "", ed.codeFamily, { color: String(ed.linkColor), missing: String(ed.faint),
                                  source: String(ed.dim), reveal: -1, known: function (l) { return !ed.linkKnown || ed.linkKnown(l) } })
                horizontalAlignment: row.tinfo.align[index] === "right" ? TextEdit.AlignRight : row.tinfo.align[index] === "center" ? TextEdit.AlignHCenter : TextEdit.AlignLeft
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
            visible: row.tableRow !== 0 && row.tableRow < row.tableLen - 1
            x: -tableClip.shift
            y: row.tableRow === 1 ? Math.round(row.height / 2) : row.height - 1
            width: row.tinfo ? row.tinfo.width : 0
            height: 1
            color: row.tableRow === 1 ? ed.dim : Qt.rgba(ed.faint.r, ed.faint.g, ed.faint.b, 0.35)
          }
          // More to see: the paper fades in at the edge the table goes on past.
          Rectangle {
            visible: tableClip.shift > 0.5
            anchors.left: parent.left
            width: Math.min(ed.cellGap * 2, tableClip.width / 4)
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: ed.background }
              GradientStop { position: 1; color: Qt.rgba(ed.background.r, ed.background.g, ed.background.b, 0) }
            }
          }
          Rectangle {
            visible: tableClip.shift < tableClip.reach - 0.5
            anchors.right: parent.right
            width: Math.min(ed.cellGap * 2, tableClip.width / 4)
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: Qt.rgba(ed.background.r, ed.background.g, ed.background.b, 0) }
              GradientStop { position: 1; color: ed.background }
            }
          }
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

        Repeater {
          model: row.bars
          Rectangle {
            required property int index
            x: row.outerLevel * ed.markerWidth + index * ed.quoteWidth + Math.round(ed.textSize * 0.15)
            width: Math.max(2, Math.round(ed.textSize * 0.12))
            height: row.height
            radius: ed.cornerRadius
            color: ed.quoteColor
          }
        }

        Text {
          id: label
          visible: row.kind === "calloutHead" && !row.priv
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
          objectName: "box"
          readonly property int size: Math.round(ed.textSize * 0.72)
          visible: row.kind === "task"
          x: row.indentX + Math.round((ed.markerWidth - size) / 2) - Math.round(ed.textSize * 0.15)
          y: row.gapTop + Math.round((row.firstLine - size) / 2)
          width: size
          height: size
          radius: Math.max(2, Math.round(ed.cornerRadius / 2))
          // The person's box is this square; the agent's and the shared one
          // draw their own shape inside it, and the square gives way.
          // Under the pointer (the lines' own area says which box that is:
          // `boxHover`) a box's edge turns the accent; its fill never does.
          // A ticked box stays the tick's colour, with the accent edge round
          // it. Before (2026-11-24) the box asked its own area, which hears
          // a click but no longer the hover: a box ticked by a click stayed
          // filled with the accent after the pointer had gone, while one
          // ticked with Ctrl+L was green.
          readonly property bool lit: ed.boxHover === row.index && ed.handOn
          readonly property color edge: box.lit ? ed.accent : ed.boxColor
          readonly property int stroke: Math.max(1, Math.round(ed.textSize * 0.08))
          // Cancelled is closed but not done (2026-11-15): grey, with a
          // dash, so it is never read as ticked.
          readonly property color shut: row.cancelled ? ed.cancelColor : ed.checkColor
          color: row.checked && row.author === "" ? box.shut : "transparent"
          border.width: row.author !== "" || (row.checked && !box.lit) ? 0 : box.stroke
          border.color: box.edge

          // The agent's: a diamond, outlined while open, filled when done.
          Rectangle {
            visible: row.author === "agent"
            anchors.centerIn: parent
            width: Math.round(box.size * 0.74)
            height: width
            rotation: 45
            radius: Math.max(1, Math.round(ed.cornerRadius / 2))
            color: row.checked ? box.shut : "transparent"
            border.width: row.checked && !box.lit ? 0 : box.stroke
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
            strokePx: box.stroke
            color: row.checked ? box.shut : box.edge
          }

          Text {
            objectName: "tick"
            anchors.centerIn: parent
            visible: row.checked
            textFormat: Text.PlainText
            text: row.cancelled ? "–" : "✓"
            color: ed.background
            font.family: ed.fontFamily
            // Smaller in the agent's diamond and the seal, which hold less
            // than the square.
            font.pixelSize: Math.round(box.size * (row.author === "" ? 0.85 : 0.62))
            font.styleName: "Bold"           // the face's own cut; font.bold beside it, Qt emboldens it again
          }

          MouseArea {
            id: boxArea
            anchors.fill: parent
            anchors.margins: -Math.round(ed.textSize * 0.25)
            enabled: box.visible && !ed.readOnly
            cursorShape: Qt.PointingHandCursor
            // The click only: the hover is the lines' area's (`pointer`).
            Component.onDestruction: if (ed.boxHover === row.index) ed.boxHover = -1
            onClicked: ed.clickCheckbox(row.index)
            Loader { anchors.fill: parent; active: !!ed.boxTip && box.lit; sourceComponent: ed.boxTip }
          }
          Loader {
            active: !!ed.boxBadge && row.index === ed.focusedRow
            sourceComponent: ed.boxBadge
            anchors.bottom: parent.top
            anchors.bottomMargin: Math.round(ed.textSize * 0.2)
            anchors.horizontalCenter: parent.horizontalCenter
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
          readonly property bool late: !row.checked && row.dueAt > 0 && row.dueAt < ed.now
          visible: row.dueLabel !== "" || row.pending
          anchors.right: parent.right
          y: row.gapTop + Math.round((row.firstLine - height) / 2)
          width: dueText.implicitWidth + (row.deadline > 0 || row.pending || row.binding ? Math.round(ed.textSize * 0.9) : 0)
          height: dueText.implicitHeight + Math.round(ed.textSize * 0.2)
          radius: ed.cornerRadius
          color: "transparent"
          // A day to work on it (⏳) with no deadline answers the mouse
          // too (2026-11-27): it reads as a date, and a click on it now asks
          // "do on?", as a deadline's asks for its new day.
          readonly property bool clickable: row.deadline > 0 || row.doDay !== ""
          readonly property bool lit: ed.pillHover === row.index && clickable && ed.handOn
          border.width: row.deadline > 0 || row.pending || row.binding ? 1 : 0
          // A date meant but not read: the pill says so, quietly.
          border.color: row.pending && row.cueBad ? ed.faint : row.pending || row.binding || lit ? ed.accent : late ? ed.urgent : ed.faint
          Text {
            id: dueText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: row.pending ? row.cueLabel : row.dueLabel
            color: row.pending && row.cueBad ? ed.dim : row.pending || row.binding || due.lit ? ed.accent : due.late ? ed.urgent : ed.dim
            font.family: ed.fontFamily
            font.styleName: ed.fontStyle
            font.pixelSize: Math.round(ed.textSize * 0.78)
          }
          // A deadline's pill is its reschedule, as Ctrl+D on the line
          // (2026-11-25, the mouse pass).
          MouseArea {
            id: dueArea
            anchors.fill: parent
            anchors.margins: -Math.round(ed.textSize * 0.2)
            enabled: due.clickable && !row.pending && !ed.readOnly
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ed.datePillClicked(row.index)
          }
          Loader { anchors.fill: parent; active: !!ed.pillTip && due.lit; sourceComponent: ed.pillTip }
        }

        // Under the words: search matches (faint, the current one
        // stronger) and a selection across lines. A piece that wraps is
        // drawn as its first line, the whole lines between, and its last.
        Repeater {
          model: ed.paintIn(row.index, ed.marks, ed.currentMark, ed.selAnchor, ed.selCursor, ed.rows)
            .concat(row.pending && !row.cueBad ? [{ a: row.cueAt, b: row.cueEnd >= 0 ? row.cueEnd : row.body.length, kind: "cue" }] : [])
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
                radius: ed.cornerRadius
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
          opacity: row.reveal && !row.tableDrawn && !row.sunkHead ? 1 : 0
          color: row.checked || row.kind === "front" || row.img ? ed.dim
            : row.kind === "heading" ? ed.headingColors[Math.max(0, Math.min(row.headingLevel, ed.headingColors.length) - 1)]
            : row.kind === "code" ? ed.codeColor : ed.foreground
          selectionColor: ed.selectionColor
          selectedTextColor: ed.foreground
          // A table being written shows as written, in the code face
          // (2026-11-27): its pipes read as the table's marks, and its
          // columns as columns where the rows are padded alike.
          font.family: row.kind === "code" || row.kind === "front" || row.kind === "table" ? ed.codeFamily : ed.fontFamily
          font.pixelSize: row.kind === "heading"
            ? Math.round(ed.textSize * (row.headingLevel === 1 ? 1.7 : row.headingLevel === 2 ? 1.4 : row.headingLevel === 3 ? 1.15 : 1))
            : (row.kind === "code" || row.kind === "front" || row.kind === "table" || row.img ? Math.round(ed.textSize * 0.85) : ed.textSize)
          // Headings name their cut, as prose does (2026-11-19): asked for by
          // weight Bold — even beside the named cut — Qt took Adwaita Sans's
          // Bold and emboldened it again, and the title's counters closed up.
          // So the title's weight is left normal and its cut carries it; a
          // face without a cut of that name draws the title at its regular.
          font.styleName: row.kind === "heading" ? (row.headingLevel === 1 ? "Bold" : "SemiBold")
            : row.kind === "code" || row.kind === "front" || row.kind === "table" ? "" : ed.fontStyle
          // Rank, in the three channels that have an order: size, weight and
          // the colour's distance from the prose (ThemeColors `headings`).
          // Only the title is Bold — below it the page is one weight, so H2
          // reads as a section and not as a second title.
          font.weight: row.kind === "heading" && row.headingLevel > 1 ? Font.DemiBold : Font.Normal
          cursorVisible: activeFocus && row.opened
          tabStopDistance: ed.tabStop

          onTextChanged: {
            if (ed.syncing || row.rendering) return
            var p = row.plain()
            if (p !== row.body) ed.typed(row.index, p, cursorPosition)
          }
          // Not while the row is being drawn again (`rendering`): the field's
          // cursor moves as its text is replaced, and read back then it took
          // the note's cursor with it. Alt+click on a link landed wherever
          // the field's cursor had been, not on the letter clicked: the link
          // opens to be edited (revealLink) the moment the cursor enters it,
          // and that redraw wrote the old place back (2026-11-27).
          onCursorPositionChanged: if (activeFocus && !ed.syncing && !row.rendering) ed.fieldCursor(row.index, cursorPosition)
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
    cursorShape: ed.boxHover >= 0 || ed.linkHover || ed.foldHot !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
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
      ed.mouseLed = true
      ed.goal = null
      ed.escapeAt = -1
      var h = ed.hitTest(mouse.x, mouse.y)
      // The right button: the edit menu, on the selection if the click is
      // in it, else on the cursor put where it was clicked.
      if (mouse.button === Qt.RightButton) {
        if (h.fold || h.box || h.pill) return
        var at = ed.absOf(h.i, h.col)
        var sel = ed.selectedSpan()
        if (!sel || at < sel.a || at > sel.b) { ed.clearSelection(); ed.setCursor(at, true) }
        var e = pointer.mapToItem(ed, mouse.x, mouse.y)
        ed.menuAsked(e.x, e.y)
        return
      }
      if (h.fold) { ed.foldHot = ""; ed.focusTag = ""; ed.foldClicked(); return }
      if (h.box || h.pill) { mouse.accepted = false; return }
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
      // Alt and a click: the cursor into the link, to edit it, instead of
      // following it (2026-11-25, the mouse pass); the keys reach it so too.
      var link = mouse.modifiers & Qt.AltModifier ? null : ed.linkAtHit(h)
      if (link) { pointer.linkDown = { i: h.i, link: link }; return }
      ed.clearSelection()
      ed.setCursor(pos, true)
    }
    onPositionChanged: function (mouse) {
      if (!pressed) {
        // Hovering is this area's now (for links), so a box's hand is
        // decided here too: the box's own area no longer hears the hover.
        var hv = ed.hitTest(mouse.x, mouse.y)
        ed.foldHot = hv.fold ? hv.i + (ed.isShown(hv.i) && ed.rowItem(hv.i).foldTop > 0 && mouse.y < ed.rowItem(hv.i).y + ed.rowItem(hv.i).foldTop ? "top" : "bottom") : ""
        var hl = !hv.box && !hv.fold ? ed.linkAtHit(hv) : null
        ed.linkHover = hv.pill || !!hl
        ed.pillHover = hv.pill ? hv.i : -1
        if (!hl) ed.hoverLink = null
        else if (!ed.hoverLink || ed.hoverLink.i !== hv.i || ed.hoverLink.link.at !== hl.at) ed.hoverLink = { i: hv.i, link: hl }
        if (hv.box) ed.boxHover = hv.i
        else if (ed.boxHover >= 0) ed.boxHover = -1
        return
      }
      if (pointer.downAt < 0) return
      if (ed.viewport) pointer.viewAt = pointer.mapToItem(ed.viewport, mouse.x, mouse.y)
      pointer.dragTo(mouse.x, mouse.y)
    }
    // A drag held past the top or the bottom of what shows keeps the
    // selection growing that way, faster the further out (2026-11-25, the
    // mouse pass: it grew only while the pointer moved). Where the pointer
    // is, in what shows (`viewAt`): it stays put while the lines scroll
    // under it, so the selection runs on to the edge's line each tick. Kept
    // in the lines' own coordinates, the scroll the cursor's line brought
    // into view stopped it after one (the second pass, 2026-11-25).
    property point viewAt: Qt.point(0, 0)
    readonly property real dragOut: {
      if (!pointer.pressed || pointer.downAt < 0 || !ed.viewport) return 0
      var y = pointer.viewAt.y
      return y < 0 ? y : y > ed.viewport.height ? y - ed.viewport.height : 0
    }
    Timer {
      interval: 50
      repeat: true
      running: pointer.dragOut !== 0
      onTriggered: {
        var v = ed.viewport
        var lines = 1 + Math.min(4, Math.floor(Math.abs(pointer.dragOut) / ed.textSize))
        var step = (pointer.dragOut < 0 ? -1 : 1) * lines * ed.textSize
        var top = v.originY, bottom = Math.max(top, v.originY + v.contentHeight - v.height)
        v.contentY = Math.max(top, Math.min(bottom, v.contentY + step))
        // The line at the edge the pointer is past, as it now shows.
        var at = v.mapToItem(pointer, pointer.viewAt.x, pointer.dragOut < 0 ? 1 : v.height - 1)
        pointer.dragTo(at.x, Math.max(0, Math.min(column.height - 1, at.y)))
      }
    }
    function dragTo(x, y) {
      var h = ed.hitTest(x, y)
      if (pointer.linkDown) {
        if (Math.abs(x - pointer.pressPt.x) < 6 && Math.abs(y - pointer.pressPt.y) < 6) return
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
    onExited: { ed.linkHover = false; ed.hoverLink = null; ed.pillHover = -1; ed.boxHover = -1; ed.foldHot = "" }
  }

  // Where the link under the mouse is, for its hint to sit on.
  Item {
    id: linkSpot
    readonly property var at: {
      var h = ed.hoverLink
      if (!h || !ed.handOn || pointer.pressed) return null
      var item = ed.rowItem(h.i)
      if (!item || !item.visible) return null
      if (item.tableDrawn) {
        var ca = item.cellRect(h.link.at), cb = item.cellRect(h.link.end)
        if (!ca) return null
        var q = item.mapToItem(ed, ca.x, ca.y)
        return { x: q.x, y: q.y, w: Math.max(1, cb && cb.y === ca.y ? cb.x - ca.x : ca.width), h: ca.height }
      }
      var f = item.field
      var a = f.positionToRectangle(h.link.at), b = f.positionToRectangle(h.link.end)
      var p = f.mapToItem(ed, a.x, a.y)
      return { x: p.x, y: p.y, w: Math.max(1, b.y === a.y ? b.x - a.x : f.width - a.x), h: a.height }
    }
    x: at ? at.x : 0
    y: at ? at.y : 0
    width: at ? at.w : 0
    height: at ? at.h : 0
    Loader {
      anchors.fill: parent
      readonly property var link: ed.hoverLink ? ed.hoverLink.link : null
      active: !!ed.linkTip && !!linkSpot.at
      sourceComponent: ed.linkTip
    }
  }
}
