.pragma library

// A turn of the chat, drawn as rich text (2026-11-19, chat readability,
// design A in docs/explorations/chat-readability/). Qt's own markdown
// import gives a TextEdit no say over line height, and puts no space
// between paragraphs at all, so an answer of three paragraphs read as one
// block at 1.2 leading. Rich text takes both, so the chat's markdown is
// turned into the little HTML Qt draws: paragraphs, headings (as bold
// lines), lists, quotes, code, rules; bold, italic, code, strikethrough,
// links. A table is the one thing left to Qt's markdown: `html` returns ""
// and the turn falls back to it.
//
// A quote of the paper, [“its words” (p. 9)](quote:…), is drawn as prose —
// the words in the text's own colour, no underline — and only its page in
// the accent: the colour marks where to click without taking the reading.
//
// style: { fg, accent, code (a family), leading (Qt's line-height, in % of
// the font's own line), gap (px after a paragraph) }

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// The words of one line or paragraph, inline markdown to HTML.
function inline(text, style) {
  var keep = []
  function hold(h) { keep.push(h); return "\u0000" + (keep.length - 1) + "\u0001" }
  var t = String(text)
  // Code first: inside it, brackets and stars are only themselves.
  t = t.replace(/`([^`\n]+)`/g, function (m, c) {
    return hold("<code style=\"font-family:'" + style.code + "'\">" + esc(c) + "</code>")
  })
  t = t.replace(/(^|[^!])\[([^\]\n]+)\]\(([^)\s]+)\)/g, function (m, pre, label, href) {
    return pre + hold(link(label, href, style))
  })
  t = t.replace(/<(https?:\/\/[^>\s]+)>/g, function (m, href) { return hold(link(href, href, style)) })
  t = esc(t)
  t = t.replace(/\*\*([^*\n]+?)\*\*/g, "<b>$1</b>").replace(/__([^_\n]+?)__/g, "<b>$1</b>")
  t = t.replace(/(^|[^*\w])\*([^*\s][^*\n]*?)\*(?!\*)/g, "$1<i>$2</i>")
    .replace(/(^|[^_\w])_([^_\s][^_\n]*?)_(?![_\w])/g, "$1<i>$2</i>")
  t = t.replace(/~~([^~\n]+?)~~/g, "<s>$1</s>")
  return t.replace(/\u0000(\d+)\u0001/g, function (m, i) { return keep[parseInt(i)] })
}

function link(label, href, style) {
  var h = esc(href)
  if (/^quote:/.test(href)) {
    var m = /^([\s\S]*?)\s*\((p\.\s*\d+)\)\s*$/.exec(label)
    var words = m ? m[1] : label, page = m ? m[2] : ""
    return "<a href=\"" + h + "\" style=\"color:" + style.fg + ";text-decoration:none\">" + inline(words, style)
      + (page ? " <span style=\"color:" + style.accent + "\">(" + esc(page).replace(/\s+/, "&nbsp;") + ")</span>" : "")
      + "</a>"
  }
  return "<a href=\"" + h + "\" style=\"color:" + style.accent + "\">" + inline(label, style) + "</a>"
}

function para(style, last) {
  return "line-height:" + style.leading + "%;margin-top:0;margin-bottom:" + (last ? 0 : style.gap) + "px"
}

// Plain words (the student's own): their lines kept, at the chat's leading.
function plain(text, style) {
  var ps = String(text).split(/\n{2,}/)
  return ps.map(function (p, i) {
    return "<p style=\"" + para(style, i === ps.length - 1) + "\">" + esc(p).replace(/\n/g, "<br/>") + "</p>"
  }).join("")
}

function html(md, style) {
  var lines = String(md || "").replace(/\r/g, "").split("\n")
  // A table: Qt's markdown draws it; this does not try.
  for (var k = 0; k + 1 < lines.length; k++)
    if (/^\s*\|.*\|\s*$/.test(lines[k]) && /^\s*\|?\s*:?-{3,}/.test(lines[k + 1])) return ""
  var blocks = []                       // { kind, text | items | code }
  var i = 0
  while (i < lines.length) {
    var line = lines[i]
    if (/^\s*$/.test(line)) { i++; continue }
    var fence = /^\s*(```|~~~)/.exec(line)
    if (fence) {
      var code = []
      i++
      while (i < lines.length && lines[i].trim().indexOf(fence[1]) !== 0) code.push(lines[i++])
      i++
      blocks.push({ kind: "code", code: code.join("\n") })
      continue
    }
    var h = /^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/.exec(line)
    if (h) { blocks.push({ kind: "head", text: h[1] }); i++; continue }
    if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) { blocks.push({ kind: "rule" }); i++; continue }
    if (/^\s{0,3}>/.test(line)) {
      var q = []
      while (i < lines.length && /^\s{0,3}>/.test(lines[i])) q.push(lines[i++].replace(/^\s{0,3}>\s?/, ""))
      blocks.push({ kind: "quote", text: q.join("\n") })
      continue
    }
    var item = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/.exec(line)
    if (item) {
      var items = []
      while (i < lines.length) {
        var it = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/.exec(lines[i])
        if (it) { items.push({ depth: Math.floor(it[1].replace(/\t/g, "  ").length / 2), ordered: /\d/.test(it[2]), text: it[3] }); i++; continue }
        // A line under an item, indented or not, is more of that item,
        // until a blank line.
        if (!/^\s*$/.test(lines[i]) && items.length > 0) { items[items.length - 1].text += " " + lines[i].trim(); i++; continue }
        break
      }
      blocks.push({ kind: "list", items: items })
      continue
    }
    var p = []
    while (i < lines.length && !/^\s*$/.test(lines[i]) && !/^\s*(```|~~~)/.test(lines[i])
           && !/^\s{0,3}#{1,6}\s/.test(lines[i]) && !/^\s{0,3}>/.test(lines[i])
           && !(p.length > 0 && /^\s*([-*+]|\d+[.)])\s+/.test(lines[i])))
      p.push(lines[i++])
    blocks.push({ kind: "para", text: p.join("\n") })
  }

  function words(t) {
    // A hard break (two spaces, or a backslash, at the line's end) stays one;
    // any other newline is a space, as markdown has it.
    return inline(t.replace(/( {2,}|\\)\n/g, "\u0002").replace(/\n/g, " "), style).replace(/\u0002/g, "<br/>")
  }
  function list(items, last) {
    var out = "", stack = []
    items.forEach(function (it) {
      while (stack.length > it.depth + 1) out += stack.pop() ? "</ol>" : "</ul>"
      while (stack.length < it.depth + 1) {
        out += (it.ordered ? "<ol" : "<ul") + " style=\"margin-top:0;margin-bottom:" + (stack.length === 0 && !last ? style.gap : 0) + "px\">"
        stack.push(it.ordered)
      }
      out += "<li style=\"line-height:" + style.leading + "%;margin-bottom:" + Math.round(style.gap / 3) + "px\">" + words(it.text) + "</li>"
    })
    while (stack.length > 0) out += stack.pop() ? "</ol>" : "</ul>"
    return out
  }

  return blocks.map(function (b, n) {
    var last = n === blocks.length - 1
    if (b.kind === "code")
      return "<pre style=\"font-family:'" + style.code + "';margin-top:0;margin-bottom:" + (last ? 0 : style.gap) + "px\">" + esc(b.code) + "</pre>"
    if (b.kind === "head") return "<p style=\"" + para(style, last) + "\"><b>" + words(b.text) + "</b></p>"
    if (b.kind === "rule") return "<hr/>"
    if (b.kind === "quote")
      return "<p style=\"" + para(style, last) + ";margin-left:14px;color:" + (style.dim || style.fg) + "\">" + words(b.text) + "</p>"
    if (b.kind === "list") return list(b.items, last)
    return "<p style=\"" + para(style, last) + "\">" + words(b.text) + "</p>"
  }).join("")
}
