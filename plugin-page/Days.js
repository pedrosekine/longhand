// Days — the daily notes as the sidebar's calendar sees them.
//
// A daily note is a file whose name is a date. The configured format comes
// first; the common others (2023-03-08, 2023.03.08, 20230308) are read too,
// because a vault that changed its format keeps the old notes. Anything
// whose name is not a date is not a daily note and is not listed.
.pragma library

var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"]

// A moment-style format (YYYY, MM, DD and separators) as a regex with the
// order of its parts.
function pattern(fmt) {
  var order = []
  var re = ""
  var i = 0
  while (i < fmt.length) {
    if (fmt.substr(i, 4) === "YYYY") { re += "(\\d{4})"; order.push("y"); i += 4 }
    else if (fmt.substr(i, 2) === "MM") { re += "(\\d{2})"; order.push("m"); i += 2 }
    else if (fmt.substr(i, 2) === "DD") { re += "(\\d{2})"; order.push("d"); i += 2 }
    else { re += fmt.charAt(i).replace(/[.*+?^${}()|[\]\\\-]/g, "\\$&"); i++ }
  }
  return { re: new RegExp("^" + re + "$"), order: order }
}

// { date: Date, configured: bool } or null. `configured` says the name is
// in the vault's own format — the one the runner reads.
function parse(stem, fmt) {
  var fmts = [fmt || "YYYY-MM-DD", "YYYY-MM-DD", "YYYY.MM.DD", "YYYY_MM_DD", "YYYYMMDD"]
  for (var k = 0; k < fmts.length; k++) {
    var p = pattern(fmts[k])
    var m = stem.match(p.re)
    if (!m) continue
    var y = 0, mo = 0, d = 0
    for (var j = 0; j < p.order.length; j++) {
      var n = parseInt(m[j + 1], 10)
      if (p.order[j] === "y") y = n
      else if (p.order[j] === "m") mo = n
      else d = n
    }
    var date = new Date(y, mo - 1, d)
    if (date.getMonth() !== mo - 1 || date.getDate() !== d) continue
    return { date: date, configured: k === 0 }
  }
  return null
}

function key(d) {
  return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
}

// Which days have a note: key -> stem. A day with names in two formats
// keeps the one in the vault's own format.
function index(stems, fmt) {
  var out = {}
  for (var i = 0; i < stems.length; i++) {
    var p = parse(stems[i], fmt)
    if (!p) continue
    var k = key(p.date)
    if (!out[k] || p.configured) out[k] = stems[i]
  }
  return out
}

// A date in a moment-style format (YYYY, MM, DD).
function format(d, fmt) {
  function two(n) { return (n < 10 ? "0" : "") + n }
  return (fmt || "YYYY-MM-DD").replace("YYYY", String(d.getFullYear()))
    .replace("MM", two(d.getMonth() + 1)).replace("DD", two(d.getDate()))
}

// The file name for a day: the note that exists, or the one it would get.
function stemFor(d, fmt, idx) {
  return idx[key(d)] || format(d, fmt)
}

// A month as 6 weeks x 7 days for the calendar: a Date per cell, null for
// cells outside the month. `firstDow` is the locale's first weekday,
// 0 = Sunday.
function grid(year, month, firstDow) {
  var first = new Date(year, month, 1)
  var lead = (first.getDay() - firstDow + 7) % 7
  var days = new Date(year, month + 1, 0).getDate()
  var out = []
  for (var c = 0; c < 42; c++) {
    var n = c - lead + 1
    out.push(n >= 1 && n <= days ? new Date(year, month, n) : null)
  }
  return out
}

// `d` moved by whole months, the day clamped to the target month's length
// (31 January + 1 month = 28/29 February).
function addMonths(d, n) {
  var y = d.getFullYear(), m = d.getMonth() + n
  var last = new Date(y, m + 1, 0).getDate()
  return new Date(y, m, Math.min(d.getDate(), last))
}

function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
}

function monthLabel(d) {
  return MONTHS[d.getMonth()] + " " + d.getFullYear()
}

// "Friday 9 October", with the year when it is not this one.
function longLabel(stem, fmt) {
  var p = parse(stem, fmt)
  if (!p) return stem
  var d = p.date
  var names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  return names[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
    + (d.getFullYear() === new Date().getFullYear() ? "" : " " + d.getFullYear())
}
