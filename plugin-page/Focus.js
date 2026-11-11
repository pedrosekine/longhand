// Focus.js — one project's part of a day, the rest folded away
// (2026-11-11). Opened from a project's list, the sheet shows only the
// lines its tag claims; the rest of the day is still there, folded to a
// line that says how much. Nothing about the note changes: it is still the
// one daily file, saved whole. This only says which lines are drawn.
//
// The claiming rule is the runner's (`tagged_sections` in longhand-agent),
// so the list and the sheet agree on what a section is: a heading carrying
// the tag claims every line under it until the next heading of the same or
// a higher level, and a box carrying the tag outside its sections is the
// project's too, with the lines of detail under it.
//
// While the view is open what it shows only grows: a line written in it
// stays shown even when what was typed ends the section (a new `#`
// heading), so nothing typed vanishes under the fingers (`carry`).
.pragma library
.import "Task.js" as Task

var HEADING_RE = /^(#{1,6})\s+(\S.*?)\s*$/
var TAG_RE = /(^|\s)#([\w\/-]+)/g
var FENCE_RE = /^\s*(?:>[ \t]?)*[ \t]*(```|~~~)/

function tagsIn(s) {
  var out = [], m
  TAG_RE.lastIndex = 0
  while ((m = TAG_RE.exec(String(s || ""))) !== null) out.push(m[2].toLowerCase())
  return out
}

// The note's headings outside fences and the frontmatter: { line, level, text }.
function headings(lines) {
  var out = []
  var fence = ""
  var front = lines.length > 0 && lines[0].replace(/\s+$/, "") === "---" ? 1 : 0
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (front === 1) { if (i > 0 && line.replace(/\s+$/, "") === "---") front = 2; continue }
    var f = line.match(FENCE_RE)
    if (f) { fence = fence === "" ? f[1] : (f[1] === fence ? "" : fence); continue }
    if (fence !== "") continue
    var h = line.match(HEADING_RE)
    if (h) out.push({ line: i, level: h[1].length, text: h[2] })
  }
  return out
}

// The last line of a box's details: the lines under it indented deeper,
// blank ones between them included (Task.details' rule).
function detailEnd(lines, at, indent, quoted) {
  var last = at
  for (var i = at + 1; i < lines.length; i++) {
    var m = lines[i].match(Task.QUOTED_RE)
    var depth = (m[2].match(/>/g) || []).length
    var rest = m[3]
    if (rest.trim() === "") { if (depth === (quoted || 0) || depth === 0) continue; break }
    if (depth !== (quoted || 0)) break
    if (m[1].length + rest.length - rest.replace(/^\s+/, "").length <= indent || HEADING_RE.test(rest.replace(/^\s+/, ""))) break
    last = i
  }
  return last
}

// The lines one tag claims, as [start, end) line ranges in order, merged
// where they touch, without the blank lines at their ends.
function claims(text, tag) {
  var want = String(tag || "").replace(/^#/, "").toLowerCase()
  if (want === "") return []
  var lines = String(text).split("\n")
  var heads = headings(lines)
  var ranges = []
  var claimed = -1
  for (var n = 0; n < heads.length; n++) {
    var h = heads[n]
    if (h.line <= claimed || tagsIn(h.text).indexOf(want) < 0) continue
    var end = lines.length
    for (var k = n + 1; k < heads.length; k++) if (heads[k].level <= h.level) { end = heads[k].line; break }
    ranges.push([h.line, end])
    claimed = end - 1
  }
  var boxes = Task.scan(String(text))
  for (var b = 0; b < boxes.length; b++) {
    var t = boxes[b]
    if (t.project.toLowerCase() !== want || t.claimed.toLowerCase() === want) continue
    ranges.push([t.line, detailEnd(lines, t.line, t.indent, t.quoted) + 1])
  }
  ranges.sort(function (x, y) { return x[0] - y[0] })
  var out = []
  for (var r = 0; r < ranges.length; r++) {
    var a = ranges[r][0], e = ranges[r][1]
    while (e > a + 1 && lines[e - 1].trim() === "") e--
    if (out.length > 0 && a <= out[out.length - 1][1]) out[out.length - 1][1] = Math.max(out[out.length - 1][1], e)
    else out.push([a, e])
  }
  return out
}

// One flag a line: true where it is drawn.
function mask(count, ranges) {
  var out = []
  for (var i = 0; i < count; i++) out.push(false)
  for (var r = 0; r < ranges.length; r++)
    for (var j = ranges[r][0]; j < Math.min(count, ranges[r][1]); j++) out[j] = true
  return out
}

function any(m) {
  for (var i = 0; i < (m || []).length; i++) if (m[i]) return true
  return false
}

// After an edit, the old flags carried onto the new lines. The editor
// knows the edit as a run of `oldMid` lines at `a` that became `newMid`
// lines (the rest unchanged before and after it): the new lines are shown
// when any line they replaced was, or — lines only added — when the line
// above or below them is.
function carry(prev, a, oldMid, newMid) {
  var out = prev.slice(0, a)
  var shown = false
  for (var i = a; i < a + oldMid; i++) if (prev[i]) shown = true
  if (oldMid === 0) shown = !!prev[a - 1] || !!prev[a]
  for (var k = 0; k < newMid; k++) out.push(shown)
  return out.concat(prev.slice(a + oldMid))
}

// What is folded around each drawn line, for its fold mark: `above[i]`,
// how many written (not blank) lines are hidden right before line i;
// `below[i]`, on the last drawn line, how many after it. A run of hidden
// blank lines alone is no fold.
function folds(m, lines) {
  var above = [], below = []
  var hidden = 0
  var last = -1
  for (var i = 0; i < m.length; i++) {
    above.push(0)
    below.push(0)
    if (!m[i]) { if (String(lines[i] || "").trim() !== "") hidden++; continue }
    above[i] = hidden
    hidden = 0
    last = i
  }
  if (last >= 0) below[last] = hidden
  return { above: above, below: below }
}

// The tag a line belongs to, for the key that focuses on it: a box's own
// tag, else the outermost tagged heading whose section holds the line.
// "" when none does.
function tagAt(text, line) {
  var lines = String(text).split("\n")
  var box = Task.parse(lines[line] || "")
  if (box && box.project) return box.project.toLowerCase()
  var heads = headings(lines)
  for (var n = 0; n < heads.length && heads[n].line <= line; n++) {
    var tags = tagsIn(heads[n].text)
    for (var t = 0; t < tags.length; t++) {
      var rs = claims(text, tags[t])
      for (var r = 0; r < rs.length; r++) if (line >= rs[r][0] && line < rs[r][1]) return tags[t]
    }
  }
  return ""
}
