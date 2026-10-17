// Task.js — one grammar for a checkbox line.
//
// Every surface reads checkbox lines, and until 2026-10-15 each read them
// its own way: four regexes in `longhand-agent`, two more in Bound.js, and
// none of them agreed about a line inside a fence. One grammar, twinned in
// `agent/task.py` and cross-checked line for line by `tests/test_task.py`.
//
// On disk a rich one reads
//
//   - [ ] draft the intro #dtm ⏫ ⏳ 2026-10-18 📅 2026-10-20 17:00 ^d12
//
// and is one of three kinds (decided 2026-10-15, see docs/diary.md):
//
//   note box   thinking, part of the notes. No date, no priority. It is not
//              meant to be closed, so it is not counted as if it were.
//   task       given a do-date (⏳) or a priority. Carried forward; mine to
//              schedule.
//   deadline   given a due date (📅) or bound to the store (`^dN`). Imposed
//              from outside and judged by its date.
//
// The vocabulary is Obsidian Tasks', so a note still reads in Obsidian on
// the other machine and as plain text anywhere: 📅 due, ⏳ scheduled (our
// do-date, called `when` here because that is the verb in the dashboard),
// 🛫 start, ➕ created, ✅ done, ❌ cancelled, 🔁 recurrence, and 🔺⏫🔼🔽⏬
// for priority. Three of those five are offered (⏫ / none / 🔽); all five
// are read, so one arriving from Obsidian is understood and kept. An effort
// estimate has no emoji anything else reads, so it is a Dataview inline
// field: `[est:: 1h]`. `^dN` is an Obsidian block id naming deadline N.
//
// Markers are matched by alternation rather than a character class: half of
// them are surrogate pairs in JS, and a class would split them.
.pragma library

