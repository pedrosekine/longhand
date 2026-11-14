// Next — what's next: the dashboard's rows, in the order they ask something
// of you (moved out of Page.qml on 2026-10-30, the split's fourth pass;
// `tests/tst_next.qml` holds it). The page's state comes in as one object:
//
//   deadlines    the store's items (Deadlines.qml)
//   tasks        the boxes in the notes (`longhand-tasks`)
//   projects     the curriculum's, for a course's name
//   raised       what the agent raised, under "from the agent"
//   proposals    the agent's open proposals and questions
//   showShelf, showGrading   the folded bands, unfolded
//   lens, query, order       the course strip: the courses picked, the
//                words typed, and the order ("ask", "course", "date")
//   folds        by date, the bands folded or unfolded (`bandOpen`)
//   now          the moment it is asked, when not given
.pragma library
.import "Say.js" as Say

function taskOfAnchor(tasks, id) {
  for (var i = 0; i < tasks.length; i++) if (tasks[i].anchor === id) return tasks[i]
  return null
}

function taskOfKey(tasks, key) {
  if (!key) return null
  for (var i = 0; i < tasks.length; i++) if (tasks[i].key === key) return tasks[i]
  return null
}

// The dashboard's rows, in the order they ask something of you:
//
//   DUE            deadlines — late ones are the earliest, so they lead;
//                  ones closed today stay until tomorrow
//   DOING          boxes with a day on them (⏳ a do-date, or 📅 still
//                  unbound), by that day
//   TO SCHEDULE    boxes with a priority but no day yet — the pile the
//                  do-date is for
//   #project       note boxes, under the project that claims them, newest
//                  first
//   SET ASIDE      folded: boxes whose silence ran out, or put aside with
//                  `s` (agent/lifespan.py) — never rewritten, back when
//                  touched
//   WAITING FOR A GRADE   folded: done deadlines with no grade yet
//   FROM THE AGENT
//
// That is the order "what it asks" (`order`); "course" puts the courses
// first, each with those bands inside, and "date" makes one timeline. The
// course strip narrows any of them (`lens`, `query`; `narrowed`).
//
// Note boxes group by project rather than by the day they were written,
// because the day a thought was written is not how it is looked for
// (2026-10-15, and the 31 trips to the calendar before it). A box bound to
// the store is listed once, as its deadline.
function rows(s) {
  var now = s.now || new Date()
  var f = narrowed(s)
  var b = buckets(f, now)
  var order = s.order === "course" ? byCourse : s.order === "date" ? byDate : byAsk
  var out = order(b, f, now)
  folded(out, b, f)
  return withProposals(out, f.proposals, s.tasks)
}

// What the list is made of, before it is put in an order.
function buckets(s, now) {
  var today = new Date(now.getTime())
  today.setHours(0, 0, 0, 0)
  // Closed today (done, or cancelled) stays until tomorrow, so what just
  // happened can still be seen; a deadline no line stands for yet has a
  // band of its own.
  var due = s.deadlines.filter(function (d) {
    return (d.status === "open" && d.link !== "")
      || ((d.status === "done" || d.status === "cancelled") && d.doneAt * 1000 >= today.getTime())
  })
  var waiting = s.deadlines.filter(function (d) { return d.status === "open" && d.link === "" })
  // Open ones first, then the closed, each by its date. (Until 2026-10-30
  // the closed were split by status, done and cancelled each sorting after
  // the other, so their order was the sort's to pick.)
  due.sort(function (a, b) {
    var ao = a.status === "open", bo = b.status === "open"
    if (ao !== bo) return ao ? -1 : 1
    return a.due - b.due
  })
  waiting.sort(function (a, b) { return a.due - b.due })
  var doing = [], later = [], notes = [], shelf = []
  for (var i = 0; i < s.tasks.length; i++) {
    var t = s.tasks[i]
    if (t.anchor > 0) continue
    if (t.away) shelf.push(t)
    else if (t.when !== "" || t.due !== "") doing.push(t)
    else if (t.kind === "task") later.push(t)
    else notes.push(t)
  }
  doing.sort(function (a, b) { return (a.when || a.due).localeCompare(b.when || b.due) })
  later.sort(function (a, b) { return b.priority - a.priority || a.age - b.age })
  var grading = s.deadlines.filter(function (d) {
    return d.status === "done" && d.grade === "" && d.doneAt * 1000 < today.getTime()
  })
  grading.sort(function (a, b) { return b.doneAt - a.doneAt })
  return { due: due, waiting: waiting, doing: doing, later: later, notes: notes, shelf: shelf, grading: grading }
}

