// Outside — a note changed on disk while the page has it open (Obsidian,
// Syncthing from the other machine), taken in as an edit (2026-11-28, the
// navigation pass).
//
// Until then the page loaded the disk's text over its own: the undo
// history started over, the cursor went back to the same count of
// characters (a line added above moved it into another line), and words
// typed in the 300 ms before their save were dropped without a word.
//
// Now the change is the one span the disk's text differs in from what the
// page last wrote or read (`base`), and it is laid into the page's text as
// it is (`ours`): beside words still waiting to be saved when the two
// spans are apart, over them only when they touch the same place.
.pragma library

// The one span `b` differs from `a` in: { a, b } in `a`, and the words `b`
// has there (`s`). Null when they are the same.
function span(a, b) {
  a = String(a); b = String(b)
  if (a === b) return null
  var p = 0
  while (p < a.length && p < b.length && a.charCodeAt(p) === b.charCodeAt(p)) p++
  var q = 0
  while (q < a.length - p && q < b.length - p && a.charCodeAt(a.length - 1 - q) === b.charCodeAt(b.length - 1 - q)) q++
  return { a: p, b: a.length - q, s: b.substring(p, b.length - q) }
}

// What to do with `theirs` (the disk) given `base` (what the page last
// wrote or read) and `ours` (the page's text now):
//   { edit: { a, b, s } in `ours`, or null when nothing changes,
//     kept: true when words of ours not yet saved stay beside theirs,
//     clash: true when both changed the same place — theirs is laid over
//            ours there, and one undo gives ours back }
function take(base, ours, theirs) {
  base = String(base); ours = String(ours); theirs = String(theirs)
  if (theirs === ours) return { edit: null, kept: false, clash: false }
  var mine = span(base, ours), their = span(base, theirs)
  // Nothing of ours waiting (or theirs is no change from what we had):
  // the span between ours and theirs, as it is.
  if (!mine || !their) return { edit: their ? span(ours, theirs) : null, kept: false, clash: false }
  // Apart: one ends where, or before, the other begins. Spans that share a
  // character, or two insertions at one point (whose words go first?), are
  // the same place.
  var bothInsert = mine.a === mine.b && their.a === their.b && mine.a === their.a
  var apart = !bothInsert && (mine.b <= their.a || their.b <= mine.a)
  if (!apart) return { edit: span(ours, theirs), kept: false, clash: true }
  // Theirs, in our text's places: after ours, moved by what ours changed.
  var shift = their.a >= mine.b ? mine.s.length - (mine.b - mine.a) : 0
  return { edit: { a: their.a + shift, b: their.b + shift, s: their.s }, kept: true, clash: false }
}

// The text an edit makes.
function applied(text, edit) {
  return edit ? text.substring(0, edit.a) + edit.s + text.substring(edit.b) : text
}
