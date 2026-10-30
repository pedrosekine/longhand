// Bound lines — a checkbox line in a note that stands for a deadline.
//
// The deadline lives in the store (`pomo deadline`); the line is its face in
// the notes. On disk a bound line reads
//
//   - [ ] chapter 2 draft #thesis 📅 2026-10-16 17:00 ^d6
//
// `📅 date [time]` is the Obsidian Tasks due date; `^d6` is an Obsidian block
// id naming deadline #6, so `[[2026.10.09#^d6]]` links to the line. A date
// with no time is a deadline at the end of that day (the store says 23:59).
//
// A line becomes bound when it is written with a cue at its end ("due
// friday 17:00", "by monday", "until 20 oct", "before tomorrow", "📅 fri",
// "on the 8th of Feb"),
// or by Ctrl+D. The first #tag in it is the deadline's project.
.pragma library
.import "Task.js" as Task

var CUE_RE = /^(.*\S)\s+(?:due|by|until|before)\s+(.+?)\s*$/i
var CAL_RE = /^(.*\S)\s*📅\s*(.+?)\s*$/
// "on" is the commonest of them in a sentence ("work on part 3", "focus on
// today"), so it cues a date only when what follows begins as one: a
// weekday, a month and a day, or a day and a month ("the 8th of Feb") —
// never "today", never a lone number.
var MONTH = "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\\.?"
var ON_RE = new RegExp("^(.*\\S)\\s+on\\s+("
  + "(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)[a-z]*\\b.*"
  + "|(?:the\\s+)?\\d{1,2}(?:st|nd|rd|th)?(?:\\s+of)?\\s+" + MONTH + "(?:\\s.*)?"
  + "|" + MONTH + "\\s+\\d{1,2}(?:st|nd|rd|th)?\\b.*"
  + ")\\s*$", "i")
var TAG_RE = /(^|\s)#([\w\/-]+)/
var ANCHOR_RE = /^\s*[-*+] \[([ xX\/\-])\] .*\s\^d(\d+)\s*$/
// What a date phrase has in it. "by phone" or "until done" must not read as
// one (GNU date accepts single letters as time zones, so be strict here).
var DATEISH_RE = /\d|\b(today|tonight|tomorrow|yesterday|mon|tues?|wed|thu|thur|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday|jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|march|april|june|july|august|september|october|november|december|week|month|noon|midnight|next)\b/i