// By what each row asks of you: the order the dashboard was made in.
function byAsk(b, s, now) {
  var rows = []
  if (b.due.length > 0) {
    rows.push({ kind: "head", text: "DUE", tag: "" })
    var month = ""
    for (var k = 0; k < b.due.length; k++) {
      var lbl = Say.monthLabel(b.due[k].due * 1000, now)
      if (lbl !== month) { rows.push({ kind: "month", text: lbl }); month = lbl }
      rows.push({ kind: "deadline", deadline: b.due[k] })
    }
  }
  if (b.waiting.length > 0) {
    rows.push({ kind: "head", text: "NOT IN A NOTE YET", tag: "" })
    for (var w = 0; w < b.waiting.length; w++) rows.push({ kind: "deadline", deadline: b.waiting[w] })
  }
  if (b.doing.length > 0) {
    rows.push({ kind: "head", text: "DOING", tag: "" })
    var dm = ""
    for (var d1 = 0; d1 < b.doing.length; d1++) {
      var dl1 = Say.monthLabel(Say.taskMs(b.doing[d1]), now)
      if (dl1 !== dm) { rows.push({ kind: "month", text: dl1 }); dm = dl1 }
      rows.push({ kind: "task", task: b.doing[d1] })
    }
  }
  if (b.later.length > 0) {
    rows.push({ kind: "head", text: "TO SCHEDULE", tag: "" })
    for (var l = 0; l < b.later.length; l++) rows.push({ kind: "task", task: b.later[l] })
  }
  var groups = byProject(b.notes, s.projects)
  for (var g = 0; g < groups.length; g++) {
    var named = bandName(groups[g].key, groups[g].items, s.projects)
    rows.push({ kind: "head", text: named, tag: groups[g].key === "" ? "" : "#" + groups[g].key })
    // Under a band, a row does not repeat it: the section it was written
    // in is what the row still has to say.
    for (var m = 0; m < groups[g].items.length; m++)
      rows.push({ kind: "task", task: groups[g].items[m], under: named })
  }
  return rows
}

// By course (2026-11-03, the course strip's order): a band for each, and
// in it what each row asks of you, in the same order as above.
function byCourse(b, s, now) {
  var parts = [["DUE", b.due.concat(b.waiting), "deadline"], ["DOING", b.doing, "task"],
               ["TO SCHEDULE", b.later, "task"], ["", b.notes, "task"]]
  var keys = courseKeys(s, [b.due, b.waiting, b.doing, b.later, b.notes])
  var rows = []
  for (var c = 0; c < keys.length; c++) {
    var key = keys[c], items = [], mine = []
    for (var p = 0; p < parts.length; p++) {
      var got = parts[p][1].filter(function (x) { return (x.project || "") === key })
      mine.push(got)
      if (parts[p][2] === "task") items = items.concat(got)
    }
    var named = bandName(key, items, s.projects)
    rows.push({ kind: "head", text: named, tag: key === "" ? "" : "#" + key })
    for (var q = 0; q < parts.length; q++) {
      if (mine[q].length === 0) continue
      // Its notes need no word of their own: they are what is left.
      if (parts[q][0] !== "") rows.push({ kind: "month", text: parts[q][0] })
      for (var i = 0; i < mine[q].length; i++)
        rows.push(parts[q][2] === "deadline" ? { kind: "deadline", deadline: mine[q][i] }
                                             : { kind: "task", task: mine[q][i], under: named })
    }
  }
  return rows
}

