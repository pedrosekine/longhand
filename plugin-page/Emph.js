// Emphasis, drawn — the inline markdown of a row, read and rendered.
//
// The markdown that says *what kind of line* this is (`# `, `- `, `> `) is
// lifted off the row and drawn instead (Rows.js). Inline markdown cannot be
// lifted the same way: `**` sits between the words, and every offset in this
// editor — the cursor, a selection across lines, a search mark, a bound
// line's tail — counts the characters of the body exactly as they are on
// disk.
//
// So the markers stay in the text and are drawn to nothing instead. A row
// with emphasis is rich text whose *plain* text is the body character for
// character, with each marker in a span one pixel tall and transparent.
// Qt keeps one document position per character either way, so the cursor,
// `positionToRectangle` and everything built on them stay exact.
//
// Break an emphasis — delete one `*` of a pair — and it stops being
// emphasis: the markers come back at full size, which is how you see them
// in order to edit them. Nothing ever hides a marker that is not doing a
// job.
//
// What is read, deliberately narrow: `**bold**`, `*italic*`, `` `code` ``,
// `~~struck~~`, and `__`/`_` for the same two (Obsidian writes both). They
// nest, so `**bold *and* italic**` is both. A marker must hold something,
// and that something may not start or end in a space — which is what keeps
// `2 * 3 * 4` arithmetic. An underscore inside a word is part of the word,
// so `snake_case_name` is never italic.
//
// Arrows are drawn the same way (2026-10-27): `->`, `<-` and `<->` show as
// →, ← and ↔. Their first character is drawn as the arrow and the rest to
// nothing, so the file keeps what was typed and every offset holds. Not in
// code, nor inside a link.
.pragma library
.import "Links.js" as Links

// Longest first within a family, and the ones that bind tightest first:
// a backtick opening at a position wins over anything inside it.
var OPENERS = ["`", "**", "__", "~~", "*", "_"]
var KIND = { "`": "code", "**": "bold", "__": "bold", "~~": "strike", "*": "italic", "_": "italic" }

function wordish(c) { return c !== "" && /[A-Za-z0-9\u00c0-\u024f]/.test(c) }

// Where the marker opened at `i` closes, or -1. The content may not be
// empty nor start or end in a space; a one-character marker is never half
// of a two-character one; `_` only works at the edges of a word.
// The links of the line being drawn (absolute ranges), while `html`
// draws it: emphasis is read over the whole line, but never inside a
// link, so `**bold with a [[link]] inside**` is bold around a link
// (2026-10-27; links used to cut the line first, and the `**` showed).
var LINKS = []
var ARROWS = []
var SRC = ""
var STYLE = null
function linkAt(pos) {
  for (var i = 0; i < LINKS.length; i++) if (pos >= LINKS[i].at && pos < LINKS[i].end) return LINKS[i]
  return null
}

function closerOf(s, m, i, base) {
  base = base || 0
  var one = m.length === 1 && m !== "`"
  if (one && (s.charAt(i - 1) === m || s.charAt(i + 1) === m)) return -1
  if (m.charAt(0) === "_" && i > 0 && wordish(s.charAt(i - 1))) return -1
  var j = i + m.length
  if (/\s/.test(s.charAt(j))) return -1
  var c = m.charAt(0)
  for (var k = j + 1; k + m.length <= s.length; k++) {
    if (s.substr(k, m.length) !== m) continue
    if (LINKS.length && linkAt(base + k)) continue
    // A closer takes the *end* of its run of markers, so in `***word***`
    // the outer `**` takes the last two stars and leaves the first for the
    // `*` inside it — bold and italic, the way the keys write it.
    var run = k
    while (run < s.length && s.charAt(run) === c) run++
    if (run - k > m.length) k = run - m.length
    if (one && (s.charAt(k - 1) === m || s.charAt(k + 1) === m)) continue
    if (/\s/.test(s.charAt(k - 1))) continue
    if (m.charAt(0) === "_" && wordish(s.charAt(k + m.length))) continue
    return k
  }
  return -1
}

