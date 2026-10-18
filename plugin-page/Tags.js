// Tags.js — `#` offers the tags that exist, so a new tag is a choice, not a
// typo (2026-10-18; docs/plan.md, "Tag suggestions while typing").
//
// The tags that exist: every project's (its knowledge file's `Tag:`), then
// the tags written in the notes — in the open boxes the dashboard knows and
// in the note on screen — most used first. Pure; the page keeps the list
// (the `@` list, which calls projects, is drawn the same way).
.pragma library

var TAG_RE = /(^|\s)#([\w\/-]+)/g

function inText(text) {
  var out = []
  var m
  TAG_RE.lastIndex = 0
  while ((m = TAG_RE.exec(String(text || ""))) !== null) out.push(m[2])
  return out
}

// [{ tag, name, project }]: the projects first, in their order; then the
// other tags by how often they are written.
function known(projects, tasks, noteText) {
  var out = []
  var seen = {}
  for (var i = 0; i < (projects || []).length; i++) {
    var p = projects[i]
    if (!p || !p.tag || seen[p.tag.toLowerCase()]) continue
    seen[p.tag.toLowerCase()] = true
    out.push({ tag: p.tag, name: p.name || "", project: true })
  }
  var count = {}
  var spelled = {}
  function add(t) {
    var k = t.toLowerCase()
    if (seen[k]) return
    count[k] = (count[k] || 0) + 1
    if (!spelled[k]) spelled[k] = t
  }
  for (var j = 0; j < (tasks || []).length; j++) (tasks[j].tags || []).forEach(add)
  inText(noteText).forEach(add)
  Object.keys(count).sort(function (a, b) { return count[b] - count[a] || (a < b ? -1 : 1) })
    .forEach(function (k) { out.push({ tag: spelled[k], name: "", project: false }) })
  return out
}

// What `#q` offers: the tags with q in them (a project also by its name),
// those starting with it first. Nothing once q is a tag already — Enter
// there is a new line, not a completion — and nothing for an empty q, so
// starting a heading never flashes a list.
function suggest(tags, q) {
  q = String(q || "").toLowerCase()
  if (q === "") return []
  if (tags.some(function (t) { return t.tag.toLowerCase() === q })) return []
  var starts = [], within = []
  for (var i = 0; i < tags.length; i++) {
    var t = tags[i]
    var tag = t.tag.toLowerCase()
    if (tag.indexOf(q) === 0) starts.push(t)
    else if (tag.indexOf(q) > 0 || (t.name && t.name.toLowerCase().indexOf(q) >= 0)) within.push(t)
  }
  return starts.concat(within).slice(0, 8)
}