// By date: one timeline across the courses — every deadline and every
// box with a day, by that day — then what has no day yet. Until
// 2026-11-03 it was banded by month alone, so Thursday's call and a paper
// due at the month's end read as one band; now the bands narrow as they
// come near (`bands`), and each folds (`folds`).
function byDate(b, s, now) {
  var dated = []
  // What was closed today is today's, whatever day it was due; on a day,
  // what is still open comes first.
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  function put(ms, row, closed) { dated.push({ ms: closed ? Math.max(ms, today) : ms, row: row, closed: closed }) }
  for (var i = 0; i < b.due.length; i++) put(b.due[i].due * 1000, { kind: "deadline", deadline: b.due[i] }, b.due[i].status !== "open")
  for (var w = 0; w < b.waiting.length; w++) put(b.waiting[w].due * 1000, { kind: "deadline", deadline: b.waiting[w] }, false)
  for (var d = 0; d < b.doing.length; d++) put(Say.taskMs(b.doing[d]), { kind: "task", task: b.doing[d] }, !!b.doing[d].done)
  dated.sort(function (x, y) {
    var dx = new Date(x.ms).setHours(0, 0, 0, 0), dy = new Date(y.ms).setHours(0, 0, 0, 0)
    return dx - dy || (x.closed ? 1 : 0) - (y.closed ? 1 : 0) || x.ms - y.ms
  })
  var spans = bands(now), groups = []
  for (var k = 0; k < dated.length; k++) {
    var ms = dated[k].ms
    var at = 0
    while (at + 1 < spans.length && ms >= spans[at + 1].from) at++
    var span = spans[at]
    // Past the month this one is in, a band for each month.
    var id = span.id === "month" ? "m" + Qt.formatDate(new Date(ms), "yyyy-MM") : span.id
    var g = groups.length > 0 && groups[groups.length - 1].id === id ? groups[groups.length - 1] : null
    if (!g) {
      g = { id: id, text: span.id === "month" ? Say.monthLabel(ms, now).toUpperCase() : span.text, items: [] }
      groups.push(g)
    }
    g.items.push(dated[k])
  }
  var rest = b.later.concat(b.notes)
  if (rest.length > 0) groups.push({ id: "none", text: "NO DAY YET", items: rest.map(function (t) { return { row: { kind: "task", task: t } } }) })
  // Today is said even when nothing is due: the line that says so is the
  // answer to the first question the list is opened with.
  if (groups.length > 0 && !groups.some(function (x) { return x.id === "today" }))
    groups.splice(groups.length > 0 && groups[0].id === "late" ? 1 : 0, 0, { id: "today", text: "TODAY", items: [] })
  var words = String(s.query || "").split(/\s+/).some(function (x) { return x !== "" && x.charAt(0) !== "#" })
  var rows = []
  for (var n = 0; n < groups.length; n++) {
    var gr = groups[n]
    var open = gr.id === "late" || words || bandOpen(s.folds, gr.id)
    var first = gr.items.length > 0 ? gr.items[0].row : null
    rows.push({ kind: "band", id: gr.id, text: gr.text, count: gr.items.length, open: open, fixed: gr.id === "late",
                next: first ? (first.kind === "deadline" ? { title: first.deadline.title, ms: first.deadline.due * 1000 }
                                                         : { title: Say.taskTitle(first.task), ms: Say.taskMs(first.task) }) : null })
    if (open) for (var r = 0; r < gr.items.length; r++) rows.push(gr.items[r].row)
  }
  return rows
}

