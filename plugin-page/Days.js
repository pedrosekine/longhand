// Days — the daily notes as the sidebar lists them.
//
// A daily note is a file whose name is a date. The configured format comes
// first; the common others (2023-03-08, 2023.03.08, 20230308) are read too,
// because a vault that changed its format keeps the old notes. Anything
// whose name is not a date is not a daily note and is not listed.
.pragma library

var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

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

// Rows for the sidebar, newest first: a header per month, then its days.
// `today` is today's stem, so it is listed even before its file exists.
function rows(stems, fmt, today) {
  var days = []
  var seen = {}
  var all = stems.slice()
  if (today && all.indexOf(today) < 0) all.push(today)
  for (var i = 0; i < all.length; i++) {
    var p = parse(all[i], fmt)
    if (!p || seen[p.date.getTime()]) continue
    seen[p.date.getTime()] = true
    days.push({ stem: all[i], date: p.date, configured: p.configured })
  }
  days.sort(function (a, b) { return b.date - a.date })
  var out = []
  var month = ""
  var thisYear = new Date().getFullYear()
  for (var k = 0; k < days.length; k++) {
    var dd = days[k].date
    var label = MONTHS[dd.getMonth()] + (dd.getFullYear() === thisYear ? "" : " " + dd.getFullYear())
    if (label !== month) {
      out.push({ kind: "month", label: label.toUpperCase() })
      month = label
    }
    out.push({ kind: "day", stem: days[k].stem, label: WEEKDAYS[dd.getDay()] + " " + dd.getDate(),
               today: days[k].stem === today, configured: days[k].configured })
  }
  return out
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