var BOX_RE = /^(\s*)([-*+]) \[([ xX\/\-])\](?: (.*))?$/
var ANCHOR_RE = /\s\^d(\d+)\s*$/
var TAG_RE = /(^|\s)#([\w\/-]+)/g
var FIELD_RE = /\[([a-z]+)::\s*([^\]]*)\]/g
var DATE_RE = /^(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}))?/
var FENCE_RE = /^\s*(```|~~~)/
var HEADING_RE = /^(#{1,6})\s+(\S.*?)\s*$/

// marker → the field it fills. Order is the order they are written in.
var MARKS = [["📅", "due"], ["⏳", "when"], ["🛫", "start"], ["➕", "created"],
             ["✅", "doneAt"], ["❌", "cancelledAt"], ["🔁", "recur"]]
// Obsidian Tasks' five levels on one scale, so sorting is a number and the
// two we do not offer still mean what they meant.
var PRIOS = [["🔺", 3], ["⏫", 2], ["🔼", 1], ["🔽", -1], ["⏬", -2]]

var MARK_RE = new RegExp("(" + MARKS.map(function (m) { return m[0] }).join("|") + "|"
                         + PRIOS.map(function (p) { return p[0] }).join("|") + ")", "g")

function _state(ch) {
  return ch === "x" || ch === "X" ? "x" : ch
}

// A date phrase as the store wants it: "YYYY-MM-DD" or "YYYY-MM-DD HH:MM".
function _date(s) {
  var m = s.match(DATE_RE)
  if (!m) return ""
  return m[1] + (m[2] ? " " + (m[2].length === 4 ? "0" + m[2] : m[2]) : "")
}

// One checkbox line, or null. Nothing here knows about the note around it;
// `scan` is what adds the heading path and the parent.
function parse(line) {
  var m = line.match(BOX_RE)
  if (!m) return null
  var body = (m[4] === undefined ? "" : m[4]).replace(/\s+$/, "")
  var t = {
    lead: m[1] + m[2] + " ", indent: m[1].length, marker: m[2], state: _state(m[3]),
    done: m[3] === "x" || m[3] === "X", started: m[3] === "/", cancelled: m[3] === "-",
    text: body, title: "", tags: [], project: "", due: "", when: "", start: "",
    created: "", doneAt: "", cancelledAt: "", recur: "", priority: 0, est: "",
    anchor: 0, kind: "note"
  }

  var rest = body
  var a = rest.match(ANCHOR_RE)
  if (a) { t.anchor = parseInt(a[1], 10); rest = rest.slice(0, a.index) }

  // Each marker owns the words after it, up to the next marker.
  var found = [], mm
  MARK_RE.lastIndex = 0
  while ((mm = MARK_RE.exec(rest))) found.push({ at: mm.index, mark: mm[1] })
  for (var i = 0; i < found.length; i++) {
    var from = found[i].at + found[i].mark.length
    var to = i + 1 < found.length ? found[i + 1].at : rest.length
    var seg = rest.slice(from, to).trim()
    var mark = found[i].mark
    for (var j = 0; j < PRIOS.length; j++) if (PRIOS[j][0] === mark) t.priority = PRIOS[j][1]
    for (var k = 0; k < MARKS.length; k++) {
      if (MARKS[k][0] !== mark) continue
      t[MARKS[k][1]] = MARKS[k][1] === "recur" ? seg : _date(seg)
    }
  }
  var words = found.length > 0 ? rest.slice(0, found[0].at) : rest

  var tag
  TAG_RE.lastIndex = 0
  while ((tag = TAG_RE.exec(words))) t.tags.push(tag[2])
  if (t.tags.length > 0) t.project = t.tags[0]

  var fld
  FIELD_RE.lastIndex = 0
  while ((fld = FIELD_RE.exec(words))) if (fld[1] === "est") t.est = fld[2].trim()

  t.title = words.replace(FIELD_RE, " ").replace(TAG_RE, "$1").replace(/\s+/g, " ").trim()
  t.kind = t.anchor > 0 || t.due !== "" ? "deadline"
    : t.when !== "" || t.priority !== 0 ? "task" : "note"
  return t
}

// Every checkbox in a note, with what the note says about it: the headings
// above it (its project, and the words that make a bare title mean
// something three days later) and the box it is nested under. Lines inside
// a fence or the frontmatter are text, not tasks — the old regexes counted
// them, which is how a fenced example became a task.
function scan(text) {
  var lines = text.split("\n")
  var out = []
  var heads = []   // { level, title, tag }
  var boxes = []   // { indent, line }
  var fence = ""
  var front = lines.length > 0 && lines[0].replace(/\s+$/, "") === "---" ? 1 : 0
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (front === 1) { if (line.replace(/\s+$/, "") === "---") front = 2; continue }
    var f = line.match(FENCE_RE)
    if (f) { fence = fence === "" ? f[1] : (f[1] === fence ? "" : fence); continue }
    if (fence !== "") continue

    var h = line.match(HEADING_RE)
    if (h) {
      var level = h[1].length
      while (heads.length > 0 && heads[heads.length - 1].level >= level) heads.pop()
      var tags = [], tg
      TAG_RE.lastIndex = 0
      while ((tg = TAG_RE.exec(h[2]))) tags.push(tg[2])
      heads.push({ level: level, title: h[2].replace(TAG_RE, "$1").replace(/\s+/g, " ").trim(),
                   tag: tags.length > 0 ? tags[0] : "" })
      boxes = []
      continue
    }

    var t = parse(line)
    // A box with no words is a leftover of editing, not a task (2026-10-17).
    // A bound one keeps its place: its deadline must not be cancelled
    // because its words were cleared.
    if (!t || (t.title === "" && t.anchor === 0)) continue
    while (boxes.length > 0 && boxes[boxes.length - 1].indent >= t.indent) boxes.pop()
    t.line = i
    t.depth = boxes.length
    t.parent = boxes.length > 0 ? boxes[boxes.length - 1].line : -1
    t.path = heads.map(function (x) { return x.title })
    t.claimed = ""
    for (var p = heads.length - 1; p >= 0; p--) if (heads[p].tag !== "") { t.claimed = heads[p].tag; break }
    if (t.project === "") t.project = t.claimed
    boxes.push({ indent: t.indent, line: i })
    out.push(t)
  }
  for (var k = 0; k < out.length; k++) out[k].details = details(lines, out[k].line, out[k].indent)
  return out
}

// How many lines of detail a box has: the lines under it indented deeper
// than it, up to the first that is not (docs/tasks.md — details stay in the
// note, under the task).
function details(lines, at, indent) {
  var n = 0
  for (var i = at + 1; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    if (line.length - line.replace(/^\s+/, "").length <= indent || HEADING_RE.test(line)) break
    n++
  }
  return n
}

// Where a task sits, for a row too narrow for the note: "Design Theory ›
// Essay 2". Empty when the box is under no heading at all, which is itself
// worth seeing — it is a box with nothing to give it meaning.
function where(t) {
  var parts = (t.path || []).slice()
  return parts.join(" › ")
}

// --- changing a line, surgically ------------------------------------------
//
// The page is the only writer of a note, and it may change a line's facts —
// a tick, a date, a priority — never its words (principle 2, docs/diary.md).
// So an edit here keeps the words exactly as they are and rebuilds only the
// metadata tail, in a canonical order, out of the pieces that were already
// there. A marker this grammar does not know keeps its place and its value
// rather than being dropped, which is what re-rendering a line from what was
// understood would do.

// Where the fields are written when one has to be added. Obsidian Tasks
// reads them in any order; this is the order it writes.
var ORDER = ["prio", "🔁", "➕", "🛫", "⏳", "📅", "❌", "✅"]

// A line pulled apart: the box, the words, the fields in the order they
// appear, and the anchor that must stay last.
function pieces(line) {
  var m = line.match(BOX_RE)
  if (!m) return null
  var head = m[1] + m[2] + " [" + m[3] + "] "
  var body = (m[4] === undefined ? "" : m[4]).replace(/\s+$/, "")
  var tailAnchor = ""
  var a = body.match(ANCHOR_RE)
  if (a) { tailAnchor = " ^d" + a[1]; body = body.slice(0, a.index) }

  var found = [], mm
  MARK_RE.lastIndex = 0
  while ((mm = MARK_RE.exec(body))) found.push({ at: mm.index, mark: mm[1] })
  var fields = []
  for (var i = 0; i < found.length; i++) {
    var to = i + 1 < found.length ? found[i + 1].at : body.length
    fields.push({ mark: found[i].mark, value: body.slice(found[i].at + found[i].mark.length, to).trim() })
  }
  var words = (found.length > 0 ? body.slice(0, found[0].at) : body).replace(/\s+$/, "")
  return { head: head, state: m[3], words: words, fields: fields, anchor: tailAnchor }
}

function render(p) {
  var body = p.words
  for (var i = 0; i < p.fields.length; i++)
    body += " " + p.fields[i].mark + (p.fields[i].value !== "" ? " " + p.fields[i].value : "")
  body += p.anchor
  // The box already ends in a space, so a line of nothing but fields must
  // not start with a second one.
  return p.head + (p.words === "" ? body.replace(/^\s+/, "") : body)
}

function _isPrio(mark) {
  for (var i = 0; i < PRIOS.length; i++) if (PRIOS[i][0] === mark) return true
  return false
}

// Where a mark belongs among the fields already present.
function _slot(fields, mark) {
  var want = ORDER.indexOf(_isPrio(mark) ? "prio" : mark)
  if (want < 0) return fields.length
  for (var i = 0; i < fields.length; i++) {
    var here = ORDER.indexOf(_isPrio(fields[i].mark) ? "prio" : fields[i].mark)
    if (here > want) return i
  }
  return fields.length
}

// `[ ]` → `[x]`, `[-]`, `[/]`. The line is otherwise untouched, which is why
// this is a replace and not a render.
function setState(line, state) {
  return line.replace(/^(\s*[-*+] \[)[ xX\/\-](\])/, "$1" + state + "$2")
}

// One field set, replaced or (with an empty value) taken out.
function setField(line, mark, value) {
  var p = pieces(line)
  if (!p) return line
  var at = -1
  for (var i = 0; i < p.fields.length; i++) if (p.fields[i].mark === mark) at = i
  if (value === "") {
    if (at >= 0) p.fields.splice(at, 1)
  } else if (at >= 0) {
    p.fields[at].value = value
  } else {
    p.fields.splice(_slot(p.fields, mark), 0, { mark: mark, value: value })
  }
  return render(p)
}

// A line with new words and every fact it carried kept: the dashboard's
// rename (Ctrl+E). The words are the person's, typed by them.
function setWords(line, words) {
  var p = pieces(line)
  if (!p) return line
  p.words = String(words).replace(/\s+/g, " ").trim()
  return render(p)
}

// The words of a box's text, without its facts: what a rename starts from.
function wordsOf(text) {
  var p = pieces("- [ ] " + text)
  return p ? p.words : text
}

// Priority is one of the five glyphs or none, so setting it takes the old
// one out wherever it sat. 0 leaves the line with no priority at all.
function setPriority(line, level) {
  var p = pieces(line)
  if (!p) return line
  var kept = []
  for (var i = 0; i < p.fields.length; i++) if (!_isPrio(p.fields[i].mark)) kept.push(p.fields[i])
  p.fields = kept
  if (level !== 0) {
    var glyph = ""
    for (var j = 0; j < PRIOS.length; j++) if (PRIOS[j][1] === level) glyph = PRIOS[j][0]
    if (glyph !== "") p.fields.splice(_slot(p.fields, glyph), 0, { mark: glyph, value: "" })
  }
  return render(p)
}

// Three levels are offered where five are read: none → high → low → none.
// One key walks the scale, and a level that is only read (🔺 🔼 ⏬, from
// Obsidian) walks on from the offered one nearest it.
function nextPriority(level) {
  return level >= 1 ? -1 : level <= -1 ? 0 : 2
}

// The line whose words are these, whatever facts it now carries. The
// dashboard's list is read before the edit it asks for, so a line that has
// since gained a ❌ or a ⏳ must still be found — matching the whole line
// would miss on the way back from a drop.
function sameWords(line, text) {
  var a = pieces(line), b = pieces("- [ ] " + text)
  return !!a && !!b && a.words === b.words
}

function findWords(lines, hint, text) {
  if (hint >= 0 && hint < lines.length && sameWords(lines[hint], text)) return hint
  for (var i = 0; i < lines.length; i++) if (sameWords(lines[i], text)) return i
  return -1
}

// A block as its conversation knows it: every list line reduced to its
// words, without its box, its facts or its anchor. Ticking a box, binding
// its date or setting its priority leaves the block the agent answered;
// only changing the words makes it another (2026-10-17). Lines that are
// not list items are kept as they are.
var ITEM_RE = /^(\s*)(?:[-*+]|\d+[.)])\s+(?:\[[ xX\/\-]\](?=\s|$)\s*)?(.*)$/

function identity(text) {
  return String(text).split("\n").map(function (line) {
    var m = line.match(ITEM_RE)
    if (!m) return line
    var rest = m[2].replace(/\s+$/, "")
    var a = rest.match(ANCHOR_RE)
    if (a) rest = rest.slice(0, a.index)
    MARK_RE.lastIndex = 0
    var mm = MARK_RE.exec(rest)
    if (mm) rest = rest.slice(0, mm.index)
    return m[1] + "- " + rest.replace(/\s+/g, " ").trim()
  }).join("\n")
}