// The bands of the timeline, nearest first, each from the moment it
// starts: what is late, today, the rest of this week (Monday to Sunday),
// next week, the rest of this month, and then a band for each month.
function bands(now) {
  var y = now.getFullYear(), m = now.getMonth(), d = now.getDate()
  function at(days) { return new Date(y, m, d + days).getTime() }
  var toMonday = 7 - (now.getDay() + 6) % 7
  var out = [{ id: "late", text: "LATE", from: -Infinity },
             { id: "today", text: "TODAY", from: at(0) },
             { id: "week", text: "THIS WEEK", from: at(1) },
             { id: "next", text: "NEXT WEEK", from: at(toMonday) }]
  var after = at(toMonday + 7), monthEnd = new Date(y, m + 1, 1).getTime()
  if (after < monthEnd) out.push({ id: "rest", text: "LATER IN " + Qt.formatDate(now, "MMMM").toUpperCase(), from: after })
  out.push({ id: "month", text: "", from: Math.max(after, monthEnd) })
  return out
}

// Whether a band shows what it holds: as it was last folded or unfolded,
// else as all were (`*`, from fold all or unfold all), else the near ones
// open — what is late, today, this week and next — and the far ones shut.
function bandOpen(folds, id) {
  var f = folds || {}
  if (f[id] !== undefined) return !!f[id]
  if (f["*"] !== undefined) return !!f["*"]
  return ["late", "today", "week", "next"].indexOf(id) >= 0
}

// What is away and what is owed a grade, each folded into one row until
// asked for: there to be found, never in the way. Then what the agent
// raised.
function folded(rows, b, s) {
  if (b.shelf.length > 0) {
    if (!s.showShelf) rows.push({ kind: "shelf", count: b.shelf.length })
    else {
      rows.push({ kind: "head", text: "SET ASIDE", tag: "" })
      for (var sh = 0; sh < b.shelf.length; sh++) rows.push({ kind: "task", task: b.shelf[sh] })
    }
  }
  if (b.grading.length > 0) {
    if (!s.showGrading) rows.push({ kind: "grading", count: b.grading.length })
    else {
      rows.push({ kind: "head", text: "WAITING FOR A GRADE", tag: "" })
      for (var gr = 0; gr < b.grading.length; gr++) rows.push({ kind: "deadline", deadline: b.grading[gr] })
    }
  }
  var raised = s.raised || []
  if (raised.length > 0) {
    rows.push({ kind: "head", text: "FROM THE AGENT", tag: "" })
    for (var j = 0; j < raised.length; j++) rows.push({ kind: "raised", item: raised[j] })
  }
}

// Note boxes under the project that claims them, in the order first met.
function byProject(items, projects) {
  var groups = [], seen = ({})
  for (var n = 0; n < items.length; n++) {
    var key = items[n].project || ""
    if (seen[key] === undefined) { seen[key] = groups.length; groups.push({ key: key, items: [] }) }
    groups[seen[key]].items.push(items[n])
  }
  return groups
}

// The course's own name, not its tag: a band that reads "Interdisciplinary
// Seminar" says more than #intsem. The sidebar knows the names from the
// curriculum; for a tag it does not know, the heading the notes themselves
// use is the next best name — from a box under its own course's headings,
// never one written inside another course's section.
function bandName(key, items, projects) {
  if (key === "") return "No project"
  var named = Say.courseName(key, projects)
  if (named !== key) return named
  for (var h = 0; h < items.length; h++) {
    if (!Say.inOwnCourse(items[h], key)) continue
    var path0 = (items[h].path || [])[0]
    if (path0) return path0
  }
  return named
}

// The courses there is something for, in the sidebar's order (the soonest
// session first), then tags it does not know as they come, then no project.
function courseKeys(s, lists) {
  var have = {}, extra = [], keys = []
  for (var l = 0; l < lists.length; l++)
    for (var i = 0; i < lists[l].length; i++) {
      var k = lists[l][i].project || ""
      if (have[k]) continue
      have[k] = true
      if (k !== "" && !(s.projects || []).some(function (p) { return p.tag === k })) extra.push(k)
    }
  for (var p = 0; p < (s.projects || []).length; p++) if (have[s.projects[p].tag]) keys.push(s.projects[p].tag)
  keys = keys.concat(extra)
  if (have[""]) keys.push("")
  return keys
}

