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
//
// An unbound checkbox whose words end in a date ("… by 30 oct") carries it
// as read (Dates.js): where in the body the date words start (`cueAt`, -1
// when none) and how the date reads (`cueLabel`) — what the page lights up
// while the line is being written, and binds when it is left.
.pragma library
.import "Blocks.js" as Blocks
.import "Bound.js" as Bound
.import "Dates.js" as Dates

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
    suffix: "", deadline: 0, dueLabel: "", dueAt: 0, cueAt: -1, cueLabel: ""
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
    if (t.deadline <= 0) readCue(t)
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
  // The tail owns one space before it; more are the words' own — a space
  // just typed at their end, which the tail would otherwise swallow.
  var lead = t.suffix.match(/^\s*/)[0]
  if (lead.length > 1) {
    t.body += lead.substring(0, lead.length - 1)
    t.suffix = t.suffix.substring(lead.length - 1)
  }
  t.deadline = m[5] ? parseInt(m[5], 10) : 0
  if (m[3]) {
    var d = m[3].split("-")
    var hm = m[4] ? m[4].split(":") : ["23", "59"]
    var at = new Date(+d[0], +d[1] - 1, +d[2], +hm[0], +hm[1])
    t.dueAt = at.getTime()
    t.dueLabel = dayLabel(at, !!m[4])
  }
}

// "Fri 30 Oct", "Mon 8 Feb 2027", "Fri 16 Oct · 17:00".
function dayLabel(at, timed) {
  return DAYS[at.getDay()] + " " + at.getDate() + " " + MONTHS[at.getMonth()]
    + (at.getFullYear() !== new Date().getFullYear() ? " " + at.getFullYear() : "")
    + (timed ? " · " + (at.getHours() < 10 ? "0" : "") + at.getHours() + ":" + (at.getMinutes() < 10 ? "0" : "") + at.getMinutes() : "")
}

// A date at the end of an unbound checkbox's words, as read.
function readCue(t) {
  var c = Bound.cue(t.body)
  var w = c ? Dates.read(c.phrase) : null
  if (!w) return
  var rest = t.body.substring(c.head.length)
  t.cueAt = c.head.length + (rest.length - rest.replace(/^\s+/, "").length)
  var at = new Date(w.ms)
  t.cueLabel = dayLabel(at, !(at.getHours() === 23 && at.getMinutes() === 59))
}

// The whole note as rows. Each row also carries:
//   raw        the line as it is on disk
//   start      offset of the line in the text
//   blank      a whitespace-only line outside fences: drawn as space
//   lead       a blank line before any text: drawn as nothing at all
//   priv       inside a `> [!private]` callout
//   space      the air above the row, in body ems (spaceAbove)
//   bodyEnd    offset where the words end (before a bound line's tail)
function derive(text) {
  var lines = text.split("\n")
  var blocks = Blocks.split(text)
  var front = [], priv = []
  for (var b = 0; b < blocks.length; b++) {
    for (var l = blocks[b].start; l < blocks[b].end; l++) {
      if (blocks[b].kind === "frontmatter") front[l] = true
      if (blocks[b].private && blocks[b].kind === "callout") priv[l] = true
    }
  }

  var out = []
  var pos = 0
  var fence = false
  var seenText = false
  var lastText = null   // the last row with text
  var blankGap = 0      // space already given by blank lines since it
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
    if (r.blank) {
      r.space = r.lead || blankGap > 0 ? 0 : SPACE.paragraph
      blankGap += r.space
    } else {
      r.space = lastText ? spaceAbove(lastText, r, blankGap) : 0
      lastText = r
      blankGap = 0
      seenText = true
    }
    out.push(r)
    pos += raw.length + 1
  }
  return out
}

// The page's vertical rhythm, in body ems. More above a heading than below
// it, so a heading sits with what it heads; list items close; the lines of
// one quote, callout, fence or frontmatter with none between them. Blank
// lines in the markdown are one paragraph's space however many there are,
// and count towards a heading's.
var SPACE = { paragraph: 0.75, line: 0.25, item: 0.25, change: 0.5, belowHeading: 0.35,
              heading: [0, 1.75, 1.4, 1.1, 0.9, 0.9, 0.9] }

function listy(r) { return r.kind === "task" || r.kind === "bullet" || r.kind === "ordered" }

// The space above row `r`, whose previous row with text is `p`, with
// `blank` ems of blank lines between them already.
function spaceAbove(p, r, blank) {
  if (r.kind === "heading") return Math.max(0, SPACE.heading[r.headingLevel] - blank)
  if (blank > 0) return 0
  if (p.kind === "heading") return SPACE.belowHeading
  if (r.kind === "quote" && (p.kind === "quote" || p.kind === "calloutHead")) return 0
  if (r.kind === p.kind && (r.kind === "code" || r.kind === "front")) return 0
  if (listy(r) && listy(p)) return SPACE.item
  if (r.kind === "plain" && p.kind === "plain") return SPACE.line
  return SPACE.change
}

// A list's markers after lines in it moved to another level (Tab,
// Shift+Tab). A moved item takes the kind of the item before it at its new
// level — a number counts on from that one's, a bullet stays a bullet — or,
// first at its level, keeps its kind, a number starting at 1. Numbers in
// the list then count on within each level, from where each run starts.
// Checkboxes are never turned into anything. Returns [{ line, marker }]
// for the lines whose marker should change.
function inList(r) { return listy(r) || (r.kind === "plain" && r.level > 0) }

function relist(rows, moved) {
  if (moved.length === 0) return []
  var lo = Math.min.apply(null, moved), hi = Math.max.apply(null, moved)
  while (lo > 0 && inList(rows[lo - 1])) lo--
  while (hi < rows.length - 1 && inList(rows[hi + 1])) hi++
  var isMoved = {}
  for (var m = 0; m < moved.length; m++) isMoved[moved[m]] = true
  var last = []   // per level, the item before at that level, under the same parent
  var out = []
  for (var i = lo; i <= hi; i++) {
    var r = rows[i]
    if (!listy(r)) continue
    var L = r.level
    last.length = L + 1
    var prev = last[L]
    var kind = r.kind
    if (isMoved[i] && prev && kind !== "task" && prev.kind !== "task" && prev.kind !== kind) kind = prev.kind
    var want
    if (kind === "ordered") {
      var own = r.kind === "ordered" ? r.marker.match(/^(\d+)([.)])(\s*)$/) : null
      var delim = own ? own[2] : (prev && prev.delim) || "."
      var n = prev && prev.kind === "ordered" ? prev.num + 1 : (own && !isMoved[i] ? parseInt(own[1], 10) : 1)
      want = n + delim + (own ? own[3] : " ")
      last[L] = { kind: "ordered", num: n, delim: delim }
    } else if (kind === "bullet") {
      want = r.kind === "bullet" ? r.marker : (prev && prev.marker ? prev.marker : "- ")
      last[L] = { kind: "bullet", marker: want }
    } else {
      want = r.marker
      last[L] = { kind: "task" }
    }
    if (want !== r.marker) out.push({ line: i, marker: want })
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
