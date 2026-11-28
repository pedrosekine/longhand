// Dates — a date phrase read in the page, at once, as it is typed.
//
// The deadline store is the CLI's (`pomo deadline`), and it reads dates with
// GNU date. Asking it meant a process per phrase, so a date could only be
// recognised after the fact, behind a prompt. This reads the same phrases
// the same way (`tests/tst_dates.qml` holds them to it) — "friday" is this
// Friday or today, "next friday" the one after today, a bare day is its
// end (23:59), a day and month already past this year are next year's,
// periods and offsets keep the clock time — and hands the store an exact
// `YYYY-MM-DD HH:MM`, so the page and the CLI can never read one
// differently. A few phrases GNU date refuses read here too ("30 oct
// 17:00", "the 8th of Feb"); the dotted "12.11" `pomo` reads by hand, as
// here. Across a clock change an offset keeps the wall clock ("in 2
// weeks" from 08:58 is 08:58), where GNU date counts hours (07:58).
.pragma library

var MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
var DAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
var MONTH_RE = "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?"
var DAY_RE = "(sun|mon|tue|wed|thu|fri|sat)[a-z]*\\.?"
var TIME_RE = "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?"
// A time that may come before its day: one that cannot be a day or a
// distance ("17:00", "5pm", "5:30pm", "noon", "midnight").
var CLOCK_FIRST = "\\d{1,2}:\\d{2}(?:\\s*(?:am|pm))?|\\d{1,2}\\s*(?:am|pm)|noon|midnight"

function two(n) { return (n < 10 ? "0" : "") + n }

// { ms, iso } for a phrase, or null when it names no date.
function read(text, now) {
  now = now ? new Date(now) : new Date()
  var s = String(text || "").toLowerCase()
    .replace(/\([^)]*\)/g, " ")
    .replace(/^\s*(in|by|on|at|due|until|till)\s+/, "")
    .replace(/\s+/g, " ").trim()
  if (new RegExp("\\b" + MONTH_RE).test(s))
    s = s.replace(/^the /, "").replace(/\b(\d{1,2})(st|nd|rd|th)\b/g, "$1").replace(/ of /g, " ")
  var m

  // Offsets and periods name a distance. In hours the clock time rides
  // along; in days, weeks or months it is a day, owed by its end as a named
  // day is (2026-11-28, the deadlines pass: "due in 3 days" written at
  // 10:00 was due at 10:00, written at 23:30 at 23:30).
  if ((m = s.match(/^(\d+)\s*(h|hrs?|hours?|d|days?|w|weeks?|months?)$/))) {
    var n = parseInt(m[1], 10), u = m[2].charAt(0)
    var d = new Date(now)
    if (u === "h") d.setHours(d.getHours() + n)
    else if (u === "d") d.setDate(d.getDate() + n)
    else if (u === "w") d.setDate(d.getDate() + 7 * n)
    else d.setMonth(d.getMonth() + n)
    return result(d, u !== "h")
  }
  if ((m = s.match(/^next (week|month|year)$/))) {
    var p = new Date(now)
    if (m[1] === "week") p.setDate(p.getDate() + 7)
    else if (m[1] === "month") p.setMonth(p.getMonth() + 1)
    else p.setFullYear(p.getFullYear() + 1)
    return result(p, true)
  }
  // The time first ("5pm friday", "10:00 tomorrow", "noon on monday"): read
  // as the day, then the time.
  if ((m = s.match(new RegExp("^(?:at )?(" + CLOCK_FIRST + ")(?: on)? (.+)$")))
      && !/^\d+\s*(h|hrs?|hours?|d|days?|w|weeks?|months?)$/.test(m[1]))
    s = m[2] + " " + m[1]

  // A day, then maybe a time.
  var rest, day = null
  if ((m = s.match(/^(today|tonight|tomorrow|yesterday)\b ?(.*)$/))) {
    day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (m[1] === "tomorrow" ? 1 : m[1] === "yesterday" ? -1 : 0))
    rest = m[2]
  } else if ((m = s.match(new RegExp("^(this |next )?" + DAY_RE + "(?: (.*))?$")))) {
    var want = DAYS.indexOf(m[2])
    var ahead = (want - now.getDay() + 7) % 7
    if (m[1] === "next " && ahead === 0) ahead = 7
    day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + ahead)
    rest = m[3] || ""
  } else if ((m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?: (.*))?$/))) {
    day = dayOf(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10))
    rest = m[4] || ""
  } else if ((m = s.match(new RegExp("^(\\d{1,2}) " + MONTH_RE + "(?: (\\d{4}))?(?: (.*))?$")))
             || (m = s.match(new RegExp("^" + MONTH_RE + " (\\d{1,2})(?: (\\d{4}))?(?: (.*))?$")))) {
    var dayFirst = /^\d/.test(m[1])
    var dd = parseInt(dayFirst ? m[1] : m[2], 10)
    var mm = MONTHS.indexOf(dayFirst ? m[2] : m[1])
    var yy = m[3] ? parseInt(m[3], 10) : now.getFullYear()
    day = dayOf(yy, mm, dd)
    rest = m[4] || ""
    // No year written and the day is over: next year's.
    if (day && !m[3] && day < new Date(now.getFullYear(), now.getMonth(), now.getDate()))
      day = dayOf(yy + 1, mm, dd)
  } else if ((m = s.match(/^(\d{1,2})\.(\d{1,2})(?:\.(\d{4}|\d{2})?)?(?: (.*))?$/))) {
    // Dotted, day first, as written in Germany and Brazil: "12.11",
    // "12.11.", "12.11.2026", "12.11.26". No year, and the day is over:
    // next year's, as with a month by name.
    var dy = m[3] ? parseInt(m[3], 10) : now.getFullYear()
    if (m[3] && m[3].length === 2) dy += 2000
    day = dayOf(dy, parseInt(m[2], 10) - 1, parseInt(m[1], 10))
    rest = m[4] || ""
    if (day && !m[3] && day < new Date(now.getFullYear(), now.getMonth(), now.getDate()))
      day = dayOf(dy + 1, parseInt(m[2], 10) - 1, parseInt(m[1], 10))
  } else if ((new RegExp("^" + TIME_RE + "$").test(s) && /[:apm]/.test(s)) || /^(noon|midnight)$/.test(s)) {
    day = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    rest = s
  }
  if (!day) return null
  if (rest === "") return result(day, true)
  var hm = clock(rest.replace(/^at /, ""))
  if (!hm) return null
  if (hm[0] === 23 && hm[1] === 59) return result(day, true)
  day.setHours(hm[0], hm[1], 0, 0)
  return result(day, false)
}