// ------------------------------------------------------- the course strip

// What is typed into the strip's ⌕ (2026-11-03): words, each of which a
// row must hold — in its words, the section it was written in or its
// course — and #tags, each a course as its chip would pick it (the first
// whose tag starts so; one that matches none matches nothing).
function query(text, tags) {
  var out = { words: [], tags: [] }
  var parts = String(text || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < parts.length; i++) {
    var w = parts[i]
    if (w === "" || w === "#") continue
    if (w.charAt(0) !== "#") { out.words.push(w); continue }
    var t = w.substring(1), hit = "\u0000"
    for (var k = 0; k < tags.length; k++) if (tags[k] === t) hit = t
    if (hit === "\u0000") for (var j = 0; j < tags.length; j++) if (tags[j] !== "" && tags[j].indexOf(t) === 0) { hit = tags[j]; break }
    if (out.tags.indexOf(hit) < 0) out.tags.push(hit)
  }
  return out
}

function allTags(s) {
  var seen = {}, out = []
  function add(t) { t = t || ""; if (!seen[t]) { seen[t] = true; out.push(t) } }
  for (var p = 0; p < (s.projects || []).length; p++) add(s.projects[p].tag)
  for (var i = 0; i < s.deadlines.length; i++) add(s.deadlines[i].project)
  for (var j = 0; j < s.tasks.length; j++) add(s.tasks[j].project)
  return out
}

function said(x, projects) {
  var p = x.project || ""
  return [x.title || "", x.question || "", x.name || "", (x.path || []).join(" "), p, p ? Say.courseName(p, projects) : ""]
    .join(" ").toLowerCase()
}

// The state with only what the lens and the words keep: the courses picked
// on the strip (`lens`, "" for no project) and those typed as #tags, and
// every word typed. A box bound to a deadline stays, for finding its line.
// What the agent raised is about no course: it goes while a course is
// picked, and stays for words it holds.
function narrowed(s) {
  var q = query(s.query, allTags(s))
  var lens = (s.lens || []).concat(q.tags)
  if (lens.length === 0 && q.words.length === 0) return s
  function keeps(project, text) {
    if (lens.length > 0 && lens.indexOf(project || "") < 0) return false
    for (var w = 0; w < q.words.length; w++) if (text.indexOf(q.words[w]) < 0) return false
    return true
  }
  var out = {}
  for (var k in s) out[k] = s[k]
  out.deadlines = s.deadlines.filter(function (d) { return keeps(d.project, said(d, s.projects)) })
  out.tasks = s.tasks.filter(function (t) { return t.anchor > 0 || keeps(t.project, said(t, s.projects)) })
  out.proposals = (s.proposals || []).filter(function (x) {
    var t = taskOfKey(s.tasks, x.key)
    return keeps(x.project || (t ? t.project : ""), said(x, s.projects) + " " + (t ? said(t, s.projects) : ""))
  })
  out.raised = lens.length > 0 ? [] : (s.raised || []).filter(function (x) {
    return keeps("", String(x.text || "").toLowerCase())
  })
  return out
}

// What is open: deadlines not met, and boxes not set aside.
function openOf(s) {
  var due = s.deadlines.filter(function (d) { return d.status === "open" })
  var boxes = s.tasks.filter(function (t) { return !(t.anchor > 0) && !t.away && !t.done })
  return { due: due, boxes: boxes }
}