// The body as a list of nodes: { text } for words, { marker, kind, children }
// for an emphasis. Code holds its content as written — markdown inside a
// code span is content, not markup.
// `base` is where `s` sits in the row's body, so every node knows its own
// place there: `at`/`end` span the markers too, `inner` is what they hold.
function parse(s, base) {
  base = base || 0
  var out = []
  var lit = "", litAt = base
  var i = 0
  while (i < s.length) {
    var L = LINKS.length ? linkAt(base + i) : null
    if (L) {
      if (lit === "") litAt = base + i
      lit += s.substring(i, Math.min(s.length, L.end - base))
      i = L.end - base
      continue
    }
    var marker = "", close = -1
    for (var m = 0; m < OPENERS.length; m++) {
      if (s.substr(i, OPENERS[m].length) !== OPENERS[m]) continue
      close = closerOf(s, OPENERS[m], i, base)
      if (close >= 0) { marker = OPENERS[m]; break }
    }
    if (marker === "") { if (lit === "") litAt = base + i; lit += s.charAt(i); i++; continue }
    if (lit !== "") { out.push({ text: lit, at: litAt }); lit = "" }
    var inner = s.substring(i + marker.length, close)
    out.push({ marker: marker, kind: KIND[marker],
               at: base + i, end: base + close + marker.length,
               inner: [base + i + marker.length, base + close],
               children: marker === "`" ? [{ text: inner, at: base + i + marker.length }] : parse(inner, base + i + marker.length) })
    i = close + marker.length
  }
  if (lit !== "") out.push({ text: lit, at: litAt })
  return out
}

// ------------------------------------------------------------- arrows

// Longest first, so `<->` is one arrow and not `<` and `->`.
var ARROW_FORMS = [["<->", "\u2194"], ["->", "\u2192"], ["<-", "\u2190"]]

// What a drawn arrow leaves in the field: the glyph, then what is hidden.
// A field's text is read back through these (`unarrow`), so a body that
// already holds one of them as written is never drawn with arrows — the
// reading back would change it.
var DRAWN = ["\u2194->", "\u2192>", "\u2190-"]

// The arrows of a body, as { at, end, glyph }: none in code, none in a link.
function arrowsIn(s) {
  if (!/<-|->/.test(s)) return []
  for (var d = 0; d < DRAWN.length; d++) if (s.indexOf(DRAWN[d]) >= 0) return []
  var code = /`/.test(s) ? parse(s, 0).filter(function (n) { return n.kind === "code" }) : []
  var links = /\[/.test(s) ? linksIn(s) : []
  var out = []
  for (var i = 0; i < s.length; i++) {
    for (var f = 0; f < ARROW_FORMS.length; f++) {
      var form = ARROW_FORMS[f][0]
      if (s.substr(i, form.length) !== form) continue
      var end = i + form.length, inside = false
      for (var c = 0; c < code.length && !inside; c++) inside = i < code[c].end && end > code[c].at
      for (var l = 0; l < links.length && !inside; l++) inside = i < links[l].end && end > links[l].at
      if (!inside) { out.push({ at: i, end: end, glyph: ARROW_FORMS[f][1] }); i = end - 1 }
      break
    }
  }
  return out
}

// A field that drew arrows, read back as the body.
function unarrow(t) {
  return t.replace(/\u2194->/g, "<->").replace(/\u2192>/g, "->").replace(/\u2190-/g, "<-")
}

function anyIn(nodes) {
  for (var i = 0; i < nodes.length; i++) if (nodes[i].marker) return true
  return false
}

// Is there anything here to draw? A body without one of these characters
// never needs parsing, and a row without emphasis stays plain text.
function has(s) {
  return (/[*_`~]/.test(s) && anyIn(parse(s))) || (/\[/.test(s) && linksIn(s).length > 0) || arrowsIn(s).length > 0
}

// Links (docs/files.md, 2026-10-27) are drawn the same way: the brackets
// and the target stay in the text, one pixel and transparent, and what
// shows is the alias, else the target as written, in the link colour —
// faint when the vault has no such note. With the cursor inside one, it is
// drawn as written instead, dim, so it can be edited; nothing else ever
// hides a link's source. A link inside a code span is code.
function linksIn(s) {
  var code = parse(s, 0).filter(function (n) { return n.kind === "code" })
  return Links.inLine(s).filter(function (l) {
    for (var i = 0; i < code.length; i++) if (l.at < code[i].end && l.end > code[i].at) return false
    return true
  })
}

