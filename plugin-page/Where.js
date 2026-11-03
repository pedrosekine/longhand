// Where — the path Ctrl+Shift+C copies, so a file in Longhand can be handed
// to an agent outside it (2026-11-03; `tests/tst_where.qml` holds it). An
// agent reads `path:line` and `path:first-last`, and opens the file on
// disk, so the line is the file's: the frontmatter and the agent link line
// the page keeps out of the editor (`before`) are counted too.
.pragma library

// The 1-based line of the file that offset `pos` of `text` falls on.
function lineAt(text, pos) {
  var n = 1
  for (var i = 0; i < pos && i < text.length; i++) if (text.charAt(i) === "\n") n++
  return n
}

// `from` and `to` are offsets into the editor's text (`body`); `to` only
// when lines are selected. A selection that ends at a line's very start
// does not take that line, as an editor's selection of whole lines does not.
function at(path, before, body, from, to) {
  var t = before + body
  var first = lineAt(t, before.length + from)
  if (to === undefined || to <= from) return path + ":" + first
  var end = before.length + to
  var last = lineAt(t, end)
  if (last > first && t.charAt(end - 1) === "\n") last--
  return path + ":" + (last > first ? first + "-" + last : first)
}
