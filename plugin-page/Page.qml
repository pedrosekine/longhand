import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "Blocks.js" as Blocks
import "Bound.js" as Bound
import "Dates.js" as Dates
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
// and the student says so — by pressing Ctrl+Enter or the header's "ask",
// which both send the block the cursor is in (a run of list items counts as
// one submission). Writing is never interrupted to offer it: the prompt
// that used to ask went on 2026-10-15, answered no 41 times against yes
// once, and nothing is held in between or marked as sendable, because every
// block is. A block without a sign never goes. Opening the page runs one automatic pass so answers are
// waiting when you come back.
//
// The agent's answers are painted, never inserted, and only in the
// gutter — the student's words are always drawn at full strength (a veil
// over seen blocks was tried and made the note hard to read): a block with
// a reply carries a filled mark, accent until you have looked at it. Nothing else is on
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
// Under the calendar, the projects that exist (the agent's
// knowledge/projects/, via `student-agent projects`), soonest session
// first: the tags to use, so no new ones get invented. Enter starts a
// class — `# Course #tag` on a new line at the end of today's note, the
// cursor under it; Ctrl+Enter puts just the tag at the cursor.
//
// Deadlines live in the store (`pomo deadline`); a checkbox line can stand
// for one (Bound.js). Write a checkbox that ends in a date — "due fri
// 17:00", "by monday", "📅 tomorrow" — and the date lights up as it is
// typed, its pill shown in the accent (Dates.js reads it, at once, in the
// page); leaving the line makes it the deadline, no question asked, as
// Todoist does. Backspace right as it lights up, Ctrl+D on the line, or
// Ctrl+Z after it is bound keep the date as words. Ctrl+D on a line not
// being written binds it on purpose, reschedules a bound line, or (date
// cleared) unbinds it. A list leaves for the agent only once its dates are
// bound, so the agent sees them as deadlines. A bound line
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
  readonly property alias searchInput: searchField
  readonly property alias palette: pal
  property bool overlayOpen: false
  property bool windowOpen: false
  readonly property bool opened: overlayOpen          // what the shell's toggle asks
  readonly property bool showing: overlayOpen || windowOpen
  readonly property bool alongside: !overlayOpen      // where the sheet is drawn

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  // The Omarchy theme's palette, by role (ThemeColors.qml): secondary and faint
  // text in the theme's own tuned greys, headings and marks in its colours.
  readonly property color accent: pal.accent
  readonly property color dim: pal.dim
  readonly property color faint: pal.faint
  readonly property color urgent: pal.red
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

  // The measure: a line of text holds at most `measureChars` characters,
  // the reading length typography settles on (45–75). It is counted in the
  // page's own type, so it follows the zoom and the font: zoomed in, the
  // column widens with the letters and still holds 72; zoomed out, the
  // space beside it grows, never the lines. A window narrower than the
  // measure just wraps. The same in the window and on the overlay.
  readonly property int measureChars: 72
  FontMetrics { id: bodyMetrics; font.family: root.fontFamily; font.pixelSize: root.textSize }
  readonly property real chWidth: bodyMetrics.averageCharacterWidth
  readonly property int measure: Math.round(root.chWidth * root.measureChars)
  readonly property int sheetFor: root.measure + 2 * root.sheetPadding
  readonly property int sheetWidth: Math.min(root.sheetFor, content.width - root.sp(48))
  // In the window the sheet is centred in the room beside the sidebar; an
  // open margin moves it left only as far as it has to, so opening one
  // where there is room does not shift the text.
  readonly property int sheetRoom: content.width - root.sideSpace - (root.marginOpen ? root.marginWidth + root.marginGap : 0)
  readonly property int windowSheetWidth: Math.max(0, Math.min(root.sheetFor, root.sheetRoom))
  readonly property int windowSheetX: root.sideSpace + Math.max(0, Math.min(
    Math.round((content.width - root.sideSpace - root.windowSheetWidth) / 2), root.sheetRoom - root.windowSheetWidth))
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
  // A project's sections want more room than a month grid, but only where
  // the note can still have its full measure beside them.
  readonly property int sidebarWidth: root.projectOpen
    && content.width - root.sp(320) - root.marginGap >= root.sheetFor ? root.sp(320) : root.sp(236)

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
  property int projFocus: -1         // in the projects list (-1: not there)
  property var projects: []          // [{ tag, name, next: { at, room } }]
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
  property var ask: null         // { hashes, trigger, yes } — the prompt after Enter
  property bool marginOpen: false
  property int marginFocus: -1   // -1 note; 0..n-1 proposal rows; n = chat field
  property bool tasksOpen: false
  property bool projectOpen: false   // the margin is showing one project's notes
  property var sections: []          // [{ date, line, heading, title, sub, preview, open, done }]
  property string projectTag: ""
  property string projectName: ""
  property int sectionFocus: 0
  property var pendingSection: null  // a heading to land on once its note is open
  property var tasks: []
  property var raised: []
  property var tickHistory: []   // ticks made from the panel, newest last, for Ctrl+Z
  property var contextFor: null  // task whose surrounding block is shown in the panel
  property bool showOlder: false
  property int taskFocus: 0
  property string currentHash: ""
  property string currentTrigger: ""   // the sign on the block under the cursor, for the header's "ask"
  property bool searchOpen: false
  property var matches: []       // [{ start, end }] text offsets, in note order
  property int matchIndex: -1
  property int searchFrom: 0     // the cursor when the search opened
  readonly property var currentRecord: agent.record(currentHash)
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
      // The margin is on-demand only, so a page opened from nothing shows
      // the note alone — not the panel the last session left open.
      root.marginOpen = false
      root.tasksOpen = false
      root.projectOpen = false
      root.marginFocus = -1
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
    if (/^[-*+] \[[xX]\] \S/.test(t)) return "tick"
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

  // Ctrl+Enter: send the block under the cursor, if it carries a sign for
  // the agent. A block without one stays where it is; the margin says why.
  property bool noSignHint: false
  property string hint: ""   // a passing word under the cursor (a date that did not read, …)
  function showHint(t) { root.hint = t; hintTimer.restart() }
  function sendCurrent() {
    if (root.currentHash === "") return
    if (root.currentTrigger === "") { root.noSignHint = true; hintTimer.restart(); return }
    // A dated item may still be binding. The agent has to see its dates as
    // deadlines, never as words to propose a second time (2026-10-13), so
    // the send waits for the queue — as the prompt used to before it went.
    root.whenWritten(function () {
      var h = root.hashNearLine(root.lineIndexAt(editor.cursorPosition))
      if (h === "") return
      var trigger = root.triggerForBlock(h)
      if (trigger === "") { root.noSignHint = true; hintTimer.restart(); return }
      // A list of boxes is one submission however it is sent.
      root.send(trigger, trigger === "checkbox" || trigger === "tick" ? root.listAround(h) : [h])
    })
  }

  function send(trigger, hashes) {
    root.used("send", trigger)
    root.ask = null
    root.requestRun(trigger, hashes.join(","))
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
    root.declineAsk(true)   // anything else: the prompt just goes away
    return false
  }

  // One thing is ever asked under the cursor now: delete the deadline of a
  // line that went. (A date at the end of a checkbox is not asked about
  // either: it lights up and binds. Sending is never asked about — the
  // header's "ask" and Ctrl+Enter are the ways in.)
  function acceptAsk() {
    var a = root.ask
    root.ask = null
    if (!a) return
    root.used("prompt", a.kind + ":yes")
    if (a.kind === "delete") dl.hide(a.id)
  }

  // `brushed`: typed past, not answered.
  function declineAsk(brushed) {
    var a = root.ask
    root.ask = null
    if (a) root.used("prompt", a.kind + (brushed ? ":dismissed" : ":no"))
  }

  function askText(a) {
    var choice = (a.yes ? "[yes]   no" : "yes   [no]") + "   · ←→ choose · Enter"
    return "this line had a deadline: " + a.title + ". remove it too (kept in history)?   " + choice
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
      if (!rec) continue
      var r = editor.blockRect(b.start, b.end)
      if (!r) continue
      out.push({ hash: b.hash, y: r.y, h: r.h,
                 reply: rec.state === "reply", unread: rec.state === "reply" && !rec.read })
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

  // The editor carries list markers over Enter itself. The page used to
  // ask "send to agent?" here; it asks nothing now (2026-10-15 — the
  // prompt was answered no 41 times against yes once, and the agent has
  // the header's "ask" and Ctrl+Enter instead). Writing a line is never
  // interrupted by the agent again.
  function lineFinished(lineIndex, lineText) {
    Qt.callLater(root.flush)
  }

  // Enter on an empty item left the list. Its dated items bind as each is
  // left; nothing is asked. A list is still one submission when it is sent
  // — `listAround` works that out from the cursor.
  function listLeft(lineIndex) {
    Qt.callLater(root.flush)
  }

  property var afterWrites: []
  function whenWritten(fn) {
    if (!dl.busy) fn()
    else root.afterWrites = root.afterWrites.concat([fn])
  }

  // Keys the page owns, ahead of editing. True when taken.
  function pageKey(event) {
    var ctrl = event.modifiers & Qt.ControlModifier
    var alt = event.modifiers & Qt.AltModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var k = event.key
    if (root.askKey(event)) return true
    if (root.zoomKey(event)) return true
    if (k === Qt.Key_Escape) { if (!root.alongside) root.dismiss(); return true }
    if (k === Qt.Key_P && ctrl) { root.togglePin(); return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ctrl) { root.sendCurrent(); return true }
    if (k === Qt.Key_Up && alt) { root.jumpBlock(-1); return true }
    if (k === Qt.Key_Down && alt) { root.jumpBlock(1); return true }
    // With Shift these select instead (the editor's selectToBlockEdge).
    if (k === Qt.Key_Up && ctrl && !shift) { root.jumpWithinBlock(-1); return true }
    if (k === Qt.Key_Down && ctrl && !shift) { root.jumpWithinBlock(1); return true }
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
    if (!p || p.accepted || root.currentHash === "" || acceptProc.running) return
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

  // ------------------------------------------------- a project's notes

  // Class notes found by their course instead of by the date they happened
  // on (the week of 2026-10-12 opened the calendar 31 times looking for
  // them): every section of the project's tag, newest first, opened in
  // place. The claiming rule lives in `student-agent sections`.
  function openProject(pr) {
    if (!pr) return
    root.used("project-notes")
    root.projectTag = pr.tag
    root.projectName = pr.name || pr.tag
    root.sections = []
    root.sectionFocus = 0
    root.sidebarOpen = true
    root.projectOpen = true
    sectionsProc.command = [svc.runner, "sections", "--tag", pr.tag]
    sectionsProc.running = true
    sidebarKeys.forceActiveFocus()
  }

  // The projects list's keys, in one function so the page can be driven
  // without a keyboard. Enter (or Right) opens the project's own notes —
  // the list is there to find them. Writing into the note is the shifted
  // pair: Shift+Enter starts a class, Ctrl+Enter puts the tag at the
  // cursor. Inverted 2026-10-15; `@` in the note is the way to write one.
  function projectsKey(k, ctrl, shift) {
    var pr = root.projects[root.projFocus]
    if (k === Qt.Key_Up && !ctrl) root.projFocus = Math.max(0, root.projFocus - 1)
    else if (k === Qt.Key_Down && !ctrl) root.projFocus = Math.min(root.projects.length - 1, root.projFocus + 1)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (pr && ctrl) root.insertTag(pr)
      else if (pr && shift) root.startClass(pr)
      else if (pr) root.openProject(pr)
    }
    else if (k === Qt.Key_Right && !ctrl) root.openProject(pr)
    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_Escape) root.projFocus = -1
    else if (!ctrl) { root.projFocus = -1; return false }
    else return false
    return true
  }

  // Back out of a project to the list it came from.
  function leaveProject() {
    root.projectOpen = false
    root.sections = []
    var i = -1
    for (var k = 0; k < root.projects.length; k++) if (root.projects[k].tag === root.projectTag) i = k
    root.projFocus = Math.max(0, i)
    sidebarKeys.forceActiveFocus()
  }

  function moveSectionFocus(d) {
    if (root.sections.length === 0) return
    root.sectionFocus = Math.max(0, Math.min(root.sections.length - 1, root.sectionFocus + d))
  }

  // Enter: the note itself, the cursor on the section's own heading. The
  // list stays in the sidebar, as the calendar does after opening a day, so
  // the next section is one key away.
  function openSection(s) {
    if (!s) return
    root.pendingSection = s
    if (s.date === svc.noteDate && svc.ready) root.landOnSection()
    else root.openNote(s.date)
    editor.focusNote()
  }

  // By its words, not its line number: the note may have been written in
  // since the list was gathered (the same reason Tasks.js looks by words).
  function landOnSection() {
    if (!root.pendingSection || !svc.ready) return
    var want = root.pendingSection.heading
    root.pendingSection = null
    var re = new RegExp("^#{1,6} +" + want.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + " *$", "m")
    var m = re.exec(editor.text)
    if (m) editor.setCursor(m.index + m[0].length, true)
  }

  // A section's second line in the list: what is under it, or its first
  // words when it has no headings of its own.
  function sectionUnder(s) {
    if (s.sub && s.sub.length > 0) {
      var names = []
      for (var i = 0; i < s.sub.length && i < 4; i++) names.push(s.sub[i].text.replace(/\s*#[\w\/-]+/g, ""))
      return names.join(" · ") + (s.sub.length > 4 ? " · +" + (s.sub.length - 4) : "")
    }
    return (s.preview || []).join(" · ")
  }

  function sectionWhen(s) {
    var p = svc.configured ? Days.parse(s.date, svc.dailyFormat()) : null
    if (!p) return s.date
    return Qt.formatDate(p.date, "ddd d MMM") + (s.age === 0 ? " · today" : s.age === 1 ? " · yesterday" : "")
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
  property var declined: ({})       // raw lines whose date stays words (Backspace, Ctrl+D, Ctrl+Z)
  property var autoBound: null      // { id, raw, made }: the line the page just bound as it was left
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
  // The store learns where the line is. `auto`: bound because it was left
  // with a date at its end — an undo step of its own, so Ctrl+Z takes it
  // back (boundEdited); `made`: the deadline was added for it.
  function writeBinding(raw, head, ms, id, auto, made) {
    var r = root.rowByRaw(raw)
    if (!r || r.kind !== "task" || r.deadline > 0) return
    if (auto) {
      editor.snapshot(true)
      root.autoBound = { id: id, raw: raw, made: !!made }
    }
    root.writeLine(r, r.raw.substring(0, r.prefixLen) + head.replace(/\s+$/, "") + Bound.tail(ms, id))
    if (editor.typedRaw === raw) editor.typedRaw = ""
    dl.set(id, ["--link", Bound.link(svc.noteDate, id)])
    root.used("bound")
  }

  // A checkbox's date (`w`, as Dates.read gives it) becomes its deadline.
  // The store is handed the exact day and time, never the words.
  function bindCue(raw, c, w, auto) {
    if (root.bindTwin(raw, c.head, c.project, w.iso, w.ms, auto)) return
    var stem = svc.noteDate
    dl.add(c.title, c.project, w.iso, function (id) {
      if (id > 0 && svc.noteDate === stem) root.writeBinding(raw, c.head, w.ms, id, auto, true)
    })
  }

  function decline(raw) {
    var d = Object.assign({}, root.declined)
    d[raw] = true
    root.declined = d
  }

  function undecline(raw) {
    if (!root.declined[raw]) return
    var d = Object.assign({}, root.declined)
    delete d[raw]
    root.declined = d
  }

  // An open deadline with these words (or mostly) on that day that no line
  // holds yet — the agent's proposal for this same line, accepted a moment
  // before — becomes the line's, rather than a second one being added. It
  // takes the line's date and, if it has none, the line's #tag.
  function bindTwin(raw, head, project, phrase, ms, auto) {
    var key = Bound.titleKey(head), tw = Bound.wordsOf(head)
    var day = new Date(ms).toDateString()
    for (var i = 0; i < dl.items.length; i++) {
      var d = dl.items[i]
      if (d.status !== "open" || d.link !== "" || new Date(d.due * 1000).toDateString() !== day) continue
      if (Bound.titleKey(d.title) !== key && Bound.overlap(tw, Bound.wordsOf(d.title)) < 0.5) continue
      var args = dl.words(phrase)
      if (project !== "" && d.project === "") args = ["--project", project].concat(args)
      dl.set(d.id, args)
      root.writeBinding(raw, head, ms, d.id, auto, false)
      return true
    }
    return false
  }

  // What changed among bound lines with the last edit: a box ticked or
  // unticked goes to the store at once; a line gone (not cut) asks — unless
  // it is the page's own binding taken back with Ctrl+Z: the words are back,
  // the deadline it made for them goes, and the line stays words.
  function boundEdited(was, now) {
    for (var id in was) {
      if (!(id in now)) {
        var d = dl.byId[id]
        var ab = root.autoBound
        // (The text, not editor.rows: they catch up after this signal.)
        if (ab && ab.id === parseInt(id, 10) && editor.text.split("\n").indexOf(ab.raw) >= 0) {
          root.autoBound = null
          if (ab.made) dl.remove(ab.id)
          else dl.set(ab.id, ["--link", ""])
          root.decline(ab.raw)
          root.used("bound", "undone")
          continue
        }
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
  // store; a checkbox just written with a date at its end becomes a
  // deadline, without asking — its date was lit up while it was typed, and
  // Backspace, Ctrl+D or Ctrl+Z keep it words. Only a line typed in: moving
  // through an old note never turns its "by friday" into this Friday.
  function leftLine(i) {
    var typed = editor.typedRaw
    var r = editor.rows[i]
    if (!r || r.kind !== "task" || !svc.ready || root.quiet) return
    if (r.deadline > 0) {
      // Spaces left at the end of its words would sit unseen before the
      // date, where the cursor wanders into them: a left line has none.
      if (/\s$/.test(r.body)) root.writeLine(r, r.raw.substring(0, r.prefixLen) + r.body.replace(/\s+$/, "") + r.suffix)
      var d = dl.byId[r.deadline]
      var title = Bound.titleOf(r.body)
      // A #tag sets the project; a line without one leaves it as it is (an
      // agent's proposal may have named it without the line saying so).
      var project = Bound.projectOf(r.body) || (d ? d.project : "")
      if (d && title !== "" && (title !== d.title || project !== d.project))
        dl.set(d.id, ["--title", title, "--project", project])
      return
    }
    if (r.raw !== typed || r.cueAt < 0 || root.declined[r.raw]) return
    var c = Bound.cue(r.body)
    var w = c ? Dates.read(c.phrase) : null
    if (w) root.bindCue(r.raw, c, w, true)
  }

  function trackLine() {
    var line = root.lineIndexAt(editor.cursorPosition)
    if (line === root.lastLine) return
    var prev = root.lastLine
    root.lastLine = line
    if (prev >= 0) root.leftLine(prev)
    var r = editor.rows[prev]
    if (!r || r.raw !== editor.typedRaw || r.deadline > 0 || r.cueAt < 0 || root.declined[r.raw]) editor.typedRaw = ""
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
      var w = Dates.read(c.phrase)
      if (!w) { root.showHint("that date did not read: " + c.phrase); return }
      // Lit up while being written: Ctrl+D keeps it words. Otherwise (an
      // old line, or one kept as words): it becomes the deadline now.
      if (r.raw === editor.typedRaw && !root.declined[r.raw]) { root.decline(r.raw); root.used("cue", "kept"); return }
      root.undecline(r.raw)
      root.bindCue(r.raw, c, w, false)
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
      if (root.bindTwin(a.raw, head, project, text, w.ms)) return
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
    root.landOnSection()
    root.doPendingWrite()
    root.writeClass()
  }

  // An agent proposal was accepted: once the store has the deadline, the
  // unbound checkbox it is about becomes its line — by its words or its
  // date (Bound.matchLine), looked for across the whole submission (a list
  // is one, each item its own block). A lone checkbox answered with a lone
  // proposal is its line whatever the words; otherwise no match, no line —
  // the deadline waits in the store rather than taking another line's place.
  function checkAccept() {
    var pa = root.pendingAccept
    if (!pa) return
    var rec = agent.record(pa.hash)
    var p = rec && rec.proposals ? rec.proposals[pa.index] : null
    var id = p && p.accepted ? p.accepted.id : 0
    if (!id || !dl.byId[id]) return
    root.pendingAccept = null
    var hashes = rec.group && rec.group.indexOf(pa.hash) >= 0 ? rec.group : [pa.hash]
    var free = []
    for (var k = 0; k < hashes.length; k++) {
      var b = root.blockBounds(hashes[k])
      if (!b) continue
      for (var i = b.start; i < b.end; i++) {
        var r = editor.rows[i]
        if (r && r.kind === "task" && r.deadline <= 0) free.push(r)
      }
    }
    var heads = free.map(function (r) { var c = Bound.cue(r.body); return c ? c.head : r.body })
    var at = Bound.matchLine(p.title || "", dl.byId[id].due * 1000, free.map(function (r) { return r.body }))
    var dated = rec.proposals.filter(function (q) { return q.kind === "deadline" })
    if (at < 0 && free.length === 1 && dated.length === 1) at = 0
    if (at < 0) return
    root.writeBinding(free[at].raw, heads[at], dl.byId[id].due * 1000, id)
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
    root.projFocus = -1
    root.refreshProjects()
    sidebarKeys.forceActiveFocus()
  }

  function moveCalendar(days, months) {
    root.dueFocus = -1
    var d = root.calFocus
    if (months) d = Days.addMonths(d, months)
    if (days) d = Days.addDays(d, days)
    root.calFocus = d
  }

  function refreshProjects() {
    projectsProc.command = [svc.runner, "projects"]
    projectsProc.running = true
  }

  // "now · until 12:15 · Gold", "today 13:15 · Gold", "Wed 10:45 ·
  // Bronze", "19 Oct · Design Lab".
  function sessionLabel(n) {
    if (!n) return ""
    if (n.now) return "now · until " + Qt.formatTime(new Date(n.end), "HH:mm") + (n.room ? " · " + n.room : "")
    var at = new Date(n.at)
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    var days = Math.round((new Date(at.getFullYear(), at.getMonth(), at.getDate()) - today) / 86400000)
    var when = days === 0 ? "today " + Qt.formatTime(at, "HH:mm")
      : days === 1 ? "tomorrow " + Qt.formatTime(at, "HH:mm")
      : days < 7 ? Qt.formatDateTime(at, "ddd HH:mm") : Qt.formatDate(at, "d MMM")
    return when + (n.room ? " · " + n.room : "")
  }

  // A class begins: its heading on a new line at the end of today's note,
  // the cursor on the empty line under it. The student asked for it, and
  // the words are the course's name.
  property var pendingClass: null
  function startClass(p) {
    root.used("class", p.tag)
    root.pendingClass = p
    root.projFocus = -1
    if (svc.isToday && svc.ready) root.writeClass()
    else root.openNote(svc.todayStamp())
    editor.focusNote()
  }

  function writeClass() {
    var p = root.pendingClass
    if (!p || !svc.isToday || !svc.ready) return
    root.pendingClass = null
    var t = editor.text
    var lead = t.replace(/\s+$/, "") === "" ? (t.charAt(t.length - 1) === "\n" || t === "" ? "" : "\n")
      : (/\n\n$/.test(t) ? "" : (/\n$/.test(t) ? "\n" : "\n\n"))
    editor.insert(t.length, lead + "# " + p.name + " #" + p.tag + "\n")
    editor.setCursor(editor.length, true)
  }

  // Ctrl+Enter: just the tag, where the cursor is.
  function insertTag(p) {
    root.used("tag", p.tag)
    root.projFocus = -1
    editor.focusNote()
    var pos = editor.cursorPosition
    var before = pos > 0 ? editor.text.charAt(pos - 1) : "\n"
    editor.insert(pos, (/\s/.test(before) ? "" : " ") + "#" + p.tag + " ")
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

  ThemeColors { id: pal }

  Deadlines {
    id: dl
    onItemsChanged: { root.reconcile(); root.checkAccept() }
    onIdle: {
      var waiting = root.afterWrites
      root.afterWrites = []
      for (var i = 0; i < waiting.length; i++) waiting[i]()
    }
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
    id: sectionsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.sections = JSON.parse(text) || [] } catch (e) { root.sections = [] }
        root.sectionFocus = Math.min(root.sectionFocus, Math.max(0, root.sections.length - 1))
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("student.page sections: " + text.trim()) }
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
  // One handler for the cursor's block changing: what the header may offer
  // to send, and the timer that marks a reply read once it has been looked at.
  onCurrentHashChanged: {
    root.currentTrigger = root.triggerForBlock(root.currentHash)
    ackTimer.restart()
  }

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

  // The sessions move on while the sidebar stays open.
  Timer { interval: 300000; repeat: true; running: root.sidebarOpen && root.showing; onTriggered: root.refreshProjects() }

  Process {
    id: projectsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.projects = JSON.parse(text) || [] } catch (e) { root.projects = [] }
        root.projFocus = Math.min(root.projFocus, root.projects.length - 1)
      }
    }
  }
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

    // A click outside the sheet: on the overlay it dismisses; in the window,
    // beside the column, it goes back to writing.
    MouseArea {
      anchors.fill: parent
      onClicked: root.alongside ? editor.focusNote() : root.dismiss()
    }

    BorderSurface {
      id: sheet
      x: root.alongside ? root.windowSheetX : Math.max(Math.round((content.width - width) / 2), root.sideSpace > 0 ? root.sideSpace + root.sheetMargin : 0)
      y: root.alongside ? 0 : root.sheetMargin
      width: root.alongside ? root.windowSheetWidth : root.sheetWidth
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

            // Ask: the agent's visible way in, and the reason the "send to
            // agent?" prompt could go (2026-10-15). It sends the block the
            // cursor is in — the same path as Ctrl+Enter — and sits in the
            // header, outside the canvas, so nothing marks the student's
            // own words. Dim when this block carries a sign for the agent,
            // faint when it does not; a click then says why in one line.
            Text {
              visible: svc.header !== "" && root.agentDay
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "ask"
              color: askArea.containsMouse ? root.accent
                : (root.currentTrigger !== "" ? root.dim : root.faint)
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                id: askArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.sendCurrent(); editor.focusNote() }
              }
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

          TouchScroll { flickable: flick }

          function ensureVisible(r) {
            if (contentY >= r.y) contentY = r.y
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
          }

          // Gutter marks: a block with a reply, accent until it has been
          // read and dim after. Nothing else is marked — a block that could
          // be sent is every block, and saying so was noise (2026-10-15).
          Repeater {
            model: root.paint
            Rectangle {
              required property var modelData
              visible: modelData.reply
              x: root.sp(2)
              y: modelData.y
              width: root.sp(3)
              height: modelData.h
              radius: width
              color: modelData.unread ? root.accent : root.dim
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
            selectionColor: pal.selection
            accent: root.accent
            urgent: root.urgent
            headingColors: pal.headings
            markColor: Util.alpha(pal.yellow, 0.3)
            currentMarkColor: Util.alpha(pal.orange, 0.55)
            boxColor: pal.dim
            checkColor: pal.green
            bulletColor: pal.accent
            quoteColor: pal.faint
            privateColor: pal.magenta
            codeColor: pal.dim
            marks: root.matches
            currentMark: root.matchIndex
            tabStop: 4 * root.sp(8)
            keyFilter: root.pageKey

            onCursorRectChanged: flick.ensureVisible(cursorRect)
            // Which line the cursor is on is read once the edit is whole: the
            // editor moves the cursor a moment before its text catches up, and
            // read then, a keystroke at a line's end looked like leaving it.
            onCursorPositionChanged: { root.currentHash = root.hashNearLine(root.lineIndexAt(cursorPosition)); Qt.callLater(root.trackLine) }
            onWidthChanged: root.scheduleRepaint()
            onHeightChanged: root.scheduleRepaint()
            onReturnFinished: function (lineIndex, lineText) { root.lineFinished(lineIndex, lineText) }
            onListLeft: function (lineIndex) { root.listLeft(lineIndex) }
            declined: root.declined
            onCueDismissed: function (raw) { root.decline(raw); root.used("cue", "kept") }
            onTypedRawChanged: if (typedRaw !== "") root.autoBound = null
            onTextChanged: {
              if (root.searchOpen) Qt.callLater(root.runSearch)
              var was = root.bound
              root.bound = Bound.anchors(text)
              if (root.applying) return
              svc.markPending(text)
              saveTimer.restart()
              if (root.quiet) return
              root.boundEdited(was, root.bound)
              root.tickedCount = root.countTicked(text)
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
          // Inside a project: its sections, newest first. Enter opens one in
          // the sheet (the list stays), Left or Esc goes back to the list of
          // projects.
          if (root.projectOpen) {
            if (k === Qt.Key_Up) root.moveSectionFocus(-1)
            else if (k === Qt.Key_Down) root.moveSectionFocus(1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.openSection(root.sections[root.sectionFocus])
            else if (k === Qt.Key_Left || k === Qt.Key_Escape || k === Qt.Key_Backtab) root.leaveProject()
            else if (k === Qt.Key_Right && alt) editor.focusNote()
            else if (k === Qt.Key_B && ctrl) { root.sidebarOpen = false; root.projectOpen = false; editor.focusNote() }
            else return
            event.accepted = true
            return
          }
          // Tab walks the sidebar: the days, the day's deadlines (when it
          // has some), the projects, and back to the days.
          // In the day's deadline list: up/down pick, Enter goes to the line.
          if (root.dueFocus >= 0 && !ctrl && !alt) {
            var n = root.focusDue.length
            if (k === Qt.Key_Up) root.dueFocus = Math.max(0, root.dueFocus - 1)
            else if (k === Qt.Key_Down) root.dueFocus = Math.min(n - 1, root.dueFocus + 1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.goToDeadline(root.focusDue[root.dueFocus])
            else if (k === Qt.Key_Tab) { root.dueFocus = -1; if (root.projects.length > 0) root.projFocus = 0 }
            else if (k === Qt.Key_Backtab || k === Qt.Key_Escape) root.dueFocus = -1
            else { root.dueFocus = -1; return }
            event.accepted = true
            return
          }
          if (root.projFocus >= 0 && !alt) {
            if (root.projectsKey(k, ctrl, event.modifiers & Qt.ShiftModifier)) event.accepted = true
            return
          }
          if (k === Qt.Key_Tab && (root.focusDue.length > 0 || root.projects.length > 0)) {
            if (root.focusDue.length > 0) root.dueFocus = 0
            else root.projFocus = 0
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
        visible: !root.projectOpen
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
                color: dayCell.hasNote ? root.foreground : root.faint
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

        // The projects that exist: the tags to write, soonest session first.
        Text {
          visible: root.projects.length > 0
          topPadding: root.sp(8)
          textFormat: Text.PlainText
          text: "PROJECTS"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.caption)
        }
        Repeater {
          model: root.projects
          Rectangle {
            required property var modelData
            required property int index
            width: calendar.width
            height: projCol.implicitHeight + root.sp(6)
            radius: Style.cornerRadius
            color: root.projFocus === index && sidebarKeys.activeFocus ? Style.selectedFill : "transparent"
            Column {
              id: projCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: root.sp(4)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: "#" + modelData.tag + "  " + modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
              Text {
                visible: !!modelData.next
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: root.sessionLabel(modelData.next)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: function (mouse) {
                if (mouse.modifiers & Qt.ControlModifier) root.insertTag(modelData)
                else if (mouse.modifiers & Qt.ShiftModifier) root.startClass(modelData)
                else root.openProject(modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: sidebarKeys.activeFocus
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.projFocus >= 0 ? "↑↓ pick · Enter its notes · Shift+Enter starts a class · Ctrl+Enter puts the tag · Tab back"
            : root.dueFocus >= 0 ? "↑↓ pick · Enter goes to its line · Tab on to the projects"
            : "arrows move · Ctrl+←→ month · Home today · Enter opens" + (root.focusDue.length > 0 || root.projects.length > 0 ? " · Tab: " + (root.focusDue.length > 0 ? "this day's deadlines" : "the projects") : "")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.caption)
        }
      }

      // Drilled into a project: its sections across the days, newest first.
      // This is navigation, so it belongs on this side with the calendar —
      // the margin on the right is the agent's (decided 2026-10-15).
      Flickable {
        id: projectFlick
        visible: root.projectOpen
        anchors.fill: parent
        anchors.topMargin: sidebar.contentTopInset
        anchors.leftMargin: sidebar.contentLeftInset
        anchors.rightMargin: sidebar.contentRightInset
        anchors.bottomMargin: sidebar.contentBottomInset
        clip: true
        contentWidth: width
        contentHeight: projectColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        TouchScroll { flickable: projectFlick }

        function revealFocused() {
          var kids = projectColumn.children
          for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k.index === undefined || k.index !== root.sectionFocus) continue
            if (contentY > k.y) contentY = k.y
            else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
            return
          }
        }
        Connections { target: root; function onSectionFocusChanged() { Qt.callLater(projectFlick.revealFocused) } }

        Column {
          id: projectColumn
          width: parent.width
          spacing: root.sp(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "← #" + root.projectTag
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.leaveProject() }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.projectName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          Text {
            width: parent.width
            visible: root.sections.length === 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            topPadding: root.sp(6)
            text: sectionsProc.running ? "…" : "nothing under #" + root.projectTag + " yet — a “# Course #" + root.projectTag + "” heading starts one"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
          }

          Repeater {
            model: root.sections
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool hot: root.sectionFocus === index && sidebarKeys.activeFocus
              width: projectColumn.width
              height: secCol.implicitHeight + root.sp(8)
              radius: Style.cornerRadius
              color: hot ? Style.selectedFill : "transparent"
              Column {
                id: secCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.sp(4)
                anchors.rightMargin: root.sp(4)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: root.sectionWhen(modelData)
                    + (modelData.open > 0 ? "   ○ " + modelData.open : "")
                    + (modelData.done > 0 ? "   ✓ " + modelData.done : "")
                  color: modelData.date === svc.noteDate ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  text: root.sectionUnder(modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.sectionFocus = index; root.openSection(modelData) }
              }
            }
          }

          Text {
            width: parent.width
            visible: sidebarKeys.activeFocus
            topPadding: root.sp(6)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "↑↓ pick · Enter opens it in the sheet · ← back to the projects"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
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

        TouchScroll { flickable: tasksFlick }

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

        TouchScroll { flickable: marginFlick }

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
            text: "Nothing from the agent on this block yet. Ctrl+Enter sends it, or ask below."
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