function esc(t) {
  return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// One pixel, transparent, and drawn back over itself: at 1px a character
// still advances about half a pixel, which a long link target made a gap of
// (2026-10-27); -0.48px of letter spacing takes that back to nearly nothing.
var HIDDEN = "<span style=\"font-size:1px;color:transparent;letter-spacing:-0.48px\">"
var TAGS = { bold: ["<b>", "</b>"], italic: ["<i>", "</i>"], strike: ["<s>", "</s>"] }

function render(nodes, codeFamily) {
  var out = ""
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (!n.marker) { out += textWithLinks(n.text, n.at); continue }
    var mark = HIDDEN + esc(n.marker) + "</span>"
    var inner = render(n.children, codeFamily)
    var tags = n.kind === "code"
      ? ["<span style=\"font-family:'" + codeFamily.replace(/['"\\]/g, "") + "'\">", "</span>"]
      : TAGS[n.kind]
    out += mark + tags[0] + inner + tags[1] + mark
  }
  return out
}

// The body as rich text whose plain text is the body itself. `pre-wrap`
// is what keeps it so: without it the renderer would eat runs of spaces
// and the trailing space of a line being written, and every offset after
// them would be off by one.
// `links`: { color, missing, source (colours), known(link) -> bool,
// reveal (the column of a link being edited, else -1) }; without it links
// are left as written.
function html(s, codeFamily, links) {
  codeFamily = codeFamily || "monospace"
  var ls = links ? linksIn(s) : []
  LINKS = ls
  ARROWS = arrowsIn(s)
  SRC = s
  STYLE = links
  var out = render(parse(s, 0), codeFamily)
  LINKS = []
  ARROWS = []
  SRC = ""
  STYLE = null
  return "<span style=\"white-space:pre-wrap\">" + out + "</span>"
}

// A run of words, with the links inside it drawn as links.
function textWithLinks(t, at) {
  if (at === undefined) return esc(t)
  if (!LINKS.length) return words(t, at)
  var out = "", pos = at, end = at + t.length
  for (var i = 0; i < LINKS.length; i++) {
    var l = LINKS[i]
    if (l.at < pos || l.end > end) continue
    out += words(SRC.substring(pos, l.at), pos) + linkHtml(l)
    pos = l.end
  }
  return out + words(SRC.substring(pos, end), pos)
}

// Words, with their arrows drawn: the glyph over the first character, the
// rest of it to nothing.
function words(t, at) {
  if (!ARROWS.length) return esc(t)
  var out = "", pos = 0
  for (var i = 0; i < ARROWS.length; i++) {
    var a = ARROWS[i]
    if (a.at < at + pos || a.end > at + t.length) continue
    out += esc(t.substring(pos, a.at - at)) + a.glyph + HIDDEN + esc(t.substring(a.at - at + 1, a.end - at)) + "</span>"
    pos = a.end - at
  }
  return out + esc(t.substring(pos))
}

function linkHtml(l) {
  var links = STYLE
  if (links.reveal === l.at) return "<span style=\"color:" + links.source + "\">" + esc(SRC.substring(l.at, l.end)) + "</span>"
  var known = links.known(l)
  return HIDDEN + esc(SRC.substring(l.at, l.inner[0])) + "</span>"
    + "<span style=\"color:" + (known ? links.color : links.missing) + (known ? ";text-decoration:underline" : "") + "\">"
    + esc(SRC.substring(l.inner[0], l.inner[1])) + "</span>"
    + HIDDEN + esc(SRC.substring(l.inner[1], l.end)) + "</span>"
}


// ----------------------------------------------------------- the cursor

// Where the markers are drawn to nothing, as [a, b) in the body, each the
// opening or the closing side. Runs that touch and face the same way merge,
// so `***word***` has one at each end rather than two.
function runsIn(nodes, out) {
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (!n.marker) continue
    out.push({ a: n.at, b: n.inner[0], open: true })
    out.push({ a: n.inner[1], b: n.end, open: false })
    runsIn(n.children, out)
  }
  return out
}

function parseWithLinks(s) {
  var ls = /\[/.test(s) ? linksIn(s) : []
  LINKS = ls
  var nodes = parse(s, 0)
  LINKS = []
  return nodes
}

function hidden(s) {
  return merged(/[*_`~]/.test(s) ? runsIn(parseWithLinks(s), []) : [])
}

// Where the cursor may not stand: inside a marker run, and inside an
// arrow — an arrow is one thing to it, and a click on its right half lands
// after it.
function stops(s) {
  var raw = /[*_`~]/.test(s) ? runsIn(parseWithLinks(s), []) : []
  var arrows = arrowsIn(s)
  for (var i = 0; i < arrows.length; i++) raw.push({ a: arrows[i].at, b: arrows[i].end, arrow: true })
  return merged(raw)
}

// Runs that touch and face the same way are one; an arrow is always its own
// (two arrows side by side keep the place between them).
function merged(raw) {
  raw.sort(function (x, y) { return x.a - y.a })
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var last = out.length > 0 ? out[out.length - 1] : null
    if (last && !last.arrow && !raw[i].arrow && last.open === raw[i].open && last.b === raw[i].a) last.b = raw[i].b
    else out.push({ a: raw[i].a, b: raw[i].b, open: raw[i].open, arrow: !!raw[i].arrow })
  }
  return out
}

// Where the cursor may stand, as Google Docs has it (2026-11-27): between
// two drawn characters there is one place, right after the one on the left,
// so what is typed there takes that character's emphasis. Before a bold
// word the place is outside its markers (typing is plain), after it inside
// (typing goes on in bold); the same for italic, struck and code, and for
// emphasis nested. A run of markers is never stood in: the place is its
// start. Until then the cursor rested against the words on both sides, so
// typing before a bold word was bold too, and a line beginning or ending in
// emphasis had two places that looked one — an arrow press that seemed to
// do nothing, and no telling which the next letter would be. Ctrl+B and
// its kin step out of (or into) an emphasis at its edge (NoteEditor,
// `escapeAt`). An arrow (`->`) is one thing: before it or after it.
function forbidden(runs, col, len) {
  for (var i = 0; i < runs.length; i++) {
    var r = runs[i]
    if (r.arrow ? (col > r.a && col < r.b) : (col > r.a && col <= r.b)) return true
  }
  return false
}

// The column to rest at. With `dir` (+1 / -1) the cursor is travelling and
// carries on that way, so markers cost no keypress of their own; without
// it (a click, a jump) it lands on the place the run stands for — a click
// on an arrow's right half after the arrow.
function validCol(runs, col, len, dir) {
  col = Math.max(0, Math.min(len, col))
  if (!forbidden(runs, col, len)) return col
  if (dir) {
    var step = dir > 0 ? 1 : -1
    var c = col
    while (c > 0 && c < len && forbidden(runs, c, len)) c += step
    if (!forbidden(runs, c, len)) return c
    col = c                     // the line's end, inside a run: its place
  }
  for (var i = 0; i < runs.length; i++) {
    var r = runs[i]
    if (r.arrow && col > r.a && col < r.b) return r.b
    if (!r.arrow && col > r.a && col <= r.b) return r.a
  }
  return col
}

// Where Ctrl+B (`kind`, "bold") takes a cursor standing at `col` that is
// not inside a word: out of an emphasis of that kind whose words end here
// (what is typed next is not bold), into one whose words start here, or
// back where it stepped from. -1: none here.
function stepFor(s, col, kind) {
  var nodes = parseWithLinks(s)
  var runs = runsIn(nodes, [])
  // The markers right after the place: they stand for it.
  var b = col
  for (var moved = true; moved;) {
    moved = false
    for (var i = 0; i < runs.length; i++) if (runs[i].a === b && runs[i].b > b) { b = runs[i].b; moved = true }
  }
  var to = -1
  var walk = function (list) {
    for (var k = 0; k < list.length && to < 0; k++) {
      var n = list[k]
      if (!n.marker) continue
      if (n.kind === kind) {
        if (n.end === col) to = n.inner[1]                                   // stepped out: back in
        else if (n.inner[0] === col && n.at < col) to = n.at                 // stepped in: back out
        else if (n.inner[1] >= col && n.inner[1] <= b && n.inner[1] > n.inner[0]) to = n.end   // its end: out
        else if (n.at >= col && n.at < b) to = n.inner[0]                    // its start: in
      }
      if (to < 0) walk(n.children)
    }
  }
  walk(nodes)
  return to
}

// [a, b) without the markers at its edges whose partners are outside it:
// a selection that starts before a bold word's markers and ends inside its
// words is the words.
function trimRuns(s, a, b) {
  var nodes = parseWithLinks(s)
  var inside = function (list) {
    for (var k = 0; k < list.length; k++) {
      var n = list[k]
      if (!n.marker) continue
      if (n.at === a && n.end > b && n.inner[0] <= b) { a = n.inner[0]; return true }
      if (n.end === b && n.at < a && n.inner[1] >= a) { b = n.inner[1]; return true }
      if (inside(n.children)) return true
    }
    return false
  }
  for (var guard = 0; guard < 8 && a < b && inside(nodes); guard++) {}
  return { a: a, b: b }
}

function nodeWithContent(nodes, a, b) {
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (!n.marker) continue
    if (n.inner[0] === a && n.inner[1] === b) return n
    var deeper = nodeWithContent(n.children, a, b)
    if (deeper) return deeper
  }
  return null
}

// The innermost emphasis holding [a, b), or null.
function nodeHolding(nodes, a, b) {
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (!n.marker) continue
    if (a >= n.inner[0] && b <= n.inner[1]) return nodeHolding(n.children, a, b) || n
  }
  return null
}

