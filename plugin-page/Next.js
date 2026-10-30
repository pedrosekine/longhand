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
// Note boxes group by project rather than by the day they were written,
// because the day a thought was written is not how it is looked for
// (2026-10-15, and the 31 trips to the calendar before it). A box bound to
// the store is listed once, as its deadline.
function rows(s) {
  var now = s.now || new Date()
  var rows = []
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
  if (due.length > 0) {
    rows.push({ kind: "head", text: "DUE", tag: "" })
    var month = ""
    for (var k = 0; k < due.length; k++) {
      var lbl = Say.monthLabel(due[k].due * 1000, now)
      if (lbl !== month) { rows.push({ kind: "month", text: lbl }); month = lbl }
      rows.push({ kind: "deadline", deadline: due[k] })
    }
  }
  if (waiting.length > 0) {
    waiting.sort(function (a, b) { return a.due - b.due })
    rows.push({ kind: "head", text: "NOT IN A NOTE YET", tag: "" })
    for (var w = 0; w < waiting.length; w++) rows.push({ kind: "deadline", deadline: waiting[w] })
  }

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
  if (doing.length > 0) {
    rows.push({ kind: "head", text: "DOING", tag: "" })
    var dm = ""
    for (var d1 = 0; d1 < doing.length; d1++) {
      var dl1 = Say.monthLabel(Say.taskMs(doing[d1]), now)
      if (dl1 !== dm) { rows.push({ kind: "month", text: dl1 }); dm = dl1 }
      rows.push({ kind: "task", task: doing[d1] })
    }
  }
  if (later.length > 0) {
    rows.push({ kind: "head", text: "TO SCHEDULE", tag: "" })
    for (var l = 0; l < later.length; l++) rows.push({ kind: "task", task: later[l] })
  }

  var groups = [], seen = ({})
  for (var n = 0; n < notes.length; n++) {
    var key = notes[n].project || ""
    if (seen[key] === undefined) { seen[key] = groups.length; groups.push({ key: key, items: [] }) }
    groups[seen[key]].items.push(notes[n])
  }
  for (var g = 0; g < groups.length; g++) {
    // The course's own name, not its tag: a band that reads
    // "Interdisciplinary Seminar" says more than #intsem. The sidebar
    // knows the names from the curriculum; for a tag it does not know,
    // the heading the notes themselves use is the next best name.
    var gk = groups[g].key
    var named = gk === "" ? "No project" : Say.courseName(gk, s.projects)
    if (gk !== "" && named === gk) {
      for (var h = 0; h < groups[g].items.length; h++) {
        var path0 = (groups[g].items[h].path || [])[0]
        if (path0) { named = path0; break }
      }
    }
    rows.push({ kind: "head", text: named, tag: gk === "" ? "" : "#" + gk })
    // Under a band, a row does not repeat it: the section it was written
    // in is what the row still has to say.
    for (var m = 0; m < groups[g].items.length; m++)
      rows.push({ kind: "task", task: groups[g].items[m], under: named })
  }
  // What is away and what is owed a grade, each folded into one row until
  // asked for: there to be found, never in the way.
  if (shelf.length > 0) {
    if (!s.showShelf) rows.push({ kind: "shelf", count: shelf.length })
    else {
      rows.push({ kind: "head", text: "SET ASIDE", tag: "" })
      for (var sh = 0; sh < shelf.length; sh++) rows.push({ kind: "task", task: shelf[sh] })
    }
  }
  var grading = s.deadlines.filter(function (d) {
    return d.status === "done" && d.grade === "" && d.doneAt * 1000 < today.getTime()
  })
  if (grading.length > 0) {
    if (!s.showGrading) rows.push({ kind: "grading", count: grading.length })
    else {
      grading.sort(function (a, b) { return b.doneAt - a.doneAt })
      rows.push({ kind: "head", text: "WAITING FOR A GRADE", tag: "" })
      for (var gr = 0; gr < grading.length; gr++) rows.push({ kind: "deadline", deadline: grading[gr] })
    }
  }
  var raised = s.raised || []
  if (raised.length > 0) {
    rows.push({ kind: "head", text: "FROM THE AGENT", tag: "" })
    for (var j = 0; j < raised.length; j++) rows.push({ kind: "raised", item: raised[j] })
  }
  return withProposals(rows, s.proposals, s.tasks)
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