// A time of day after a day, as [hours, minutes], or null: "17:00",
// "5pm", "5:30 pm", the European "9.30", "21h" and "9h30", "noon", and
// "midnight" — the day's end, as a bare day is, never the start of the
// next. (Alone, "21h" is twenty-one hours from now and "9.30" a day.)
function clock(text) {
  if (text === "noon") return [12, 0]
  if (text === "midnight") return [23, 59]
  var t = text.match(new RegExp("^" + TIME_RE + "$"))
  var h, min
  if (t && (t[2] || t[3])) {
    h = parseInt(t[1], 10); min = t[2] ? parseInt(t[2], 10) : 0
    if (t[3] === "pm" && h < 12) h += 12
    if (t[3] === "am" && h === 12) h = 0
  } else if ((t = text.match(/^(\d{1,2})(?:\.(\d{2})|h(\d{2})?)$/))) {
    h = parseInt(t[1], 10); min = parseInt(t[2] || t[3] || "0", 10)
  } else return null
  return h > 23 || min > 59 ? null : [h, min]
}

// The day, or null for one that does not exist (31 feb).
function dayOf(y, m, d) {
  var x = new Date(y, m, d)
  return x.getFullYear() === y && x.getMonth() === m && x.getDate() === d ? x : null
}

// A bare day is a deadline at its end.
function result(d, bare) {
  if (bare) d.setHours(23, 59, 0, 0)
  else d.setSeconds(0, 0)
  return {
    ms: d.getTime(),
    iso: d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) + " " + two(d.getHours()) + ":" + two(d.getMinutes())
  }
}
