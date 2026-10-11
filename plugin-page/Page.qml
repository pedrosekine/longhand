import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "Blocks.js" as Blocks
import "Bound.js" as Bound
import "Days.js" as Days
import "Tasks.js" as Tasks

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
//
// Ctrl+F finds in today's note, as you type, in the words you see (not
// the markdown under them). Enter goes to the next match, Shift+Enter to
// the previous, both wrapping; Ctrl+Enter puts the cursor on the match with
// it selected and closes the search; Esc closes it and leaves the cursor
// where it was.
//
// Ctrl+B opens the sidebar: a month calendar of the daily notes. It is
// never there unless asked — the page still opens blank on today. A day's
// number is full where a note exists and faded where none does; a dot marks
// today, an outline the day in the sheet. Arrows move a day (left/right) or
// a week (up/down), Ctrl+Left/Right or PageUp/PageDown a month, Home goes
// to today; Enter (or a click) opens the day in the same sheet, editable
// like today. A day without a note opens empty and gets its file only when
// something is written. Alt+Left goes back into the sidebar, Alt+Right or
// Esc back to the note, Ctrl+B closes it. A note whose file name is not in
// the vault's own date format (older notes) is edited plainly: the runner
// cannot read it, so the agent signs do nothing there.
//
// Deadlines live in the store (`pomo deadline`); a checkbox line can stand
// for one (Bound.js). Write a checkbox that ends in a date — "due fri
// 17:00", "by monday", "📅 tomorrow" — and on leaving the line the page
// asks "deadline: … ?" (yes is the default); Ctrl+D does it on purpose, or
// reschedules a bound line, or (date cleared) unbinds it. A bound line
// shows its date at its end. Ticking it marks the deadline done, editing
// its words renames it, a #tag moves its project; deleting the line asks
// whether the deadline goes too — hidden, kept in history (a cut does not
// ask: it is moving). Changes made in the popup or the CLI reach the line
// when the page opens the note:
// the store wins.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property string windowTitle: "Page — today's note"

  // Handles for a test harness driving the page over IPC.
  readonly property alias editorItem: editor
  readonly property alias whenInput: whenField
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
  // One size for the whole page, like a browser's zoom: text, spacing,
  // margins, the panel. The base is the shell's own type scale (which
  // follows the theme's font base-size), so the page sits with the rest of
  // the desktop; Ctrl+= / Ctrl+- / Ctrl+0 step it and the step is kept in
  // ~/.local/state/omarchy-student/page.json.
  readonly property var zoomSteps: [0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2]
  property real zoom: 1
  function sp(n) { return Math.max(1, Math.round(Style.spaceReal(n) * root.zoom)) }
  function fs(n) { return Math.max(1, Math.round(n * root.zoom)) }
  readonly property int textSize: root.fs(Style.font.title)

  readonly property int sheetWidth: Math.min(root.sp(760), content.width - root.sp(48))
  readonly property int sheetMargin: root.sp(28)
  readonly property int sheetPadding: alongside ? root.sp(28) : root.sp(44)
  readonly property int marginGap: root.sp(18)
  readonly property int gutter: root.sp(18)
  readonly property int marginWidth: alongside
    ? Math.max(0, Math.min(root.sp(300), Math.round(content.width * 0.45)))
    : Math.max(0, Math.min(root.sp(300), content.width - (content.width + sheetWidth) / 2 - marginGap - sheetMargin))

  readonly property string dateLabel: svc.noteDate !== "" && svc.configured
    ? Days.longLabel(svc.noteDate, svc.dailyFormat()) : ""

  // Which day is in the sheet, and whether the agent can work on it: the
  // runner reads only names in the vault's own format.
  readonly property bool agentDay: {
    if (svc.noteDate === "" || !svc.configured) return false
    var p = Days.parse(svc.noteDate, svc.dailyFormat())
    return !!p && p.configured
  }
  property string pendingStamp: ""   // a day to open once the save in flight lands

  // The sidebar: a month calendar.
  property bool sidebarOpen: false
  property var dayStems: []
  property var calFocus: new Date()   // the day the calendar's cursor is on
  readonly property var dayIndex: svc.configured ? Days.index(root.dayStems, svc.dailyFormat()) : ({})
  // First column of the calendar: `weekStart` in config.json ("monday",
  // "sunday", "saturday"), else the locale's.
  readonly property int firstDow: {
    var w = String((svc.config && svc.config.weekStart) || "").toLowerCase()
    var named = { sunday: 0, monday: 1, saturday: 6 }
    return w in named ? named[w] : Qt.locale().firstDayOfWeek % 7
  }
  readonly property var calCells: Days.grid(root.calFocus.getFullYear(), root.calFocus.getMonth(), root.firstDow)
  readonly property string openKey: {
    var p = svc.configured && svc.noteDate !== "" ? Days.parse(svc.noteDate, svc.dailyFormat()) : null
    return p ? Days.key(p.date) : ""
  }
  readonly property int sidebarWidth: root.sp(236)

  // Deadlines by the day they fall on, for the calendar (hidden ones too:
  // the calendar is history), each day's in due order.
  readonly property var dueByDay: {
    var m = {}
    var items = dl.items
    for (var i = 0; i < items.length; i++) {
      var k = Days.key(new Date(items[i].due * 1000))
      if (!m[k]) m[k] = []
      m[k].push(items[i])
    }
    for (var key in m) m[key].sort(function (a, b) { return a.due - b.due })
    return m
  }
  readonly property var focusDue: root.dueByDay[Days.key(root.calFocus)] || []
  property int dueFocus: -1          // in the list under the calendar (-1: the grid has the keys)
  property int pendingGoto: 0        // a deadline whose line to land on once its note is open
  readonly property int sideSpace: root.sidebarOpen && root.problem === "" ? root.sidebarWidth + root.marginGap : 0
  property bool applying: false

  // Runner plumbing: one process at a time, the last request wins.
  property var queued: []      // runner commands waiting, oldest first
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
  property bool searchOpen: false
  property var matches: []       // [{ start, end }] text offsets, in note order
  property int matchIndex: -1
  property int searchFrom: 0     // the cursor when the search opened
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
  //
  // `{"goto":"[[2026.10.09#^d6]]"}` (the deadlines popup's `o`) opens on the
  // line that stands for deadline #6, in the window if that is where the
  // page already is.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var goto = payload.goto ? Bound.parseLink(payload.goto) : null
    var fresh = !root.showing
    if (payload.shape === "alongside" || (goto && root.windowOpen && !root.overlayOpen)) {
      root.windowOpen = true
      if (root.overlayOpen) root.dismiss()
    } else {
      root.overlayOpen = true
    }
    if (fresh) {
      root.sidebarOpen = false
      agent.reload()
      if (goto && svc.configured && goto.stem !== svc.todayStamp()) {
        svc.openDate(goto.stem)
      } else {
        root.openPassPending = true
        svc.openToday()
        if (svc.ready) root.openPass()
      }
    }
    if (goto) {
      root.pendingGoto = goto.id
      if (svc.ready && svc.noteDate === goto.stem) root.landOnGoto()
      else if (!fresh) root.openNote(goto.stem)
    }
    Qt.callLater(editor.focusNote)
  }

  // ------------------------------------------------------------ usage

  // What the page is used for, for judging it after a stretch of real use
  // (`student-agent stats`): event names and numbers only, never a word of
  // the notes. Appended to the state folder — not the vault, never in a
  // payload — a few lines at a time.
  readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-student/usage.tsv"
  property var usageBuf: []
  property double openedAt: 0

  function used(event, detail) {
    root.usageBuf = root.usageBuf.concat([Math.floor(Date.now() / 1000) + "\t" + event + "\t" + (detail === undefined ? "" : detail)])
  }

  function flushUsage() {
    if (root.usageBuf.length === 0 || usageProc.running) return
    usageProc.command = ["sh", "-c", 'printf "%s\n" "$1" >> "$2"', "sh", root.usageBuf.join("\n"), root.usagePath]
    root.usageBuf = []
    usageProc.running = true
  }

  onShowingChanged: {
    if (root.showing) {
      root.openedAt = Date.now()
      root.used("open", root.overlayOpen ? "overlay" : "window")
    } else if (root.openedAt > 0) {
      root.used("close", Math.round((Date.now() - root.openedAt) / 1000))
      root.openedAt = 0
      root.flushUsage()
    }
  }

  function zoomBy(dir) {
    var steps = root.zoomSteps
    var i = 0
    for (var k = 0; k < steps.length; k++) if (Math.abs(steps[k] - root.zoom) < Math.abs(steps[i] - root.zoom)) i = k
    root.setZoom(steps[Math.max(0, Math.min(steps.length - 1, i + dir))])
  }

  function setZoom(z) {
    if (z === root.zoom) { zoomHint.restart(); return }
    root.zoom = z
    root.used("zoom", z)
    zoomHint.restart()
    zoomFile.setText(JSON.stringify({ zoom: z }) + "\n")
    root.scheduleRepaint()
  }

  // Ctrl+= (or +), Ctrl+-, Ctrl+0: wherever the keyboard is in the page.
  function zoomKey(event) {
    if (!(event.modifiers & Qt.ControlModifier)) return false
    var k = event.key
    if (k === Qt.Key_Equal || k === Qt.Key_Plus) { root.zoomBy(1); return true }
    if (k === Qt.Key_Minus || k === Qt.Key_Underscore) { root.zoomBy(-1); return true }
    if (k === Qt.Key_0) { root.setZoom(1); return true }
    return false
  }

  function openPass() {
    if (!root.openPassPending) return
    root.openPassPending = false
    root.requestRun("open", "")
  }

  // What the shell calls to hide the page: the overlay goes, the window
  // (if open) stays and gets the sheet back.
  function close() {
    root.leftLine(root.lastLine)
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
    root.used("pin", root.overlayOpen ? "to-window" : "to-overlay")
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
  function applyText(t, keepCursor) {
    var at = editor.cursorPosition
    root.applying = true
    editor.load(t)
    root.applying = false
    // Line indices belong to the text they were taken from.
    root.lastLine = -1
    if (keepCursor) editor.setCursor(Math.min(at, editor.length))
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
    if (!root.agentDay) return
    root.flush()
    var cmd = [svc.runner, "run", "--trigger", trigger, "--date", svc.noteDate]
    if (hash) cmd.push("--hash", hash)
    root.enqueue(cmd, hash)
  }

  function stage(trigger, hashes) {
    if (!hashes || hashes.length === 0 || !root.agentDay) return
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
  property string hint: ""   // a passing word under the cursor (a date that did not read, …)
  function showHint(t) { root.hint = t; hintTimer.restart() }
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
    root.used("send", trigger)
    root.ask = null
    root.unstage(hashes)
    root.requestRun(trigger, hashes.join(","))
  }

  function askAbout(trigger, hashes) {
    if (!hashes || hashes.length === 0 || !root.agentDay) return
    root.ask = { kind: "send", hashes: hashes, trigger: trigger, yes: false }
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
      root.ask = Object.assign({}, root.ask, { yes: !root.ask.yes })
      return true
    }
    // No letters answer a prompt: a "y" may be the first letter of the
    // next word (in Spanish it is a word), and a prompt must never act on
    // what was meant as writing.
    if (k === Qt.Key_Escape) { root.declineAsk(); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (root.ask.yes) { root.acceptAsk(); return true }
      root.declineAsk()
      return false   // a plain Enter: let it fall through and behave as usual
    }
    root.declineAsk()   // anything else: the prompt just goes away
    return false
  }

  // Three things are ever asked under the cursor: send this block to the
  // agent, make this line a deadline, and delete the deadline of a line
  // that went.
  function acceptAsk() {
    var a = root.ask
    root.ask = null
    if (!a) return
    root.used("prompt", a.kind + ":yes")
    if (a.kind === "send") root.send(a.trigger, a.hashes)
    else if (a.kind === "deadline") root.bindCue(a.raw, a.cue, a.ms)
    else if (a.kind === "delete") dl.hide(a.id)
  }

  function declineAsk() {
    var a = root.ask
    root.ask = null
    if (a) root.used("prompt", a.kind + ":no")
    if (a && a.kind === "deadline") {
      var d = Object.assign({}, root.declined)
      d[a.raw] = true
      root.declined = d
    }
  }

  function askText(a) {
    var choice = (a.yes ? "[yes]   no" : "yes   [no]") + "   · ←→ choose · Enter"
    if (a.kind === "deadline") return "deadline: " + a.cue.title + " · " + a.label + "?   " + choice
    if (a.kind === "delete") return "this line had a deadline: " + a.title + ". remove it too (kept in history)?   " + choice
    return "send to agent?   " + choice
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
    if (!root.agentDay) return
    root.flush()
    root.enqueue([svc.runner, "chat", "--hash", hash, "--message", message, "--date", svc.noteDate], hash)
  }

  // In order, each once: a confirmed send must never be dropped because
  // something else was asked for while the runner was busy.
  function enqueue(cmd, hash) {
    var key = JSON.stringify(cmd)
    for (var i = 0; i < root.queued.length; i++) if (JSON.stringify(root.queued[i].cmd) === key) return
    root.queued = root.queued.concat([{ cmd: cmd, hash: hash }])
    if (!svc.saving) root.launchQueued()
  }

  function launchQueued() {
    if (root.queued.length === 0 || root.running || svc.saving) return
    var q = root.queued[0]
    root.queued = root.queued.slice(1)
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
    if (root.zoomKey(event)) return true
    if (k === Qt.Key_Escape) { if (!root.alongside) root.dismiss(); return true }
    if (k === Qt.Key_P && ctrl) { root.togglePin(); return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ctrl) { root.sendCurrent(); return true }
    if (k === Qt.Key_Up && alt) { root.jumpBlock(-1); return true }
    if (k === Qt.Key_Down && alt) { root.jumpBlock(1); return true }
    if (k === Qt.Key_Up && ctrl) { root.jumpWithinBlock(-1); return true }
    if (k === Qt.Key_Down && ctrl) { root.jumpWithinBlock(1); return true }
    if (k === Qt.Key_Right && alt) { root.diveIn(); return true }
    if (k === Qt.Key_T && ctrl) { root.toggleTasks(); return true }
    if (k === Qt.Key_F && ctrl) { root.openSearch(); return true }
    if (k === Qt.Key_B && ctrl) { root.toggleSidebar(); return true }
    if (k === Qt.Key_D && ctrl) { root.deadlineKey(); return true }
    if (k === Qt.Key_Left && alt && root.sidebarOpen) { root.focusSidebar(); return true }
    return false
  }

  function diveIn() {
    root.used("margin")
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
    root.pendingAccept = { hash: root.currentHash, index: i }
    acceptProc.command = [svc.runner, "accept", "--hash", root.currentHash, "--index", String(i), "--date", svc.noteDate]
    acceptProc.running = true
  }

  // ------------------------------------------------------------ tasks panel

  function toggleTasks() {
    root.tasksOpen = !root.tasksOpen
    if (root.tasksOpen) root.used("whats-next")
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
  // One list by what bites first: deadlines (late ones are the earliest, so
  // they lead; ones done today stay until tomorrow), then checkboxes with no
  // date, newest day first, then what the agent raised. A checkbox that
  // stands for a deadline is listed once, as the deadline.
  function buildTaskRows() {
    var rows = []
    var older = 0
    var lastDate = ""
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    var due = dl.items.filter(function (d) {
      return d.status === "open" || (d.status === "done" && d.doneAt * 1000 >= today.getTime())
    })
    due.sort(function (a, b) {
      if (a.status !== b.status) return a.status === "open" ? -1 : 1
      return a.due - b.due
    })
    if (due.length > 0) {
      rows.push({ kind: "day", date: "DEADLINES", recent: true })
      for (var k = 0; k < due.length; k++) rows.push({ kind: "deadline", deadline: due[k] })
    }
    for (var i = 0; i < root.tasks.length; i++) {
      var t = root.tasks[i]
      if (/\s\^d\d+\s*$/.test(t.text)) continue
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
    if (row.kind === "deadline") {
      var d = row.deadline
      if (Bound.parseLink(d.link)) { root.backToNote(); root.goToDeadline(d); return }
      // No line yet: the first Enter says so, the second writes one into
      // today's note.
      if (root.contextFor && root.contextFor.deadline === d.id) root.writeIntoToday(d)
      else root.contextFor = { deadline: d.id }
    }
    if (row.kind === "raised") {
      dismissProc.command = [svc.runner, "dismiss", "--date", row.item.date, "--kind", row.item.kind, "--index", String(row.item.index)]
      dismissProc.running = true
    }
  }

  function tickFocused() {
    var row = root.taskRows[root.taskFocus]
    if (row && row.kind === "task") root.tickTask(row.task)
    if (row && row.kind === "deadline") {
      var d = row.deadline
      if (d.status === "open") {
        dl.markDone(d.id)
        root.tickHistory = root.tickHistory.concat([{ deadline: d.id }])
        root.tickBoundLine(d.id, true)
      } else {
        dl.reopen(d.id)
        root.tickBoundLine(d.id, false)
      }
    }
  }

  // A deadline's line in the sheet, ticked or unticked to match (lines in
  // other notes catch up when those are opened).
  function deadlineRowText(d) {
    var at = new Date(d.due * 1000)
    var when = Qt.formatDateTime(at, "ddd d MMM") + (at.getHours() === 23 && at.getMinutes() === 59 ? "" : " " + Qt.formatTime(at, "HH:mm"))
    return (d.status === "open" ? "○ " : "✓ ") + d.title + "   " + when + (d.project ? " · " + d.project : "")
  }

  function deadlineColor(d) {
    if (d.status !== "open") return root.dim
    return d.due * 1000 < Date.now() ? root.urgent : root.foreground
  }

  function tickBoundLine(id, done) {
    var r = root.rowByDeadline(id)
    if (r) root.writeLine(r, r.raw.replace(/^(\s*[-*+] \[)[ xX](\])/, "$1" + (done ? "x" : " ") + "$2"))
  }

  // A deadline no line stands for gets one, at the end of today's note.
  property var pendingWrite: null
  function writeIntoToday(d) {
    root.pendingWrite = d
    root.contextFor = null
    root.backToNote()
    if (svc.isToday && svc.ready) root.doPendingWrite()
    else root.openNote(svc.todayStamp())
  }

  function doPendingWrite() {
    var d = root.pendingWrite
    if (!d || !svc.isToday || !svc.ready) return
    root.pendingWrite = null
    var tag = /^[\w\/-]+$/.test(d.project) ? " #" + d.project : ""
    var line = "- [" + (d.status === "open" ? " " : "x") + "] " + d.title + tag + Bound.tail(d.due * 1000, d.id)
    var t = editor.text
    root.quiet = true
    editor.insert(t.length, (t === "" || t.charAt(t.length - 1) === "\n" ? "" : "\n") + line)
    root.quiet = false
    root.bound = Bound.anchors(editor.text)
    Qt.callLater(root.flush)
    dl.set(d.id, ["--link", Bound.link(svc.noteDate, d.id)])
    root.pendingGoto = d.id
    root.landOnGoto()
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
    if (t.deadline) { dl.reopen(t.deadline); root.tickBoundLine(t.deadline, false); return }
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

  // ------------------------------------------------------------ deadlines

  property var bound: ({})          // id -> { line, checked }: bound lines as last seen
  property bool quiet: false        // the page is writing (binding, catching up): not the student
  property var declined: ({})       // raw lines whose "deadline?" got a no, not asked again
  property int lastLine: -1
  property bool reconcilePending: false
  property var pendingAccept: null  // { hash, index }: an agent proposal accepted, its line to bind
  property var whenFor: null        // the line Ctrl+D is asking "when?" about: { raw, id }

  function rowByRaw(raw, kindOk) {
    var rows = editor.rows
    for (var i = 0; i < rows.length; i++) if (rows[i].raw === raw) return rows[i]
    return null
  }

  function rowByDeadline(id) {
    var rows = editor.rows
    for (var i = 0; i < rows.length; i++) if (rows[i].deadline === id) return rows[i]
    return null
  }

  // Replace a whole line as the page, not the student.
  function writeLine(r, raw) {
    if (!r || raw === r.raw) return
    root.quiet = true
    editor.replace(r.start, r.start + r.raw.length, raw)
    root.quiet = false
    root.bound = Bound.anchors(editor.text)
    root.tickedCount = root.countTicked(editor.text)
    Qt.callLater(root.flush)
  }

  // Give a line its deadline: the words it keeps (`head`), then the tail.
  // The store learns where the line is.
  function writeBinding(raw, head, ms, id) {
    var r = root.rowByRaw(raw)
    if (!r || r.kind !== "task" || r.deadline > 0) return
    root.writeLine(r, r.raw.substring(0, r.prefixLen) + head.replace(/\s+$/, "") + Bound.tail(ms, id))
    dl.set(id, ["--link", Bound.link(svc.noteDate, id)])
    root.used("bound")
  }

  function bindCue(raw, c, ms) {
    var stem = svc.noteDate
    dl.add(c.title, c.project, c.phrase, function (id) {
      if (id > 0 && svc.noteDate === stem) root.writeBinding(raw, c.head, ms, id)
    })
  }

  // What changed among bound lines with the last edit: a box ticked or
  // unticked goes to the store at once; a line gone (not cut) asks.
  function boundEdited(was, now) {
    for (var id in was) {
      if (!(id in now)) {
        var d = dl.byId[id]
        if (d && !editor.cutting) root.ask = { kind: "delete", id: d.id, title: d.title, yes: false }
        continue
      }
      if (was[id].checked !== now[id].checked) {
        if (now[id].checked) dl.markDone(id)
        else dl.reopen(id)
      }
    }
  }

  // The cursor left line `i`: a bound line's words and #tag go to the
  // store; an unbound checkbox ending in a date is asked about.
  function leftLine(i) {
    var r = editor.rows[i]
    if (!r || r.kind !== "task" || !svc.ready || root.quiet) return
    if (r.deadline > 0) {
      var d = dl.byId[r.deadline]
      var title = Bound.titleOf(r.body)
      // A #tag sets the project; a line without one leaves it as it is (an
      // agent's proposal may have named it without the line saying so).
      var project = Bound.projectOf(r.body) || (d ? d.project : "")
      if (d && title !== "" && (title !== d.title || project !== d.project))
        dl.set(d.id, ["--title", title, "--project", project])
      return
    }
    var c = Bound.cue(r.body)
    if (!c || root.declined[r.raw]) return
    var raw = r.raw
    var stem = svc.noteDate
    dl.when(c.phrase, function (w) {
      if (!w || root.ask || svc.noteDate !== stem || !root.rowByRaw(raw)) return
      root.ask = { kind: "deadline", raw: raw, cue: c, ms: w.ms, label: w.label, yes: true }
    })
  }

  function trackLine() {
    var line = root.lineIndexAt(editor.cursorPosition)
    if (line === root.lastLine) return
    var prev = root.lastLine
    root.lastLine = line
    if (prev >= 0) root.leftLine(prev)
  }

  // Ctrl+D: make the line under the cursor a deadline, reschedule it, or
  // (date cleared) unbind it.
  function deadlineKey() {
    root.used("ctrl-d")
    var i = root.lineIndexAt(editor.cursorPosition)
    var r = editor.rows[i]
    if (!r) return
    if (r.kind !== "task") {
      if (r.kind !== "plain" && r.kind !== "bullet" && r.kind !== "blank") return
      editor.toggleCheckbox(i)
      r = editor.rows[i]
    }
    if (r.deadline > 0) {
      var d = dl.byId[r.deadline]
      root.openWhen(r.raw, r.deadline, d ? Qt.formatDateTime(new Date(d.due * 1000), "ddd d MMM HH:mm") : "")
      return
    }
    var c = Bound.cue(r.body)
    if (c) {
      var raw = r.raw
      dl.when(c.phrase, function (w) {
        if (w) root.bindCue(raw, c, w.ms)
        else root.showHint("that date did not read: " + c.phrase)
      })
      return
    }
    root.openWhen(r.raw, 0, "")
  }

  function openWhen(raw, id, text) {
    root.ask = null
    root.whenFor = { raw: raw, id: id }
    whenField.text = text
    whenField.forceActiveFocus()
    whenField.selectAll()
  }

  function closeWhen() {
    root.whenFor = null
    editor.focusNote()
  }

  function submitWhen() {
    var a = root.whenFor
    var text = whenField.text.trim()
    root.closeWhen()
    if (!a) return
    if (a.id > 0) {
      var r = root.rowByDeadline(a.id)
      if (!r) return
      if (text === "") {
        // Unbound by hand: the date goes, and the deadline is asked about
        // like a deleted line's.
        editor.replace(r.bodyEnd, r.start + r.raw.length, "")
        return
      }
      dl.when(text, function (w) {
        if (!w) { root.showHint("that date did not read: " + text); return }
        dl.set(a.id, dl.words(text))
        var now = root.rowByDeadline(a.id)
        if (now) root.writeLine(now, now.raw.slice(0, now.raw.length - now.suffix.length) + Bound.tail(w.ms, a.id))
      })
      return
    }
    if (text === "") return
    var row = root.rowByRaw(a.raw)
    if (!row) return
    var title = Bound.titleOf(row.body)
    if (title === "") { root.showHint("write what it is first, then Ctrl+D"); return }
    var head = row.body
    var project = Bound.projectOf(row.body)
    dl.when(text, function (w) {
      if (!w) { root.showHint("that date did not read: " + text); return }
      var stem = svc.noteDate
      dl.add(title, project, text, function (id) {
        if (id > 0 && svc.noteDate === stem) root.writeBinding(a.raw, head, w.ms, id)
      })
    })
  }

  // Opening a note: its bound lines catch up with the store — ticked or
  // unticked as the deadline is done or open, the date as the store has
  // it, and a line whose deadline is gone keeps its date but not its
  // anchor.
  function reconcile() {
    if (!root.reconcilePending || !dl.loaded || !svc.ready) return
    root.reconcilePending = false
    var a = Bound.anchors(editor.text)
    for (var id in a) {
      var r = editor.rows[a[id].line]
      if (!r || r.deadline !== parseInt(id, 10)) continue
      var d = dl.byId[id]
      var base = r.raw.slice(0, r.raw.length - r.suffix.length)
      var want
      if (!d) {
        want = base + (r.dueAt > 0 ? Bound.tail(r.dueAt, 0) : "")
      } else {
        base = base.replace(/^(\s*[-*+] \[)[ xX](\])/, "$1" + (d.status === "open" ? " " : "x") + "$2")
        want = base + Bound.tail(d.due * 1000, d.id)
      }
      root.writeLine(r, want)
    }
    root.bound = Bound.anchors(editor.text)
    root.landOnGoto()
    root.doPendingWrite()
  }

  // An agent proposal was accepted: once the store has the deadline, the
  // block's first unbound checkbox becomes its line.
  function checkAccept() {
    var pa = root.pendingAccept
    if (!pa) return
    var rec = agent.record(pa.hash)
    var p = rec && rec.proposals ? rec.proposals[pa.index] : null
    var id = p && p.accepted ? p.accepted.id : 0
    if (!id || !dl.byId[id]) return
    root.pendingAccept = null
    var b = root.blockBounds(pa.hash)
    if (!b) return
    for (var i = b.start; i < b.end; i++) {
      var r = editor.rows[i]
      if (!r || r.kind !== "task" || r.deadline > 0) continue
      var c = Bound.cue(r.body)
      root.writeBinding(r.raw, c ? c.head : r.body, dl.byId[id].due * 1000, id)
      return
    }
  }

  // ------------------------------------------------------------ sidebar

  function toggleSidebar() {
    root.sidebarOpen = !root.sidebarOpen
    if (root.sidebarOpen) root.used("calendar")
    if (root.sidebarOpen) root.focusSidebar()
    else editor.focusNote()
  }

  // To a deadline's line: its note opened if need be, the cursor at the end
  // of its words. A deadline no line stands for says so.
  function goToDeadline(d) {
    root.used("goto-deadline")
    var l = d ? Bound.parseLink(d.link) : null
    if (!l) { root.showHint("“" + (d ? d.title : "") + "” is not written in a note yet"); editor.focusNote(); return }
    root.pendingGoto = l.id
    if (l.stem === svc.noteDate && svc.ready) root.landOnGoto()
    else root.openNote(l.stem)
    editor.focusNote()
  }

  function landOnGoto() {
    if (!root.pendingGoto || !svc.ready) return
    var r = root.rowByDeadline(root.pendingGoto)
    root.pendingGoto = 0
    if (r) editor.setCursor(r.bodyEnd, true)
  }

  // Into the calendar, its cursor on the day in the sheet.
  function focusSidebar() {
    var p = svc.configured && svc.noteDate !== "" ? Days.parse(svc.noteDate, svc.dailyFormat()) : null
    root.calFocus = p ? p.date : new Date()
    root.dueFocus = -1
    sidebarKeys.forceActiveFocus()
  }

  function moveCalendar(days, months) {
    root.dueFocus = -1
    var d = root.calFocus
    if (months) d = Days.addMonths(d, months)
    if (days) d = Days.addDays(d, days)
    root.calFocus = d
  }

  function openCalendarDay(d) {
    root.calFocus = d
    root.openNote(Days.stemFor(d, svc.dailyFormat(), root.dayIndex))
    editor.focusNote()
  }

  function collectDays() {
    var out = []
    for (var i = 0; i < dayFiles.count; i++) {
      var name = String(dayFiles.get(i, "fileName"))
      if (/\.md$/i.test(name)) out.push(name.slice(0, -3))
    }
    root.dayStems = out
  }

  // Put another day in the sheet. Whatever is typed is written first, to
  // the note it was typed in; a save still in flight is waited for. What
  // belonged to the old day (staging, the prompt, the margin) goes with it.
  function openNote(stamp) {
    if (stamp === "" || stamp === svc.noteDate) return
    if (root.searchOpen) root.closeSearch(false)
    root.leftLine(root.lastLine)
    root.flush()
    var p = svc.configured ? Days.parse(stamp, svc.dailyFormat()) : null
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    root.used("day", p ? Math.round((today - p.date) / 86400000) : "")
    root.ask = null
    root.staged = ({})
    root.marginOpen = false
    root.tasksOpen = false
    root.marginFocus = -1
    if (svc.saving) { root.pendingStamp = stamp; return }
    svc.openDate(stamp)
  }

  // ------------------------------------------------------------ search

  function openSearch() {
    if (!root.searchOpen) { root.searchFrom = editor.cursorPosition; root.used("find") }
    root.searchOpen = true
    searchField.forceActiveFocus()
    searchField.selectAll()
    root.runSearch()
  }

  // Every case-insensitive occurrence in the rows' words. The current match
  // starts as the first one at or after where the search began.
  function runSearch() {
    var q = searchField.text.toLowerCase()
    var out = []
    if (q !== "") {
      var rows = editor.rows
      for (var i = 0; i < rows.length; i++) {
        var r = rows[i]
        if (r.blank) continue
        var body = r.body.toLowerCase()
        var base = r.start + r.prefixLen
        for (var at = body.indexOf(q); at >= 0; at = body.indexOf(q, at + q.length))
          out.push({ start: base + at, end: base + at + q.length })
      }
    }
    var idx = -1
    for (var k = 0; k < out.length; k++) if (out[k].start >= root.searchFrom) { idx = k; break }
    if (idx < 0 && out.length > 0) idx = 0
    root.matches = out
    root.matchIndex = idx
    root.revealMatch()
  }

  function stepMatch(d) {
    var n = root.matches.length
    if (n === 0) return
    root.matchIndex = (root.matchIndex + d + n) % n
    root.revealMatch()
  }

  function revealMatch() {
    var m = root.matches[root.matchIndex]
    if (!m) return
    var r = editor.rectAt(m.start)
    if (!r) return
    var pad = r.height * 2
    flick.ensureVisible(Qt.rect(r.x, Math.max(0, r.y - pad), r.width, r.height + pad * 2))
  }

  // Ctrl+Enter lands on the match, selected; Esc goes back where it was.
  function closeSearch(go) {
    var m = root.matches[root.matchIndex]
    root.searchOpen = false
    root.matches = []
    root.matchIndex = -1
    if (go && m) editor.select(m.start, m.end)
    else editor.setCursor(root.searchFrom, true)
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
    onLoaded: { root.applyText(svc.body); root.reconcilePending = true; root.reconcile(); root.openPass() }
    onExternalChange: { root.applyText(svc.body, true); root.reconcilePending = true; root.reconcile() }
    onSavedNow: {
      if (root.pendingStamp !== "") {
        var s = root.pendingStamp
        root.pendingStamp = ""
        svc.openDate(s)
      }
      root.launchQueued()
    }
  }

  Deadlines {
    id: dl
    onItemsChanged: { root.reconcile(); root.checkAccept() }
  }

  AgentState {
    id: agent
    config: svc.config
    date: svc.noteDate
    onStateChanged: { root.scheduleRepaint(); root.checkAccept() }
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
      // The note may have changed since the list was read (Tasks.js).
      var at = Tasks.find(lines, t.line, t.text, p.untick)
      if (at >= 0) {
        lines[at] = Tasks.flip(lines[at], !p.untick)
        setText(lines.join("\n"))
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
        ackProc.command = [svc.runner, "ack", "--hash", root.currentHash, "--date", svc.noteDate]
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

  // The daily folder, for the sidebar. Watched, so today's note appears as
  // soon as it is written.
  FolderListModel {
    id: dayFiles
    folder: svc.configured ? "file://" + svc.config.vault + "/" + svc.config.daily.dir : ""
    nameFilters: ["*.md"]
    showDirs: false
    showDotAndDotDot: false
    onStatusChanged: if (status === FolderListModel.Ready) root.collectDays()
    onCountChanged: root.collectDays()
  }

  Process { id: usageProc; onExited: root.flushUsage() }
  Timer { interval: 300000; running: root.usageBuf.length > 0; repeat: true; onTriggered: root.flushUsage() }

  // The zoom step survives restarts. Machine state, not config, and never
  // in the vault.
  FileView {
    id: zoomFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-student/page.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var z = Number(JSON.parse(text()).zoom)
        if (isFinite(z) && z >= 0.5 && z <= 3) root.zoom = z
      } catch (e) {}
    }
  }

  // The zoom level shows in the header for a moment after it changes.
  Timer { id: zoomHint; interval: 1500 }

  Timer {
    id: hintTimer
    interval: 2500
    onTriggered: { root.noSignHint = false; root.hint = "" }
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
    title: root.windowTitle
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
      font.pixelSize: root.fs(Style.font.bodySmall)
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
      x: root.alongside ? root.sideSpace : Math.max(Math.round((content.width - width) / 2), root.sideSpace > 0 ? root.sideSpace + root.sheetMargin : 0)
      y: root.alongside ? 0 : root.sheetMargin
      width: root.alongside ? content.width - root.sideSpace - (root.marginOpen ? root.marginWidth + root.marginGap : 0) : root.sheetWidth
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
            color: svc.isToday ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          // On another day: the way back to today.
          Text {
            visible: !svc.isToday && svc.noteDate !== ""
            anchors.left: dateText.right
            anchors.leftMargin: root.sp(12)
            anchors.verticalCenter: dateText.verticalCenter
            textFormat: Text.PlainText
            text: root.agentDay ? "back to today" : "back to today · agent off for this note"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.openNote(svc.todayStamp()); editor.focusNote() }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.sp(10)

            Text {
              visible: zoomHint.running
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Math.round(root.zoom * 100) + "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.bodySmall)
            }

            // The pin: which shape you are in. Ctrl+P or a click flips it.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "pin"
              color: root.alongside ? root.foreground : root.faint
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.bodySmall)
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
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
            }

            // Saved / unsaved: a dot that brightens while a write is
            // pending and settles once it landed.
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: root.sp(6)
              height: width
              radius: width / 2
              color: root.problem !== "" ? root.urgent : (svc.pending || svc.saving ? root.foreground : root.faint)
              Behavior on color { ColorAnimation { duration: 180 } }
            }
          }
        }

        // The search line: only there while searching.
        Item {
          id: searchBar
          visible: root.searchOpen
          anchors.top: header.bottom
          anchors.topMargin: root.searchOpen ? root.sp(16) : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.searchOpen ? searchField.implicitHeight : 0

          TextField {
            id: searchField
            anchors.left: parent.left
            anchors.right: searchCount.left
            anchors.rightMargin: root.sp(12)
            placeholderText: "find in today's note"
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
            foreground: root.foreground
            onTextChanged: if (root.searchOpen) root.runSearch()
            Keys.onPressed: function (event) {
              var ctrl = event.modifiers & Qt.ControlModifier
              var k = event.key
              if (root.zoomKey(event)) { event.accepted = true; return }
              if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                if (ctrl) root.closeSearch(true)
                else root.stepMatch(event.modifiers & Qt.ShiftModifier ? -1 : 1)
                event.accepted = true
              } else if (k === Qt.Key_Escape) {
                root.closeSearch(false)
                event.accepted = true
              } else if (k === Qt.Key_F && ctrl) {
                searchField.selectAll()
                event.accepted = true
              }
            }
          }

          Text {
            id: searchCount
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: searchField.text === "" ? "Enter next · Shift+Enter back · Ctrl+Enter go"
              : (root.matches.length === 0 ? "no match" : (root.matchIndex + 1) + " / " + root.matches.length)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }
        }

        Text {
          visible: root.problem !== ""
          anchors.top: searchBar.bottom
          anchors.topMargin: root.sp(24)
          anchors.left: parent.left
          anchors.right: parent.right
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.problem
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.body)
        }

        Flickable {
          id: flick
          visible: root.problem === ""
          anchors.top: searchBar.bottom
          anchors.topMargin: root.sp(24)
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
              x: root.sp(2)
              y: modelData.y
              width: root.sp(3)
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
            accent: root.accent
            urgent: root.urgent
            marks: root.matches
            currentMark: root.matchIndex
            tabStop: 4 * root.sp(8)
            keyFilter: root.pageKey

            onCursorRectChanged: flick.ensureVisible(cursorRect)
            onCursorPositionChanged: { root.currentHash = root.hashNearLine(root.lineIndexAt(cursorPosition)); root.trackLine() }
            onWidthChanged: root.scheduleRepaint()
            onHeightChanged: root.scheduleRepaint()
            onReturnFinished: function (lineIndex, lineText) { root.lineFinished(lineIndex, lineText) }
            onListLeft: function (lineIndex) { root.listLeft(lineIndex) }
            onTextChanged: {
              if (root.searchOpen) Qt.callLater(root.runSearch)
              var was = root.bound
              root.bound = Bound.anchors(text)
              if (root.applying) return
              svc.markPending(text)
              saveTimer.restart()
              if (root.quiet) return
              root.boundEdited(was, root.bound)
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
            visible: (!!root.ask || root.noSignHint || root.hint !== "") && !root.whenFor
            x: root.gutter
            y: editor.cursorRect.y + editor.cursorRect.height + root.sp(2)
            width: editor.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.hint !== "" ? root.hint
              : root.noSignHint
              ? "no sign for the agent on this block — start a line with @, make it a checkbox, or end it with ?"
              : (root.ask ? root.askText(root.ask) : "")
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
            z: 2
          }

          // Ctrl+D's question: when? Under the line, in the page's own words.
          Row {
            visible: !!root.whenFor
            x: root.gutter
            y: editor.cursorRect.y + editor.cursorRect.height + root.sp(4)
            spacing: root.sp(8)
            z: 3
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "when?"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            TextField {
              id: whenField
              width: root.sp(220)
              placeholderText: root.whenFor && root.whenFor.id > 0 ? "empty: no deadline" : "fri 17:00 · in 3 days · 20 oct"
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.body)
              foreground: root.foreground
              Keys.onPressed: function (event) {
                if (root.zoomKey(event)) { event.accepted = true; return }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitWhen(); event.accepted = true }
                else if (event.key === Qt.Key_Escape) { root.closeWhen(); event.accepted = true }
              }
            }
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

    // The sidebar: the daily notes, only while asked for.
    BorderSurface {
      id: sidebar
      visible: root.sidebarOpen && root.problem === ""
      x: root.alongside ? 0 : sheet.x - root.marginGap - root.sidebarWidth
      y: sheet.y
      height: sheet.height
      width: root.sidebarWidth
      radius: root.alongside ? 0 : Style.cornerRadius
      color: root.background
      borderSpec: root.alongside ? Border.none() : root.borderSpec
      padding: root.sp(16)

      MouseArea { anchors.fill: parent; onClicked: {} }

      // In the window the sidebar sits on the same ground as the sheet; a
      // hairline keeps them apart.
      Rectangle {
        visible: root.alongside
        anchors.right: parent.right
        anchors.rightMargin: -Math.round(root.marginGap / 2)
        width: 1
        height: parent.height
        color: root.faint
      }

      Item {
        id: sidebarKeys
        anchors.fill: parent
        Keys.onPressed: function (event) {
          var ctrl = event.modifiers & Qt.ControlModifier
          var alt = event.modifiers & Qt.AltModifier
          var k = event.key
          if (root.zoomKey(event)) { event.accepted = true; return }
          // In the day's deadline list (Tab went there): up/down pick,
          // Enter goes to the line, Tab or Esc back to the days.
          if (root.dueFocus >= 0 && !ctrl && !alt) {
            var n = root.focusDue.length
            if (k === Qt.Key_Up) root.dueFocus = Math.max(0, root.dueFocus - 1)
            else if (k === Qt.Key_Down) root.dueFocus = Math.min(n - 1, root.dueFocus + 1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.goToDeadline(root.focusDue[root.dueFocus])
            else if (k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_Escape) root.dueFocus = -1
            else { root.dueFocus = -1; return }
            event.accepted = true
            return
          }
          if (k === Qt.Key_Tab && root.focusDue.length > 0) {
            root.dueFocus = 0
          } else if (k === Qt.Key_Escape || (k === Qt.Key_B && ctrl)) {
            if (k === Qt.Key_B) root.sidebarOpen = false
            editor.focusNote()
          } else if (k === Qt.Key_Right && alt) {
            editor.focusNote()
          } else if (k === Qt.Key_Left) {
            if (ctrl) root.moveCalendar(0, -1)
            else root.moveCalendar(-1, 0)
          } else if (k === Qt.Key_Right) {
            if (ctrl) root.moveCalendar(0, 1)
            else root.moveCalendar(1, 0)
          } else if (k === Qt.Key_Up) {
            root.moveCalendar(-7, 0)
          } else if (k === Qt.Key_Down) {
            root.moveCalendar(7, 0)
          } else if (k === Qt.Key_PageUp) {
            root.moveCalendar(0, -1)
          } else if (k === Qt.Key_PageDown) {
            root.moveCalendar(0, 1)
          } else if (k === Qt.Key_Home) {
            root.calFocus = new Date()
          } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.openCalendarDay(root.calFocus)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: calendar
        anchors.fill: parent
        anchors.topMargin: sidebar.contentTopInset
        anchors.leftMargin: sidebar.contentLeftInset
        anchors.rightMargin: sidebar.contentRightInset
        anchors.bottomMargin: sidebar.contentBottomInset
        spacing: root.sp(10)

        readonly property real cell: Math.floor(width / 7)

        // Month, with a way to step it by mouse.
        Item {
          width: parent.width
          height: monthText.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "‹"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.title)
            MouseArea { anchors.fill: parent; anchors.margins: -root.sp(6); cursorShape: Qt.PointingHandCursor; onClicked: root.moveCalendar(0, -1) }
          }
          Text {
            id: monthText
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: Days.monthLabel(root.calFocus)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
            font.weight: Font.DemiBold
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "›"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.title)
            MouseArea { anchors.fill: parent; anchors.margins: -root.sp(6); cursorShape: Qt.PointingHandCursor; onClicked: root.moveCalendar(0, 1) }
          }
        }

        Grid {
          columns: 7

          // Weekday initials, from the locale's first day.
          Repeater {
            model: 7
            Text {
              required property int index
              width: calendar.cell
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: Qt.locale().dayName((root.firstDow + index) % 7, Locale.NarrowFormat)
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.caption)
            }
          }

          // The days: full where a note exists, faded where none does.
          Repeater {
            model: root.calCells
            Item {
              id: dayCell
              required property var modelData
              readonly property string k: modelData ? Days.key(modelData) : ""
              readonly property bool hasNote: k !== "" && !!root.dayIndex[k]
              readonly property bool isOpen: k !== "" && k === root.openKey
              readonly property bool isCursor: k !== "" && k === Days.key(root.calFocus)
              readonly property bool isToday: k !== "" && k === Days.key(new Date())
              width: calendar.cell
              height: Math.round(calendar.cell * 0.92)

              Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Style.cornerRadius
                visible: dayCell.isCursor && sidebarKeys.activeFocus
                color: Style.selectedFill
              }
              Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Style.cornerRadius
                visible: dayCell.isOpen
                color: "transparent"
                border.width: 1
                border.color: root.dim
              }
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData ? modelData.getDate() : ""
                color: dayCell.hasNote ? root.foreground : Util.alpha(root.foreground, 0.28)
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.body)
                font.weight: dayCell.isOpen ? Font.DemiBold : Font.Normal
              }
              Rectangle {
                visible: dayCell.isToday
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.max(2, Math.round(calendar.cell * 0.1))
                width: Math.max(3, Math.round(calendar.cell * 0.12))
                height: width
                radius: width / 2
                color: root.accent
              }
              // Deadlines on this day: a corner mark — accent while one is
              // open, urgent when one is late, hollow when all are done.
              Rectangle {
                readonly property var due: dayCell.k !== "" ? (root.dueByDay[dayCell.k] || []) : []
                readonly property bool open: due.some(function (d) { return d.status === "open" })
                readonly property bool late: due.some(function (d) { return d.status === "open" && d.due * 1000 < Date.now() })
                visible: due.length > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Math.round(calendar.cell * 0.12)
                anchors.rightMargin: Math.round(calendar.cell * 0.12)
                width: Math.max(4, Math.round(calendar.cell * 0.16))
                height: width
                radius: Math.max(1, Math.round(width * 0.3))
                color: late ? root.urgent : (open ? root.accent : "transparent")
                border.width: open ? 0 : 1
                border.color: root.dim
              }
              MouseArea {
                anchors.fill: parent
                enabled: !!modelData
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCalendarDay(modelData)
              }
            }
          }
        }

        // The day under the cursor, and whether it has a note yet.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: svc.configured
            ? Days.longLabel(Days.format(root.calFocus, svc.dailyFormat()), svc.dailyFormat())
              + (root.dayIndex[Days.key(root.calFocus)] ? "" : " · no note")
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.bodySmall)
        }

        // That day's deadlines. Tab goes into the list; Enter or a click
        // goes to the line that stands for one.
        Repeater {
          model: root.focusDue
          Rectangle {
            required property var modelData
            required property int index
            readonly property bool late: modelData.status === "open" && modelData.due * 1000 < Date.now()
            width: calendar.width
            height: dueRow.implicitHeight + root.sp(6)
            radius: Style.cornerRadius
            color: root.dueFocus === index && sidebarKeys.activeFocus ? Style.selectedFill : "transparent"
            Text {
              id: dueRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: root.sp(4)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: (modelData.status === "open" ? "○ " : "✓ ") + modelData.title
                + " · " + Qt.formatTime(new Date(modelData.due * 1000), "HH:mm")
                + (modelData.project ? " · " + modelData.project : "")
                + (Bound.parseLink(modelData.link) ? "" : " · no line")
              color: late ? root.urgent : (modelData.status === "open" ? root.foreground : root.dim)
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToDeadline(modelData)
            }
          }
        }

        Text {
          width: parent.width
          visible: sidebarKeys.activeFocus
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.dueFocus >= 0 ? "↑↓ pick · Enter goes to its line · Tab back to the days"
            : "arrows move · Ctrl+←→ month · Home today · Enter opens" + (root.focusDue.length > 0 ? " · Tab: this day's deadlines" : "")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.caption)
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
      padding: root.sp(22)

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Keyboard focus while in the margin (proposal rows or the tasks
      // panel). The chat field has its own handling.
      Item {
        id: marginKeys
        anchors.fill: parent
        Keys.onPressed: function (event) {
          var alt = event.modifiers & Qt.AltModifier
          var k = event.key
          if (root.zoomKey(event)) { event.accepted = true; return }
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
        anchors.topMargin: margin.contentTopInset + root.sp(4)
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
          spacing: root.sp(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "WHAT'S NEXT"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
          }

          Text {
            width: parent.width
            visible: root.taskRows.length === 0
            textFormat: Text.PlainText
            text: "nothing open"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          Repeater {
            model: root.taskRows
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool hot: root.taskFocus === index && modelData.kind !== "day"
              width: tasksColumn.width
              height: rowText.implicitHeight + (modelData.kind === "day" ? root.sp(12) : root.sp(8))
              radius: Style.cornerRadius
              color: hot ? Style.selectedFill : "transparent"
              Text {
                id: rowText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.sp(6)
                anchors.rightMargin: root.sp(6)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.sp(4)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: modelData.kind === "day" ? modelData.date
                  : modelData.kind === "older" ? "+" + modelData.count + " older · Enter to show"
                  : modelData.kind === "raised"
                    ? (modelData.item.kind === "suggestion" ? "◇ " : "· ") + modelData.item.text
                      + (modelData.item.evidence ? "\n   " + modelData.item.evidence : "")
                  : modelData.kind === "deadline" ? root.deadlineRowText(modelData.deadline)
                    : "○ " + modelData.task.text.replace(/\s+📅[\s\S]*$/, "")
                color: modelData.kind === "day" ? root.dim : (modelData.kind === "older" ? root.faint
                  : modelData.kind === "deadline" ? root.deadlineColor(modelData.deadline) : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: modelData.kind === "day" ? root.fs(Style.font.caption) : root.fs(Style.font.body)
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
            visible: !!root.contextFor && (root.contextFor.deadline !== undefined || contextFile.snippet !== "")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: !root.contextFor ? ""
              : root.contextFor.deadline !== undefined ? "Not written in a note yet. Enter again writes it into today's note."
              : root.contextFor.date + "\n\n" + contextFile.snippet
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "↑↓ move · Enter goes to it · Space ticks · Ctrl+Z unticks · Esc back"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
          }
        }
      }

      Flickable {
        id: marginFlick
        visible: !root.tasksOpen
        anchors.top: parent.top
        anchors.topMargin: margin.contentTopInset + root.sp(4)
        anchors.left: parent.left
        anchors.leftMargin: margin.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: margin.contentRightInset
        anchors.bottom: chatBox.top
        anchors.bottomMargin: root.sp(10)
        clip: true
        contentWidth: width
        contentHeight: marginColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: marginColumn
          width: parent.width
          spacing: root.sp(12)

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
            font.pixelSize: root.fs(Style.font.title)
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
              height: propText.implicitHeight + root.sp(10)
              radius: Style.cornerRadius
              color: hot ? Style.selectedFill : "transparent"
              border.width: hot ? 1 : 0
              border.color: root.accent
              Text {
                id: propText
                anchors.fill: parent
                anchors.margins: root.sp(5)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: (done ? "✓ " : "○ ") + (modelData.kind === "deadline"
                  ? "deadline: " + modelData.title + " — " + modelData.when + ((modelData.project || modelData.subject) ? " · " + (modelData.project || modelData.subject) : "")
                    + (done && modelData.accepted.id ? "  #" + modelData.accepted.id : "")
                    + (modelData.error ? "  (failed: " + modelData.error + ")" : "")
                  : JSON.stringify(modelData))
                color: done ? root.dim : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.bodySmall)
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
              font.pixelSize: root.fs(Style.font.title)
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
            font.pixelSize: root.fs(Style.font.bodySmall)
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
          font.pixelSize: root.fs(Style.font.body)
          foreground: root.foreground
          Keys.onReturnPressed: function (event) { event.accepted = true; root.sendChat() }
          Keys.onEnterPressed: function (event) { event.accepted = true; root.sendChat() }
          Keys.onEscapePressed: function (event) { event.accepted = true; root.backToNote() }
          Keys.onPressed: function (event) {
            if (root.zoomKey(event)) { event.accepted = true; return }
            if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) { root.backToNote(); event.accepted = true }
            else if (event.key === Qt.Key_Up && text === "" && root.currentProposals.length > 0) { root.moveMarginFocus(-1); event.accepted = true }
          }
        }
      }
    }
  }
}
