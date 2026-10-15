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
function parse(s) {
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
               children: marker === "`" ? [{ text: inner }] : parse(inner) })
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
  return /[*_`~]/.test(s) && anyIn(parse(s))
}

function esc(t) {
  return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

var HIDDEN = "<span style=\"font-size:1px;color:transparent\">"
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
function html(s, codeFamily) {
  return "<span style=\"white-space:pre-wrap\">" + render(parse(s), codeFamily || "monospace") + "</span>"
}
