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

// ------------------------------------------------------- a new project

// Making a project (2026-10-22, agent/projects.py): a tag the runner takes,
// and whether `#q` may be offered as one — a word that starts with a
// letter, so `#1` (an issue, a number) never asks to be a project.
function isTag(t) {
  return /^[\w\/-]{1,40}$/.test(String(t || ""))
}

function canMake(q) {
  return isTag(q) && /^[A-Za-z]/.test(q)
}

// Whether a project goes by this tag already, whatever its case.
function isProject(projects, tag) {
  var low = String(tag || "").toLowerCase()
  return (projects || []).some(function (p) { return p && String(p.tag).toLowerCase() === low })
}

// The sidebar's field: "Master Thesis #thesis" names both; without a #tag,
// the name's words, lowercased and joined by `-`, are its tag. { name,
// tag, taken } — tag "" while there is nothing to make.
function fromField(text, projects) {
  var s = String(text || "")
  var m = s.match(/(^|\s)#([\w\/-]+)\s*$/)
  var name = (m ? s.slice(0, m.index) : s).replace(/\s+/g, " ").trim().slice(0, 80)
  var tag = m ? m[2] : (name.toLowerCase().match(/[a-z0-9]+/g) || []).join("-").slice(0, 40).replace(/-+$/, "")
  if (!isTag(tag)) tag = ""
  return { name: name || tag, tag: tag, taken: tag !== "" && isProject(projects, tag) }
}

// ------------------------------------------------ reaching a project

// Reaching a project by its letters (plan.md item 19, 2026-11-17): in the
// sidebar `#` and the letters, and the switcher (Ctrl+O). The projects
// whose tag starts with q, then those with a word of the name starting
// with it, then those with q anywhere in the tag or name; each group in
// the list's own order. A leading `#` is the key that started it, not a
// letter of the tag. An empty q is every project, as listed.
// Accents aside, as the files' filter: "fhoo" finds "FHOÖ", "ö" finds "o".
function _fold(s) { return String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase() }

function reach(projects, q) {
  q = _fold(String(q || "").replace(/^#/, ""))
  var list = (projects || []).filter(function (p) { return p && p.tag })
  if (q === "") return list.slice()
  var starts = [], word = [], within = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var tag = _fold(p.tag)
    var name = _fold(p.name)
    if (tag.indexOf(q) === 0) starts.push(p)
    else if (name.split(/[^\w]+/).some(function (w) { return w !== "" && w.indexOf(q) === 0 })) word.push(p)
    else if (tag.indexOf(q) > 0 || name.indexOf(q) >= 0) within.push(p)
  }
  return starts.concat(word, within)
}

// The projects in the order they are used (plan.md item 19): the most
// reached in the last four weeks first, so the project used most stops
// sitting last behind those with a session soon. `uses` is { tag: [epoch
// seconds] }, the times each was reached (opened, a section started, its
// page, its tag put, by any of the ways in); ties keep the runner's order,
// soonest session first, which is also the whole order before anything is
// used. A count over weeks, not the last one used, so the order — and the
// Alt+digit of each — moves slowly.
var USE_WINDOW = 28 * 86400

function byUse(projects, uses, nowSec) {
  var since = nowSec - USE_WINDOW
  var list = (projects || []).slice()
  var score = list.map(function (p) {
    return ((uses || {})[p.tag] || []).filter(function (t) { return t > since }).length
  })
  var idx = list.map(function (p, i) { return i })
  idx.sort(function (a, b) { return score[b] - score[a] || a - b })
  return idx.map(function (i) { return list[i] })
}

// One more use of tag at nowSec, and the uses older than the window let go.
function used(uses, tag, nowSec) {
  var since = nowSec - USE_WINDOW
  var out = {}
  for (var k in (uses || {})) {
    var kept = (uses[k] || []).filter(function (t) { return t > since })
    if (kept.length > 0) out[k] = kept
  }
  if (tag) out[tag] = (out[tag] || []).concat([nowSec])
  return out
}
