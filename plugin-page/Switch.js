.pragma library

// The switcher's matching (Ctrl+O; the switcher pass, 2026-11-28): the
// rules the sidebar's find already keeps (FilesPane.matches, Tags.reach),
// so a name is found the same way everywhere. Every word somewhere, case
// and accents aside ("thesis notes" finds projects/thesis/meeting-notes.md,
// "uber" finds "Über"); the name's own matches first, then shorter paths.

function fold(s) { return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase() }

function words(q) { return fold(q).split(/\s+/).filter(function (w) { return w !== "" }) }

function hasAll(hay, ws) {
  for (var i = 0; i < ws.length; i++) if (hay.indexOf(ws[i]) < 0) return false
  return true
}

// A view or action row: every word in its title, what it is about, or the
// words it is also known by.
function viewMatches(v, q) {
  var ws = words(q)
  return ws.length > 0 && hasAll(fold(v.title + " " + (v.sub || "") + " " + (v.keywords || "")), ws)
}

// The vault's notes and papers that hold every word in their path (or a
// paper's name and title, `names[rel]`: { name, title }), at most `max`.
// `isDay(stem)` says which notes in `daily` (its folder) are days; the
// agent's folder (`agentRoot`) is not the student's. A day is newest first
// among equals; any other file A to Z.
function files(paths, q, opts) {
  var ws = words(q)
  if (!paths || ws.length === 0) return []
  var daily = opts.daily || "", agentRoot = opts.agentRoot || "", names = opts.names || {}
  var scored = []
  for (var i = 0; i < paths.length; i++) {
    var rel = paths[i]
    if (!/\.(md|pdf)$/i.test(rel)) continue
    if (agentRoot !== "" && (rel === agentRoot || rel.indexOf(agentRoot + "/") === 0)) continue
    var named = names[rel]
    var shown = named ? fold(named.name + " " + (named.title || "")) : ""
    var relF = fold(rel)
    if (!hasAll(relF + " " + shown, ws)) continue
    var slash = rel.lastIndexOf("/")
    var stem = rel.slice(slash + 1).replace(/\.(md|pdf)$/i, "")
    var stemF = fold(stem)
    var inName = 0
    for (var k = 0; k < ws.length; k++) if (stemF.indexOf(ws[k]) >= 0 || shown.indexOf(ws[k]) >= 0) inName++
    var isPdf = /\.pdf$/i.test(rel)
    var inDaily = !isPdf && daily !== "" && rel.indexOf(daily + "/") === 0 && rel.slice(daily.length + 1).indexOf("/") < 0
    var isDay = inDaily && (!opts.isDay || opts.isDay(stem))
    var folder = slash > 0 ? rel.slice(0, slash) : ""
    scored.push({
      score: (stemF.indexOf(ws[0]) === 0 || shown.indexOf(ws[0]) === 0 ? 3000 : 0) + inName * 1000 - rel.length,
      day: isDay, rel: rel,
      item: {
        kind: "file", tag: "", path: rel, date: isDay ? stem : "",
        title: named && named.name ? named.name : stem,
        sub: isDay ? "daily note" : named && named.title ? named.title : (folder || rel),
        hint: isPdf ? "pdf" : isDay ? "day" : "note"
      }
    })
  }
  scored.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score
    if (a.day && b.day) return a.rel < b.rel ? 1 : a.rel > b.rel ? -1 : 0
    return a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0
  })
  return scored.slice(0, opts.max || 6).map(function (x) { return x.item })
}

// Where in `s` each word of `q` is, accents aside: [{ a, b }] in s's own
// letters, in order, none overlapping.
function spans(s, q) {
  s = String(s || "")
  var ws = words(q)
  if (ws.length === 0 || s === "") return []
  // The folded letters, each with the letter of `s` it came from.
  var f = "", at = []
  for (var i = 0; i < s.length; i++) {
    var c = fold(s.charAt(i))
    for (var j = 0; j < c.length; j++) { f += c.charAt(j); at.push(i) }
  }
  var marks = []
  ws.forEach(function (w) {
    var from = 0, k
    while ((k = f.indexOf(w, from)) >= 0) {
      marks.push({ a: at[k], b: at[k + w.length - 1] + 1 })
      from = k + w.length
    }
  })
  marks.sort(function (x, y) { return x.a - y.a || y.b - x.b })
  var out = []
  marks.forEach(function (m) {
    var last = out[out.length - 1]
    if (last && m.a <= last.b) last.b = Math.max(last.b, m.b)
    else out.push({ a: m.a, b: m.b })
  })
  return out
}

function _esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

// `s` as rich text with the words of `q` in bold: what was matched, seen
// at a glance.
function marked(s, q) {
  s = String(s || "")
  var sp = spans(s, q)
  var out = "", at = 0
  sp.forEach(function (m) {
    out += _esc(s.slice(at, m.a)) + "<b>" + _esc(s.slice(m.a, m.b)) + "</b>"
    at = m.b
  })
  return out + _esc(s.slice(at))
}

// The first of the words in a line, to select on landing there: { a, b }
// or null.
function firstSpan(s, q) {
  var sp = spans(s, q)
  return sp.length > 0 ? sp[0] : null
}
