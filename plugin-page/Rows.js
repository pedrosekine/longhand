// Rows — the note as the page draws it: one row per line, with the markdown
// that only says *what kind* of line it is lifted off and drawn instead.
//
// `# `, `- `, `- [ ] `, `1. `, `> `, `> [!private] ` and leading indentation
// are the row's prefix; what is left is the row's body, the only part the
// student types into. Joining prefix and body gives back the line exactly,
// so the note on disk is never rewritten — it changes only where the student
// typed. Lines inside frontmatter or a code fence keep their markdown: there
// it is the content.
//
// Blank lines are not rows you type on; the page draws them as the space
// between blocks.
//
// A checkbox line can also carry a tail: `📅 2026-10-16 17:00 ^d6`, the
// date of the deadline it stands for and an Obsidian block id naming that
// deadline (#6). The tail is lifted too and drawn as a date at the line's
// end; the body is only the words before it.
.pragma library
.import "Blocks.js" as Blocks

var HEADING_RE = /^(#{1,6} )(.*)$/
var CALLOUT_RE = /^(>[ \t]?\[!([^\]]+)\][+-]?[ \t]?)(.*)$/
var QUOTE_RE = /^(>[ \t]?)(.*)$/
var TASK_RE = /^([-*+] \[([ xX])\] )(.*)$/
var BULLET_RE = /^([-*+] )(.*)$/
var ORDERED_RE = /^((\d+)([.)]) )(.*)$/
var FENCE_RE = /^[ \t]*(```|~~~)/
// The tail of a bound checkbox: a due date (and time), then the anchor.
var TAIL_RE = /^([\s\S]*?)((?:\s+📅\s*(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}))?)?(?:\s+\^d(\d+))?\s*)$/
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Indentation as nesting depth: a tab is a level, and so is every started
// run of four spaces (two-space and four-space lists both nest by one).
function levelOf(indent) {
  var tabs = 0, spaces = 0
  for (var i = 0; i < indent.length; i++) {
    if (indent.charAt(i) === "\t") tabs++
    else spaces++
  }
  return Math.min(8, tabs + Math.ceil(spaces / 4))
}

function make(kind, indent, marker, body) {
  return {
    kind: kind, indent: indent, marker: marker, body: body,
    prefixLen: indent.length + marker.length, level: levelOf(indent),
    checked: false, ordinal: "", headingLevel: 0, callout: "",
    suffix: "", deadline: 0, dueLabel: "", dueAt: 0
  }
}

// One line, outside frontmatter and fences.
function parseLine(raw) {
  var m = raw.match(/^([ \t]*)([\s\S]*)$/)
  var indent = m[1], rest = m[2]
  var x
  if (indent === "") {
    if ((x = rest.match(HEADING_RE))) {
      var h = make("heading", "", x[1], x[2])
      h.headingLevel = x[1].length - 1
      return h
    }
    if ((x = rest.match(CALLOUT_RE))) {
      var c = make("calloutHead", "", x[1], x[3])
      c.callout = x[2].trim().toLowerCase()
      return c
    }
    if ((x = rest.match(QUOTE_RE))) return make("quote", "", x[1], x[2])
  }
  if ((x = rest.match(TASK_RE))) {
    var t = make("task", indent, x[1], x[3])
    t.checked = x[2] !== " "
    liftTail(t)
    return t
  }
  if ((x = rest.match(BULLET_RE))) return make("bullet", indent, x[1], x[2])
  if ((x = rest.match(ORDERED_RE))) {
    var o = make("ordered", indent, x[1], x[4])
    o.ordinal = x[2] + x[3]
    return o
  }
  return make(rest === "" ? "blank" : "plain", indent, "", rest)
}

// Take a bound checkbox's tail off its body. Only a real tail is lifted: a
// body that merely ends in spaces keeps them (they are being typed).
function liftTail(t) {
  var m = t.body.match(TAIL_RE)
  if (!m || !(m[3] || m[5])) return
  t.body = m[1]
  t.suffix = m[2]
  t.deadline = m[5] ? parseInt(m[5], 10) : 0
  if (m[3]) {
    var d = m[3].split("-")
    var hm = m[4] ? m[4].split(":") : ["23", "59"]
    var at = new Date(+d[0], +d[1] - 1, +d[2], +hm[0], +hm[1])
    t.dueAt = at.getTime()
    t.dueLabel = DAYS[at.getDay()] + " " + at.getDate() + " " + MONTHS[at.getMonth()]
      + (at.getFullYear() !== new Date().getFullYear() ? " " + at.getFullYear() : "")
      + (m[4] ? " · " + m[4] : "")
  }
}

// The whole note as rows. Each row also carries:
//   raw        the line as it is on disk
//   start      offset of the line in the text
//   blank      a whitespace-only line outside fences: drawn as space
//   lead       a blank line before any text: drawn as nothing at all
//   priv       inside a `> [!private]` callout
//   gapAbove   starts a new block right under the previous line (no blank
//              line between), so the page leaves a little air above it
//   bodyEnd    offset where the words end (before a bound line's tail)
function derive(text) {
  var lines = text.split("\n")
  var blocks = Blocks.split(text)
  var front = [], priv = [], blockStart = []
  for (var b = 0; b < blocks.length; b++) {
    blockStart[blocks[b].start] = true
    for (var l = blocks[b].start; l < blocks[b].end; l++) {
      if (blocks[b].kind === "frontmatter") front[l] = true
      if (blocks[b].private && blocks[b].kind === "callout") priv[l] = true
    }
  }

  var out = []
  var pos = 0
  var fence = false
  var seenText = false
  for (var i = 0; i < lines.length; i++) {
    var raw = lines[i]
    var r
    if (front[i]) {
      r = make("front", "", "", raw)
    } else if (fence || FENCE_RE.test(raw)) {
      r = make("code", "", "", raw)
      if (FENCE_RE.test(raw)) fence = !fence
    } else {
      r = parseLine(raw)
    }
    r.raw = raw
    r.start = pos
    r.bodyEnd = pos + r.prefixLen + r.body.length
    r.priv = !!priv[i]
    r.blank = r.kind === "blank"
    r.lead = r.blank && !seenText
    r.gapAbove = !!blockStart[i] && i > 0 && !out[i - 1].blank && !out[i - 1].lead
    if (!r.blank) seenText = true
    out.push(r)
    pos += raw.length + 1
  }
  return out
}

// The row holding text offset `pos` (a line's end belongs to the line).
function rowAt(rows, pos) {
  for (var i = rows.length - 1; i >= 0; i--) if (rows[i].start <= pos) return i
  return 0
}

// Where in a row's body an offset lands; an offset inside the lifted prefix
// lands at the start of the body.
function columnIn(row, pos) {
  return Math.max(0, Math.min(row.body.length, pos - row.start - row.prefixLen))
}

// The next row a cursor moving `dir` (+1 / -1) lands on: blank lines are
// space, not places, so they are skipped — unless nothing but blank lines
// lies below, which is where a new block is being started.
function nextTextRow(rows, i, dir) {
  var j = i + dir
  while (j >= 0 && j < rows.length && rows[j].blank) j += dir
  if (j >= 0 && j < rows.length) return j
  if (dir > 0 && i + 1 < rows.length) return i + 1
  return -1
}

// What Enter carries to the next line: the list marker (a ticked box comes
// back unticked, a number counts up) or the quote marker. Empty when the
// line is not a list item or a quote.
function continuation(row) {
  if (row.kind === "task") return row.indent + row.marker.replace(/\[[xX]\]/, "[ ]")
  if (row.kind === "bullet") return row.indent + row.marker
  if (row.kind === "ordered") {
    var m = row.marker.match(/^(\d+)([.)])(\s*)$/)
    return row.indent + (parseInt(m[1], 10) + 1) + m[2] + m[3]
  }
  if (row.kind === "quote" || row.kind === "calloutHead") return "> "
  return ""
}

// Ctrl+Left / Ctrl+Right inside a line's words: where the next word starts
// (dir +1, past the end of this one) or where this or the previous word
// starts (dir -1). A word is anything that is not space or punctuation, so
// "ação", "Übung" and "año" are one word each.
var SEP_RE = /[\s.,;:!?()\[\]{}"'`<>\/\\|@#*_~=+–—-]/

function wordStep(text, col, dir) {
  var i = col
  if (dir > 0) {
    while (i < text.length && !SEP_RE.test(text.charAt(i))) i++
    while (i < text.length && SEP_RE.test(text.charAt(i))) i++
  } else {
    while (i > 0 && SEP_RE.test(text.charAt(i - 1))) i--
    while (i > 0 && !SEP_RE.test(text.charAt(i - 1))) i--
  }
  return i
}
