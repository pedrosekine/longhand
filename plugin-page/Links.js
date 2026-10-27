// Links — what a note points at, and where that is (docs/files.md,
// "Rendering", 2026-10-27).
//
// Three forms, as Obsidian writes them:
//   [[target]], [[target|alias]], [[target#heading]], [[#heading]],
//   [[target#^block]]                      a wikilink
//   ![[name.png]], ![[name.png|300]]       an embed (an image, here)
//   [text](path or url), ![alt](path)      a markdown link or image
//
// Resolving is Obsidian's rule, which is what the vault was written
// against: a target with a folder in it is a path from the vault's root; a
// bare name is matched by file name, case aside, and when several files
// share it the one at the vault's root wins (Obsidian's own, on purpose: a
// name means the same note everywhere), then the one in the note's own
// folder, else the shortest path.
// A markdown link's path is relative to the note (with %20 for spaces),
// else from the root. The index is a list of the vault's paths, read when a
// note first needs it (Page.qml); this file only reads and decides.
.pragma library

var IMAGE_RE = /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i
var WIKI_EMBED_LINE = /^!\[\[([^\]|#]+?)(?:\|([^\]]*))?\]\]\s*$/
var MD_IMAGE_LINE = /^!\[([^\]]*)\]\(\s*<?([^)>]+?)>?(?:\s+"([^"]*)")?\s*\)\s*$/

// A line that is only an image: { target, width, alt, wiki } or null.
// `width` is Obsidian's `|300` (or `|300x200`, of which the width counts).
function imageLine(line) {
  var t = String(line).trim(), m
  if ((m = t.match(WIKI_EMBED_LINE)) && IMAGE_RE.test(m[1].trim())) {
    var size = (m[2] || "").match(/^\s*(\d+)(?:x\d+)?\s*$/)
    return { target: m[1].trim(), width: size ? parseInt(size[1], 10) : 0, alt: size ? "" : (m[2] || "").trim(), wiki: true }
  }
  if ((m = t.match(MD_IMAGE_LINE)) && !/^[a-z]+:\/\//i.test(m[2]) && IMAGE_RE.test(m[2].trim())) {
    var alt = m[1].trim(), w = alt.match(/^(.*?)\|(\d+)$/)
    return { target: decode(m[2].trim()), width: w ? parseInt(w[2], 10) : 0, alt: w ? w[1].trim() : alt, wiki: false }
  }
  return null
}

// The links inside a line's words, in order, each with its place:
// { at, end, inner: [a, b], target, heading, kind: "wiki" | "md" | "embed",
//   url }. `inner` is what is shown when the link is drawn: the alias, else
// the target as written. An external url (`[text](https://…)`) is a link
// too, with `url` set; it is opened, never resolved.
function inLine(s) {
  s = String(s)
  var out = []
  var re = /(!?)\[\[([^\[\]\n]+?)\]\]|(!?)\[([^\[\]\n]*)\]\(\s*<?([^()\s>]+(?:\([^()\s]*\))?[^()\s>]*)>?(?:\s+"[^"]*")?\s*\)/g
  var m
  while ((m = re.exec(s)) !== null) {
    if (m[2] !== undefined) {
      var body = m[2], bar = body.indexOf("|")
      var target = bar >= 0 ? body.substring(0, bar) : body
      var hash = target.indexOf("#")
      var start = m.index + m[1].length + 2
      out.push({ at: m.index, end: m.index + m[0].length, kind: m[1] ? "embed" : "wiki",
                 inner: bar >= 0 ? [start + bar + 1, start + body.length] : [start, start + body.length],
                 target: (hash >= 0 ? target.substring(0, hash) : target).trim(),
                 heading: hash >= 0 ? target.substring(hash + 1).trim() : "", url: "" })
    } else {
      var text = m[4], dest = m[5]
      var open = m.index + m[3].length + 1
      var ext = /^[a-z][a-z0-9+.-]*:/i.test(dest)
      var h = ext ? -1 : dest.indexOf("#")
      out.push({ at: m.index, end: m.index + m[0].length, kind: m[3] ? "embed" : "md",
                 inner: text === "" ? [open, open] : [open, open + text.length],
                 target: ext ? "" : decode(h >= 0 ? dest.substring(0, h) : dest),
                 heading: h >= 0 ? decode(dest.substring(h + 1)) : "", url: ext ? dest : "" })
    }
  }
  return out
}

function decode(s) {
  try { return decodeURIComponent(s) } catch (e) { return s }
}

// The link holding column `col`, strictly inside it (its edges are the
// words around it), or null.
function at(links, col) {
  for (var i = 0; i < links.length; i++) if (col > links[i].at && col < links[i].end) return links[i]
  return null
}

function folderOf(rel) { var i = rel.lastIndexOf("/"); return i < 0 ? "" : rel.substring(0, i) }
function baseOf(rel) { return rel.substring(rel.lastIndexOf("/") + 1) }

// Collapse `a/./b` and `a/x/../b`; null when it climbs out of the vault.
function normal(path) {
  var out = []
  var parts = path.split("/")
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    if (p === "" || p === ".") continue
    if (p === "..") { if (out.length === 0) return null; out.pop() }
    else out.push(p)
  }
  return out.join("/")
}

// The index: { paths: [rel], byName: { lowercased file name: [rel] } }.
function index(paths) {
  var byName = {}
  for (var i = 0; i < paths.length; i++) {
    var k = baseOf(paths[i]).toLowerCase()
    ;(byName[k] = byName[k] || []).push(paths[i])
  }
  return { paths: paths, byName: byName, all: makeSet(paths) }
}

function makeSet(paths) {
  var s = {}
  for (var i = 0; i < paths.length; i++) s[paths[i]] = true
  return s
}

// Where `target` (as written in the note at `from`) is, or "". `wiki`:
// Obsidian's name rule, with `.md` added when the name has no extension;
// else a path relative to the note, then from the root.
function resolve(idx, target, from, wiki) {
  if (!idx || target === "") return ""
  var dir = folderOf(from)
  if (!wiki) {
    var rel = normal((dir === "" ? "" : dir + "/") + target)
    if (rel !== null && idx.all[rel]) return rel
    var root = normal(target)
    return root !== null && idx.all[root] ? root : ""
  }
  var name = /\.[A-Za-z0-9]+$/.test(baseOf(target)) ? target : target + ".md"
  if (name.indexOf("/") >= 0) {
    var exact = normal(name)
    if (exact !== null && idx.all[exact]) return exact
    // Obsidian also accepts a partial path that ends a real one.
    var tail = "/" + name.toLowerCase()
    var hits = idx.paths.filter(function (p) { return ("/" + p.toLowerCase()).slice(-tail.length) === tail })
    return shortest(hits, dir)
  }
  return shortest(idx.byName[name.toLowerCase()] || [], dir)
}

function shortest(hits, dir) {
  if (hits.length === 0) return ""
  for (var r = 0; r < hits.length; r++) if (hits[r].indexOf("/") < 0) return hits[r]
  for (var i = 0; i < hits.length; i++) if (folderOf(hits[i]) === dir) return hits[i]
  return hits.slice().sort(function (a, b) { return a.length - b.length || (a < b ? -1 : 1) })[0]
}
