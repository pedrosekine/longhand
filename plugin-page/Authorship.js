// Authorship.js — who made a line: the person, the agent, or both together.
//
// docs/agent.md, "Who made it" (2026-10-17). Kept by line, for boxes and
// bullets only — prose is the person's by definition, since the agent never
// writes it — and kept in the layer (authors.json beside the deadline
// store), never as a mark in the note: a line is known by its words, as a
// sent block is. Three states:
//
//   ""          the person's: they wrote it (no record at all)
//   "agent"     the agent wrote it, and its words are untouched
//   "together"  the agent's, and the person changed its words; or the
//               person's, reworded by the agent with the person's accept
//
// Facts do not change who made a line: a tick, a date, a priority leave it
// as it was. Changing the words of the agent's line makes it "together".
// An edit made outside the page (Obsidian) cannot be followed; the line's
// record is then dropped when its note is read, so it falls back to the
// person's — erring towards theirs.
//
// Everything here is pure: the page holds the records and the file.
.pragma library
.import "Task.js" as Task

var LIST_RE = /^\s*[-*+] /

// A box or a bullet: the only lines that carry who made them.
function isListLine(raw) {
  return LIST_RE.test(raw || "")
}

// A line as its authorship knows it: its words, without its box, its
// facts, its anchor or its indentation (Task.identity), so a tick or a
// date leaves it the same line.
function key(raw) {
  return Task.identity(raw || "").replace(/^\s+/, "")
}

// The person changed the words of a line someone else had a hand in.
function edited(author) {
  return author ? "together" : ""
}

// The records of one note, [{ id, author }], laid on its lines: line index
// -> author. A record finds the first unclaimed line with its words; one
// whose words are gone (edited elsewhere) is dropped.
function restore(records, lines) {
  var out = {}
  var used = {}
  for (var r = 0; r < (records || []).length; r++) {
    var rec = records[r]
    if (!rec || !rec.id || !rec.author) continue
    for (var i = 0; i < lines.length; i++) {
      if (used[i] || !isListLine(lines[i]) || key(lines[i]) !== rec.id) continue
      out[i] = rec.author
      used[i] = true
      break
    }
  }
  return out
}

// line index -> author, back to the records kept for the note.
function serialize(map, lines) {
  var out = []
  for (var i = 0; i < lines.length; i++)
    if (map[i] && isListLine(lines[i])) out.push({ id: key(lines[i]), author: map[i] })
  return out
}

// Who made each line after an edit, from who made each line before it.
// Lines that did not change keep their author where they now are; in the
// changed stretch, a line found again with the same words (moved, or only
// its facts changed) keeps its author, and a line whose words changed keeps
// its place in the stretch and, if someone else had a hand in it, becomes
// "together". A line split in two: the first half is the edited line, the
// second is new, and the person's. Two lines joined: the joined line was
// edited.
function carry(oldLines, newLines, map) {
  return carryBy(oldLines, newLines, map, isListLine, edited)
}

// The same, for any kind of line a value rides on (`accept`), and what an
// edit of its words does to the value (`onEdit`): Threads.js keeps a
// conversation on its block's lines this way.
function carryBy(oldLines, newLines, map, accept, onEdit) {
  var out = {}
  var n = oldLines.length, m = newLines.length
  var p = 0
  while (p < n && p < m && oldLines[p] === newLines[p]) p++
  var q = 0
  while (q < n - p && q < m - p && oldLines[n - 1 - q] === newLines[m - 1 - q]) q++
  for (var i = 0; i < p; i++) if (map[i]) out[i] = map[i]
  for (var k = 0; k < q; k++) if (map[n - 1 - k]) out[m - 1 - k] = map[n - 1 - k]

  var oldEnd = n - q, newEnd = m - q
  var taken = {}
  var left = []
  for (var o = p; o < oldEnd; o++) {
    if (!map[o]) continue
    var found = -1
    var id = key(oldLines[o])
    for (var j = p; j < newEnd; j++) {
      if (!taken[j] && accept(newLines[j]) && key(newLines[j]) === id) { found = j; break }
    }
    if (found >= 0) { out[found] = map[o]; taken[found] = true }
    else left.push(o)
  }
  for (var l = 0; l < left.length; l++) {
    var from = left[l]
    if (newEnd <= p) break                       // the stretch was deleted
    var to = Math.min(p + (from - p), newEnd - 1)
    if (taken[to] || !accept(newLines[to])) continue
    out[to] = onEdit(map[from])
    taken[to] = true
  }
  return out
}
