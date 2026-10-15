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
// friday 17:00", "by monday", "until 20 oct", "before tomorrow", "📅 fri"),
// or by Ctrl+D. The first #tag in it is the deadline's project.
.pragma library

var CUE_RE = /^(.*\S)\s+(?:due|by|until|before)\s+(.+?)\s*$/i
var CAL_RE = /^(.*\S)\s*📅\s*(.+?)\s*$/
var TAG_RE = /(^|\s)#([\w\/-]+)/
var ANCHOR_RE = /^\s*[-*+] \[([ xX])\] .*\s\^d(\d+)\s*$/
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
  var m = body.match(CAL_RE) || body.match(CUE_RE)
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

// Bound lines in a text: id -> { line, checked }.
function anchors(text) {
  var out = {}
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(ANCHOR_RE)
    if (m) out[m[2]] = { line: i, checked: m[1] !== " " }
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