// The strip's chips: a course for each that has something open, in the
// order of the course bands, with how much it holds of what the words
// keep — and any course picked though nothing is open in it. With them,
// how much the list holds now (`shown`) against all that is open
// (`total`), the agent's proposals the lens keeps (`asks`, for the
// agent's chip) and those it leaves out (`outside`).
// Each chip says too what it holds by what it asks, and its next
// deadline, for the strip unfolded.
function courses(s) {
  var all = openOf(s)
  var keys = courseKeys(s, [all.due, all.boxes])
  for (var l = 0; l < (s.lens || []).length; l++) if (keys.indexOf(s.lens[l]) < 0) keys.push(s.lens[l])
  var worded = openOf(narrowed({ deadlines: s.deadlines, tasks: s.tasks, projects: s.projects, proposals: [], raised: [],
                                 query: String(s.query || "").split(/\s+/).filter(function (w) { return w.charAt(0) !== "#" }).join(" ") }))
  var chips = []
  for (var c = 0; c < keys.length; c++) {
    var key = keys[c]
    var mine = function (x) { return (x.project || "") === key }
    var due = worded.due.filter(mine), boxes = worded.boxes.filter(mine)
    var doing = boxes.filter(function (t) { return t.when !== "" || t.due !== "" }).length
    var next = due.slice().sort(function (a, b) { return a.due - b.due })[0] || null
    chips.push({ tag: key, label: key === "" ? "none" : key, name: bandName(key, all.boxes.filter(mine), s.projects),
                 count: due.length + boxes.length, due: due.length, doing: doing, later: boxes.length - doing,
                 next: next ? { title: next.title, due: next.due } : null })
  }
  var kept = narrowed(s), now = openOf(kept)
  var props = s.proposals || [], asks = kept.proposals || []
  return { chips: chips, total: all.due.length + all.boxes.length, shown: now.due.length + now.boxes.length,
           asks: asks, outside: props.length - asks.length }
}

// The agent's proposals and questions, as rows (docs/agent.md): each right
// under the box it is about, so the decision is made where the box is;
// one about a box not on the list waits under "from the agent".
function withProposals(rows, props, tasks) {
  if (!props || props.length === 0) return rows
  var byKey = {}, used = {}
  for (var i = 0; i < props.length; i++) {
    var k = props[i].key
    if (k) (byKey[k] = byKey[k] || []).push(props[i])
  }
  var out = []
  for (var r = 0; r < rows.length; r++) {
    out.push(rows[r])
    var t = rows[r].kind === "task" ? rows[r].task
      : rows[r].kind === "deadline" ? taskOfAnchor(tasks, rows[r].deadline.id) : null
    var mine = t && t.key ? byKey[t.key] : null
    if (!mine) continue
    for (var m = 0; m < mine.length; m++) {
      if (used[mine[m].id]) continue
      used[mine[m].id] = true
      out.push({ kind: Say.askKind(mine[m]), item: mine[m], task: t })
    }
  }
  // A document to file, or a deadline found in the writing — about no box
  // yet — goes in its course's band, when the list has one. (A band's tag
  // has its #, a proposal's project not: until 2026-10-30 they were
  // compared as they were, never matched, and every one waited under
  // "from the agent".)
  for (var f = 0; f < props.length; f++) {
    if (used[props[f].id] || (props[f].kind !== "file" && props[f].kind !== "deadline") || !props[f].project) continue
    for (var b = 0; b < out.length; b++) {
      if (out[b].kind !== "head" || out[b].tag !== "#" + props[f].project) continue
      out.splice(b + 1, 0, { kind: Say.askKind(props[f]), item: props[f], task: null })
      used[props[f].id] = true
      break
    }
  }
  var rest = props.filter(function (x) { return !used[x.id] })
  if (rest.length === 0) return out
  var at = -1
  for (var h = 0; h < out.length; h++) if (out[h].kind === "head" && out[h].text === "FROM THE AGENT") at = h
  var extra = rest.map(function (x) {
    return { kind: Say.askKind(x), item: x, task: taskOfKey(tasks, x.key) }
  })
  if (at < 0) return out.concat([{ kind: "head", text: "FROM THE AGENT", tag: "" }]).concat(extra)
  return out.slice(0, at + 1).concat(extra).concat(out.slice(at + 1))
}
