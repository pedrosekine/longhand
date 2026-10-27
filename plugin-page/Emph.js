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
function closerOf(s, m, i) {
  var one = m.length === 1 && m !== "`"
  if (one && (s.charAt(i - 1) === m || s.charAt(i + 1) === m)) return -1
  if (m.charAt(0) === "_" && i > 0 && wordish(s.charAt(i - 1))) return -1
  var j = i + m.length
  if (/\s/.test(s.charAt(j))) return -1
  var c = m.charAt(0)
  for (var k = j + 1; k + m.length <= s.length; k++) {
    if (s.substr(k, m.length) !== m) continue
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
  var lit = ""
  var i = 0
  while (i < s.length) {
    var marker = "", close = -1
    for (var m = 0; m < OPENERS.length; m++) {
      if (s.substr(i, OPENERS[m].length) !== OPENERS[m]) continue
      close = closerOf(s, OPENERS[m], i)
      if (close >= 0) { marker = OPENERS[m]; break }
    }
    if (marker === "") { lit += s.charAt(i); i++; continue }
    if (lit !== "") { out.push({ text: lit }); lit = "" }
    var inner = s.substring(i + marker.length, close)
    out.push({ marker: marker, kind: KIND[marker],
               at: base + i, end: base + close + marker.length,
               inner: [base + i + marker.length, base + close],
               children: marker === "`" ? [{ text: inner }] : parse(inner, base + i + marker.length) })
    i = close + marker.length
  }
  if (lit !== "") out.push({ text: lit })
  return out
}

function anyIn(nodes) {
  for (var i = 0; i < nodes.length; i++) if (nodes[i].marker) return true
  return false
}

// Is there anything here to draw? A body without one of these characters
// never needs parsing, and a row without emphasis stays plain text.
function has(s) {
  return (/[*_`~]/.test(s) && anyIn(parse(s))) || (/\[/.test(s) && linksIn(s).length > 0)
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
    if (!n.marker) { out += esc(n.text); continue }
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
  if (ls.length === 0) return "<span style=\"white-space:pre-wrap\">" + render(parse(s), codeFamily) + "</span>"
  var out = "", pos = 0
  for (var i = 0; i < ls.length; i++) {
    var l = ls[i]
    if (l.at > pos) out += render(parse(s.substring(pos, l.at), pos), codeFamily)
    if (links.reveal === l.at) {
      out += "<span style=\"color:" + links.source + "\">" + esc(s.substring(l.at, l.end)) + "</span>"
    } else {
      var shown = s.substring(l.inner[0], l.inner[1])
      var colour = links.known(l) ? links.color : links.missing
      out += HIDDEN + esc(s.substring(l.at, l.inner[0])) + "</span>"
        + "<span style=\"color:" + colour + (links.known(l) ? ";text-decoration:underline" : "") + "\">" + esc(shown) + "</span>"
        + HIDDEN + esc(s.substring(l.inner[1], l.end)) + "</span>"
    }
    pos = l.end
  }
  if (pos < s.length) out += render(parse(s.substring(pos), pos), codeFamily)
  return "<span style=\"white-space:pre-wrap\">" + out + "</span>"
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

function hidden(s) {
  if (!/[*_`~]/.test(s)) return []
  var raw = runsIn(parse(s, 0), [])
  raw.sort(function (x, y) { return x.a - y.a })
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var last = out.length > 0 ? out[out.length - 1] : null
    if (last && last.open === raw[i].open && last.b === raw[i].a) last.b = raw[i].b
    else out.push({ a: raw[i].a, b: raw[i].b, open: raw[i].open })
  }
  return out
}

// A marker run is one thing to the cursor: it rests at the run's inner
// edge — against the words — and never inside it. The line's own two ends
// are always a place to stand, so a line that begins or ends in emphasis
// can still be written before and after.
function forbidden(runs, col, len) {
  if (col <= 0 || col >= len) return false
  for (var i = 0; i < runs.length; i++) {
    var r = runs[i]
    if (r.open ? (col >= r.a && col < r.b) : (col > r.a && col <= r.b)) return true
  }
  return false
}

// The column to rest at. With `dir` (+1 / -1) the cursor is travelling and
// carries on that way, so a run costs one keypress rather than its length;
// without it (a click, a jump) it lands on the run's inner edge.
function validCol(runs, col, len, dir) {
  col = Math.max(0, Math.min(len, col))
  if (!forbidden(runs, col, len)) return col
  if (!dir) {
    for (var i = 0; i < runs.length; i++) {
      var r = runs[i]
      if (r.open && col >= r.a && col < r.b) return r.b
      if (!r.open && col > r.a && col <= r.b) return r.a
    }
    return col
  }
  var step = dir > 0 ? 1 : -1
  while (col > 0 && col < len && forbidden(runs, col, len)) col += step
  return Math.max(0, Math.min(len, col))
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
  var nodes = parse(s, 0)
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
