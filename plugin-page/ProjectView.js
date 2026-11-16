// ProjectView — what a project's view in the sidebar lists, and in what
// order (2026-11-16, the design study "readings and notes"): one list, so
// writing and reading are seen together instead of one pushing the other
// off the bottom.
//
//   OPEN      what needs the person: the open boxes of the project's
//             sections, then the questions still waiting in its papers
//   BY DAY    the sections and the days a paper was read, newest first, so
//             Sunday's reading stands beside Saturday's writing
//   Shelf     the papers not begun, folded to one line
//   Files     the project's own documents, folded to one line
//
// Words and order only, no state of the page's: the sections, the papers
// (`longhand-read papers`), the filed documents, which folds are open, and
// `iso(section)`, a section's day as YYYY-MM-DD (the daily notes' own
// format is the page's to read). Each row has a `key` that stays the same
// when the list is read again, so the selection holds on its row, and
// `pick` when it can be selected.
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

// The open loops: each open box, then each waiting question.
function openRows(sections, papers) {
  var out = []
  for (var i = 0; i < sections.length; i++) {
    var s = sections[i], boxes = s.boxes || []
    for (var j = 0; j < boxes.length; j++) {
      if ((boxes[j].state || " ") !== " ") continue
      out.push({ kind: "box", pick: true, key: "b:" + s.date + ":" + boxes[j].line, section: s, index: i,
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

  var out = []
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
  // on the same day; newest day first.
  // A day that holds only open boxes is all in OPEN already: not twice.
  var days = []
  for (var a = 0; a < sections.length; a++) {
    var sb = sections[a].boxes || []
    if (!sections[a].heading && sb.length > 0 && sb.every(function (x) { return (x.state || " ") === " " })) continue
    days.push({ kind: "section", pick: true, key: sectionKey(sections[a]), section: sections[a], index: a,
                day: iso(sections[a]), order: 0, seq: a })
  }
  for (var b = 0; b < reading.length; b++) {
    var pd = reading[b].days
    for (var day in pd)
      days.push({ kind: "read", pick: true, key: "r:" + reading[b].pdf + ":" + day, paper: reading[b], day: day,
                  label: citeLabel(reading[b]), title: citeTitle(reading[b]), said: marksSaid(pd[day].h, pd[day].q),
                  order: 1, seq: b })
  }
  days.sort(function (x, y) {
    return x.day !== y.day ? (x.day < y.day ? 1 : -1) : x.order !== y.order ? x.order - y.order : x.seq - y.seq
  })
  // A paper read on several days: its title under the newest only.
  var titled = {}
  for (var t = 0; t < days.length; t++) {
    if (days[t].kind !== "read") continue
    if (titled[days[t].paper.pdf]) days[t].title = ""
    titled[days[t].paper.pdf] = true
  }
  if (days.length > 0) {
    if (open.length > 0) out.push({ kind: "cap", key: "cap:days", text: "BY DAY" })
    out = out.concat(days)
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
// (the first when `key` is not in the list).
function step(list, key, d) {
  var picks = []
  for (var i = 0; i < list.length; i++) if (list[i].pick) picks.push(list[i].key)
  if (picks.length === 0) return ""
  var at = picks.indexOf(key)
  if (at < 0) return picks[0]
  return picks[Math.max(0, Math.min(picks.length - 1, at + d))]
}

// The row with this key, else the first that can be picked; null for none.
function find(list, key) {
  var first = null
  for (var i = 0; i < list.length; i++) {
    if (list[i].key === key) return list[i]
    if (!first && list[i].pick) first = list[i]
  }
  return first
}