// The deadline's title: the words, without #tags.
function titleOf(words) {
  return words.replace(/(^|\s)#[\w\/-]+/g, " ").replace(/\s+/g, " ").trim()
}

// The project: the first #tag, if any.
function projectOf(words) {
  var m = words.match(TAG_RE)
  return m ? m[2] : ""
}

// A cue at the end of a checkbox's words, or null.
// { head: the words before the cue, phrase: the date words, title, project }
function cue(body) {
  var m = body.match(CAL_RE)
  if (!m) {
    // The last cue counts: of a cue word and "on", the one further along.
    var w = body.match(CUE_RE), o = body.match(ON_RE)
    m = w && o ? (o[1].length > w[1].length ? o : w) : (w || o)
  }
  if (!m || !DATEISH_RE.test(m[2])) return null
  return { head: m[1], phrase: m[2], title: titleOf(m[1]), project: projectOf(body) }
}

// The words a title is compared by: no #tags, case, punctuation or spacing.
function titleKey(words) {
  return titleOf(words).toLowerCase().replace(/[.,;:!?()\[\]"'“”‘’*_`]/g, " ").replace(/\s+/g, " ").trim()
}

var MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
var STOP = { a: 1, an: 1, the: 1, of: 1, and: 1, or: 1, by: 1, on: 1, to: 1, for: 1, in: 1, at: 1, due: 1, until: 1, before: 1, with: 1 }

// The days a line names, as "month-day": "30 oct", "the 19th of Feb",
// "Oct 30", "2026-10-30".
function daysIn(words) {
  var out = [], m
  var iso = /(\d{4})-(\d{2})-(\d{2})/g
  while ((m = iso.exec(words))) out.push(parseInt(m[2], 10) + "-" + parseInt(m[3], 10))
  var dm = /\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]{3})[a-z]*/gi
  while ((m = dm.exec(words))) if (MONTHS.indexOf(m[2].toLowerCase()) >= 0) out.push((MONTHS.indexOf(m[2].toLowerCase()) + 1) + "-" + parseInt(m[1], 10))
  var md = /\b([a-z]{3})[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b/gi
  while ((m = md.exec(words))) if (MONTHS.indexOf(m[1].toLowerCase()) >= 0) out.push((MONTHS.indexOf(m[1].toLowerCase()) + 1) + "-" + parseInt(m[2], 10))
  return out
}

// The words that say what a line is about: no filler, no dates.
function wordsOf(words) {
  return titleKey(words).split(" ").filter(function (w) {
    return w !== "" && !STOP[w] && MONTHS.indexOf(w.substring(0, 3)) < 0 && !/^\d+(st|nd|rd|th)?$/.test(w)
  })
}

// How much of the shorter set of words the other one has, 0..1.
function overlap(a, b) {
  if (a.length === 0 || b.length === 0) return 0
  var n = 0
  for (var i = 0; i < a.length; i++) if (b.indexOf(a[i]) >= 0) n++
  return n / Math.min(a.length, b.length)
}

// Of `bodies` (unbound checkboxes' words), the one an agent's proposal is
// about. The agent rewords titles ("Registered topic, supervisor and peer
// group" for "A registered topic and supervisor, and a peer group"), so:
// the same words if a line has them; else the lines naming the deadline's
// day, the one sharing most words; else the one sharing most words, if at
// least half. -1 when none is, or two are equally likely.
function matchLine(title, dueMs, bodies) {
  var t = titleKey(title)
  if (t === "") return -1
  var heads = bodies.map(function (b) { var c = cue(b); return c ? c.head : b })
  for (var i = 0; i < heads.length; i++) if (titleKey(heads[i]) === t) return i
  var d = new Date(dueMs)
  var day = (d.getMonth() + 1) + "-" + d.getDate()
  var tw = wordsOf(title)
  var scored = bodies.map(function (b, i) {
    return { i: i, dated: dueMs > 0 && daysIn(b).indexOf(day) >= 0, words: overlap(tw, wordsOf(heads[i])) }
  })
  var pool = scored.filter(function (s) { return s.dated })
  if (pool.length === 0) pool = scored.filter(function (s) { return s.words >= 0.5 })
  if (pool.length === 0) return -1
  pool.sort(function (a, b) { return b.words - a.words })
  return pool.length > 1 && pool[0].words === pool[1].words ? -1 : pool[0].i
}

function two(n) { return (n < 10 ? "0" : "") + n }

// The tail written after the words: ` 📅 2026-10-16 17:00 ^d6`. The time is
// left out when the deadline is the end of the day.
function tail(ms, id) {
  var d = new Date(ms)
  var s = " 📅 " + d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate())
  if (!(d.getHours() === 23 && d.getMinutes() === 59)) s += " " + two(d.getHours()) + ":" + two(d.getMinutes())
  return id > 0 ? s + " ^d" + id : s
}

// Bound lines in a text: id -> { line, checked, state }. A cancelled line
// (`[-]`) is still bound: its tag is in the note.
function anchors(text) {
  var out = {}
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(ANCHOR_RE)
    if (m) out[m[2]] = { line: i, checked: m[1] === "x" || m[1] === "X", state: m[1] === "X" ? "x" : m[1] }
  }
  return out
}

// The link the store keeps for a bound line.
function link(stem, id) {
  return "[[" + stem + "#^d" + id + "]]"
}

