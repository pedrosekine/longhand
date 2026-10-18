// Threads.js — a sent block keeps its conversation when its words change
// (docs/plan.md, "A sent block keeps its conversation through word edits",
// 2026-10-18).
//
// A block's conversation is filed under the hash of its text when it was
// asked, and found again by its words (Task.identity), so a tick, a date or
// a priority keep it — but rewording the block used to cut it loose. Now
// the conversation also rides on the block's lines, in the layer
// (threads.json beside the deadline store, never a mark in the note):
// pinned to the block's first line once it has a reply, carried through
// every edit in the page as authorship is (Authorship.carryBy), and kept by
// the line's words when the note is saved. A block whose words changed is
// still the block the conversation is about as long as one of its lines
// carries it. An edit made outside the page (Obsidian) cannot be followed:
// the pin is dropped when its words are no longer found, as a line's
// authorship is.
//
// line index -> record hash (the block hash the conversation is filed under)
.pragma library
.import "Authorship.js" as Authorship

function any(line) {
  return String(line || "").trim() !== ""
}

function key(raw) {
  return Authorship.key(raw)
}

// The note's pins, [{ id, rec }], laid on its lines.
function restore(records, lines) {
  var out = {}
  var used = {}
  for (var r = 0; r < (records || []).length; r++) {
    var rec = records[r]
    if (!rec || !rec.id || !rec.rec) continue
    for (var i = 0; i < lines.length; i++) {
      if (used[i] || !any(lines[i]) || key(lines[i]) !== rec.id) continue
      out[i] = rec.rec
      used[i] = true
      break
    }
  }
  return out
}

function serialize(map, lines) {
  var out = []
  for (var i = 0; i < lines.length; i++)
    if (map[i] && any(lines[i])) out.push({ id: key(lines[i]), rec: map[i] })
  return out
}

// After an edit: a rewording keeps the pin where the line now is.
function carry(oldLines, newLines, map) {
  return Authorship.carryBy(oldLines, newLines, map, any, function (v) { return v })
}

// The conversation a block carries: the first of its lines with a pin.
function find(map, block) {
  if (!block) return ""
  for (var i = block.start; i < block.end; i++) if (map[i]) return map[i]
  return ""
}

// Pin a conversation to a block that has none yet; false when it had one.
function pin(map, block, rec) {
  if (!block || !rec || find(map, block) !== "") return false
  map[block.start] = rec
  return true
}