// The innermost emphasis of `kind` holding [a, b) — its words, or its words
// with its markers exactly — or null (2026-11-27). For the keys that wrap:
// inside a bold phrase Ctrl+B takes the bold off what it is on, where it
// used to write a second pair inside the first, and the markdown broke.
function ofKind(s, a, b, kind) {
  var found = null
  var walk = function (nodes) {
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n.marker) continue
      var inside = a >= n.inner[0] && b <= n.inner[1]
      if (!inside && !(a === n.at && b === n.end)) continue
      if (n.kind === kind) found = n
      if (inside) walk(n.children)
    }
  }
  walk(parseWithLinks(s))
  return found
}

// [a, b) widened over the markers right against it, within [lo, hi): the
// italic round a word goes with the word when the bold round both is
// split, rather than staying behind as a stray `*`.
function widen(s, a, b, lo, hi) {
  var runs = runsIn(parseWithLinks(s), [])
  for (var moved = true; moved;) {
    moved = false
    for (var i = 0; i < runs.length; i++) {
      var r = runs[i]
      if (r.open && r.b === a && r.a >= lo && r.a < a) { a = r.a; moved = true }
      if (!r.open && r.a === b && r.b <= hi && r.b > b) { b = r.b; moved = true }
    }
  }
  return { a: a, b: b }
}

// What a deletion of [a, b) should really take.
//
// Two rules, and both exist so that no keystroke can put a `**` on the
// screen that the student did not type. Inside an emphasis, a deletion that
// would leave a space against a marker takes the space with it: markdown
// does not read `**two **` as emphasis at all, so the markers would come
// back for a space nobody can see. And deleting the last of what an
// emphasis holds takes the emphasis itself — a pair holding nothing is
// markers with no job, and markers with no job are drawn. The second rule
// cascades: emptying the italic inside `***word***` empties the bold too.
function collapse(s, a, b) {
  var nodes = parseWithLinks(s)
  var owner = nodeHolding(nodes, a, b)
  if (owner) {
    while (b === owner.inner[1] && a > owner.inner[0] && /\s/.test(s.charAt(a - 1))) a--
    while (a === owner.inner[0] && b < owner.inner[1] && /\s/.test(s.charAt(b))) b++
  }
  for (var guard = 0; guard < 8; guard++) {
    var n = nodeWithContent(nodes, a, b)
    if (!n) break
    a = n.at
    b = n.end
  }
  return { a: a, b: b }
}
