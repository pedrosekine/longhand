import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Blocks.js" as Blocks

// The page: today's note as a blank sheet in the shell, with the agent in
// the margin. Two shapes of the same sheet: the overlay (a layer over
// everything, Esc leaves) and alongside (a normal Hyprland window you tile
// next to slides or a PDF; Esc does nothing there). Ctrl+P pins the overlay
// into a window and back; the pin mark in the header says which you are in.
//
// The two live side by side. With the window open somewhere, SUPER+ALT+=
// still brings the overlay up where you are; the sheet moves into it (one
// sheet, one editor, nothing to keep in sync) and the window says where it
// went. Esc or the same key again puts it back in the window. The shell's
// toggle asks `opened`, so `opened` means the overlay, never the window.
//
// No file tree, no chrome. A themed sheet, the date, the text. Every keystroke
// is saved (coalesced over a few hundred milliseconds, flushed on Enter and
// on close) so the file on disk is always what you see. Escape closes.
//
// The note is drawn, never shown as markdown (NoteEditor): headings set
// large, checkboxes as boxes (click or Ctrl+L), private callouts marked as
// such, and more space between blocks than between the lines of one block.
// Underneath it stays plain markdown, changed only where you typed. Enter
// continues a list item (checkboxes reset to unticked), Enter on an empty
// item leaves the list, Tab nests. Alt+Up/Down jump between blocks — the
// same block splitting the agent uses, so the navigation unit and the reply
// unit are one thing; Ctrl+Up/Down go to the start and end of the current
// block.
//
// The page is also the trigger, but never by accident. A block reaches the
// agent only when it carries a sign for it — a checkbox, an `@`, a `?` —
// and the student says so. Finishing an `@` or `?` line with Enter *stages*
// the block (hollow gutter mark) and shows a washed prompt under the cursor
// that defaults to no: Enter again or Esc ignores it, an arrow then Enter
// sends. A checkbox list is the special case: Enter just gives the next
// bullet; the whole run of items is staged as one submission when you
// leave the list (Enter on an empty bullet). Ctrl+Enter sends the staged
// block or list under the cursor at any later moment. A block without a
// sign never goes. Opening the page runs one automatic pass so answers are
// waiting when you come back.
//
// The agent's answers are painted, never inserted: a block the agent has
// seen is veiled a little; a block with a reply carries a filled mark in
// the gutter, accent until you have looked at it. Nothing else is on
// screen until asked: Alt+Right opens the margin for the block under the
// cursor — the reply, its proposals (Enter accepts one; local code runs the
// CLI, the model never does), and the chat about that block; Alt+Left or
// Esc closes it again. Ctrl+T opens the what's-next panel in the same
// place: every open checkbox across the daily notes (last seven days open,
// older collapsed; Enter ticks one, in the original note, because the page
// is the one program that edits notes) and, below, what the agent has
// raised — suggestions with their evidence, observations from open passes
// — where Enter waves one off and the runner remembers that.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool overlayOpen: false
  property bool windowOpen: false
  readonly property bool opened: overlayOpen          // what the shell's toggle asks
  readonly property bool showing: overlayOpen || windowOpen
  readonly property bool alongside: !overlayOpen      // where the sheet is drawn

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property color dim: Util.alpha(foreground, 0.45)
  readonly property color faint: Util.alpha(foreground, 0.22)
  readonly property color urgent: Color.urgent
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.family
  readonly property int textSize: Style.font.heading

  readonly property int sheetWidth: Math.min(Style.space(760), content.width - Style.space(48))
  readonly property int sheetMargin: Style.space(28)
  readonly property int sheetPadding: alongside ? Style.space(28) : Style.space(44)
  readonly property int marginGap: Style.space(18)
  readonly property int gutter: Style.space(18)
  readonly property int marginWidth: alongside
    ? Math.max(0, Math.min(Style.space(300), Math.round(content.width * 0.45)))
    : Math.max(0, Math.min(Style.space(300), content.width - (content.width + sheetWidth) / 2 - marginGap - sheetMargin))

  property string dateLabel: ""
  property bool applying: false

  // Runner plumbing: one process at a time, the last request wins.
  property var queued: null
  property bool running: false
  property string runningHash: ""
  property bool openPassPending: false
  property int tickedCount: 0

  // What is painted and what the margin shows.
  property var paint: []
  property var staged: ({})      // hash -> { trigger, group: [hashes] }, waiting for Ctrl+Enter
  property var ask: null         // { hashes, trigger, yes } — the prompt after Enter
  property bool marginOpen: false
  property int marginFocus: -1   // -1 note; 0..n-1 proposal rows; n = chat field
  property bool tasksOpen: false
  property var tasks: []
  property var raised: []
  property var tickHistory: []   // ticks made from the panel, newest last, for Ctrl+Z
  property var contextFor: null  // task whose surrounding block is shown in the panel
  property bool showOlder: false
  property int taskFocus: 0
  property string currentHash: ""
  readonly property var currentRecord: agent.record(currentHash)
  readonly property var currentStaged: staged[currentHash] || null
  readonly property var currentProposals: (currentRecord && currentRecord.proposals) ? currentRecord.proposals : []
  readonly property var taskRows: root.buildTaskRows()
  readonly property bool replyWaiting: root.hasUnreadInNote()

  readonly property string problem: svc.configError || svc.error

  // `{"shape":"alongside"}` asks for the window: it takes the sheet back
  // from the overlay if that is up. Anything else brings the overlay up,
  // over the window if there is one. Only coming from nothing counts as
  // opening the page, and runs the automatic pass.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var fresh = !root.showing
    if (payload.shape === "alongside") {
      root.windowOpen = true
      if (root.overlayOpen) root.dismiss()
    } else {
      root.overlayOpen = true
    }
    if (fresh) {
      root.dateLabel = Qt.formatDate(new Date(), "dddd d MMMM")
      root.openPassPending = true
      svc.openToday()
      agent.reload()
      if (svc.ready) root.openPass()
    }
    Qt.callLater(editor.focusNote)
  }

  function openPass() {
    if (!root.openPassPending) return
    root.openPassPending = false
    root.requestRun("open", "")
  }

  // What the shell calls to hide the page: the overlay goes, the window
  // (if open) stays and gets the sheet back.
  function close() {
    root.flush()
    root.overlayOpen = false
    if (root.windowOpen) Qt.callLater(editor.focusNote)
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "student.page")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Ctrl+P: the same sheet, the other shape. Pinning the overlay opens
  // the window and closes the overlay; unpinning the window does the
  // reverse.
  function togglePin() {
    root.flush()
    if (root.overlayOpen) {
      root.windowOpen = true
      root.dismiss()
    } else {
      root.windowOpen = false
      root.overlayOpen = true
    }
    Qt.callLater(editor.focusNote)
  }

  // Disk → editor. Guarded so the resulting textChanged does not look like
  // typing and schedule a write of what was just read.
  function applyText(t) {
    root.applying = true
    editor.load(t)
    root.applying = false
    root.tickedCount = root.countTicked(t)
    root.scheduleRepaint()
  }

  function flush() {
    saveTimer.stop()
    if (svc.ready) svc.save(editor.text)
  }

  // ------------------------------------------------------------ triggers

  function countTicked(t) {
    var m = t.match(/^\s*[-*+] \[[xX]\] /gm)
    return m ? m.length : 0
  }

  function triggerFor(lineText) {
    var t = lineText.trim()
    if (/^@/.test(t)) return "mention"
    if (/^[-*+] \[ \] \S/.test(t)) return "checkbox"
    if (/\?$/.test(t)) return "question"
    return ""
  }

  function hashOfLine(lineIndex) {
    var blocks = Blocks.split(editor.text)
    var k = Blocks.blockAt(blocks, lineIndex)
    return k < 0 ? "" : blocks[k].hash
  }

  // For the margin: the block under the cursor, or the nearest one above
  // when the cursor rests on a blank line — which is where it lands right
  // after finishing a line.
  function hashNearLine(lineIndex) {
    var blocks = Blocks.split(editor.text)
    var k = Blocks.blockAt(blocks, lineIndex)
    // An item that is only its marker (what Enter leaves behind) is as good
    // as a blank line: look up to the block that has words.
    if (k >= 0 && /^\s*[-*+] (\[[ xX]\] )?$/.test(blocks[k].text)) k = -1
    if (k < 0) for (var i = blocks.length - 1; i >= 0; i--) if (blocks[i].start <= lineIndex && !/^\s*[-*+] (\[[ xX]\] )?$/.test(blocks[i].text)) { k = i; break }
    return k < 0 ? "" : blocks[k].hash
  }

  function requestRun(trigger, hash) {
    root.flush()
    var cmd = [svc.runner, "run", "--trigger", trigger]
    if (hash) cmd.push("--hash", hash)
    root.enqueue(cmd, hash)
  }

  function stage(trigger, hashes) {
    if (!hashes || hashes.length === 0) return
    var next = ({})
    for (var k in root.staged) next[k] = root.staged[k]
    for (var i = 0; i < hashes.length; i++) next[hashes[i]] = { trigger: trigger, group: hashes }
    root.staged = next
    root.scheduleRepaint()
  }

  function unstage(hashes) {
    var next = ({})
    for (var k in root.staged) if (hashes.indexOf(k) < 0) next[k] = root.staged[k]
    root.staged = next
  }

  // Ctrl+Enter: send the block under the cursor, if it carries a sign for
  // the agent. A block without one stays where it is; the margin says why.
  property bool noSignHint: false
  function sendCurrent() {
    var hash = root.currentHash
    if (hash === "") return
    var st = root.staged[hash]
    if (st) { root.send(st.trigger, st.group); return }
    var trigger = root.triggerForBlock(hash)
    if (!trigger) { root.noSignHint = true; hintTimer.restart(); return }
    root.send(trigger, trigger === "checkbox" ? root.listAround(hash) : [hash])
  }

  function send(trigger, hashes) {
    root.ask = null
    root.unstage(hashes)
    root.requestRun(trigger, hashes.join(","))
  }

  function askAbout(trigger, hashes) {
    if (!hashes || hashes.length === 0) return
    root.ask = { hashes: hashes, trigger: trigger, yes: false }
  }

  // The run of adjacent list items around a block: no blank line between
  // them, all top-level items. One list, one submission.
  function listAround(hash) {
    var blocks = Blocks.split(editor.text)
    var k = -1
    for (var i = 0; i < blocks.length; i++) if (blocks[i].hash === hash) { k = i; break }
    if (k < 0 || blocks[k].kind !== "item") return [hash]
    var lo = k, hi = k
    while (lo > 0 && blocks[lo - 1].kind === "item" && blocks[lo - 1].end === blocks[lo].start) lo--
    while (hi < blocks.length - 1 && blocks[hi + 1].kind === "item" && blocks[hi + 1].start === blocks[hi].end) hi++
    var out = []
    for (var j = lo; j <= hi; j++) out.push(blocks[j].hash)
    return out
  }

  function listHasCheckbox(hashes) {
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++)
      if (hashes.indexOf(blocks[i].hash) >= 0 && /^\s*[-*+] \[ \] \S/m.test(blocks[i].text)) return true
    return false
  }

  function dropAsk() { root.ask = null }

  // Keys while the prompt is up. Returns true when the key was consumed.
  function askKey(event) {
    if (!root.ask) return false
    var k = event.key
    if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Tab) {
      root.ask = { hashes: root.ask.hashes, trigger: root.ask.trigger, yes: !root.ask.yes }
      return true
    }
    if (k === Qt.Key_Escape) { root.dropAsk(); return true }
    if (event.text === "y" || event.text === "Y") { root.send(root.ask.trigger, root.ask.hashes); return true }
    if (event.text === "n" || event.text === "N") { root.dropAsk(); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (root.ask.yes) { root.send(root.ask.trigger, root.ask.hashes); return true }
      root.dropAsk()
      return false   // a plain Enter: let it fall through and behave as usual
    }
    root.dropAsk()   // anything else: the prompt just goes away
    return false
  }

  function blockBounds(hash) {
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++) if (blocks[i].hash === hash) return blocks[i]
    return null
  }

  // Ctrl+Up / Ctrl+Down: start / end of the current block.
  function jumpWithinBlock(direction) {
    var b = root.blockBounds(root.currentHash)
    if (!b) return
    if (direction < 0) editor.setCursor(root.positionOfLine(b.start))
    else editor.setCursor(Math.max(0, root.positionOfLine(b.end) - 1))
  }

  function triggerForBlock(hash) {
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].hash !== hash) continue
      var lines = blocks[i].text.split("\n")
      return root.triggerFor(lines[0]) || root.triggerFor(lines[lines.length - 1])
    }
    return ""
  }

  function requestChat(hash, message) {
    root.flush()
    root.enqueue([svc.runner, "chat", "--hash", hash, "--message", message], hash)
  }

  function enqueue(cmd, hash) {
    root.queued = { cmd: cmd, hash: hash }
    if (!svc.saving) root.launchQueued()
  }

  function launchQueued() {
    if (!root.queued || root.running || svc.saving) return
    var q = root.queued
    root.queued = null
    root.running = true
    root.runningHash = q.hash
    runner.command = q.cmd
    runner.running = true
  }

  // ------------------------------------------------------------ painting

  function lineBounds(pos) {
    var t = editor.text
    var start = t.lastIndexOf("\n", pos - 1) + 1
    var end = t.indexOf("\n", pos)
    if (end < 0) end = t.length
    return { start: start, end: end, text: t.substring(start, end) }
  }

  function lineIndexAt(pos) {
    var n = 0
    var t = editor.text
    for (var i = 0; i < pos && i < t.length; i++) if (t.charCodeAt(i) === 10) n++
    return n
  }

  function positionOfLine(lineIndex) {
    var t = editor.text
    var pos = 0
    for (var k = 0; k < lineIndex; k++) {
      var nl = t.indexOf("\n", pos)
      if (nl < 0) return t.length
      pos = nl + 1
    }
    return pos
  }

  function scheduleRepaint() { Qt.callLater(root.repaint) }

  // Geometry for every block the agent knows about, in editor coordinates.
  function repaint() {
    var out = []
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++) {
      var b = blocks[i]
      var rec = agent.record(b.hash)
      var isStaged = !!root.staged[b.hash]
      if (!rec && !isStaged) continue
      var r = editor.blockRect(b.start, b.end)
      if (!r) continue
      out.push({ hash: b.hash, y: r.y, h: r.h,
                 reply: !!rec && rec.state === "reply", unread: !!rec && rec.state === "reply" && !rec.read,
                 seen: !!rec && rec.state !== "reply", staged: isStaged })
    }
    root.paint = out
    root.currentHash = root.hashNearLine(root.lineIndexAt(editor.cursorPosition))
  }

  function hasUnreadInNote() {
    var p = root.paint
    for (var i = 0; i < p.length; i++) if (p[i].unread) return true
    return false
  }

  function jumpBlock(direction) {
    var blocks = Blocks.split(editor.text)
    if (blocks.length === 0) return
    var line = root.lineIndexAt(editor.cursorPosition)
    var target = -1
    if (direction < 0) {
      for (var i = blocks.length - 1; i >= 0; i--) if (blocks[i].start < line) { target = i; break }
    } else {
      for (var j = 0; j < blocks.length; j++) if (blocks[j].start > line) { target = j; break }
    }
    if (target < 0) return
    editor.setCursor(root.positionOfLine(blocks[target].start))
  }

  // The editor carries list markers over Enter itself; what the page
  // decides is whether the agent is asked. A finished `@` or `?` line is
  // staged and asked about.
  function lineFinished(lineIndex, lineText) {
    Qt.callLater(root.flush)
    var trigger = root.triggerFor(lineText)
    if (trigger === "" || trigger === "checkbox") return
    var hash = root.hashOfLine(lineIndex)
    root.stage(trigger, [hash])
    root.askAbout(trigger, [hash])
  }

  // Enter on an empty item left the list. If it carried checkboxes, the
  // whole run of items is one submission.
  function listLeft(lineIndex) {
    Qt.callLater(root.flush)
    if (lineIndex <= 0) return
    var prev = root.hashOfLine(lineIndex - 1)
    if (prev === "") return
    var group = root.listAround(prev)
    if (root.listHasCheckbox(group)) { root.stage("checkbox", group); root.askAbout("checkbox", group) }
  }

  // Keys the page owns, ahead of editing. True when taken.
  function pageKey(event) {
    var ctrl = event.modifiers & Qt.ControlModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    if (root.askKey(event)) return true
    if (k === Qt.Key_Escape) { if (!root.alongside) root.dismiss(); return true }
    if (k === Qt.Key_P && ctrl) { root.togglePin(); return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ctrl) { root.sendCurrent(); return true }
    if (k === Qt.Key_Up && alt) { root.jumpBlock(-1); return true }
    if (k === Qt.Key_Down && alt) { root.jumpBlock(1); return true }
    if (k === Qt.Key_Up && ctrl) { root.jumpWithinBlock(-1); return true }
    if (k === Qt.Key_Down && ctrl) { root.jumpWithinBlock(1); return true }
    if (k === Qt.Key_Right && alt) { root.diveIn(); return true }
    if (k === Qt.Key_T && ctrl) { root.toggleTasks(); return true }
    return false
  }

  function diveIn() {
    if (root.marginWidth <= 0 || root.currentHash === "") return
    root.marginOpen = true
    if (root.currentProposals.length > 0) {
      root.marginFocus = 0
      marginKeys.forceActiveFocus()
    } else {
      root.marginFocus = root.currentProposals.length
      chatField.forceActiveFocus()
    }
  }

  function backToNote() {
    root.marginFocus = -1
    root.marginOpen = false
    root.tasksOpen = false
    editor.focusNote()
  }

  function moveMarginFocus(d) {
    var n = root.currentProposals.length
    var next = Math.max(0, Math.min(n, root.marginFocus + d))
    root.marginFocus = next
    if (next === n) chatField.forceActiveFocus()
    else marginKeys.forceActiveFocus()
  }

  function acceptProposal(i) {
    var p = root.currentProposals[i]
    if (!p || p.accepted || root.currentHash === "") return
    acceptProc.command = [svc.runner, "accept", "--hash", root.currentHash, "--index", String(i)]
    acceptProc.running = true
  }

  // ------------------------------------------------------------ tasks panel

  function toggleTasks() {
    root.tasksOpen = !root.tasksOpen
    if (root.tasksOpen) {
      root.marginOpen = true
      root.taskFocus = 0
      root.refreshTasks()
      marginKeys.forceActiveFocus()
    } else {
      root.backToNote()
    }
  }

  function refreshTasks() {
    tasksProc.command = [svc.runner, "next", "--days", "7"]
    tasksProc.running = true
  }

  // Rows for the panel: a day header per date, its open tasks, and older
  // days folded into one row until asked for.
  function buildTaskRows() {
    var rows = []
    var older = 0
    var lastDate = ""
    for (var i = 0; i < root.tasks.length; i++) {
      var t = root.tasks[i]
      if (!t.recent && !root.showOlder) { older++; continue }
      if (t.date !== lastDate) { rows.push({ kind: "day", date: t.date, recent: t.recent }); lastDate = t.date }
      rows.push({ kind: "task", task: t })
    }
    if (older > 0) rows.push({ kind: "older", count: older })
    if (root.raised.length > 0) {
      rows.push({ kind: "day", date: "FROM THE AGENT", recent: true })
      for (var j = 0; j < root.raised.length; j++) rows.push({ kind: "raised", item: root.raised[j] })
    }
    return rows
  }

  function moveTaskFocus(d) {
    var rows = root.taskRows
    var i = root.taskFocus
    do { i += d } while (i >= 0 && i < rows.length && rows[i].kind === "day")
    if (i >= 0 && i < rows.length) root.taskFocus = i
  }

  // Enter: go to the task. Today's note: the cursor lands on its line and
  // the panel closes. Another day: its surrounding block unfolds under the
  // row. Space or x ticks; Ctrl+Z takes the last tick back.
  function activateTask() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    if (row.kind === "older") { root.showOlder = true; return }
    if (row.kind === "task") root.goToTask(row.task)
    if (row.kind === "raised") {
      dismissProc.command = [svc.runner, "dismiss", "--date", row.item.date, "--kind", row.item.kind, "--index", String(row.item.index)]
      dismissProc.running = true
    }
  }

  function tickFocused() {
    var row = root.taskRows[root.taskFocus]
    if (row && row.kind === "task") root.tickTask(row.task)
  }

  function goToTask(t) {
    if (t.date === svc.noteDate) {
      var m = root.taskRegex(t.text).exec(editor.text)
      if (!m) return
      root.backToNote()
      editor.setCursor(m.index + m[0].length, true)
      return
    }
    root.contextFor = (root.contextFor && root.contextFor.file === t.file && root.contextFor.line === t.line) ? null : t
    if (root.contextFor) {
      contextFile.path = t.file
      if (contextFile.path === t.file) contextFile.reload()
    }
  }

  function taskRegex(text) {
    return new RegExp("^(\\s*[-*+] )\\[ \\] " + text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$", "m")
  }

  function untickLast() {
    if (root.tickHistory.length === 0) return
    var t = root.tickHistory[root.tickHistory.length - 1]
    root.tickHistory = root.tickHistory.slice(0, -1)
    var re = new RegExp("^(\\s*[-*+] )\\[[xX]\\] " + t.text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$", "m")
    if (t.date === svc.noteDate) {
      var m = re.exec(editor.text)
      if (!m) return
      var pos = m.index + m[1].length + 1
      editor.remove(pos, pos + 1)
      editor.insert(pos, " ")
      root.flush()
      Qt.callLater(root.refreshTasks)
      return
    }
    tickFile.pending = { task: t, untick: true }
    if (tickFile.path === t.file) tickFile.reload()
    else tickFile.path = t.file
  }

  // Tick in the original note. Today's note is live in the editor; any
  // other day is rewritten on disk, one line changed.
  function tickTask(t) {
    var re = root.taskRegex(t.text)
    root.tickHistory = root.tickHistory.concat([t])
    if (t.date === svc.noteDate) {
      var text = editor.text
      var m = re.exec(text)
      if (!m) return
      var pos = m.index + m[1].length + 1
      editor.remove(pos, pos + 1)
      editor.insert(pos, "x")
      root.flush()
      Qt.callLater(root.refreshTasks)
      return
    }
    tickFile.pending = { task: t, untick: false }
    if (tickFile.path === t.file) tickFile.reload()
    else tickFile.path = t.file
  }

  function sendChat() {
    var msg = chatField.text.trim()
    if (msg === "" || root.currentHash === "") return
    chatField.text = ""
    root.requestChat(root.currentHash, msg)
  }

  // ------------------------------------------------------------ services

  Service {
    id: svc
    onLoaded: { root.applyText(svc.body); root.openPass() }
    onExternalChange: root.applyText(svc.body)
    onSavedNow: root.launchQueued()
  }

  AgentState {
    id: agent
    config: svc.config
    onStateChanged: root.scheduleRepaint()
  }

  Process {
    id: runner
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("student.page runner: " + text.trim())
    }
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.log("student.page runner: " + text.trim())
    }
    onExited: function (code, status) {
      root.running = false
      root.runningHash = ""
      agent.reload()
      root.launchQueued()
    }
  }

  Process {
    id: acceptProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("student.page accept: " + text.trim()) }
    onExited: function (code, status) { agent.reload() }
  }

  Process {
    id: tasksProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var nx = JSON.parse(text)
          root.tasks = nx.tasks || []
          root.raised = nx.raised || []
        } catch (e) { root.tasks = []; root.raised = [] }
        root.taskFocus = Math.min(root.taskFocus, Math.max(0, root.taskRows.length - 1))
      }
    }
  }

  Process {
    id: dismissProc
    onExited: function (code, status) { root.refreshTasks(); agent.reload() }
  }

  // One-line rewrite of another day's note when a task is ticked from
  // the panel. Atomic, and only ever the line the student pointed at.
  FileView {
    id: tickFile
    property var pending: null
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var p = tickFile.pending
      if (!p) return
      tickFile.pending = null
      var t = p.task
      var lines = text().split("\n")
      if (t.line < lines.length) {
        var re = p.untick ? new RegExp("^(\\s*[-*+] )\\[[xX]\\] ") : new RegExp("^(\\s*[-*+] )\\[ \\] ")
        if (re.test(lines[t.line])) {
          lines[t.line] = lines[t.line].replace(re, p.untick ? "$1[ ] " : "$1[x] ")
          setText(lines.join("\n"))
        }
      }
    }
    onSaved: root.refreshTasks()
    onLoadFailed: tickFile.pending = null
  }

  // Another day's note, read to show the block around a task in the panel.
  FileView {
    id: contextFile
    property string snippet: ""
    printErrors: false
    onLoaded: {
      var t = root.contextFor
      if (!t) { contextFile.snippet = ""; return }
      var blocks = Blocks.split(text())
      var k = Blocks.blockAt(blocks, t.line)
      var lo = k, hi = k
      while (lo > 0 && blocks[lo - 1].kind === "item" && blocks[lo - 1].end === blocks[lo].start) lo--
      while (hi < blocks.length - 1 && blocks[hi + 1].kind === "item" && blocks[hi + 1].start === blocks[hi].end) hi++
      var parts = []
      if (lo > 0) parts.push(blocks[lo - 1].text)
      for (var i = Math.max(0, lo); i <= hi && i < blocks.length; i++) parts.push(blocks[i].text)
      if (hi + 1 < blocks.length) parts.push(blocks[hi + 1].text)
      contextFile.snippet = parts.join("\n\n")
    }
    onLoadFailed: contextFile.snippet = ""
  }

  // Looking at a reply for a moment marks it read — nothing else needs to.
  Process { id: ackProc }
  Timer {
    id: ackTimer
    interval: 1200
    onTriggered: {
      var rec = root.currentRecord
      if (rec && rec.state === "reply" && !rec.read && root.currentHash !== "") {
        ackProc.command = [svc.runner, "ack", "--hash", root.currentHash]
        ackProc.running = true
      }
    }
  }
  onCurrentHashChanged: ackTimer.restart()

  Timer {
    id: saveTimer
    interval: 300
    onTriggered: root.flush()
  }

  Timer {
    id: hintTimer
    interval: 2500
    onTriggered: root.noSignHint = false
  }

  // ------------------------------------------------------------ window

  PanelWindow {
    id: panel
    visible: root.overlayOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "student-page"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
  }

  // The alongside shape: an ordinary window, tiled and moved with the
  // keys the student already has. Closing it from the compositor closes
  // the page.
  FloatingWindow {
    id: win
    visible: root.windowOpen
    title: "Page — today's note"
    color: root.background
    implicitWidth: Style.space(680)
    implicitHeight: Style.space(900)
    minimumSize: Qt.size(Style.space(360), Style.space(300))
    onVisibleChanged: {
      if (visible) Qt.callLater(editor.focusNote)
      else if (root.windowOpen) {
        // Closed from the compositor.
        root.flush()
        root.windowOpen = false
      }
    }

    // The sheet is on the overlay for now; it comes back here when that
    // closes.
    Text {
      anchors.centerIn: parent
      visible: root.overlayOpen
      textFormat: Text.PlainText
      text: "on the overlay · Esc brings it back"
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // One content tree, whichever window is showing.
  Item {
    id: content
    parent: root.overlayOpen ? panel.contentItem : win.contentItem
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      visible: !root.alongside
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      enabled: !root.alongside
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: sheet
      x: root.alongside ? 0 : Math.round((content.width - width) / 2)
      y: root.alongside ? 0 : root.sheetMargin
      width: root.alongside ? content.width - (root.marginOpen ? root.marginWidth + root.marginGap : 0) : root.sheetWidth
      height: root.alongside ? content.height : content.height - root.sheetMargin * 2
      radius: root.alongside ? 0 : Style.cornerRadius
      color: root.background
      borderSpec: root.alongside ? Border.none() : root.borderSpec
      padding: root.sheetPadding

      MouseArea {
        anchors.fill: parent
        onClicked: editor.focusNote()
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: sheet.contentTopInset
        anchors.rightMargin: sheet.contentRightInset
        anchors.bottomMargin: sheet.contentBottomInset
        anchors.leftMargin: sheet.contentLeftInset

        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: dateText.implicitHeight

          Text {
            id: dateText
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: root.dateLabel
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            // The pin: which shape you are in. Ctrl+P or a click flips it.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "pin"
              color: root.alongside ? root.foreground : root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePin() }
            }

            // The agent mark: faint at rest, brighter while a run is in
            // flight, accent while a reply in this note is still unread.
            Text {
              visible: svc.header !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "agent"
              color: root.replyWaiting ? root.accent : (root.running ? root.foreground : root.faint)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              Behavior on color { ColorAnimation { duration: 240 } }
            }

            // Saved / unsaved: a dot that brightens while a write is
            // pending and settles once it landed.
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.problem !== "" ? root.urgent : (svc.pending || svc.saving ? root.foreground : root.faint)
              Behavior on color { ColorAnimation { duration: 180 } }
            }
          }
        }

        Text {
          visible: root.problem !== ""
          anchors.top: header.bottom
          anchors.topMargin: Style.space(24)
          anchors.left: parent.left
          anchors.right: parent.right
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.problem
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Flickable {
          id: flick
          visible: root.problem === ""
          anchors.top: header.bottom
          anchors.topMargin: Style.space(24)
          anchors.left: parent.left
          anchors.leftMargin: -root.gutter
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          contentWidth: width
          contentHeight: editor.height + height * 0.4
          boundsBehavior: Flickable.StopAtBounds

          function ensureVisible(r) {
            if (contentY >= r.y) contentY = r.y
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
          }

          // Gutter marks: filled for a block with a reply (accent until
          // read), hollow for a block staged and waiting for Ctrl+Enter.
          Repeater {
            model: root.paint
            Rectangle {
              required property var modelData
              visible: modelData.reply || modelData.staged
              x: Style.space(2)
              y: modelData.y
              width: Style.space(3)
              height: modelData.h
              radius: width
              color: modelData.reply ? (modelData.unread ? root.accent : root.dim) : "transparent"
              border.width: modelData.reply ? 0 : 1
              border.color: root.accent
              Behavior on color { ColorAnimation { duration: 240 } }
            }
          }

          NoteEditor {
            id: editor
            x: root.gutter
            width: flick.width - root.gutter
            height: implicitHeight
            enabled: svc.ready
            fontFamily: root.fontFamily
            textSize: root.textSize
            foreground: root.foreground
            background: root.background
            dim: root.dim
            faint: root.faint
            selectionColor: Style.selectionFill
            tabStop: 4 * Style.space(8)
            keyFilter: root.pageKey

            onCursorRectChanged: flick.ensureVisible(cursorRect)
            onCursorPositionChanged: root.currentHash = root.hashNearLine(root.lineIndexAt(cursorPosition))
            onWidthChanged: root.scheduleRepaint()
            onHeightChanged: root.scheduleRepaint()
            onReturnFinished: function (lineIndex, lineText) { root.lineFinished(lineIndex, lineText) }
            onListLeft: function (lineIndex) { root.listLeft(lineIndex) }
            onTextChanged: {
              if (root.applying) return
              svc.markPending(text)
              saveTimer.restart()
              var ticked = root.countTicked(text)
              if (ticked > root.tickedCount) {
                var th = root.hashOfLine(root.lineIndexAt(editor.cursorPosition))
                if (th !== "") root.stage("tick", root.listAround(th))
              }
              root.tickedCount = ticked
              root.scheduleRepaint()
            }
          }

          // Below the last line: a click goes to the end of the note.
          MouseArea {
            y: editor.height
            width: flick.width
            height: Math.max(0, flick.contentHeight - editor.height)
            onClicked: editor.setCursor(editor.length, true)
          }

          // The gentle prompt after Enter on a signed line, and the
          // no-sign hint: washed text just under the cursor, gone as soon
          // as you type.
          Text {
            visible: !!root.ask || root.noSignHint
            x: root.gutter
            y: editor.cursorRect.y + editor.cursorRect.height + Style.space(2)
            width: editor.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.noSignHint
              ? "no sign for the agent on this block — start a line with @, make it a checkbox, or end it with ?"
              : (root.ask && root.ask.yes
                ? "send to agent?  no   [yes]   · Enter or y sends"
                : "send to agent?  [no]   yes   · y sends · n, Enter or Esc ignores")
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            z: 2
          }

          // The veil: blocks the agent has seen, and has nothing to say
          // about, recede a little. Drawn over the text in the sheet's own
          // colour so the theme decides how it looks.
          Repeater {
            model: root.paint
            Rectangle {
              required property var modelData
              visible: modelData.seen
              x: root.gutter
              y: modelData.y
              width: editor.width
              height: modelData.h
              color: root.background
              opacity: 0.5
              z: 1
            }
          }
        }
      }
    }

    // The margin: the agent's side of the page, a narrower sheet beside the
    // note. Shows whatever it has to say about the block under the cursor,
    // and the field to talk back.
    BorderSurface {
      id: margin
      visible: root.marginWidth > 0 && root.problem === "" && root.marginOpen
      x: sheet.x + sheet.width + root.marginGap
      y: sheet.y
      height: sheet.height
      width: root.marginWidth
      radius: root.alongside ? 0 : Style.cornerRadius
      color: root.background
      borderSpec: root.alongside ? Border.none() : root.borderSpec
      padding: Style.space(22)

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Keyboard focus while in the margin (proposal rows or the tasks
      // panel). The chat field has its own handling.
      Item {
        id: marginKeys
        anchors.fill: parent
        Keys.onPressed: function (event) {
          var alt = event.modifiers & Qt.AltModifier
          var k = event.key
          if (k === Qt.Key_Escape || (k === Qt.Key_Left && alt)) { root.backToNote(); event.accepted = true; return }
          if (root.tasksOpen) {
            var ctrl = event.modifiers & Qt.ControlModifier
            if (k === Qt.Key_Up) { root.moveTaskFocus(-1); event.accepted = true }
            else if (k === Qt.Key_Down) { root.moveTaskFocus(1); event.accepted = true }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) { root.activateTask(); event.accepted = true }
            else if (k === Qt.Key_Space || event.text === "x") { root.tickFocused(); event.accepted = true }
            else if (k === Qt.Key_Z && ctrl) { root.untickLast(); event.accepted = true }
            else if (k === Qt.Key_T && ctrl) { root.toggleTasks(); event.accepted = true }
            return
          }
          if (k === Qt.Key_Up) { root.moveMarginFocus(-1); event.accepted = true }
          else if (k === Qt.Key_Down) { root.moveMarginFocus(1); event.accepted = true }
          else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { root.acceptProposal(root.marginFocus); event.accepted = true }
        }
      }

      // The tasks panel.
      Flickable {
        id: tasksFlick
        visible: root.tasksOpen
        anchors.fill: parent
        anchors.topMargin: margin.contentTopInset + Style.space(4)
        anchors.leftMargin: margin.contentLeftInset
        anchors.rightMargin: margin.contentRightInset
        anchors.bottomMargin: margin.contentBottomInset
        clip: true
        contentWidth: width
        contentHeight: tasksColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        // Keep the focused row in view.
        function revealFocused() {
          var kids = tasksColumn.children
          for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k.index === undefined || k.index !== root.taskFocus) continue
            if (contentY > k.y) contentY = k.y
            else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
            return
          }
        }
        Connections { target: root; function onTaskFocusChanged() { Qt.callLater(tasksFlick.revealFocused) } }

        Column {
          id: tasksColumn
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "WHAT'S NEXT"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.taskRows.length === 0
            textFormat: Text.PlainText
            text: "nothing open"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.taskRows
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool hot: root.taskFocus === index && modelData.kind !== "day"
              width: tasksColumn.width
              height: rowText.implicitHeight + (modelData.kind === "day" ? Style.space(12) : Style.space(8))
              radius: Style.cornerRadius
              color: hot ? Style.selectedFill : "transparent"
              Text {
                id: rowText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: modelData.kind === "day" ? modelData.date
                  : modelData.kind === "older" ? "+" + modelData.count + " older · Enter to show"
                  : modelData.kind === "raised"
                    ? (modelData.item.kind === "suggestion" ? "◇ " : "· ") + modelData.item.text
                      + (modelData.item.evidence ? "\n   " + modelData.item.evidence : "")
                    : "○ " + modelData.task.text
                color: modelData.kind === "day" ? root.dim : (modelData.kind === "older" ? root.faint : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: modelData.kind === "day" ? Style.font.caption : Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                enabled: modelData.kind !== "day"
                onClicked: { root.taskFocus = index; root.activateTask() }
              }
            }
          }

          // The block around a task from another day, unfolded on Enter.
          Text {
            width: parent.width
            visible: !!root.contextFor && contextFile.snippet !== ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.contextFor ? root.contextFor.date + "\n\n" + contextFile.snippet : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "↑↓ move · Enter goes to it · Space ticks · Ctrl+Z unticks · Esc back"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Flickable {
        id: marginFlick
        visible: !root.tasksOpen
        anchors.top: parent.top
        anchors.topMargin: margin.contentTopInset + Style.space(4)
        anchors.left: parent.left
        anchors.leftMargin: margin.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: margin.contentRightInset
        anchors.bottom: chatBox.top
        anchors.bottomMargin: Style.space(10)
        clip: true
        contentWidth: width
        contentHeight: marginColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: marginColumn
          width: parent.width
          spacing: Style.space(12)

          Text {
            width: parent.width
            visible: root.running && root.runningHash === root.currentHash && root.currentHash !== ""
            textFormat: Text.PlainText
            text: "…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.textSize
          }

          Text {
            width: parent.width
            visible: !!(root.currentRecord && root.currentRecord.reply)
            textFormat: Text.MarkdownText
            wrapMode: Text.WordWrap
            text: root.currentRecord && root.currentRecord.reply ? root.currentRecord.reply : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          // Proposals: what the agent would like to do, done only when the
          // student says so. Enter on a row runs it through the CLI.
          Repeater {
            model: root.currentProposals
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool hot: root.marginFocus === index && marginKeys.activeFocus
              readonly property bool done: !!modelData.accepted
              width: marginColumn.width
              height: propText.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: hot ? Style.selectedFill : "transparent"
              border.width: hot ? 1 : 0
              border.color: root.accent
              Text {
                id: propText
                anchors.fill: parent
                anchors.margins: Style.space(5)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: (done ? "✓ " : "○ ") + (modelData.kind === "deadline"
                  ? "deadline: " + modelData.title + " — " + modelData.when + (modelData.subject ? " · " + modelData.subject : "")
                    + (done && modelData.accepted.id ? "  #" + modelData.accepted.id : "")
                    + (modelData.error ? "  (failed: " + modelData.error + ")" : "")
                  : JSON.stringify(modelData))
                color: done ? root.dim : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { root.marginFocus = index; root.acceptProposal(index) }
              }
            }
          }

          Repeater {
            model: root.currentRecord && root.currentRecord.chat ? root.currentRecord.chat : []
            Text {
              required property var modelData
              width: marginColumn.width
              textFormat: modelData.role === "agent" ? Text.MarkdownText : Text.PlainText
              wrapMode: Text.WordWrap
              text: modelData.text
              color: modelData.role === "agent" ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          Text {
            width: parent.width
            visible: !root.currentRecord || !root.currentRecord.reply
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.currentStaged ? "Staged. Ctrl+Enter sends it, or ask below." : "Nothing from the agent on this block yet. Ask below."
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Item {
        id: chatBox
        visible: !root.tasksOpen
        anchors.left: parent.left
        anchors.leftMargin: margin.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: margin.contentRightInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: margin.contentBottomInset
        height: chatField.visible ? chatField.implicitHeight : 0

        TextField {
          id: chatField
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.marginOpen && !root.tasksOpen
          placeholderText: "…"
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          foreground: root.foreground
          Keys.onReturnPressed: function (event) { event.accepted = true; root.sendChat() }
          Keys.onEnterPressed: function (event) { event.accepted = true; root.sendChat() }
          Keys.onEscapePressed: function (event) { event.accepted = true; root.backToNote() }
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) { root.backToNote(); event.accepted = true }
            else if (event.key === Qt.Key_Up && text === "" && root.currentProposals.length > 0) { root.moveMarginFocus(-1); event.accepted = true }
          }
        }
      }
    }
  }
}
