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
