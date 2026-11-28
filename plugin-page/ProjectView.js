// ProjectView — what a project's view in the sidebar lists, and in what
// order (2026-11-16, the design study "readings and notes"; this week and
// its pages, 2026-11-21): one list, so writing and reading are seen
// together instead of one pushing the other off the bottom.
//
//   Project page  a row of its own: the whole project in one scroll (Alt+P)
//   OPEN          what needs the person: the open boxes of the project's
//                 sections, then the questions still waiting in its papers
//   THIS WEEK     its page first (Alt+W), then the sections and the days a
//                 paper was read this week, Monday to Sunday, newest first
//   Earlier       the days before this week, folded to one line that names
//                 its meetings
//   Shelf         the papers not begun, folded to one line
//   Files         the project's own documents, folded to one line
//
// Before, every day the project ever had was listed, so the list grew a
// row a day while the two pages that gather it were two grey lines.
//
// Words and order only, no state of the page's: the sections, the papers
// (`longhand-read papers`), the filed documents, which folds are open,
// `iso(section)`, a section's day as YYYY-MM-DD (the daily notes' own
// format is the page's to read), `today` as YYYY-MM-DD and the project's
// `name`. Each row has a `key` that stays the same when the list is read
// again, so the selection holds on its row, and `pick` when it can be
// selected.
.pragma library
.import "Say.js" as Say

// A paper as it is cited: "Moser et al. 2026", from the project's
// bibliography; its file's name when it has no entry.
function citeLabel(p) {
  var c = (p && p.cite) || {}
  return c.authors ? c.authors + (c.year ? " " + c.year : "") : (p ? p.title : "")
}

function citeTitle(p) {
  return (p && p.cite && p.cite.title) || ""
}

// "11 highlights, 6 questions" — what a day of reading left.
function marksSaid(h, q) {
  var bits = []
  if (h) bits.push(h + (h === 1 ? " highlight" : " highlights"))
  if (q) bits.push(q + (q === 1 ? " question" : " questions"))
  return bits.join(", ")
}

function sectionKey(s) {
  return "s:" + s.date + ":" + (s.heading || s.title || s.line)
}

// The open loops: each open box, then each waiting question. A section's
// own boxes are its `tasks` (the runner's, 2026-11-28); a day's boxes
// written outside any of its sections, its `boxes`. Each row keeps its box,
// so Enter lands on that line and not on the section's first.
function openRows(sections, papers) {
  var out = []
  for (var i = 0; i < sections.length; i++) {
    var s = sections[i], boxes = s.boxes || s.tasks || []
    for (var j = 0; j < boxes.length; j++) {
      if ((boxes[j].state || " ") !== " ") continue
      out.push({ kind: "box", pick: true, key: "b:" + s.date + ":" + boxes[j].line, section: s, index: i, box: boxes[j],
                 text: Say.plainLine("- [ ] " + boxes[j].text).replace(/^○\s*/, "") })
    }
  }
  for (var k = 0; k < papers.length; k++) {
    var p = papers[k]
    var qs = p.questions || []
    for (var m = 0; m < qs.length; m++)
      out.push({ kind: "question", pick: true, key: "q:" + p.pdf + ":" + qs[m].id, paper: p,
                 id: qs[m].id, text: qs[m].text, note: qs[m].note || "", page: qs[m].page, label: citeLabel(p) })
  }
  return out
}

var OPEN_SHOWN = 5
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function _date(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""))
  return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null
}
function _iso(d) {
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
}

// The week `today` is in, Monday to Sunday, as the week's page counts it
// (`longhand-agent week`): { from, to } as YYYY-MM-DD and its name,
// "16–22 Nov" (or "30 Nov – 6 Dec" across a month).
function weekOf(today) {
  var d = _date(today) || new Date()
  var mon = new Date(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() + 6) % 7)
  var sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6)
  var said = mon.getMonth() === sun.getMonth()
    ? mon.getDate() + "–" + sun.getDate() + " " + MONTHS[sun.getMonth()]
    : mon.getDate() + " " + MONTHS[mon.getMonth()] + " – " + sun.getDate() + " " + MONTHS[sun.getMonth()]
  return { from: _iso(mon), to: _iso(sun), said: said }
}

