.pragma library

// A question's answer, for hovering it on the page (plan.md item 18's
// sibling, 2026-11-16: "for every question I ask, can the same hover show
// the answer?"). The paper's conversation keeps which marks each message
// pointed at (`marks: ["h2"]`); the agent's turn after it is the answer.
// Asked together, the answer comes in parts, each opened by a line that is
// only its mark's name (`h3:`, the runner asks for that): each question
// gets its own part. Nothing is written: this reads the conversation.

// The first exchange that answered mark `id`: { student, agent (turn
// indexes), asked (the question's words, as typed), text (its part of the
// answer), more (the agent's answers after it, up to the next question about
// a mark: the conversation that went on about it) }, or null when none has.
// (2026-11-27: every answer after it in the paper counted, and the first
// question asked seemed to have fourteen answers more.)
function forMark(turns, id) {
  turns = turns || []
  for (var i = 0; i + 1 < turns.length; i++) {
    var a = turns[i], b = turns[i + 1]
    if (a.role !== "student" || !a.marks || a.marks.indexOf(id) < 0) continue
    if (b.role !== "agent" || b.error || !b.text) continue
    var more = 0
    for (var k = i + 2; k < turns.length; k++) {
      if (turns[k].role === "student" && turns[k].marks && turns[k].marks.length > 0) break
      if (turns[k].role === "agent" && !turns[k].error) more++
    }
    return { student: i, agent: i + 1, asked: asked(a.text, id), text: part(b.text, id, a.marks), more: more }
  }
  return null
}

// What was asked about mark `id`, in the words typed. Waiting questions
// asked together (Paper.qml's askWaiting: "My waiting questions, one by
// one:" and a line "- h5: its note" each) were typed as their notes: its
// line's note, or "" when it had none — the passage marked is the question.
function asked(text, id) {
  text = String(text || "").trim()
  if (!/^My (question|waiting questions)[^\n]*:\s*\n/.test(text)) return text
  var lines = text.split("\n")
  for (var i = 1; i < lines.length; i++) {
    var m = /^\s*-\s*(h\d+)(?::\s*(.*))?$/.exec(lines[i])
    if (m && m[1] === id) return (m[2] || "").trim()
  }
  return ""
}

// A line that opens one question's part: `h3:`, maybe bold or in code,
// maybe with the answer's first words after it.
var LABEL = /^\s*[*_`#\s]*(h\d+)[*_`]*\s*:[*_`]*\s*(.*)$/

// Mark `id`'s part of an answer to marks `ids`. One mark: the whole. Several:
// from its name's line to the next name's; the whole when its name is not
// there (the answer did not keep to the parts).
function part(text, id, ids) {
  text = String(text || "")
  if (!ids || ids.length < 2) return text.trim()
  var lines = text.split("\n"), out = null
  for (var i = 0; i < lines.length; i++) {
    var m = LABEL.exec(lines[i])
    if (m && ids.indexOf(m[1]) >= 0) {
      if (out !== null) break
      if (m[1] === id) out = m[2] ? [m[2]] : []
      continue
    }
    if (out !== null) out.push(lines[i])
  }
  return out === null ? text.trim() : out.join("\n").trim()
}

// An answer as a tip says it: plain words (no markdown marks, a quote's
// words kept), its first sentences up to `max` characters, cut at a word
// with "…" when longer. { text, cut }.
function gist(text, max) {
  max = max || 240
  var t = String(text || "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/^\s*>\s?/gm, "")
    .replace(/^\s*#+\s*/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "")
    .replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, "$1$2")
    .replace(/(^|[\s(])[*_]([^*_\n]+)[*_](?=[\s).,;:!?]|$)/g, "$1$2")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/\s+/g, " ")
    .trim()
  if (t.length <= max) return { text: t, cut: false }
  // Whole sentences while they fit, else the first cut at a word.
  var re = /[.!?](["”’)]*)\s+(?=[A-Z“"(])/g, end = -1, m
  while ((m = re.exec(t)) !== null) {
    var at = m.index + 1 + m[1].length
    if (at > max) break
    end = at
  }
  if (end >= max * 0.4) return { text: t.slice(0, end), cut: true }
  var cut = t.lastIndexOf(" ", max)
  return { text: t.slice(0, cut > max * 0.5 ? cut : max).replace(/[\s,;:]+$/, "") + "…", cut: true }
}