// A link back to a note and line, or null: "[[2026.10.09#^d6]]".
function parseLink(s) {
  var m = String(s || "").match(/^\[\[([^\]#|]+)#\^d(\d+)\]\]$/)
  return m ? { stem: m[1], id: parseInt(m[2], 10) } : null
}

// ---- the page's bound lines (moved out of Page.qml on 2026-10-30, the
// split's third pass). The note comes in as its rows and the store as its
// items; the page does the writing.

// A deadline's line, for one no line stands for yet: written at the end of
// today's note.
function lineFor(d) {
  var tag = /^[\w\/-]+$/.test(d.project) ? " #" + d.project : ""
  return "- [" + (d.status === "open" ? " " : "x") + "] " + d.title + tag + tail(d.due * 1000, d.id)
}

// A bound line ticked, with the day it was done, or unticked, without it —
// as every tick in the page.
function ticked(raw, done, day) {
  return done ? Task.setField(Task.setState(raw, "x"), "✅", day) : Task.setField(Task.setState(raw, " "), "✅", "")
}

// What changed among bound lines with an edit (`was`, `now`: anchors).
// `gone`: the ids no longer in the note; `changed`: a line back, or ticked,
// or cancelled.
function edits(was, now) {
  var gone = [], changed = false
  for (var id in was) {
    if (!(id in now)) gone.push(parseInt(id, 10))
    else if (was[id].state !== now[id].state) changed = true
  }
  for (var n in now) if (!(n in was)) changed = true
  return { gone: gone, changed: changed }
}

// An open deadline with these words (or mostly) on that day that no line
// holds yet; null when there is none.
function twin(items, head, ms) {
  var key = titleKey(head), tw = wordsOf(head)
  var day = new Date(ms).toDateString()
  for (var i = 0; i < items.length; i++) {
    var d = items[i]
    if (d.status !== "open" || d.link !== "" || new Date(d.due * 1000).toDateString() !== day) continue
    if (titleKey(d.title) !== key && overlap(tw, wordsOf(d.title)) < 0.5) continue
    return d
  }
  return null
}

// The line Tab bound (`rec`: { ms, line }), as it is now: a box still
// carrying that date and no number, the nearest to where it was (Enter may
// have moved it); -1 when there is none.
function tabBound(rows, rec) {
  var best = -1
  for (var i = 0; i < rows.length; i++) {
    var x = rows[i]
    if (x.kind !== "task" || x.deadline > 0 || Math.floor(x.dueAt / 60000) !== Math.floor(rec.ms / 60000)) continue
    if (best < 0 || Math.abs(i - rec.line) < Math.abs(best - rec.line)) best = i
  }
  return best
}

// That line with the store's number: ` ^dN` at its end. Left already
// (`left`: Enter came first), tidied as a left bound line is: no spaces at
// the end of its words or its tail.
function numbered(r, id, left) {
  var tag = " ^d" + id
  return left ? r.raw.substring(0, r.prefixLen) + r.body.replace(/\s+$/, "") + r.suffix.replace(/\s+$/, "") + tag
    : r.raw.replace(/\s+$/, "") + tag
}

// A bound line caught up with the store (`r`: its row, `d`: its deadline,
// or none when the store has lost it). The store's state on the box, and
// the day it was closed after its date, as every tick and drop writes it:
// `📅 … ✅ <day> ^dN`, or `❌ <day>` for a cancelled one; open again,
// neither. A line whose deadline the store no longer has keeps its date,
// without the number.
function caughtUp(r, d, now) {
  var base = r.raw.slice(0, r.raw.length - r.suffix.length)
  if (!d) return base + (r.dueAt > 0 ? tail(r.dueAt, 0) : "")
  var box = d.status === "open" ? " " : d.status === "cancelled" ? "-" : "x"
  base = Task.setState(base, box).replace(/\s*[❌✅]\s*\d{4}-\d{2}-\d{2}/g, "")
  var closed = box === " " ? "" : (box === "-" ? " ❌ " : " ✅ ")
    + Qt.formatDate(new Date(d.doneAt > 0 ? d.doneAt * 1000 : (now || new Date()).getTime()), "yyyy-MM-dd")
  return base + tail(d.due * 1000, 0) + closed + " ^d" + d.id
}