// What the week's page holds, counted: "3 papers read · 3 done · 3
// questions to bring" (the questions are every one still waiting, as on
// that page).
function weekSaid(weekDays, asked) {
  var papers = {}, read = 0, done = 0
  for (var i = 0; i < weekDays.length; i++) {
    var r = weekDays[i]
    if (r.kind === "read" && !papers[r.paper.pdf]) { papers[r.paper.pdf] = true; read++ }
    if (r.kind === "section") done += r.section.done || 0
  }
  var bits = []
  if (read) bits.push(read + (read === 1 ? " paper read" : " papers read"))
  if (done) bits.push(done + " done")
  if (asked) bits.push(asked + (asked === 1 ? " question to bring" : " questions to bring"))
  return bits.length > 0 ? bits.join(" · ") : "nothing written or read yet"
}

// The meetings in the days folded away, by name: "Bernd Meeting, Kick-off"
// (two at most, then "…").
function namedIn(days, name) {
  var names = []
  for (var i = 0; i < days.length; i++) {
    if (days[i].kind !== "section") continue
    var t = Say.sectionTitle(days[i].section, name).replace(/^#+\s*/, "").replace(/(^|\s)#[\w\/-]+/g, "").replace(/\s+/g, " ").trim()
    if (t !== "" && names.indexOf(t) < 0) names.push(t)
  }
  return names.length > 2 ? names.slice(0, 2).join(", ") + ", …" : names.join(", ")
}

function rows(sections, papers, docs, opts) {
  sections = sections || []
  papers = papers || []
  docs = docs || []
  opts = opts || {}
  var iso = opts.iso || function (s) { return s.date }
  var reading = [], shelf = [], files = []
  for (var i = 0; i < papers.length; i++) {
    var p = papers[i]
    if (p.missing) continue
    if (p.kind === "document") files.push({ kind: "doc", pick: true, key: "d:" + p.pdf, pdf: p.pdf, name: p.title })
    else if (p.days && Object.keys(p.days).length > 0) reading.push(p)
    else shelf.push(p)
  }
  for (var d = 0; d < docs.length; d++)
    files.push({ kind: "doc", pick: true, key: "f:" + docs[d].path, doc: docs[d], name: docs[d].name })
  // Nothing under the tag yet: its two pages still (a new project's page
  // has its sessions and deadlines), and the view says how to start one
  // under them (2026-11-28; it hid both pages until then).

  // The whole project in one scroll, first: its page (its key, `act`).
  var out = [{ kind: "page", pick: true, key: "page:project", page: "project", text: "Project page", act: "listPage",
               role: "The whole project in one scroll: what's next, deadlines, papers, files, every section" }]
  var open = openRows(sections, reading)
  if (open.length > 0) {
    out.push({ kind: "cap", key: "cap:open", text: "OPEN · " + open.length })
    // A long band would push the days off the sidebar: the first OPEN_SHOWN,
    // the rest one line away.
    if (open.length > OPEN_SHOWN + 1 && !opts.open) {
      out = out.concat(open.slice(0, OPEN_SHOWN))
      out.push({ kind: "fold", pick: true, key: "fold:open", fold: "open", open: false,
                 text: (open.length - OPEN_SHOWN) + " more open" })
    } else {
      out = out.concat(open)
      if (open.length > OPEN_SHOWN + 1)
        out.push({ kind: "fold", pick: true, key: "fold:open", fold: "open", open: true, text: "fewer" })
    }
  }

  // The days: a section, or a paper read that day. Sections before reading
  // on the same day; newest day first. Papers read the same day: the one
  // read last first, by when its note was saved (a mark keeps only its day,
  // 2026-11-22). That time is a paper's last day only; an earlier day of it
  // goes after those known, in the papers' order.
  // A day that holds only open boxes is all in OPEN already: not twice.
  // The same heading twice in a day: a key each, by its place among them.
  var days = [], seen = {}
  for (var a = 0; a < sections.length; a++) {
    var sb = sections[a].boxes || []
    if (!sections[a].heading && sb.length > 0 && sb.every(function (x) { return (x.state || " ") === " " })) continue
    var sk = sectionKey(sections[a])
    seen[sk] = (seen[sk] || 0) + 1
    if (seen[sk] > 1) sk += "#" + seen[sk]
    days.push({ kind: "section", pick: true, key: sk, section: sections[a], index: a,
                day: iso(sections[a]), order: 0, seq: a })
  }
  for (var b = 0; b < reading.length; b++) {
    var pd = reading[b].days
    for (var day in pd)
      days.push({ kind: "read", pick: true, key: "r:" + reading[b].pdf + ":" + day, paper: reading[b], day: day,
                  label: citeLabel(reading[b]), said: marksSaid(pd[day].h, pd[day].q), order: 1, seq: b,
                  saved: day === reading[b].last ? (reading[b].saved || 0) : 0 })
  }
  days.sort(function (x, y) {
    return x.day !== y.day ? (x.day < y.day ? 1 : -1) : x.order !== y.order ? x.order - y.order
      : (x.saved || 0) !== (y.saved || 0) ? (y.saved || 0) - (x.saved || 0) : x.seq - y.seq
  })

  // This week, under its page; the days before it, folded.
  var week = weekOf(opts.today)
  var thisWeek = days.filter(function (x) { return x.day >= week.from && x.day <= week.to })
  var earlier = days.filter(function (x) { return x.day < week.from })
  var asked = open.filter(function (x) { return x.kind === "question" }).length
  out.push({ kind: "cap", key: "cap:week", text: "THIS WEEK · " + week.said.toUpperCase() })
  out.push({ kind: "page", pick: true, key: "page:week", page: "week", text: "Week page", act: "listWeek",
             role: "For a supervisor update or the diary: done, written, read, still open, questions to bring",
             said: weekSaid(thisWeek, asked) })
  out = out.concat(thisWeek)
  if (earlier.length > 0) {
    var count = {}
    for (var e = 0; e < earlier.length; e++) count[earlier[e].day] = true
    var n = Object.keys(count).length, named = namedIn(earlier, opts.name)
    out.push({ kind: "fold", pick: true, key: "fold:earlier", fold: "earlier", open: !!opts.earlier,
               text: "Earlier · " + n + (n === 1 ? " day" : " days") + (named !== "" && !opts.earlier ? " · " + named : "") })
    if (opts.earlier) out = out.concat(earlier)
  }

  if (shelf.length > 0) {
    shelf.sort(function (x, y) { return citeLabel(x).toLowerCase() < citeLabel(y).toLowerCase() ? -1 : 1 })
    out.push({ kind: "fold", pick: true, key: "fold:shelf", fold: "shelf", open: !!opts.shelf,
               text: "Shelf · " + shelf.length + " not begun" })
    if (opts.shelf)
      for (var c = 0; c < shelf.length; c++)
        out.push({ kind: "paper", pick: true, key: "p:" + shelf[c].pdf, paper: shelf[c],
                   label: citeLabel(shelf[c]), title: citeTitle(shelf[c]) })
  }
  if (files.length > 0) {
    out.push({ kind: "fold", pick: true, key: "fold:files", fold: "files", open: !!opts.files,
               text: "Files · " + files.length })
    if (opts.files) out = out.concat(files)
  }
  return out
}

// The key of the row `d` steps from `key` among those that can be picked
// (the first when `key` is not in the list — the first that is not a page,
// so a project opens on what is open in it, its page one key up).
function step(list, key, d) {
  var picks = []
  for (var i = 0; i < list.length; i++) if (list[i].pick) picks.push(list[i].key)
  if (picks.length === 0) return ""
  var at = picks.indexOf(key)
  if (at < 0) { var f = find(list, ""); return f ? f.key : picks[0] }
  return picks[Math.max(0, Math.min(picks.length - 1, at + d))]
}

// The row with this key, else the first that can be picked and is not a
// page (a page when there is nothing else); null for none.
function find(list, key) {
  var first = null, page = null
  for (var i = 0; i < list.length; i++) {
    if (list[i].key === key) return list[i]
    if (!list[i].pick) continue
    if (list[i].kind === "page") { if (!page) page = list[i] }
    else if (!first) first = list[i]
  }
  return first || page
}
