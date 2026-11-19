import QtQuick
import "Shortcuts.js" as Sc
import "Answers.js" as Answers

// The paper's room (plan.md item 15, step 2), moved out of Page.qml on
// 2026-11-16 (plan item 4): what the agent's pane holds beside a PDF of the
// vault — its marks as a list, the marks attached to the next message, the
// strip, the keys. `page` is the page; the conversation itself is the note
// room's (Page.qml), its pane DayPane.qml.
Item {
  id: pp
  required property Item page
  visible: false

  // ------------------------------------------------- the paper's room
  //
  // Reading a paper (plan.md item 15, step 2, 2026-11-15): with a PDF of
  // the vault open, the agent's pane is the paper's — one conversation for
  // the whole paper, never one per mark ("shared context makes more sense",
  // the student). The pane turns between the paper's marks, as a list, and
  // its chat: Enter on a row goes to the chat with that mark attached, Esc
  // comes back. Above the list a strip: all, highlights, questions (the
  // waiting ones first); Ctrl+Enter asks every waiting question at once.
  // `^` in the box attaches a mark, as `@` points at a block.
  readonly property bool shown: page.pdfShown && page.pdfRel !== "" && page.pdfRel.charAt(0) !== "/"
  readonly property bool askable: pp.shown && page.pdfItem.read.text !== false && !page.pdfItem.read.private
  readonly property bool room: page.noteRoom && pp.shown
  property var marks: []          // attached to the next message
  property bool listing: true        // the list, or the chat
  property string filter: "all"   // "all", "h", "q"
  // The row the keys are on: -1 is the first, the paper as a whole (asked
  // about with nothing attached: 2026-11-15, the student found no way to
  // just chat with the paper), then the marks from 0.
  property int at: -1
  property var kept: []           // Space on rows: kept, to attach together
  Connections {
    target: pp.page
    function onPdfRelChanged() { pp.marks = []; pp.kept = []; pp.at = -1; pp.listing = true; pp.filter = "all" }
  }
  // Which marks have had an answer: pointed at by a message answered.
  readonly property var answered: {
    var out = ({})
    var t = pp.shown && page.noteTalk && page.noteTalk.turns ? page.noteTalk.turns : []
    for (var i = 0; i + 1 < t.length; i++)
      if (t[i].role === "student" && t[i].marks && t[i + 1].role === "agent" && !t[i + 1].error)
        for (var k = 0; k < t[i].marks.length; k++) out[t[i].marks[k]] = true
    return out
  }
  function markState(m) {
    if (m.kind !== "q") return m.note ? "note" : ""
    return pp.answered[m.id] ? "answered" : "waiting"
  }
  // The rows, as the strip shows them: in page order; questions with the
  // waiting ones first.
  readonly property var rows: {
    var ms = (page.pdfItem.read && page.pdfItem.read.marks) ? page.pdfItem.read.marks : []
    var f = pp.filter
    var rows = ms.filter(function (m) { return f === "all" || m.kind === f })
    if (f === "q") rows = rows.filter(function (m) { return pp.markState(m) === "waiting" })
      .concat(rows.filter(function (m) { return pp.markState(m) !== "waiting" }))
    return rows
  }
  readonly property var waiting: ((page.pdfItem.read && page.pdfItem.read.marks) ? page.pdfItem.read.marks : [])
    .filter(function (m) { return m.kind === "q" && !pp.answered[m.id] })
  function count(kind) {
    var ms = (page.pdfItem.read && page.pdfItem.read.marks) ? page.pdfItem.read.marks : []
    return ms.filter(function (m) { return kind === "all" || m.kind === kind }).length
  }
  function markById(id) { return page.pdfItem.markById(id) }
  function head(id) {
    var m = page.pdfItem.markById(id)
    if (!m) return id
    return "p. " + m.page + " “" + (m.text.length > 48 ? m.text.slice(0, 48) + "…" : m.text) + "”"
  }
  function attach(id) {
    if (!page.pdfItem.markById(id) || pp.marks.indexOf(id) >= 0) return
    pp.marks = pp.marks.concat([id])
  }
  function showList() {
    pp.listing = true
    page.dayMention = null
    Qt.callLater(function () { page.dayPaneItem.paperKeysRef.forceActiveFocus() })
  }
  function showChat() {
    pp.listing = false
    Qt.callLater(function () { page.dayPaneItem.dayFieldRef.forceActiveFocus() })
  }
  // A question just marked: its chat, with it attached, the words to come.
  function askAbout(id) {
    if (!pp.askable) return
    if (!pp.room) page.openRoom("", true)
    pp.marks = [id]
    pp.showChat()
  }
  // A question's answer, from its mark hovered in the PDF (2026-11-16): the
  // chat opened at the exchange that answered it, lit a moment. False when
  // none has.
  function answerOf(id) {
    return Answers.forMark(page.noteTalk && page.noteTalk.turns ? page.noteTalk.turns : [], id)
  }
  function showAnswer(id) {
    var a = pp.answerOf(id)
    if (!a || !pp.shown) return false
    if (!pp.room) page.openRoom("", true)
    pp.marks = []
    pp.listing = false
    Qt.callLater(function () { page.dayPaneItem.showTurn(a.student); page.dayPaneItem.dayFieldRef.forceActiveFocus() })
    page.used("paper-talk", "answer-shown")
    return true
  }
  // An acronym the paper never spells out (plan.md item 18): asked in the
  // paper's chat, as a guess. Asked because the person pressed for it, on
  // the acronym, never by hovering.
  function askAcronym(short) {
    if (!pp.askable) { page.showHint(page.pdfItem.read.private ? "a private PDF is never sent to the agent" : "this PDF has no words to ask about"); return false }
    if (!pp.room) page.openRoom("", true)
    pp.marks = []
    pp.listing = false
    Qt.callLater(function () {
      page.sendDay("What does “" + short + "” stand for in this paper? It never spells it out, so answer with your best guess and say that it is one.")
      pp.showChat()
    })
    page.used("paper-talk", "acronym")
    return true
  }
  function pick(i) {
    var n = pp.rows.length
    pp.at = Math.max(-1, Math.min(n - 1, i))
    if (pp.at >= 0) page.pdfItem.showMark(pp.rows[pp.at].id)
    else page.pdfItem.picked = ""
  }
  // To the mark in the PDF (2026-11-16): picked there, and the keys with
  // it, so m/q change its kind, n writes its note, x removes it — the way
  // to a mark the page will not let a click reach (one inside another).
  function edit(i) {
    pp.pick(i)
    if (pp.at < 0) return
    Qt.callLater(function () { page.pdfItem.keysRef.forceActiveFocus() })
  }
  // Every waiting question in one message, each by its name, the answer
  // to come back question by question (the runner asks for that).
  function askWaiting() {
    var w = pp.waiting
    if (w.length === 0) { page.showHint("no question is waiting"); return }
    pp.marks = w.map(function (m) { return m.id })
    var lines = w.map(function (m) { return "- " + m.id + (m.note ? ": " + m.note : "") })
    page.sendDay((w.length === 1 ? "My question:\n" : "My waiting questions, one by one:\n") + lines.join("\n"))
    pp.showChat()
    page.used("paper-talk", "ask-waiting")
  }
  function keyPressed(event) {
    if (page.anywhereKey(event)) return true
    var n = pp.rows.length
    if (Sc.hit(event, "paperAll")) { pp.filter = "all"; pp.at = -1; return true }
    if (Sc.hit(event, "paperHighlights")) { pp.filter = "h"; pp.at = -1; return true }
    if (Sc.hit(event, "paperQuestions")) { pp.filter = "q"; pp.at = -1; return true }
    if (Sc.hit(event, "paperAskWaiting")) { pp.askWaiting(); return true }
    if (Sc.hit(event, "paperUp")) { pp.pick(pp.at - 1); return true }
    if (Sc.hit(event, "paperDown")) { pp.pick(pp.at + 1); return true }
    if (Sc.hit(event, "paperKeep")) {
      var row = pp.rows[pp.at]
      if (!row) return true
      var i = pp.kept.indexOf(row.id)
      pp.kept = i >= 0 ? pp.kept.filter(function (x) { return x !== row.id }) : pp.kept.concat([row.id])
      return true
    }
    if (Sc.hit(event, "paperOpen")) {
      var r = pp.at >= 0 ? pp.rows[pp.at] : null
      var ids = pp.kept.length > 0 ? pp.kept.slice() : r ? [r.id] : []
      if (ids.length === 0) pp.marks = []      // the paper as a whole
      ids.forEach(pp.attach)
      pp.kept = []
      pp.showChat()
      return true
    }
    if (Sc.hit(event, "paperChat")) { pp.showChat(); return true }
    if (Sc.hit(event, "paperEdit")) { pp.edit(pp.at); return true }
    if (Sc.hit(event, "paperBack")) {
      if (pp.kept.length > 0) { pp.kept = []; return true }
      page.closeDay(); return true
    }
    // Typing in the list goes to the box, as a dashboard row's chat does.
    if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
      pp.showChat()
      Qt.callLater(function () { page.dayPaneItem.dayFieldRef.insert(page.dayPaneItem.dayFieldRef.cursorPosition, event.text) })
      return true
    }
    return false
  }
  // `^` in the paper's box: its marks, narrowing as you type. `@`: the
  // other papers and notes the agent may see (2026-11-19, the student:
  // "@ a different paper so I can mention it to the agent"), as the day's
  // chat offers them, this paper left out.
  function updateMention() {
    var f = page.dayPaneItem.dayFieldRef
    var before = f.text.substring(0, f.cursorPosition)
    var at = before.match(/(^|\s)@([^\s@]*)$/)
    if (at) {
      // Read again as a mention begins: a paper added since is offered too.
      if (!page.dayMention) page.loadRefFiles()
      var aq = at[2].toLowerCase()
      var files = page.refFiles.filter(function (x) {
        return x.rel !== page.pdfRel && (aq === "" || x.name.toLowerCase().indexOf(aq) >= 0 || x.rel.toLowerCase().indexOf(aq) >= 0)
      }).sort(function (a, b) { return a.kind === b.kind ? 0 : a.kind === "paper" ? -1 : 1 })
        .slice(0, 8).map(function (x) { return { file: x.rel, kind: x.kind, name: x.name, head: x.kind + " · " + x.name } })
      page.dayMention = { start: f.cursorPosition - at[2].length - 1, query: at[2], items: files }
      if (page.dayMentionFocus > files.length - 1) page.dayMentionFocus = Math.max(0, files.length - 1)
      return
    }
    var m = before.match(/(^|\s)\^([^\s^]*)$/)
    if (!m) { page.dayMention = null; return }
    var q = m[2].toLowerCase()
    var ms = (page.pdfItem.read && page.pdfItem.read.marks) ? page.pdfItem.read.marks : []
    var items = ms.filter(function (x) { return q === "" || x.text.toLowerCase().indexOf(q) >= 0 || x.id === q })
      .slice(0, 8).map(function (x) { return { mark: x.id, head: pp.head(x.id) } })
    page.dayMention = { start: f.cursorPosition - m[2].length - 1, query: m[2], items: items }
    if (page.dayMentionFocus > items.length - 1) page.dayMentionFocus = Math.max(0, items.length - 1)
  }
}
