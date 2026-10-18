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
import "Task.js" as Task
import "Authorship.js" as Authorship
import "Shortcuts.js" as Sc

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
// Esc closes it again. Ctrl+T opens the dashboard: every open checkbox
// across the daily notes, carried while it is alive (a box goes quiet after
// 7 days of silence, a task after 30 — agent/lifespan.py — and waits under
// "not now"; it is never rewritten, the page being the one program that
// edits notes) and, below, what the agent has raised — suggestions with
// their evidence, observations from open passes — where Enter waves one off
// and the runner remembers that.
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
// knowledge/projects/, via `longhand-agent projects`), soonest session
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
  readonly property alias contentItem: content    // what is drawn, for tests to photograph
  readonly property alias noteService: svc
  readonly property alias whenInput: whenField
  readonly property alias searchInput: searchField
  readonly property alias palette: pal
  // For the sheets that live in files of their own (tools/extract_sheet.py).
  readonly property alias sheetItem: sheet
  readonly property alias agentState: agent
  readonly property alias sectionsProcess: sectionsProc
  readonly property alias notebookSheetItem: notebookSheet
  property bool overlayOpen: false
  property bool windowOpen: false
  readonly property bool opened: overlayOpen          // what the shell's toggle asks
  readonly property bool showing: overlayOpen || windowOpen
  readonly property bool alongside: !overlayOpen      // where the sheet is drawn

  readonly property color background: Color.menu.background
  // Text at the contrast the theme chose. It was softened a fifth of the way
  // back toward the background on 2026-10-15, to fight a heaviness that
  // turned out to be the font *cut*, not the contrast (see `fontStyle`);
  // against a genuine Regular the softening only cost legibility.
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
  // The face the note is written in. The page drew in the shell's monospace
  // until 2026-10-15; prose reads better in a proportional face, and the
  // measure gets physically narrower for the same 72 characters. `font` in
  // the config names one; otherwise the first of these the machine has.
  // Fenced code and frontmatter keep a monospace, where columns mean
  // something — the editor already draws those rows apart.
  readonly property var proseChoices: [svc.pageFont, "iA Writer Quattro S", "iA Writer Duo S", Style.font.family]
  readonly property string fontFamily: {
    var have = Qt.fontFamilies()
    for (var i = 0; i < root.proseChoices.length; i++)
      if (root.proseChoices[i] !== "" && have.indexOf(root.proseChoices[i]) >= 0) return root.proseChoices[i]
    return Style.font.family
  }
  // The cut of the prose face. The iA Writer families ship with every style
  // declaring the same weight, so asking for a normal weight hands back the
  // Bold file: the page came out uniformly heavy, and `**bold**` had nowhere
  // heavier to go. Naming the style picks the real Regular. A family without
  // one is unaffected — Qt falls back to weight as before (tested against
  // DejaVu, JetBrains Mono and a family that does not exist).
  readonly property string fontStyle: "Regular"

  readonly property string codeFamily: {
    var have = Qt.fontFamilies()
    if (svc.pageCodeFont !== "" && have.indexOf(svc.pageCodeFont) >= 0) return svc.pageCodeFont
    return Style.font.family
  }
  // One size for the whole page, like a browser's zoom: text, spacing,
  // margins, the panel. The base is the shell's own type scale (which
  // follows the theme's font base-size), so the page sits with the rest of
  // the desktop; Ctrl+= / Ctrl+- / Ctrl+0 step it and the step is kept in
  // ~/.local/state/longhand/page.json.
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
  // One character of this face, measured on a lowercase alphabet — the unit
  // typography has always set measure in (72 characters is 2.8 alphabets,
  // inside the 45–75 the eye likes). For a monospace this is exactly the
  // advance, so the column is unchanged; for a proportional face it is the
  // honest average, where Qt's own averageCharacterWidth over-counts by
  // weighing capitals the same as letters nobody types as often.
  readonly property real chWidth: {
    // Reading the metrics' own font first is what makes this a binding:
    // advanceWidth is a method call, so without it QML sees no dependency
    // and the measure would stop following the zoom and the face.
    var px = bodyMetrics.font.pixelSize, fam = bodyMetrics.font.family
    return px > 0 && fam !== "" ? bodyMetrics.advanceWidth("abcdefghijklmnopqrstuvwxyz") / 26 : 1
  }
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
  // The dashboard and the keys sheet are lists, so they take the width the
  // sheet does not use — but never the sidebar's: in the window it is
  // drawn at the left edge, on the overlay beside them.
  readonly property bool wideOpen: root.dashOpen || root.keysOpen || root.settingsOpen
  readonly property int wideX: root.sideSpace + (root.alongside ? 0 : root.sheetMargin)
  readonly property int wideWidth: (root.alongside ? content.width : content.width - root.sheetMargin * 2) - root.sideSpace
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
  // What every run and every offer is gated on. A note the student marked
  // private is simply not a day the agent has: no pass on opening it, no
  // send, nothing to click. `longhand-agent` refuses such a note too — this
  // is the page not even asking.
  readonly property bool agentOn: root.agentDay && !svc.notePrivate

  // Ctrl+Shift+P, and the header's own word. Writes `agent: false` into the
  // note's frontmatter, which is what the runner reads; taking it off puts
  // the day back as it was.
  function togglePrivate() {
    if (!svc.ready) return
    var on = !svc.notePrivate
    svc.setPrivate(on)
    root.flush()
    root.used("private", on ? "on" : "off")
    root.showHint(on ? "private — the agent sees nothing in this note" : "the agent can be asked about this note again")
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
  property var pendingTask: null     // { text, line }: a task's line to land on, the same way
  readonly property int sideSpace: root.sidebarOpen && root.problem === "" ? root.sidebarWidth + root.marginGap : 0
  property bool applying: false

  // Runner plumbing: one process at a time, the last request wins.
  property var queued: []      // runner commands waiting, oldest first
  property bool running: false
  property string runningHash: ""
  // The blocks the student has asked about that have not come back yet.
  // Marked from the moment of the ask, not from when the process starts:
  // a send waits for dates to bind (`whenWritten`) and for the note to be
  // written, and "did that go?" is exactly what the mark answers.
  property var sending: []
  // The turn the student has just sent, held here until the runner writes
  // it into the day's state. The chat shows it at once: a message that
  // vanishes for the length of a pass reads as a message that did not send.
  property var pendingChat: null   // { hash, text }
  // Something is away: queued, waiting for the note to be written, or in
  // the runner. What the header's "agent" says, and what the gutter marks.
  readonly property bool working: root.running || root.sending.length > 0
  property bool openPassPending: false
  property int tickedCount: 0

  // What is painted and what the margin shows.
  property var paint: []
  property bool marginOpen: false
  property int marginFocus: -1   // -1 note; 0..n-1 proposal rows; n = chat field
  property bool dashOpen: false
  property bool projectOpen: false   // the margin is showing one project's notes
  property var sections: []          // [{ date, line, heading, title, sub, preview, open, done }]
  property string projectTag: ""
  property string projectName: ""
  property int sectionFocus: 0
  property var pendingSection: null  // a heading to land on once its note is open
  property var tasks: []
  property var raised: []
  property var tickHistory: []   // ticks made from the panel, newest last, for Ctrl+Z
  property bool showShelf: false      // the "not now" band unfolded
  // A tick from the dashboard is drawn at once, before the note is written
  // and the list read again (rowKey → true), and the row that was just
  // ticked plays the tick; the list waits for it (holdTasksUntil).
  // What the agent proposes or asks, open (`longhand-agent proposals`), and
  // the do-dates it proposed that were accepted lately (key -> date), whose
  // pills carry its tint. docs/agent.md, slice 2.
  property var proposals: []
  property var agentDates: ({})
  property bool planning: false
  property var proposalQueue: []      // answers waiting for the runner, in order
  property var doneNow: ({})
  property string justTicked: ""
  property real holdTasksUntil: 0
  property var afterTick: []          // what waits for the tick to be seen: a deadline's store write
  property bool showGrading: false    // the "waiting for a grade" band unfolded
  property var dashWhenFor: null     // what the dashboard's field is for: a task, or { deadline }
  property string dashWhenText: ""
  property string dashFieldKind: "when"   // "when" (t), "rename" (Ctrl+E) or "grade" (g)
  property string dashFieldStart: ""      // the words a rename starts from
  property int taskFocus: 0
  property string currentHash: ""
  property string currentTrigger: ""   // the sign on the block under the cursor, for the header's "ask"
  property var mention: null           // { start, query, items } while an `@` is being written
  property int mentionFocus: 0
  property bool searchOpen: false
  // The keys sheet (Ctrl+/). `keysVersion` moves whenever a key does, so
  // every hint that names one is redrawn.
  property bool keysOpen: false
  property int keysVersion: 0
  property string keysFilter: ""
  property int keysFocus: -1
  property var keysListen: null      // { id, add } while waiting for the new key
  property string keysTake: ""       // a key another action has, pressed once
  property string keysNote: ""       // what just happened, or why not

  // Settings (Ctrl+, or "settings" at the sidebar's foot): what the page lets you
  // set without editing a file — the timetable's address, for now. Written
  // to settings.json beside config.json (the page's own, as keys.json is);
  // the runner reads the keys it allows from it over the config.
  property bool settingsOpen: false
  // Settings shows one view at a time: its sections, or what the agent knows.
  property string settingsView: "main"
  property var settingsState: null     // `longhand-agent timetable`, as JSON
  property bool settingsBusy: false    // the runner is asking the university
  property string settingsNote: ""     // what just happened, or why not
  property var settingsPending: null   // the runner's flags, once the file is written
  property int settingsFocus: 0        // the calendar ↑↓ picks
  property int settingsBusyIndex: -1   // the calendar being fetched; -1 all
  property string settingsFieldKind: "add"   // the field adds a calendar, or renames the picked one
  property var settingsData: ({})      // settings.json as last read or written

  // The sound of a tick (2026-10-17), kept mindful: short and soft
  // (tick.wav, made by tools/make_tick.py), only for a tick the person makes
  // — never an untick, never a line the page or the check writes itself —
  // one at a time, never while notifications are silenced (Omarchy's Do
  // Not Disturb), and off in Settings if wanted.
  readonly property bool tickSoundOn: root.settingsData.tickSound !== false
  property int ticksHeard: 0           // ticks that asked for the sound (tests read this)
  readonly property string tickFile: String(Qt.resolvedUrl("tick.wav")).replace(/^file:\/\//, "")
  function tickSound() {
    if (!root.tickSoundOn) return
    root.ticksHeard++
    root.playTick(false)
  }
  // `force`: asked for in Settings ("hear it"), so Do Not Disturb does not
  // apply.
  function playTick(force) {
    // A test run counts the ticks and plays none (LONGHAND_SILENT).
    if (tickSoundProc.running || Quickshell.env("LONGHAND_SILENT") !== "") return
    var play = 'if command -v pw-play >/dev/null; then exec pw-play --volume=0.6 "$0"; else exec paplay "$0"; fi'
    tickSoundProc.command = ["sh", "-c", force ? play
      : '[ "$(omarchy-shell notifications isDnd 2>/dev/null)" = on ] && exit 0; ' + play, root.tickFile]
    tickSoundProc.running = true
  }
  property var hyprKeys: null        // Hyprland's keys for the page: hyprkeys.py's state
  property bool keysAdopt: false     // Enter pressed once on "let the page keep these keys"
  readonly property var keyRows: { root.keysVersion; return Sc.rows(root.keysFilter, root.hyprKeys) }
  property var matches: []       // [{ start, end }] text offsets, in note order
  property int matchIndex: -1
  property int searchFrom: 0     // the cursor when the search opened
  // A block's conversation is filed under the hash of its text when it was
  // asked, and found again by its words: ticking the box, binding a date,
  // setting a priority or cancelling it leaves the conversation where it
  // was (2026-10-17). Changing the words still makes it another block.
  // `currentRec` is the hash the cursor's block's record lives under — the
  // block's own, or the one it had when it was answered.
  readonly property var recordKeys: {
    var idx = {}
    var b = agent.blocks
    for (var h in b) {
      var r = b[h]
      if (!root.answered(r)) continue
      // Records from before the key was kept: their first line(s) stand in.
      var ks = r.key ? [r.key]
        : r.head ? (r.group ? r.head.split(" / ") : [r.head]).map(function (t) { return Blocks.fnv1a(Task.identity(t)) })
        : []
      for (var i = 0; i < ks.length; i++)
        if (!idx[ks[i]] || String(r.at) > String(b[idx[ks[i]]].at)) idx[ks[i]] = h
    }
    return idx
  }
  function recordHash(hash, text) {
    if (hash === "" || root.answered(agent.record(hash))) return hash
    return root.recordKeys[Blocks.fnv1a(Task.identity(text))] || hash
  }
  property string currentRec: ""
  function refreshRec() {
    var b = root.blockBounds(root.currentHash)
    root.currentRec = root.recordHash(root.currentHash, b ? b.text : "")
  }
  onRecordKeysChanged: root.refreshRec()
  readonly property var currentRecord: agent.record(currentRec)
  // The conversation as the margin shows it: what the runner has written,
  // plus the turn that has not landed yet.
  readonly property var chatTurns: {
    var rec = root.currentRecord
    var turns = rec && rec.chat ? rec.chat.slice() : []
    if (root.pendingChat && root.pendingChat.hash === root.currentRec)
      turns.push({ role: "student", text: root.pendingChat.text })
    return turns
  }
  // This block is away: asked and not back. `runningHash` can name a whole
  // list submission.
  readonly property bool answering: root.currentHash !== ""
    && (root.runningHash.split(",").indexOf(root.currentHash) >= 0
        || root.runningHash.split(",").indexOf(root.currentRec) >= 0
        || root.sending.indexOf(root.currentHash) >= 0)
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
      // Already a window (maybe on another workspace): bring it here. The
      // app launcher waits for a window to appear or take focus, and says
      // "Launching…" over the page until one does.
      if (root.windowOpen && !root.overlayOpen) root.raiseWindow()
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
      root.dashOpen = false
      root.projectOpen = false
      root.marginFocus = -1
      root.projectOpen = false
      // `@` can call a project without the sidebar ever being opened.
      root.refreshProjects()
      // The day's plan, at most once a day (the runner decides).
      root.runPlan(false)
      // The agent's weekly review, when a week has passed since the last.
      if (!reviewProc.running && svc.configured) {
        reviewProc.command = [svc.runner, "review", "--if-due"]
        reviewProc.running = true
      }
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
  // (`longhand-agent stats`): event names and numbers only, never a word of
  // the notes. Appended to the state folder — not the vault, never in a
  // payload — a few lines at a time.
  readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/usage.tsv"
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

  // Zoom and the keys sheet: wherever the keyboard is in the page. Every
  // key the page answers to is named in Shortcuts.js, where the student can
  // move it (the keys sheet, below).
  function anywhereKey(event) {
    if (Sc.hit(event, "zoomIn")) { root.zoomBy(1); return true }
    if (Sc.hit(event, "zoomOut")) { root.zoomBy(-1); return true }
    if (Sc.hit(event, "zoomReset")) { root.setZoom(1); return true }
    if (Sc.hit(event, "keys")) { root.toggleKeys(); return true }
    if (Sc.hit(event, "settings")) { root.toggleSettings(); return true }
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
    if (root.keysOpen) root.toggleKeys()
    if (root.settingsOpen) root.toggleSettings()
    root.leftLine(root.lastLine)
    root.flush()
    root.overlayOpen = false
    if (root.windowOpen) Qt.callLater(editor.focusNote)
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "longhand.page")
  }

  function raiseWindow() {
    raiseProc.running = false
    raiseProc.command = ["hyprctl", "eval",
      'hl.dispatch(hl.dsp.focus({ window = "title:^' + root.windowTitle + '$" }))']
    raiseProc.running = true
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
    if (!root.agentOn) return
    root.flush()
    var cmd = [svc.runner, "run", "--trigger", trigger, "--date", svc.noteDate]
    if (hash) cmd.push("--hash", hash)
    root.enqueue(cmd, hash)
  }

  // Ctrl+Enter: send the block under the cursor, if it carries a sign for
  // the agent. A block without one stays where it is; the margin says why.
  property bool noSignHint: false
  property string hint: ""   // a passing word (a date that did not read, what a check did, …)
  // What the page says in passing, in the header's status line. It used to
  // float under the cursor and print over the line below it (2026-10-17);
  // up there it covers nothing, so it can stay long enough to be read.
  readonly property string status: root.hint !== "" ? root.hint
    : root.noSignHint ? "nothing to ask here — make it a checkbox or end it with ?"
    : ""
  function showHint(t) { root.hint = t; hintTimer.restart() }
  // A block the agent has already answered is not asked again. The hash is
  // of the block's text, so a block that still carries its answer is text
  // that has not changed since: the second pass would send the identical
  // question, pay for it again, and — because a run overwrites the record —
  // throw the first answer away. Change the words and it is a different
  // block with no answer, which runs as usual; leave them and what you
  // want is the conversation, which continues the session the first pass
  // opened rather than starting a new one.
  function answered(rec) {
    return !!rec && (!!rec.reply || (!!rec.chat && rec.chat.length > 0))
  }

  function sendCurrent() {
    if (root.currentHash === "") return
    if (root.answered(root.currentRecord)) {
      if (root.marginWidth <= 0) { root.showHint("already answered — the window is too narrow to show it"); return }
      root.used("reopen")
      root.diveIn(true)
      return
    }
    if (root.currentTrigger === "") { root.noSignHint = true; hintTimer.restart(); return }
    // A dated item may still be binding. The agent has to see its dates as
    // deadlines, never as words to propose a second time (2026-10-13), so
    // the send waits for the queue — as the prompt used to before it went.
    root.markSending([root.currentHash])
    root.whenWritten(function () {
      var h = root.hashNearLine(root.lineIndexAt(editor.cursorPosition))
      if (h === "") { root.doneSending(); return }
      var trigger = root.triggerForBlock(h)
      if (trigger === "") { root.doneSending(); root.noSignHint = true; hintTimer.restart(); return }
      // A list of boxes is one submission however it is sent.
      root.send(trigger, trigger === "checkbox" || trigger === "tick" ? root.listAround(h) : [h], h)
    })
  }

  // `hashes` is the submission — a run of list items goes as one — but only
  // `focus`, the line the student asked from, is marked while it is away.
  // The mark answers "did that register?", and that is one place; lighting
  // up every item of the list to say so reads as the whole page leaving.
  // The reply, when it comes, does land on all of them: that is the group,
  // and by then it is information rather than noise.
  function send(trigger, hashes, focus) {
    root.used("send", trigger)
    root.markSending([focus || hashes[0]])
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

  function blockBounds(hash) {
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++) if (blocks[i].hash === hash) return blocks[i]
    return null
  }

  // Ctrl+Up / Ctrl+Down: to the start (end) of the block, and pressed
  // again on to the block before (after) — the way Word and Docs walk
  // paragraphs, and the way Ctrl+Shift+Up/Down already select.
  function walkBlocks(direction) {
    var blocks = Blocks.split(editor.text)
    var t = editor.text
    var pos = editor.cursorPosition
    var to = -1
    for (var i = 0; i < blocks.length; i++) {
      var edge
      if (direction < 0) {
        edge = root.positionOfLine(blocks[i].start)
        if (edge < pos && edge > to) to = edge
      } else {
        var last = root.positionOfLine(blocks[i].end - 1)
        var nl = t.indexOf("\n", last)
        edge = nl < 0 ? t.length : nl
        if (edge > pos && (to < 0 || edge < to)) to = edge
      }
    }
    if (to >= 0) editor.setCursor(to)
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

  function markSending(hashes) {
    // Drop anything that is no longer a block in the note: a line whose
    // date bound between the ask and the send is a different block now.
    var live = {}
    var blocks = Blocks.split(editor.text)
    for (var b = 0; b < blocks.length; b++) live[blocks[b].hash] = true
    var next = []
    for (var k = 0; k < root.sending.length; k++)
      if (live[root.sending[k]]) next.push(root.sending[k])
    for (var i = 0; i < hashes.length; i++) {
      var h = String(hashes[i])
      if (h !== "" && next.indexOf(h) < 0) next.push(h)
    }
    root.sending = next
    root.scheduleRepaint()
  }

  function runnerFailed() {
    var lines = runner.said.split("\n")
    var first = ""
    for (var i = 0; i < lines.length && first === ""; i++)
      if (lines[i].trim() !== "") first = lines[i].trim().replace(/^error:\s*/, "")
    runner.said = ""
    root.pendingChat = null      // it never reached the agent; do not pretend it did
    root.showHint("the agent could not run" + (first === "" ? "" : " — " + first.substring(0, 120)))
  }

  function doneSending() {
    if (root.sending.length === 0) return
    root.sending = []
    root.scheduleRepaint()
  }

  // `hash` is the record's, `mark` the block's as the note has it now (they
  // differ once a box answered has been ticked): the record is asked, the
  // block is the one drawn as away.
  function requestChat(hash, message, mark) {
    if (!root.agentOn) return
    root.markSending([mark || hash])
    root.flush()
    root.enqueue([svc.runner, "chat", "--hash", hash, "--message", message, "--date", svc.noteDate], mark || hash)
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
      var rec = agent.record(root.recordHash(b.hash, b.text))
      var flying = root.sending.indexOf(b.hash) >= 0
      if (!rec && !flying) continue
      var r = editor.blockRect(b.start, b.end)
      if (!r) continue
      out.push({ hash: b.hash, y: r.y, h: r.h, sending: flying,
                 reply: !!rec && rec.state === "reply",
                 unread: !!rec && rec.state === "reply" && !rec.read })
    }
    root.paint = out
    root.currentHash = root.hashNearLine(root.lineIndexAt(editor.cursorPosition))
  }

  function hasUnreadInNote() {
    var p = root.paint
    for (var i = 0; i < p.length; i++) if (p[i].unread) return true
    return false
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

  // ------------------------------------------------- calling a project

  // `@` in the note calls a project, the way the sidebar's list does with a
  // click — one vocabulary for "this is about that course", wherever you
  // are (2026-10-15). It is only a way of *writing*: what lands in the note
  // is the project's own `#tag`, which is what the store, the payload and
  // the sidebar have always read.
  function updateMention() {
    if (!svc.ready || !root.showing) { root.mention = null; return }
    var pos = editor.cursorPosition
    var text = editor.text
    var before = text.substring(text.lastIndexOf("\n", pos - 1) + 1, pos)
    // Only at a word's start, so an address ("a@b") is never a call.
    var m = before.match(/(^|\s)@([\w\/-]*)$/)
    if (!m) { root.mention = null; return }
    var q = m[2].toLowerCase()
    var items = []
    for (var i = 0; i < root.projects.length; i++) {
      var pr = root.projects[i]
      if (q === "" || pr.tag.toLowerCase().indexOf(q) >= 0 || String(pr.name || "").toLowerCase().indexOf(q) >= 0)
        items.push(pr)
    }
    root.mention = { start: pos - m[2].length - 1, query: m[2], items: items, atLineStart: m[1] === "" }
    if (root.mentionFocus > items.length - 1) root.mentionFocus = Math.max(0, items.length - 1)
  }

  // Enter puts the project's tag where the `@` was. Shift+Enter starts the
  // class instead — only where the `@` opened the line, since a heading in
  // the middle of a sentence is not what anyone meant.
  function acceptMention(shift) {
    var m = root.mention
    if (!m || m.items.length === 0) return
    var pr = m.items[root.mentionFocus]
    var to = editor.cursorPosition
    root.mention = null
    editor.remove(m.start, to)
    if (shift && m.atLineStart) {
      editor.insert(m.start, "# " + (pr.name || pr.tag) + " #" + pr.tag)
      root.used("mention", "class")
    } else {
      editor.insert(m.start, "#" + pr.tag + " ")
      root.used("mention", "tag")
    }
  }

  function mentionKey(event) {
    if (!root.mention || root.mention.items.length === 0) return false
    if (Sc.hit(event, "mentionUp")) { root.mentionFocus = Math.max(0, root.mentionFocus - 1); return true }
    if (Sc.hit(event, "mentionDown")) { root.mentionFocus = Math.min(root.mention.items.length - 1, root.mentionFocus + 1); return true }
    if (Sc.hit(event, "mentionClass")) { root.acceptMention(true); return true }
    if (Sc.hit(event, "mentionPick")) { root.acceptMention(false); return true }
    if (Sc.hit(event, "mentionClose")) { root.mention = null; return true }
    return false
  }

  // Keys the page owns, ahead of editing. True when taken.
  function pageKey(event) {
    if (root.mentionKey(event)) return true
    if (root.anywhereKey(event)) return true
    if (Sc.hit(event, "close")) { if (!root.alongside) root.dismiss(); return true }
    if (Sc.hit(event, "private")) { root.togglePrivate(); return true }
    if (Sc.hit(event, "pin")) { root.togglePin(); return true }
    if (Sc.hit(event, "ask")) { root.sendCurrent(); return true }
    // Selecting to the same edges is the editor's (selectToBlockEdge).
    if (Sc.hit(event, "blockStart")) { root.walkBlocks(-1); return true }
    if (Sc.hit(event, "blockEnd")) { root.walkBlocks(1); return true }
    if (Sc.hit(event, "margin")) { root.diveIn(); return true }
    if (Sc.hit(event, "dashboard")) { root.toggleDash(); return true }
    if (Sc.hit(event, "today")) { root.goToday(); return true }
    if (Sc.hit(event, "dayPrev")) { root.stepDay(-1); return true }
    if (Sc.hit(event, "dayNext")) { root.stepDay(1); return true }
    if (Sc.hit(event, "find")) { root.openSearch(); return true }
    if (Sc.hit(event, "sidebar")) { root.toggleSidebar(); return true }
    // Emphasis, where every editor puts it. The sidebar moved to the
    // shifted pair on 2026-10-15 so that Ctrl+B could be bold.
    if (Sc.hit(event, "bold")) { editor.emphasise("**"); return true }
    if (Sc.hit(event, "italic")) { editor.emphasise("*"); return true }
    if (Sc.hit(event, "code")) { editor.emphasise("`"); return true }
    if (Sc.hit(event, "strike")) { editor.emphasise("~~"); return true }
    if (Sc.hit(event, "deadline")) { root.deadlineKey(); return true }
    if (Sc.hit(event, "toSidebar") && root.sidebarOpen) { root.focusSidebar(); return true }
    return false
  }

  // `toChat`: land in the box with the cursor in it, whatever else is
  // there — the way in when the answer already exists and the next thing
  // to do is reply to it.
  function diveIn(toChat) {
    root.used("margin")
    if (root.marginWidth <= 0 || root.currentHash === "") return
    root.marginOpen = true
    if (root.currentProposals.length > 0 && toChat !== true) {
      root.marginFocus = 0
      margin.marginKeysRef.forceActiveFocus()
    } else {
      root.marginFocus = root.currentProposals.length
      margin.chatFieldRef.forceActiveFocus()
    }
  }

  function backToNote() {
    root.marginFocus = -1
    root.marginOpen = false
    root.dashOpen = false
    editor.focusNote()
  }

  function moveMarginFocus(d) {
    var n = root.currentProposals.length
    var next = Math.max(0, Math.min(n, root.marginFocus + d))
    root.marginFocus = next
    if (next === n) margin.chatFieldRef.forceActiveFocus()
    else margin.marginKeysRef.forceActiveFocus()
  }

  function acceptProposal(i) {
    var p = root.currentProposals[i]
    if (!p || p.accepted || root.currentRec === "" || acceptProc.running) return
    root.pendingAccept = { hash: root.currentRec, index: i }
    acceptProc.command = [svc.runner, "accept", "--hash", root.currentRec, "--index", String(i), "--date", svc.noteDate]
    acceptProc.running = true
  }

  // ------------------------------------------------------------ keys

  // The keys sheet: every key the page answers to, where it works, and the
  // way to move it. Drawn from Shortcuts.js, which every handler reads, so
  // the list cannot drift from what the keys do. It takes the sheet's place
  // like the dashboard. What the student moves goes to keys.json beside
  // config.json. Hyprland's six keys for the page, the timer and the
  // deadlines are listed too; once the student lets the page keep them
  // (one row, Enter twice), they move like the rest, through hyprkeys.py.
  function toggleKeys() {
    if (!root.keysOpen && root.settingsOpen) root.toggleSettings()
    root.keysOpen = !root.keysOpen
    root.stopListening()
    root.keysNote = ""
    if (root.keysOpen) {
      root.used("keys")
      keysSheet.keysFieldRef.text = ""
      root.keysFocus = root.nextKeyRow(-1, 1)
      root.hypr(["state"])
      Qt.callLater(keysSheet.keysFieldRef.forceActiveFocus)
    } else if (root.dashOpen) {
      dash.dashKeysRef.forceActiveFocus()
    } else {
      editor.focusNote()
    }
  }

  // Settings: one sheet, one section so far. Opening it reads the
  // timetable's state (no fetch); Enter in the field saves an address and
  // fetches at once, so whether it worked is seen, not hoped for.
  function toggleSettings() {
    if (!root.settingsOpen && root.keysOpen) root.toggleKeys()
    root.settingsOpen = !root.settingsOpen
    root.settingsNote = ""
    root.settingsFieldKind = "add"
    root.settingsView = "main"
    root.notebookCorrecting = false
    if (root.settingsOpen) {
      root.used("settings")
      settingsSheet.settingsFieldRef.text = ""
      root.settingsFocus = 0
      root.runTimetable([])
      root.loadNotebook()
      if (!agentChecksProc.running) {
        agentChecksProc.command = [svc.runner, "eval", "status", "--json"]
        agentChecksProc.running = true
      }
      Qt.callLater(settingsSheet.settingsFieldRef.forceActiveFocus)
    } else if (root.dashOpen) {
      dash.dashKeysRef.forceActiveFocus()
    } else {
      editor.focusNote()
    }
  }

  function settingsKey(event) {
    if (root.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    var n = root.calendarList().length
    if (seq === "Esc") {
      if (root.settingsFieldKind === "rename") { root.settingsFieldKind = "add"; settingsSheet.settingsFieldRef.text = "" }
      else root.toggleSettings()
      return true
    }
    if (seq === "Enter") {
      if (root.settingsFieldKind === "rename") root.renameCalendar(settingsSheet.settingsFieldRef.text)
      else root.addCalendar(settingsSheet.settingsFieldRef.text)
      return true
    }
    if (seq === "Up") { root.settingsFocus = Math.max(0, root.settingsFocus - 1); return true }
    if (seq === "Down") { root.settingsFocus = Math.max(0, Math.min(n - 1, root.settingsFocus + 1)); return true }
    if (Sc.hit(event, "settingsFetch")) { root.fetchCalendar(root.settingsFocus); return true }
    if (Sc.hit(event, "settingsForget")) { root.removeCalendar(root.settingsFocus); return true }
    if (Sc.hit(event, "settingsShare")) { root.toggleShare(root.settingsFocus); return true }
    if (Sc.hit(event, "settingsRename")) { root.startRename(root.settingsFocus); return true }
    if (Sc.hit(event, "settingsSound")) { root.toggleTickSound(); return true }
    if (Sc.hit(event, "settingsNotebook")) { root.openNotebook(); return true }
    return false
  }

  // What the agent knows (Settings → The agent): its notebook line by line,
  // each one to correct or forget, the student's answers, and their
  // corrections (docs/agent.md, slice 3). The runner does the writing and
  // keeps the record in corrections.md, which the agent reads every run
  // and never writes; the page only asks.
  property var notebookData: null           // `longhand-agent notebook`
  property int notebookFocus: -1
  property bool notebookCorrecting: false
  property string notebookNote: ""
  readonly property var notebookList: root.notebookRows(root.notebookData)

  function notebookRows(d) {
    var out = []
    if (!d) return out
    d.files.forEach(function (f) {
      out.push({ kind: "head", text: f.title, file: f.file, depth: 0 })
      f.lines.forEach(function (l) { out.push({ kind: "line", text: l.text, file: l.file, depth: l.depth }) })
    })
    if (d.answers.length > 0) {
      out.push({ kind: "head", text: "What you told it", file: "", depth: 0 })
      d.answers.forEach(function (a) { out.push({ kind: "answer", text: a.text, file: "answers.md", depth: 0 }) })
    }
    if (d.corrections.length > 0) {
      out.push({ kind: "head", text: "Your corrections", file: "", depth: 0 })
      d.corrections.forEach(function (c) {
        out.push({ kind: "correction", n: c.n, file: c.file, depth: 0,
                   text: c.how === "forget" ? "forget “" + c.text + "”" : "“" + c.text + "” → “" + c.to + "”",
                   note: c.date + " · " + c.file })
      })
    }
    return out
  }

  function sayNotebook() {
    var d = root.notebookData
    if (!d) return ""
    var n = 0
    d.files.forEach(function (f) { n += f.lines.length })
    if (n === 0) return "It has written nothing down yet."
    var c = d.corrections.length
    return "It keeps " + n + (n === 1 ? " note" : " notes") + " in " + d.files.length + (d.files.length === 1 ? " file" : " files")
      + (c > 0 ? ", held to " + c + (c === 1 ? " correction" : " corrections") + " of yours" : "") + "."
  }

  function loadNotebook() {
    if (notebookProc.running) return
    notebookProc.command = [svc.runner, "notebook"]
    notebookProc.running = true
  }

  function nextNotebookRow(from, dir) {
    var rows = root.notebookList
    for (var i = from + dir; i >= 0 && i < rows.length; i += dir)
      if (rows[i].kind !== "head") return i
    return from
  }

  function openNotebook() {
    root.settingsView = "notebook"
    root.notebookNote = ""
    root.notebookCorrecting = false
    root.used("notebook")
    root.loadNotebook()
    if (root.notebookFocus < 0 || root.notebookFocus >= root.notebookList.length
        || root.notebookList[root.notebookFocus].kind === "head")
      root.notebookFocus = root.nextNotebookRow(-1, 1)
    Qt.callLater(notebookSheet.notebookKeysRef.forceActiveFocus)
  }

  function closeNotebook() {
    root.settingsView = "main"
    root.notebookCorrecting = false
    Qt.callLater(settingsSheet.settingsFieldRef.forceActiveFocus)
  }

  function pickNotebook(i) {
    if (i < 0 || i >= root.notebookList.length || root.notebookList[i].kind === "head") return
    root.notebookFocus = i
    root.notebookCorrecting = false
    notebookSheet.notebookKeysRef.forceActiveFocus()
  }

  function startCorrect() {
    var row = root.notebookList[root.notebookFocus]
    if (!row) return
    if (row.kind !== "line") {
      root.notebookNote = row.kind === "answer" ? "an answer is yours: forget it, and answer again when it asks"
        : "a correction is taken back, not corrected: " + root.keyName("notebookForget")
      return
    }
    root.notebookNote = ""
    root.notebookCorrecting = true
    notebookSheet.notebookFieldRef.text = row.text
    Qt.callLater(function () { notebookSheet.notebookFieldRef.forceActiveFocus(); notebookSheet.notebookFieldRef.selectAll() })
  }

  function notebookAct(args, note, event) {
    if (notebookActProc.running) return
    root.notebookPendingNote = note
    notebookActProc.command = [svc.runner, "notebook"].concat(args)
    notebookActProc.running = true
    root.used("notebook", event)
  }
  property string notebookPendingNote: ""

  function saveCorrection(text) {
    var row = root.notebookList[root.notebookFocus]
    var to = text.replace(/\s+/g, " ").trim()
    root.notebookCorrecting = false
    notebookSheet.notebookKeysRef.forceActiveFocus()
    if (!row || row.kind !== "line" || to === "" || to === row.text) return
    root.notebookAct(["correct", "--file", row.file, "--text", row.text, "--to", to], "corrected — it keeps your words from now on", "correct")
  }

  function forgetNote() {
    var row = root.notebookList[root.notebookFocus]
    if (!row) return
    if (row.kind === "correction")
      root.notebookAct(["take-back", "--n", String(row.n)], "taken back — the agent is no longer held to it", "take-back")
    else if (row.kind === "answer")
      root.notebookAct(["forget", "--file", row.file, "--text", row.text], "forgotten — it may ask again", "forget-answer")
    else if (row.kind === "line")
      root.notebookAct(["forget", "--file", row.file, "--text", row.text], "forgotten — it stays forgotten", "forget")
  }

  function notebookKey(event) {
    if (root.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    if (root.notebookCorrecting) {
      if (seq === "Esc") { root.notebookCorrecting = false; notebookSheet.notebookKeysRef.forceActiveFocus(); return true }
      if (seq === "Enter") { root.saveCorrection(notebookSheet.notebookFieldRef.text); return true }
      return false
    }
    if (seq === "Esc") { root.closeNotebook(); return true }
    if (seq === "Up") { root.notebookFocus = root.nextNotebookRow(root.notebookFocus, -1); return true }
    if (seq === "Down") { root.notebookFocus = root.nextNotebookRow(root.notebookFocus, 1); return true }
    if (seq === "Enter" || Sc.hit(event, "notebookCorrect")) { root.startCorrect(); return true }
    if (Sc.hit(event, "notebookForget")) { root.forgetNote(); return true }
    return false
  }

  // The calendars as settings.json keeps them (the addresses live only
  // there, never in what the runner reports); the first version's single
  // address reads as one calendar whose classes only the agent sees.
  function readSettings() {
    try { return JSON.parse(settingsFile.text()) || {} } catch (e) { return {} }
  }

  function calendarList() {
    var cur = root.readSettings()
    if (Array.isArray(cur.calendars)) return cur.calendars.filter(function (c) { return c && c.url })
    if (cur.timetable) return [{ name: "Timetable", url: cur.timetable, agent: "classes" }]
    return []
  }

  // settings.json is merged, never replaced; the runner is asked only once
  // the file is written (onSaved).
  function writeCalendars(list, then) {
    var cur = root.readSettings()
    cur.calendars = list
    delete cur.timetable
    root.settingsPending = then
    root.settingsData = cur
    settingsFile.setText(JSON.stringify(cur, null, 2) + "\n")
  }

  function toggleTickSound() {
    var cur = root.readSettings()
    cur.tickSound = cur.tickSound === false
    root.settingsData = cur
    settingsFile.setText(JSON.stringify(cur, null, 2) + "\n")
    root.used("tick-sound", cur.tickSound ? "on" : "off")
    if (cur.tickSound) root.playTick(true)
  }

  // An address as calendars hand them out: https, http or webcal. A new
  // calendar starts narrow — the agent sees its classes only — and is
  // widened by choice (2026-10-17).
  function addCalendar(text) {
    var url = String(text || "").trim()
    if (url === "") { root.settingsNote = "paste a calendar's address first"; return }
    if (!/^(https?|webcal):\/\/\S+$/i.test(url)) {
      root.settingsNote = "that is not a calendar address: it starts with https:// or webcal://"
      return
    }
    var list = root.calendarList()
    for (var i = 0; i < list.length; i++)
      if (list[i].url === url) { root.settingsNote = "“" + list[i].name + "” already has that address"; root.settingsFocus = i; return }
    var host = (url.match(/^\w+:\/\/([^\/?#]+)/) || [url, url])[1]
    list.push({ name: host, url: url, agent: "classes" })
    root.settingsFocus = list.length - 1
    root.settingsBusyIndex = list.length - 1
    root.writeCalendars(list, ["--fetch", "--index", String(list.length - 1)])
    settingsSheet.settingsFieldRef.text = ""
    root.settingsNote = ""
    root.used("calendar", "added")
  }

  function removeCalendar(i) {
    var list = root.calendarList()
    if (i < 0 || i >= list.length) return
    var gone = list.splice(i, 1)[0]
    root.settingsFocus = Math.max(0, Math.min(i, list.length - 1))
    root.writeCalendars(list, [])
    root.settingsNote = "removed “" + gone.name + "”" + (list.length === 0 ? ": the sidebar goes back to the sessions in your project notes" : "")
    root.used("calendar", "removed")
  }

  function toggleShare(i) {
    var list = root.calendarList()
    if (i < 0 || i >= list.length) return
    list[i].agent = list[i].agent === "all" ? "classes" : "all"
    root.writeCalendars(list, [])
    root.settingsNote = ""
    root.used("calendar", list[i].agent)
  }

  function fetchCalendar(i) {
    var n = root.calendarList().length
    if (n === 0) { root.settingsNote = "no calendar to fetch yet"; return }
    root.settingsBusyIndex = i >= 0 && i < n ? i : -1
    root.runTimetable(["--fetch", "--index", String(root.settingsBusyIndex)])
  }

  function startRename(i) {
    var list = root.calendarList()
    if (i < 0 || i >= list.length) return
    root.settingsFieldKind = "rename"
    settingsSheet.settingsFieldRef.text = list[i].name
    settingsSheet.settingsFieldRef.selectAll()
  }

  function renameCalendar(text) {
    var name = String(text || "").replace(/\s+/g, " ").trim()
    var list = root.calendarList()
    root.settingsFieldKind = "add"
    settingsSheet.settingsFieldRef.text = ""
    var i = root.settingsFocus
    if (name === "" || i < 0 || i >= list.length || list[i].name === name) return
    list[i].name = name
    root.writeCalendars(list, [])
  }

  function runTimetable(flags) {
    if (settingsProc.running) return
    root.settingsBusy = flags.indexOf("--fetch") >= 0
    settingsProc.command = [svc.runner, "timetable"].concat(flags)
    settingsProc.running = true
  }

  // One calendar's state, in one line that answers "is it in use?" —
  // working, not working yet, or in use from an older copy — never
  // "connected" beside "failed" (2026-10-17: that read as both).
  function calendarStatus(c) {
    if (root.settingsBusy && (root.settingsBusyIndex < 0 || root.settingsBusyIndex === c.index))
      return { text: "asking…", tone: "dim" }
    var when = c.fetched > 0 ? root.sayAgo(c.fetched) : ""
    var ahead = (c.events === 1 ? "1 event" : c.events + " events") + " ahead"
      + (c.classes > 0 ? ", " + c.classes + " of them classes" : "")
    if (!c.copy) return { text: "Not working yet — nothing from it is used. " + root.sayFeedError(c.error), tone: "urgent" }
    if (c.error !== "") return { text: "In use, from the copy fetched " + when + " · " + ahead + ". The latest try did not work: " + root.sayFeedError(c.error), tone: "urgent" }
    return { text: "Working · fetched " + when + " · " + ahead, tone: "dim" }
  }

  function sayShare(c) {
    return c.agent === "all" ? "The agent sees everything in it — titles, times and places, never descriptions"
      : "The agent sees its classes only"
  }

  // Which courses the calendars know, said only when there is a calendar
  // to say it from.
  function courseLines() {
    var st = root.settingsState
    if (!st || !(st.calendars || []).some(function (c) { return c.copy })) return []
    var known = [], missing = [], nocode = []
    for (var i = 0; i < (st.courses || []).length; i++) {
      var c = st.courses[i]
      if (c.code === "") nocode.push(c.name)
      else if (c.sessions > 0) known.push(c.name + " (" + c.sessions + ")")
      else missing.push(c.name)
    }
    var out = []
    if (known.length > 0) out.push({ text: "Classes found: " + known.join(", "), tone: "dim" })
    if (missing.length > 0) out.push({ text: "No classes found for " + missing.join(", ") + " — their own session lines are used", tone: "dim" })
    if (nocode.length > 0) out.push({ text: "No course code to match by: " + nocode.join(", "), tone: "faint" })
    return out
  }

  // Everything the sheet says, as text, in order (tests/page/run.py).
  function settingsLines() {
    var st = root.settingsState
    if (!st) return []
    if (!st.configured) return [{ text: "No calendar yet. Paste a calendar's address — the .ics or webcal:// link from your university portal, or one you publish — and press Enter.", tone: "dim" }]
    var out = []
    for (var i = 0; i < st.calendars.length; i++) {
      var c = st.calendars[i]
      out.push({ text: c.name + " · " + c.address, tone: "fg" })
      out.push(root.calendarStatus(c))
      out.push({ text: root.sayShare(c), tone: "dim" })
    }
    return out.concat(root.courseLines())
  }

  // Why a fetch did not work, in words a student can act on.
  function sayFeedError(err) {
    if (err === "asks to sign in")
      return "The address answered with a sign-in page instead of a calendar, so it needs a login it cannot give. "
        + "Look for a subscribe or publish link, or a way to renew it, and paste the new one."
    if (err === "not a calendar")
      return "The address answered with a web page, not a calendar. Check that you copied the .ics or subscribe link."
    if (/^HTTP 40[13]$/.test(err)) return "It was refused (" + err + "): the link may have expired."
    if (err === "HTTP 404") return "There is nothing at that address (HTTP 404)."
    if (/^HTTP /.test(err)) return "The server had a problem (" + err + "). Try again later."
    if (err === "") return "It has not been fetched yet: " + root.keyName("settingsFetch") + " fetches it now."
    return "It could not be reached: " + err + "."
  }

  function sayAgo(epoch) {
    var s = Math.max(0, Math.round(Date.now() / 1000 - epoch))
    if (s < 60) return "just now"
    if (s < 3600) return Math.round(s / 60) + " min ago"
    if (s < 86400) return Math.round(s / 3600) + " h ago"
    return Qt.formatDate(new Date(epoch * 1000), "ddd d MMM")
  }

  // Where each surface is drawn, for tests/page/run.py to check that none
  // sits on another.
  function surfaces() {
    var out = {}
    var items = { sheet: sheet, dash: dash, keys: keysSheet, settings: settingsSheet, sidebar: sidebar, margin: margin }
    for (var n in items) {
      var it = items[n]
      if (it.visible) out[n] = { x: Math.round(it.x), w: Math.round(it.width) }
    }
    return out
  }

  // An action's key as a hint names it, kept current as it moves.
  function keyName(id) { root.keysVersion; return Sc.label(id) }

  // A hover's hint: what a thing does, and the key that does the same, so
  // the mouse teaches the keyboard. `lines` is [[words, action id], …] for
  // a thing that does more than one thing; an id of "" has no key. Read
  // from Shortcuts.js, so a key moved in the sheet is the one named.
  function tip(does, id) { return root.tips([[does, id]]) }
  function tips(lines) {
    root.keysVersion
    return lines.map(function (l) {
      if (!l[1]) return l[0]
      var k = Sc.label(l[1])
      return l[0] + "   " + (k === "—" ? "no key (" + Sc.label("keys") + " gives it one)" : k)
    }).join("\n")
  }

  function nextKeyRow(from, d) {
    var rows = root.keyRows
    for (var i = from + d; i >= 0 && i < rows.length; i += d) if (rows[i].kind !== "head") return i
    return from >= 0 && from < rows.length ? from : -1
  }

  // Keys while the sheet has them. Its own keys are fixed: a sheet whose
  // way out could be moved could lock the student in.
  function keysKey(event) {
    var seq = Sc.fromEvent(event)
    if (root.keysListen) {
      if (seq === "") return true                   // a modifier alone: still waiting
      if (seq === "Esc") { root.stopListening(); root.keysNote = ""; return true }
      if (root.keysListen.hypr) root.offerHyprKey(seq)
      else root.offerKey(seq)
      return true
    }
    if (root.anywhereKey(event)) return true
    var row = root.keyRows[root.keysFocus]
    if (seq !== "Enter") root.keysAdopt = false
    if (seq === "Esc") {
      if (root.keysFilter !== "") {
        keysSheet.keysFieldRef.text = ""
        root.keysFilter = ""
        root.keysFocus = root.nextKeyRow(-1, 1)
      } else {
        root.toggleKeys()
      }
    } else if (seq === "Up") root.keysFocus = root.nextKeyRow(root.keysFocus, -1)
    else if (seq === "Down") root.keysFocus = root.nextKeyRow(root.keysFocus, 1)
    else if (seq === "Enter" || seq === "Shift+Enter") root.listenFor(row, seq === "Shift+Enter")
    else if (seq === "Del") root.resetKey(row)
    else return false                               // typing: it finds
    return true
  }

  function listenFor(row, add) {
    root.keysTake = ""
    if (!row || row.kind === "head") return
    if (row.kind === "offer") { root.offerAdopt(); return }
    root.keysAdopt = false
    if (row.kind === "fixed") {
      root.keysNote = row.where === "Hyprland"
        ? "Hyprland's key, not the page's: the row above lets the page keep it, or change it in your Hyprland bindings (~/.config/hypr/bindings.lua)"
        : "The text field's own key: it stays, so writing works the same everywhere"
      return
    }
    root.keysListen = { id: row.id, add: add, hypr: row.kind === "hypr" }
    root.keysNote = ""
    if (row.kind === "hypr") root.hyprListen(true)
  }

  // Waiting for a new key ends: Esc, the key taken, the sheet closed.
  function stopListening() {
    if (root.keysListen && root.keysListen.hypr) root.hyprListen(false)
    root.keysListen = null
    root.keysTake = ""
  }

  // ------------------------------------------------------------ Hyprland's keys

  // hyprkeys.py, beside this file, keeps the six in ~/.config/hypr/longhand.lua
  // and answers every call with its state. One call at a time.
  readonly property string hyprKeysPy: decodeURIComponent(Qt.resolvedUrl("hyprkeys.py").toString().replace(/^file:\/\//, ""))
  function hypr(args) {
    if (hyprProc.running) return false
    hyprProc.kind = args[0]
    hyprProc.command = ["python3", root.hyprKeysPy].concat(args)
    hyprProc.running = true
    return true
  }

  function hyprDone(st) {
    if (!st) return
    root.hyprKeys = st
    root.keysVersion++
    var listening = !!root.keysListen && root.keysListen.hypr
    if (st.asks && listening) {
      // The second press of the same key takes it.
      root.keysTake = st.asks.key
      root.keysNote = Sc.show(st.asks.key) + " is Hyprland's “" + st.asks.does + "” — press it again to take it (it gets the key back when you move off it), Esc to leave it there"
    } else if (st.asks) {
      root.keysNote = Sc.show(st.asks.key) + " is Hyprland's “" + st.asks.does + "” now — Enter, then press it twice to take it back"
    } else if (st.error) {
      root.keysTake = ""
      root.keysNote = st.error
    } else if (hyprProc.kind !== "state") {
      if (listening) root.stopListening()
      root.keysNote = st.note || ""
      if (hyprProc.kind === "set") root.used("keys", "hypr")
    }
    if (root.keysListen && root.keysListen.hypr) root.hyprListen(true)   // a reload ends the submap
    var at = root.keyRows[root.keysFocus]
    if (!at || at.kind === "head") root.keysFocus = root.nextKeyRow(-1, 1)
  }

  // Letting the page keep the six is asked once, in words, and done on a
  // second Enter: it writes into the student's Hyprland config.
  function offerAdopt() {
    if (!root.keysAdopt) {
      root.keysAdopt = true
      root.keysNote = "Enter again to let the page keep these keys: it writes them to ~/.config/hypr/longhand.lua, adds one line at the end of "
        + "~/.config/hypr/bindings.lua to load it, and comments out your own lines for them there (bindings.lua is backed up first). Esc leaves them as they are."
      return
    }
    root.keysAdopt = false
    root.keysNote = "…"
    root.hypr(["adopt"])
    root.used("keys", "adopt")
  }

  function offerHyprKey(seq) {
    if (hyprProc.running) return
    var l = root.keysListen
    var args = ["set", l.id.slice(5)]
    if (l.add) args.push("--add")
    if (root.keysTake === seq) args.push("--take")
    root.keysNote = "…"
    root.hypr(args.concat([seq]))
  }

  // While the sheet waits for a Hyprland key, Hyprland is put in a submap
  // of its own that binds nothing the student can press, so every key —
  // Super+Alt+F, or the page's own Super+Alt+= — reaches the sheet instead
  // of doing what it does. Hyprland leaves it by itself after 30 seconds,
  // so a page that dies while waiting cannot keep the keyboard.
  function hyprListen(on) {
    hyprListenTimer.running = on
    submapProc.running = false
    submapProc.command = ["hyprctl", "eval", on
      ? 'hl.define_submap("longhand-keys", function() hl.bind("SUPER + CTRL + ALT + SHIFT + F24", hl.dsp.submap("reset")) end); '
        + 'longhand_keys_wait = (longhand_keys_wait or 0) + 1; local n = longhand_keys_wait; '
        + 'hl.timer(function() if longhand_keys_wait == n and hl.get_current_submap() == "longhand-keys" then hl.dispatch(hl.dsp.submap("reset")) end end, { timeout = 30000, type = "oneshot" }); '
        + 'hl.dispatch(hl.dsp.submap("longhand-keys"))'
      : 'if hl.get_current_submap() == "longhand-keys" then hl.dispatch(hl.dsp.submap("reset")) end']
    submapProc.running = true
  }

  function doesList(ids) { return ids.map(function (id) { return Sc.does(id) }).join("”, “") }

  function offerKey(seq) {
    var id = root.keysListen.id
    var c = Sc.check(id, seq)
    if (!c.ok) { root.keysTake = ""; root.keysNote = c.reason; return }   // still listening
    if (c.taken.length > 0 && root.keysTake !== seq) {
      root.keysTake = seq
      root.keysNote = Sc.show(seq) + " is “" + root.doesList(c.taken) + "” — press it again to move it here, Esc to leave it there"
      return
    }
    Sc.assign(id, seq, root.keysListen.add)
    root.keysListen = null
    root.keysTake = ""
    var bare = c.taken.filter(function (t) { return Sc.keysOf(t).length === 0 })
    root.keysNote = c.taken.length === 0 ? ""
      : Sc.show(seq) + " moved here from “" + root.doesList(c.taken) + "”"
        + (bare.length > 0 ? ", which has no key now (Del on it gives its own back)" : "")
    root.used("keys", "moved")
    root.saveKeys()
  }

  function resetKey(row) {
    root.keysTake = ""
    if (row && row.kind === "hypr") {
      if (!row.changed) { root.keysNote = "“" + row.does + "” is on its own keys already"; return }
      root.keysNote = "…"
      root.hypr(["set", row.id.slice(5)].concat(row.own))
      return
    }
    if (!row || row.kind !== "action") return
    if (!row.changed) { root.keysNote = "“" + row.does + "” is on its own keys already"; return }
    var from = Sc.reset(row.id)
    root.keysNote = from.length > 0 ? "taken back from “" + root.doesList(from) + "”" : ""
    root.used("keys", "reset")
    root.saveKeys()
  }

  function saveKeys() {
    root.keysVersion++
    var at = root.keyRows[root.keysFocus]
    if (!at || at.kind === "head") root.keysFocus = root.nextKeyRow(-1, 1)
    keysFile.setText(JSON.stringify(Sc.save(), null, 2) + "\n")
  }

  // ------------------------------------------------------------ tasks panel

  // Ctrl+T: the dashboard. Every open box and every deadline in one place,
  // full width, worked with keys — the pinned twin of the bar's deadline
  // popup (SUPER+ALT+D), which stays the glance. It takes the sheet's place
  // rather than sitting beside it: a list is not prose and does not want the
  // 72-character measure. Decided 2026-10-15, and it replaces the narrow
  // what's-next panel the margin used to hold, because two surfaces for one
  // list is part of what made the list easy to ignore.
  function toggleDash() {
    root.dashOpen = !root.dashOpen
    root.dashWhenFor = null
    root.dashWhenText = ""
    root.showShelf = false
    root.showGrading = false
    if (root.dashOpen) {
      root.used("dashboard")
      root.taskFocus = 0
      root.moveTaskFocus(0)
      root.refreshTasks()
      root.refreshProposals()
      root.runPlan(false)
      dash.dashKeysRef.forceActiveFocus()
    } else {
      editor.focusNote()
    }
  }

  function refreshTasks() {
    // Not while a tick is still being drawn: the list read again rebuilds
    // every row, which would cut the tick short.
    var wait = root.holdTasksUntil - Date.now()
    if (wait > 0) { tasksHold.interval = Math.ceil(wait); tasksHold.restart(); return }
    tasksProc.command = [svc.runner, "next", "--days", "7"]
    tasksProc.running = true
  }

  Timer { id: tasksHold; onTriggered: root.refreshTasks() }

  // A row's identity across the list being read again.
  function rowKey(row) {
    if (!row) return ""
    if (row.kind === "deadline") return "d" + row.deadline.id
    if (row.kind === "proposal" || row.kind === "question") return "p" + row.item.id
    if (row.kind === "task") return row.task.date + "|" + row.task.line + "|" + row.task.text
    return ""
  }

  // The tick, felt (2026-10-17, after Todoist): the row is done on screen
  // this frame, plays its tick, and stays — the list is not read again
  // until the tick has been seen.
  readonly property int tickMs: 450
  function markTicked(key) {
    root.tickSound()
    var d = {}
    for (var k in root.doneNow) d[k] = root.doneNow[k]
    d[key] = true
    // Which row, before it turns done: its delegate decides on the change
    // whether to play the tick.
    root.justTicked = key
    root.doneNow = d
    root.holdTasksUntil = Date.now() + root.tickMs
  }

  Timer {
    id: tickSettle
    interval: root.tickMs
    onTriggered: {
      var todo = root.afterTick
      root.afterTick = []
      for (var i = 0; i < todo.length; i++) todo[i]()
    }
  }

  // ------------------------------------------------- a project's notes

  // Class notes found by their course instead of by the date they happened
  // on (the week of 2026-10-12 opened the calendar 31 times looking for
  // them): every section of the project's tag, newest first, opened in
  // place. The claiming rule lives in `longhand-agent sections`.
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
    sidebar.sidebarKeysRef.forceActiveFocus()
  }

  // The day's deadline list in the sidebar; false for a key it does not
  // use. A function, as projectsKey is, so the page can be driven without
  // a keyboard (tests/page/run.py).
  function dueKey(event) {
    var n = root.focusDue.length
    if (Sc.hit(event, "listUp")) root.dueFocus = Math.max(0, root.dueFocus - 1)
    else if (Sc.hit(event, "listDown")) root.dueFocus = Math.min(n - 1, root.dueFocus + 1)
    else if (Sc.hit(event, "listOpen")) root.goToDeadline(root.focusDue[root.dueFocus])
    else if (Sc.hit(event, "listDone")) {
      var d = root.focusDue[root.dueFocus]
      if (d && d.status === "open") root.tickSound()
      root.tickDeadline(d)
    }
    else if (Sc.hit(event, "listNext")) { root.dueFocus = -1; if (root.projects.length > 0) root.projFocus = 0 }
    else if (Sc.hit(event, "listBack")) root.dueFocus = -1
    else return false
    return true
  }

  // The projects list's keys, in one function so the page can be driven
  // without a keyboard. Enter (or Right) opens the project's own notes —
  // the list is there to find them. Writing into the note is the shifted
  // pair: Shift+Enter starts a class, Ctrl+Enter puts the tag at the
  // cursor. Inverted 2026-10-15; `@` in the note is the way to write one.
  function projectsKey(event) {
    var pr = root.projects[root.projFocus]
    if (Sc.hit(event, "listUp")) root.projFocus = Math.max(0, root.projFocus - 1)
    else if (Sc.hit(event, "listDown")) root.projFocus = Math.min(root.projects.length - 1, root.projFocus + 1)
    else if (Sc.hit(event, "listTag")) { if (pr) root.insertTag(pr) }
    else if (Sc.hit(event, "listClass")) { if (pr) root.startClass(pr) }
    else if (Sc.hit(event, "listOpen")) { if (pr) root.openProject(pr) }
    else if (Sc.hit(event, "listInto")) root.openProject(pr)
    else if (Sc.hit(event, "listNext") || Sc.hit(event, "listBack")) root.projFocus = -1
    else if (!(event.modifiers & Qt.ControlModifier)) { root.projFocus = -1; return false }
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
    sidebar.sidebarKeysRef.forceActiveFocus()
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
  // since the list was gathered (the same reason tasks are found by words).
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

  // The dashboard's rows, in the order they ask something of you:
  //
  //   DUE            deadlines — late ones are the earliest, so they lead;
  //                  ones closed today stay until tomorrow
  //   DOING          boxes with a day on them (⏳ a do-date, or 📅 still
  //                  unbound), by that day
  //   TO SCHEDULE    boxes with a priority but no day yet — the pile the
  //                  do-date is for
  //   #project       note boxes, under the project that claims them, newest
  //                  first
  //   NOT NOW        folded: boxes whose silence ran out, or put aside with
  //                  `s` (agent/lifespan.py) — never rewritten, back when
  //                  touched
  //   WAITING FOR A GRADE   folded: done deadlines with no grade yet
  //   FROM THE AGENT
  //
  // Note boxes group by project rather than by the day they were written,
  // because the day a thought was written is not how it is looked for
  // (2026-10-15, and the 31 trips to the calendar before it). A box bound to
  // the store is listed once, as its deadline.
  function buildTaskRows() {
    var rows = []
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    // Closed today (done, or cancelled) stays until tomorrow, so what just
    // happened can still be seen; a deadline no line stands for yet has a
    // band of its own.
    var due = dl.items.filter(function (d) {
      return (d.status === "open" && d.link !== "")
        || ((d.status === "done" || d.status === "cancelled") && d.doneAt * 1000 >= today.getTime())
    })
    var waiting = dl.items.filter(function (d) { return d.status === "open" && d.link === "" })
    due.sort(function (a, b) {
      if (a.status !== b.status) return a.status === "open" ? -1 : 1
      return a.due - b.due
    })
    if (due.length > 0) {
      rows.push({ kind: "head", text: "DUE", tag: "" })
      var month = ""
      for (var k = 0; k < due.length; k++) {
        var lbl = root.monthLabel(due[k].due * 1000)
        if (lbl !== month) { rows.push({ kind: "month", text: lbl }); month = lbl }
        rows.push({ kind: "deadline", deadline: due[k] })
      }
    }
    if (waiting.length > 0) {
      waiting.sort(function (a, b) { return a.due - b.due })
      rows.push({ kind: "head", text: "NOT IN A NOTE YET", tag: "" })
      for (var w = 0; w < waiting.length; w++) rows.push({ kind: "deadline", deadline: waiting[w] })
    }

    var doing = [], later = [], notes = [], shelf = []
    for (var i = 0; i < root.tasks.length; i++) {
      var t = root.tasks[i]
      if (t.anchor > 0) continue
      if (t.away) shelf.push(t)
      else if (t.when !== "" || t.due !== "") doing.push(t)
      else if (t.kind === "task") later.push(t)
      else notes.push(t)
    }
    doing.sort(function (a, b) { return (a.when || a.due).localeCompare(b.when || b.due) })
    later.sort(function (a, b) { return b.priority - a.priority || a.age - b.age })
    if (doing.length > 0) {
      rows.push({ kind: "head", text: "DOING", tag: "" })
      var dm = ""
      for (var d1 = 0; d1 < doing.length; d1++) {
        var dl1 = root.monthLabel(root.taskMs(doing[d1]))
        if (dl1 !== dm) { rows.push({ kind: "month", text: dl1 }); dm = dl1 }
        rows.push({ kind: "task", task: doing[d1] })
      }
    }
    if (later.length > 0) {
      rows.push({ kind: "head", text: "TO SCHEDULE", tag: "" })
      for (var l = 0; l < later.length; l++) rows.push({ kind: "task", task: later[l] })
    }

    var groups = [], seen = ({})
    for (var n = 0; n < notes.length; n++) {
      var key = notes[n].project || ""
      if (seen[key] === undefined) { seen[key] = groups.length; groups.push({ key: key, items: [] }) }
      groups[seen[key]].items.push(notes[n])
    }
    for (var g = 0; g < groups.length; g++) {
      // The course's own name, not its tag: a band that reads
      // "Interdisciplinary Seminar" says more than #intsem. The sidebar
      // knows the names from the curriculum; for a tag it does not know,
      // the heading the notes themselves use is the next best name.
      var key = groups[g].key
      var named = key === "" ? "No project" : root.courseName(key)
      if (key !== "" && named === key) {
        for (var h = 0; h < groups[g].items.length; h++) {
          var path0 = (groups[g].items[h].path || [])[0]
          if (path0) { named = path0; break }
        }
      }
      rows.push({ kind: "head", text: named, tag: key === "" ? "" : "#" + key })
      // Under a band, a row does not repeat it: the section it was written
      // in is what the row still has to say.
      for (var m = 0; m < groups[g].items.length; m++)
        rows.push({ kind: "task", task: groups[g].items[m], under: named })
    }
    // What is away and what is owed a grade, each folded into one row until
    // asked for: there to be found, never in the way.
    if (shelf.length > 0) {
      if (!root.showShelf) rows.push({ kind: "shelf", count: shelf.length })
      else {
        rows.push({ kind: "head", text: "NOT NOW", tag: "" })
        for (var s = 0; s < shelf.length; s++) rows.push({ kind: "task", task: shelf[s] })
      }
    }
    var grading = dl.items.filter(function (d) {
      return d.status === "done" && d.grade === "" && d.doneAt * 1000 < today.getTime()
    })
    if (grading.length > 0) {
      if (!root.showGrading) rows.push({ kind: "grading", count: grading.length })
      else {
        grading.sort(function (a, b) { return b.doneAt - a.doneAt })
        rows.push({ kind: "head", text: "WAITING FOR A GRADE", tag: "" })
        for (var gr = 0; gr < grading.length; gr++) rows.push({ kind: "deadline", deadline: grading[gr] })
      }
    }
    if (root.raised.length > 0) {
      rows.push({ kind: "head", text: "FROM THE AGENT", tag: "" })
      for (var j = 0; j < root.raised.length; j++) rows.push({ kind: "raised", item: root.raised[j] })
    }
    return root.withProposals(rows)
  }

  // The line that stands for a deadline, as a task the edit path can find —
  // by its tag, which survives any change of words. null when no note
  // holds it.
  function lineTaskOf(d) {
    for (var i = 0; i < root.tasks.length; i++) if (root.tasks[i].anchor === d.id) return root.tasks[i]
    var l = Bound.parseLink(d.link)
    if (!l || !svc.configured) return null
    return { anchor: d.id, date: l.stem, file: svc.pathFor(l.stem), text: "", line: -1, details: 0, path: [] }
  }

  // A deadline row's second line: where its line is, where it came from,
  // how much is written under it.
  function deadlineWhere(d) {
    var bits = []
    var t = null
    for (var i = 0; i < root.tasks.length; i++) if (root.tasks[i].anchor === d.id) t = root.tasks[i]
    var place = t ? (t.path || []).slice() : []
    var full = d.project ? root.courseName(d.project) : ""
    if (full !== "" && full !== d.project && place.length > 0) place[0] = full
    if (place.length > 0) bits.push(place.join(" › "))
    else if (d.project) bits.push(root.courseLabel(d.project))
    if (d.status === "cancelled") bits.push("cancelled")
    var aside = root.asideIn(d)
    if (aside > 0) bits.push(aside === 1 ? "steps aside tomorrow" : "steps aside in " + aside + " days")
    if (d.status === "done" && d.grade !== "") bits.push("graded " + d.grade)
    var o = root.origins[String(d.id)]
    if (o && o.origin === "agent") bits.push("from the agent" + (o.rewritten ? " · rewritten by you" : ""))
    if (t && t.details > 0) bits.push(t.details === 1 ? "1 line of detail" : t.details + " lines of detail")
    return bits.join("   ·   ")
  }

  // The agent's proposals and questions, as rows (docs/agent.md): each right
  // under the box it is about, so the decision is made where the box is;
  // one about a box not on the list waits under "from the agent".
  function withProposals(rows) {
    var props = root.proposals
    if (!props || props.length === 0) return rows
    var byKey = {}, used = {}
    for (var i = 0; i < props.length; i++) {
      var k = props[i].key
      if (k) (byKey[k] = byKey[k] || []).push(props[i])
    }
    var out = []
    for (var r = 0; r < rows.length; r++) {
      out.push(rows[r])
      var t = rows[r].kind === "task" ? rows[r].task
        : rows[r].kind === "deadline" ? root.taskOfAnchor(rows[r].deadline.id) : null
      var mine = t && t.key ? byKey[t.key] : null
      if (!mine) continue
      for (var m = 0; m < mine.length; m++) {
        if (used[mine[m].id]) continue
        used[mine[m].id] = true
        out.push({ kind: mine[m].kind === "question" ? "question" : "proposal", item: mine[m], task: t })
      }
    }
    var rest = props.filter(function (x) { return !used[x.id] })
    if (rest.length === 0) return out
    var at = -1
    for (var h = 0; h < out.length; h++) if (out[h].kind === "head" && out[h].text === "FROM THE AGENT") at = h
    var extra = rest.map(function (x) {
      return { kind: x.kind === "question" ? "question" : "proposal", item: x, task: root.taskOfKey(x.key) }
    })
    if (at < 0) return out.concat([{ kind: "head", text: "FROM THE AGENT", tag: "" }]).concat(extra)
    return out.slice(0, at + 1).concat(extra).concat(out.slice(at + 1))
  }

  function taskOfAnchor(id) {
    for (var i = 0; i < root.tasks.length; i++) if (root.tasks[i].anchor === id) return root.tasks[i]
    return null
  }

  function taskOfKey(key) {
    if (!key) return null
    for (var i = 0; i < root.tasks.length; i++) if (root.tasks[i].key === key) return root.tasks[i]
    return null
  }

  // Planning (docs/agent.md): when the page or the dashboard opens (the
  // runner plans at most once a day unless what it plans around changed),
  // and now, when asked. The arithmetic and the checks are the runner's;
  // the proposals arrive as rows.
  property bool planAgain: false     // "plan now" asked while a plan was running
  property string planError: ""      // why the last plan could not be made, in words
  function runPlan(force) {
    if (!svc.configured) return
    // Asked for while the day's own plan is still running: runs right after
    // it, rather than being lost.
    if (planProc.running) { if (force) root.planAgain = true; return }
    root.planning = true
    planProc.command = [svc.runner, "plan"].concat(force ? ["--force"] : [])
    planProc.running = true
    if (force) root.used("plan", "asked")
  }

  // Why a plan failed, in words that say what to do.
  function sayPlanError(err) {
    var e = String(err)
    if (/api_key_expired|has expired/.test(e)) return "its model key has expired — make a new one and log opencode in again"
    if (/401|authentication|unauthori/i.test(e)) return "its model login was refused — log opencode in again"
    if (/timed out|ENOTFOUND|network|connect/i.test(e)) return "the model could not be reached"
    return "the model said: " + e.slice(0, 80)
  }

  function refreshProposals() {
    if (proposalsProc.running || !svc.configured) return
    proposalsProc.command = [svc.runner, "proposals"]
    proposalsProc.running = true
  }

  // The person's answer: the row goes at once, the runner records it in
  // order.
  function resolveProposal(item, how, answer) {
    root.proposals = root.proposals.filter(function (x) { return x.id !== item.id })
    var args = [svc.runner, "proposal", how, "--id", String(item.id)]
    if (answer) args = args.concat(["--answer", answer])
    root.proposalQueue = root.proposalQueue.concat([args])
    root.nextProposal()
    root.used("proposal", how)
  }

  function nextProposal() {
    if (proposalProc.running || root.proposalQueue.length === 0) return
    proposalProc.command = root.proposalQueue[0]
    root.proposalQueue = root.proposalQueue.slice(1)
    proposalProc.running = true
  }

  // Space / Ctrl+Enter on a proposal: the do-date is written on the box's
  // line — by the page, the one writer of notes — and the acceptance
  // recorded. On a question: the recommended answer.
  function acceptPlanned(row) {
    var p = row.item
    if (row.kind === "question") { root.resolveProposal(p, "accept", ""); return }
    var t = row.task || root.taskOfKey(p.key)
    if (!t) { root.showHint("its box is not on the list any more"); return }
    root.editTask(t, "when", p.date)
    var d = {}
    for (var k in root.agentDates) d[k] = root.agentDates[k]
    d[p.key] = p.date
    root.agentDates = d
    root.resolveProposal(p, "accept", "")
  }

  // An open deadline a fortnight past its date steps aside (longhand-check);
  // the days it has left, through the last four of them, else 0.
  function asideIn(d) {
    if (d.status !== "open") return 0
    var left = Math.ceil(((d.due + 14 * 86400) * 1000 - Date.now()) / 86400000)
    return left > 0 && left <= 4 ? left : 0
  }

  // What a row says. The title is the words alone: the dates and the
  // priority a line carries are drawn as marks, so the metadata is on disk
  // and quiet on screen.
  function taskTitle(t) { return t.title !== undefined && t.title !== "" ? t.title : t.text }

  // Priority is a mark beside the box, not a word in the row: ▲ for the
  // high one, ▽ for the low, nothing for the rest.
  function taskMark(t) {
    if (!t || t.priority === undefined || t.priority === 0) return ""
    return t.priority >= 1 ? "▲" : "▽"
  }

  // A course's own name, from its tag. The sidebar reads the curriculum for
  // them; a tag the list does not know stays a tag. (Not `projectName` —
  // that is the open project's own name, a property of the sidebar.)
  function courseName(tag) {
    for (var i = 0; i < root.projects.length; i++)
      if (root.projects[i].tag === tag) return root.projects[i].name || tag
    return tag
  }

  // A course for a row that has no heading path to fall back on.
  function courseLabel(tag) {
    if (!tag) return ""
    var name = root.courseName(tag)
    return name === tag ? "#" + tag : name
  }

  // Where it came from, under the words: the course in full, then the
  // section it was written in, then how long ago. The line that makes
  // "draft the intro" mean something again three days later. The dates are
  // not in here — they are pills, as they are in the note.
  function taskWhere(t, under) {
    var path = (t.path || []).slice()
    var full = t.project ? root.courseName(t.project) : ""
    // The first heading is the course itself by the convention in use, so
    // its full name belongs there when the list knows it.
    if (full !== "" && full !== t.project) {
      if (path.length > 0) path[0] = full
      else path = [full]
    } else if (path.length === 0 && t.project) {
      path = ["#" + t.project]
    }
    // Under a band that already names the course, the course is noise.
    if (under !== undefined && under !== "" && path.length > 0 && path[0] === under) path.shift()
    var bits = []
    if (path.length > 0) bits.push(path.join(" › "))
    bits.push(root.sayAge(t.age))
    if (t.details > 0) bits.push(t.details === 1 ? "1 line of detail" : t.details + " lines of detail")
    var life = root.sayLife(t)
    if (life !== "") bits.push(life)
    return bits.join("   ·   ")
  }

  // The silence clock, said only when it matters: through the last quarter
  // of a box's life, and once it is away. Nothing goes without first being
  // shown as about to (agent/lifespan.py).
  function sayLife(t) {
    if (t.away === "shelved") return "put aside"
    if (t.away === "quiet") return "gone quiet"
    if (!t.warn) return ""
    return t.left === 1 ? "goes quiet tomorrow" : "goes quiet in " + t.left + " days"
  }

  // The month a row falls in, for the band above it.
  function monthLabel(ms) {
    var d = new Date(ms)
    return Qt.formatDate(d, d.getFullYear() === new Date().getFullYear() ? "MMMM" : "MMMM yyyy")
  }

  function taskMs(t) {
    var iso = t.when || t.due
    if (!iso) return 0
    var p = iso.split(" ")[0].split("-")
    return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)).getTime()
  }

  // The dates a row carries, drawn the way the note draws them: a bordered
  // date at the line's end. The day it is owed is bare, as in the note; the
  // day I mean to work on it says so and is filled rather than outlined.
  function pillsFor(row) {
    var out = []
    if (row.kind === "deadline") {
      var d = row.deadline
      var at = new Date(d.due * 1000)
      var timed = !(at.getHours() === 23 && at.getMinutes() === 59)
      out.push({ text: root.sayDate(Qt.formatDateTime(at, timed ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd")),
                 tone: d.status !== "open" ? "done" : (d.due * 1000 < Date.now() ? "late" : "due") })
      return out
    }
    if (row.kind !== "task") return out
    var t = row.task
    if (t.when) out.push({ text: "do " + root.sayDate(t.when) + (root.agentDates[t.key] === t.when ? " ◇" : ""), tone: "do" })
    if (t.due) out.push({ text: root.sayDate(t.due), tone: "due" })
    if (t.est) out.push({ text: t.est, tone: "est" })
    return out
  }

  function sayDate(iso) {
    if (!iso) return ""
    var parts = iso.split(" ")
    var ymd = parts[0].split("-")
    var d = new Date(parseInt(ymd[0], 10), parseInt(ymd[1], 10) - 1, parseInt(ymd[2], 10))
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    var days = Math.round((d.getTime() - today.getTime()) / 86400000)
    var say = days === 0 ? "today" : days === 1 ? "tomorrow" : days === -1 ? "yesterday"
      : days < 0 ? Math.abs(days) + " days late" : Qt.formatDate(d, "ddd d MMM")
    return say + (parts[1] && parts[1] !== "23:59" ? " " + parts[1] : "")
  }

  function sayAge(age) {
    return age === 0 ? "written today" : age === 1 ? "written yesterday" : "written " + age + " days ago"
  }

  // Heads and month bands are passed over: they are not rows you act on.
  // A move of 0 is how the cursor lands on a real row to begin with.
  function moveTaskFocus(d) {
    var rows = root.taskRows
    var step = d === 0 ? 1 : d
    var i = root.taskFocus + d
    while (i >= 0 && i < rows.length && (rows[i].kind === "head" || rows[i].kind === "month")) i += step
    if (i >= 0 && i < rows.length) root.taskFocus = i
  }

  // What the list adds up to, for the line beside its name.
  readonly property string dashCount: {
    var open = 0, due = 0, done = 0
    var rows = root.taskRows
    root.doneNow
    for (var i = 0; i < rows.length; i++) {
      var now = !!root.doneNow[root.rowKey(rows[i])]
      if (rows[i].kind === "task" && !rows[i].task.away) { if (rows[i].task.done || now) done++; else open++ }
      else if (rows[i].kind === "deadline" && rows[i].deadline.status === "open") { if (now) done++; else { due++; open++ } }
      else if (rows[i].kind === "deadline" && rows[i].deadline.status === "done") done++
    }
    var asks = root.proposals.length
    if (open === 0 && done === 0 && asks === 0) return root.planning ? "planning…" : root.planError !== "" ? "the agent could not plan" : ""
    return open + " open" + (due > 0 ? "   ·   " + due + " with a date to meet" : "")
      + (done > 0 ? "   ·   " + done + " done today" : "")
      + (asks > 0 ? "   ·   " + asks + " from the agent" : "")
      + (root.planning ? "   ·   planning…" : root.planError !== "" ? "   ·   the agent could not plan: " + root.planError : "")
  }

  // Enter: go to the task's line, on any day; the dashboard closes. A
  // deadline no line stands for yet is written into today's note — the
  // person's act, which is what makes its words theirs (docs/tasks.md).
  function activateTask() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    // Enter on a question: the person's own answer, typed; on a proposal:
    // its box's line.
    if (row.kind === "question") { root.startDashAnswer(row.item); return }
    if (row.kind === "proposal") { if (row.task) root.goToTask(row.task); return }
    if (row.kind === "shelf") { root.showShelf = true; return }
    if (row.kind === "grading") { root.showGrading = true; return }
    if (row.kind === "task") root.goToTask(row.task)
    if (row.kind === "deadline") {
      var d = row.deadline
      if (Bound.parseLink(d.link)) { root.backToNote(); root.goToDeadline(d); return }
      root.writeIntoToday(d)
    }
    if (row.kind === "raised") {
      dismissProc.command = [svc.runner, "dismiss", "--date", row.item.date, "--kind", row.item.kind, "--index", String(row.item.index)]
      dismissProc.running = true
    }
  }

  function focusedTask() {
    var row = root.taskRows[root.taskFocus]
    return row && row.kind === "task" ? row.task : null
  }

  // Delete: dropping something is an answer, and the only honest one for a
  // box that is never going to happen. The line keeps its words and becomes
  // `- [-] … ❌ <today>`, so the note still says what was decided. A
  // deadline is cancelled the same way, through its line — words are only
  // ever deleted in the note — and one with no line yet is cancelled in the
  // store.
  function dropFocused() {
    var row = root.taskRows[root.taskFocus]
    if (row && (row.kind === "proposal" || row.kind === "question")) { root.resolveProposal(row.item, "decline", ""); return }
    if (row && row.kind === "deadline") { root.dropDeadline(row.deadline); return }
    var t = root.focusedTask()
    if (!t) return
    root.tickHistory = root.tickHistory.concat([{ drop: t }])
    root.editTask(t, "drop", "")
    root.used("drop")
  }

  function dropDeadline(d) {
    if (d.status === "cancelled") return
    var t = root.lineTaskOf(d)
    if (t) {
      root.tickHistory = root.tickHistory.concat([{ drop: t }])
      root.editTask(t, "drop", "")
    } else {
      root.tickHistory = root.tickHistory.concat([{ uncancel: d.id }])
      dl.cancel(d.id)
    }
    root.used("drop", "deadline")
  }

  // `p`: none → high → low → none. One key for the whole scale, because
  // three levels are offered where five are read.
  function cyclePriorityFocused() {
    var t = root.focusedTask()
    if (!t) return
    root.editTask(t, "prio", Task.nextPriority(t.priority || 0))
    root.touchBox(t, "keep")
    root.used("priority")
  }

  // `s`: not now. The box goes where quiet ones go, and nothing is written
  // into the note; `s` again (or `r`) brings it back. Its clock is the
  // layer's (agent/lifespan.py).
  function shelveFocused() {
    var t = root.focusedTask()
    if (!t || t.life === 0) return
    root.touchBox(t, t.away ? "keep" : "shelve")
    root.used(t.away ? "keep" : "shelve")
  }

  // `r`: kept on purpose — its clock starts again, and it is back if it was
  // away.
  function keepFocused() {
    var t = root.focusedTask()
    if (!t || t.life === 0) return
    root.touchBox(t, "keep")
    root.used("keep")
  }

  function touchBox(t, how) {
    if (!t || !t.key || t.life === 0) return
    boxProc.command = [svc.runner, "box", how, "--key", t.key]
    boxProc.running = true
  }

  // `g`: the grade, typed on a deadline's row, as in the popup. A grade on
  // one still open hands it in (pomo); empty clears it.
  // Enter on the agent's question: the person's own answer, in words.
  function startDashAnswer(q) {
    root.dashFieldKind = "answer"
    root.dashFieldStart = ""
    root.dashWhenText = ""
    root.dashWhenFor = { question: q }
  }

  function startDashGrade() {
    var row = root.taskRows[root.taskFocus]
    if (!row || row.kind !== "deadline" || row.deadline.status === "cancelled") return
    root.dashFieldKind = "grade"
    root.dashFieldStart = row.deadline.grade
    root.dashWhenText = row.deadline.grade
    root.dashWhenFor = { deadline: row.deadline }
  }

  // `t`: the one place in the dashboard that takes words instead of keys,
  // because a date is quicker said than picked — and it is read by the
  // note's own parser, so "friday" means here what it means there.
  function startDashWhen() {
    if (!root.focusedTask()) return
    root.dashFieldKind = "when"
    root.dashFieldStart = ""
    root.dashWhenFor = root.focusedTask()
    root.dashWhenText = ""
  }

  // Ctrl+E: the task's words, rewritten on its row (Todoist's key for it).
  // The second place the dashboard takes typed words, beside `t`; the
  // details stay in the note, under the line. A deadline the agent wrote
  // and no line holds yet is where a person writes over the agent's words.
  function startDashRename() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    var target = null, words = ""
    if (row.kind === "task") { target = row.task; words = Task.wordsOf(row.task.text) }
    else if (row.kind === "deadline" && row.deadline.status !== "cancelled") {
      var t = root.lineTaskOf(row.deadline)
      if (t && t.text !== "") { target = t; words = Task.wordsOf(t.text) }
      else if (!t) { target = { deadline: row.deadline }; words = row.deadline.title }
      else { target = t; words = row.deadline.title }
    }
    if (!target) return
    root.dashFieldKind = "rename"
    root.dashFieldStart = words
    root.dashWhenText = words
    root.dashWhenFor = target
  }

  function commitDashRename() {
    var t = root.dashWhenFor
    var words = root.dashWhenText.replace(/\s+/g, " ").trim()
    root.dashWhenFor = null
    root.dashWhenText = ""
    if (!t || words === "" || words === root.dashFieldStart) return
    if (t.deadline) dl.set(t.deadline.id, ["--title", words])
    else {
      root.authorRenamed(t.date, "- [ ] " + t.text, Task.setWords("- [ ] " + t.text, words))
      root.editTask(t, "rename", words)
    }
    root.used("rename")
  }

  function commitDashWhen() {
    if (root.dashFieldKind === "rename") { root.commitDashRename(); return }
    if (root.dashFieldKind === "answer") {
      var q = root.dashWhenFor
      var said = root.dashWhenText.replace(/\s+/g, " ").trim()
      root.dashWhenFor = null
      root.dashWhenText = ""
      if (q && q.question && said !== "") root.resolveProposal(q.question, "answer", said)
      return
    }
    if (root.dashFieldKind === "grade") {
      var g = root.dashWhenFor
      var mark = root.dashWhenText.replace(/\s+/g, " ").trim()
      root.dashWhenFor = null
      root.dashWhenText = ""
      if (g && g.deadline && mark !== root.dashFieldStart) { dl.grade(g.deadline.id, mark); root.used("grade") }
      return
    }
    var t = root.dashWhenFor
    var phrase = root.dashWhenText.trim()
    root.dashWhenFor = null
    root.dashWhenText = ""
    if (!t || phrase === "") return
    var read = Dates.read(phrase, new Date())
    if (!read) { root.hint = "no date in \"" + phrase + "\""; return }
    // A do-date is a day, not a moment: the time a deadline carries is the
    // hour something is owed, and a day you mean to work on it has none.
    root.editTask(t, "when", read.iso.split(" ")[0])
    root.used("when")
  }

  // The one edit path. Today's note is live in the editor; any other day is
  // rewritten on disk, one line at a time, found by its words because the
  // note may have moved on since the list was read.
  function editTask(t, how, arg) {
    if (t.date === svc.noteDate) {
      // By its tag when it has one: it survives any change of words or
      // state (a cancelled `[-]` line still holds it).
      var tagged = t.anchor > 0 ? Bound.anchors(editor.text)[t.anchor] : null
      var r = t.anchor > 0 ? (tagged ? editor.rows[tagged.line] : null) : root.rowByWords(t.text, t.line)
      if (!r) return
      root.writeLine(r, root.applyEdit(r.raw, how, arg))
      Qt.callLater(root.refreshTasks)
      if (t.anchor > 0) root.scheduleCheck()
      return
    }
    editFile.add(t, how, arg)
  }

  // The facts the page may change on a line, and nothing else on it
  // (principle 2: never the words).
  function applyEdit(line, how, arg) {
    if (how === "drop") return Task.setField(Task.setState(line, "-"), "❌", Qt.formatDate(new Date(), "yyyy-MM-dd"))
    if (how === "undrop") return Task.setField(Task.setState(line, " "), "❌", "")
    if (how === "prio") return Task.setPriority(line, arg)
    if (how === "when") return Task.setField(line, "⏳", arg)
    if (how === "state") return Task.setState(line, arg)
    if (how === "done") return Task.setField(Task.setState(line, "x"), "✅", Qt.formatDate(new Date(), "yyyy-MM-dd"))
    if (how === "undone") return Task.setField(Task.setState(line, " "), "✅", "")
    if (how === "rename") return Task.setWords(line, arg)
    return line
  }

  // Every key the dashboard takes, in one function so it can be driven
  // without a keyboard (tests/page/run.py).
  function dashKey(e) {
    var k = e.key
    if (root.dashWhenFor) {
      if (k === Qt.Key_Escape) { root.dashWhenFor = null; root.dashWhenText = ""; return true }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { root.commitDashWhen(); return true }
      return false
    }
    if (Sc.hit(e, "dashBack") || Sc.hit(e, "dashboard")) { root.toggleDash(); return true }
    if (Sc.hit(e, "today")) { root.goToday(); return true }
    if (Sc.hit(e, "dayPrev")) { root.stepDay(-1); return true }
    if (Sc.hit(e, "dayNext")) { root.stepDay(1); return true }
    if (Sc.hit(e, "dashUp")) { root.moveTaskFocus(-1); return true }
    if (Sc.hit(e, "dashDown")) { root.moveTaskFocus(1); return true }
    if (Sc.hit(e, "dashFirst")) { root.taskFocus = 0; root.moveTaskFocus(0); return true }
    if (Sc.hit(e, "dashLast")) { root.taskFocus = root.taskRows.length; root.moveTaskFocus(-1); return true }
    // Enter goes to it, everywhere in the page; Ctrl+Enter is the act that
    // settles it. Decided 2026-10-15, and it ends Enter meaning "done" in
    // the deadline popup and "go to it" here.
    if (Sc.hit(e, "dashDone")) { root.tickFocused(); return true }
    if (Sc.hit(e, "dashOpen")) { root.activateTask(); return true }
    if (Sc.hit(e, "dashDrop")) { root.dropFocused(); return true }
    if (Sc.hit(e, "dashUndo")) { root.untickLast(); return true }
    if (Sc.hit(e, "dashPriority")) { root.cyclePriorityFocused(); return true }
    if (Sc.hit(e, "dashWhen")) { root.startDashWhen(); return true }
    if (Sc.hit(e, "dashRename")) { root.startDashRename(); return true }
    if (Sc.hit(e, "dashShelve")) { root.shelveFocused(); return true }
    if (Sc.hit(e, "dashKeep")) { root.keepFocused(); return true }
    if (Sc.hit(e, "dashGrade")) { root.startDashGrade(); return true }
    if (Sc.hit(e, "dashPlan")) { root.runPlan(true); return true }
    return false
  }

  function tickFocused() {
    var row = root.taskRows[root.taskFocus]
    if (row && (row.kind === "proposal" || row.kind === "question")) { root.acceptPlanned(row); return }
    if (row && row.kind === "task") root.tickTask(row.task)
    if (row && row.kind === "deadline") {
      var d = row.deadline
      if (d.status === "open") {
        // The store written once the tick has been seen: its change would
        // rebuild the list mid-tick.
        root.markTicked(root.rowKey(row))
        root.afterTick = root.afterTick.concat([function () { root.tickDeadline(d) }])
        tickSettle.restart()
      } else {
        root.tickDeadline(d)
      }
    }
  }

  // Done, or open again: from the dashboard and the sidebar's list alike,
  // the line that stands for it ticked to match.
  function tickDeadline(d) {
    if (d.status === "open") {
      dl.markDone(d.id)
      root.tickHistory = root.tickHistory.concat([{ deadline: d.id }])
      root.tickBoundLine(d.id, true)
    } else {
      dl.reopen(d.id)
      root.tickBoundLine(d.id, false)
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

  // With the day it was done, or without it, as every tick in the page.
  function tickBoundLine(id, done) {
    var r = root.rowByDeadline(id)
    if (r) root.writeLine(r, done ? Task.setField(Task.setState(r.raw, "x"), "✅", Qt.formatDate(new Date(), "yyyy-MM-dd"))
                                  : Task.setField(Task.setState(r.raw, " "), "✅", ""))
  }

  // A deadline no line stands for gets one, at the end of today's note.
  property var pendingWrite: null
  function writeIntoToday(d) {
    root.pendingWrite = d
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
    editor.snapshot(true)
    root.quiet = true
    editor.insert(t.length, (t === "" || t.charAt(t.length - 1) === "\n" ? "" : "\n") + line)
    root.quiet = false
    root.bound = Bound.anchors(editor.text)
    Qt.callLater(root.flush)
    dl.set(d.id, ["--link", Bound.link(svc.noteDate, d.id)])
    root.pendingGoto = d.id
    root.landOnGoto()
  }

  // Enter: to the task's own line, on any day — its note opens and the
  // cursor lands at the end of its words. (Until 2026-10-17 another day only
  // unfolded a preview, so a task written on an earlier day could not be
  // reached; see docs/tasks.md.)
  function goToTask(t) {
    root.pendingTask = { text: t.text, line: t.line }
    root.backToNote()
    if (t.date === svc.noteDate && svc.ready) root.landOnTask()
    else root.openNote(t.date)
    editor.focusNote()
  }

  function landOnTask() {
    var p = root.pendingTask
    if (!p || !svc.ready) return
    root.pendingTask = null
    var r = root.rowByWords(p.text, p.line)
    if (r) editor.setCursor(r.start + r.raw.length, true)
  }

  // The one way a line is found again, here and in every other note: by its
  // words, whatever facts it now carries (Task.sameWords) — where it was,
  // else wherever it is now.
  function rowByWords(text, hint) {
    var rows = editor.rows
    if (hint >= 0 && hint < rows.length && Task.sameWords(rows[hint].raw, text)) return rows[hint]
    for (var i = 0; i < rows.length; i++) if (Task.sameWords(rows[i].raw, text)) return rows[i]
    return null
  }

  function untickLast() {
    if (root.tickHistory.length === 0) return
    var t = root.tickHistory[root.tickHistory.length - 1]
    root.tickHistory = root.tickHistory.slice(0, -1)
    if (t.deadline) { dl.reopen(t.deadline); root.tickBoundLine(t.deadline, false); return }
    if (t.drop) { root.editTask(t.drop, "undrop", ""); return }
    if (t.uncancel) { dl.reopen(t.uncancel); return }
    root.editTask(t, "undone", "")
  }

  // Tick in the original note, through the one edit path, with the day it
  // was done (`✅`, as Obsidian Tasks writes it; the note draws it quietly),
  // which is how a box done today stays in the dashboard until tomorrow.
  // Ticked again: open again, the day taken off.
  function tickTask(t) {
    if (t.done) { root.editTask(t, "undone", ""); return }
    root.markTicked(root.rowKey({ kind: "task", task: t }))
    root.tickHistory = root.tickHistory.concat([t])
    root.editTask(t, "done", "")
    root.used("tick")
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

  // Replace a whole line as the page, not the student, because they asked
  // (a binding, a tick or a date from the dashboard): an undo step of its
  // own, so Ctrl+Z takes it back alone, never together with the edit
  // before or after it — an undo that silently unbinds a line cancels its
  // deadline (docs/tasks.md).
  function writeLine(r, raw) {
    if (!r || raw === r.raw) return
    editor.snapshot(true)
    root.putLine(r, raw)
  }

  // A line caught up with the store, or tidied, which nobody asked for:
  // the undo states that hold it as it was get it too, so no Ctrl+Z takes
  // it back.
  function catchUp(r, raw) {
    if (!r || raw === r.raw) return
    editor.rebase(r.raw, raw)
    root.putLine(r, raw)
  }

  function putLine(r, raw) {
    root.quiet = true
    editor.replace(r.start, r.start + r.raw.length, raw)
    root.quiet = false
    root.bound = Bound.anchors(editor.text)
    root.tickedCount = root.countTicked(editor.text)
    Qt.callLater(root.flush)
  }

  // Give a line its deadline: the words it keeps (`head`), then the tail.
  // The store learns where the line is. Like every binding, an undo step
  // of its own (writeLine). `auto`: bound because it was left with a date
  // at its end, so Ctrl+Z also takes back the deadline it made, and the
  // line stays words (boundEdited); `made`: the deadline was added for it.
  function writeBinding(raw, head, ms, id, auto, made) {
    var r = root.rowByRaw(raw)
    if (!r || r.kind !== "task" || r.deadline > 0) return
    if (auto) root.autoBound = { id: id, raw: raw, made: !!made }
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

  // What changed among bound lines with the last edit. A line gone, back,
  // ticked or cancelled is the check's to carry to the store (one rule:
  // a deadline is cancelled exactly while no note holds its tag, and the
  // person is told, never asked — docs/tasks.md). The one exception is the
  // page's own binding taken back with Ctrl+Z: the words are back, the
  // deadline it made for them goes, and the line stays words.
  function boundEdited(was, now) {
    var changed = false
    for (var id in was) {
      if (!(id in now)) {
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
        changed = true
      } else if (was[id].state !== now[id].state) {
        changed = true
      }
    }
    for (var n in now) if (!(n in was)) changed = true
    if (changed) root.scheduleCheck()
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
      if (/\s$/.test(r.body)) root.catchUp(r, r.raw.substring(0, r.prefixLen) + r.body.replace(/\s+$/, "") + r.suffix)
      // Its words and its project (the line's tag, else its heading's) are
      // the line's: the check carries them to the store.
      var d = dl.byId[r.deadline]
      if (d && Bound.titleOf(r.body) !== d.title) root.scheduleCheck()
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
        editor.snapshot(true)
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
    if (title === "") { root.showHint("write what it is first, then " + root.keyName("deadline")); return }
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
    if (!root.reconcilePending || !dl.loaded || !svc.ready || root.checking || root.checkWanted) return
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
        // The store's state on the box, and the day it was closed after its
        // date, as every tick and drop writes it: `📅 … ✅ <day> ^dN`, or
        // `❌ <day>` for a cancelled one; open again, neither.
        var box = d.status === "open" ? " " : d.status === "cancelled" ? "-" : "x"
        base = Task.setState(base, box).replace(/\s*[❌✅]\s*\d{4}-\d{2}-\d{2}/g, "")
        var closed = box === " " ? "" : (box === "-" ? " ❌ " : " ✅ ")
          + Qt.formatDate(new Date(d.doneAt > 0 ? d.doneAt * 1000 : Date.now()), "yyyy-MM-dd")
        want = base + Bound.tail(d.due * 1000, 0) + closed + " ^d" + d.id
      }
      root.catchUp(r, want)
    }
    root.bound = Bound.anchors(editor.text)
    root.landOnGoto()
    root.landOnTask()
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

  // ------------------------------------------------------------ the check

  // One copy of a task (docs/tasks.md). `longhand-check` brings the store,
  // the ledger and every other note's lines in line with what the notes
  // say. It runs when a note is loaded and a moment after an edit takes a
  // tagged line away, brings one back or changes one. It reads the note in
  // the editor from disk, so it starts once the save has landed, and never
  // writes it: the page brings that one in line itself (reconcile), after.
  readonly property var editQueueState: ({ busy: editFile.busy, queue: editFile.queue.length, path: String(editFile.path) })
  property bool checkWanted: false
  property bool checking: false
  // ------------------------------------------------------------ who made it
  //
  // docs/agent.md, "Who made it": for each box and bullet, the person's,
  // the agent's, or made together — kept in the layer (authors.json), by
  // the line's words, and carried through every edit the page sees
  // (Authorship.js). A deadline's line needs no record: the ledger already
  // knows which deadlines the agent proposed, and whether its words were
  // rewritten since (`origins`).
  property var authorsStore: ({})   // stem -> [{ id, author }], as authors.json keeps it
  property var authorLines: []      // the open note's lines, as authorship last saw them
  property var authorMap: ({})      // the open note: line index -> "agent" | "together"

  // What the note draws: the records, and the agent's deadlines by the
  // ledger.
  readonly property var shownAuthors: {
    var out = {}
    for (var k in root.authorMap) out[k] = root.authorMap[k]
    var rows = editor.rows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].deadline > 0) {
        var a = root.anchoredAuthor(rows[i].deadline, Task.parse(rows[i].raw))
        if (a) out[i] = a
      }
    }
    return out
  }

  // A deadline's line, by the ledger: the agent's while its words are the
  // agent's first ones, made together once the person rewrote them.
  function anchoredAuthor(id, task) {
    var o = root.origins[String(id)]
    if (!o || o.origin !== "agent") return ""
    if (o.rewritten) return "together"
    return task && o.firstTitle && task.title !== o.firstTitle ? "together" : "agent"
  }

  // The note just read: its records laid on its lines.
  function restoreAuthors(text) {
    root.authorLines = String(text).split("\n")
    root.authorMap = Authorship.restore(root.authorsStore[svc.noteDate] || [], root.authorLines)
  }

  // An edit in the page: who made each line, carried.
  function carryAuthors(text) {
    var lines = String(text).split("\n")
    root.authorMap = Authorship.carry(root.authorLines, lines, root.authorMap)
    root.authorLines = lines
    root.keepAuthors()
  }

  // The open note's records, into the store and (soon) the file.
  function keepAuthors() {
    var stem = svc.noteDate
    if (!stem) return
    var recs = Authorship.serialize(root.authorMap, root.authorLines)
    var was = root.authorsStore[stem] || []
    if (JSON.stringify(recs) === JSON.stringify(was)) return
    var st = {}
    for (var k in root.authorsStore) st[k] = root.authorsStore[k]
    if (recs.length > 0) st[stem] = recs
    else delete st[stem]
    root.authorsStore = st
    authorsSave.restart()
  }

  // Who made a line of the open note says so: the agent wrote it (slice 2
  // calls this when one of its proposals is written in), or it was made
  // together (a rewording of the person's line, accepted).
  function markAuthor(lineIndex, author) {
    var m = {}
    for (var k in root.authorMap) m[k] = root.authorMap[k]
    if (author) m[lineIndex] = author
    else delete m[lineIndex]
    root.authorMap = m
    root.keepAuthors()
  }

  // A line of another day renamed from the dashboard: the agent's becomes
  // made together.
  function authorRenamed(stem, oldRaw, newRaw) {
    if (stem === svc.noteDate) return            // the open note carries its own
    var recs = (root.authorsStore[stem] || []).slice()
    var id = Authorship.key(oldRaw)
    for (var i = 0; i < recs.length; i++) {
      if (recs[i].id !== id) continue
      recs[i] = { id: Authorship.key(newRaw), author: Authorship.edited(recs[i].author) }
      var st = {}
      for (var k in root.authorsStore) st[k] = root.authorsStore[k]
      st[stem] = recs
      root.authorsStore = st
      authorsSave.restart()
      return
    }
  }

  // A dashboard row's maker: by the ledger for a deadline, by the records
  // of its day for a box.
  function rowAuthor(row) {
    if (!row) return ""
    if (row.kind === "proposal" || row.kind === "question") return "agent"
    if (row.kind === "deadline") {
      var lt = root.lineTaskOf(row.deadline)
      return root.anchoredAuthor(row.deadline.id, lt && lt.text ? Task.parse("- [ ] " + lt.text) : { title: row.deadline.title })
    }
    if (row.kind !== "task") return ""
    var t = row.task
    if (t.anchor > 0) return root.anchoredAuthor(t.anchor, t)
    var recs = root.authorsStore[t.date] || []
    var id = Authorship.key("- [ ] " + t.text)
    for (var i = 0; i < recs.length; i++) if (recs[i].id === id) return recs[i].author
    return ""
  }

  property var origins: ({})        // id -> { origin, firstTitle, rewritten }: the agent's deadlines
  readonly property string checkPath: (svc.config && svc.config.check) || (Quickshell.env("HOME") + "/.local/bin/longhand-check")

  function scheduleCheck() { checkTimer.restart() }

  function startCheck() {
    checkTimer.stop()
    root.checkWanted = true
    root.flush()
    root.runCheck()
  }

  function runCheck() {
    if (!root.checkWanted || root.checking || !svc.ready || svc.saving || svc.pending) return
    root.checkWanted = false
    root.checking = true
    checkGuard.restart()
    checkProc.command = [root.checkPath, "--json", "--open", svc.noteDate]
    checkProc.running = true
  }

  function checkDone(text) {
    if (!root.checking) return
    root.checking = false
    checkGuard.stop()
    var out = null
    try { out = JSON.parse(text) } catch (e) { out = null }
    if (out) {
      root.origins = out.origins || ({})
      root.sayChecked(out)
    }
    // The store as the check left it, then the open note in line with it
    // (reconcile runs when the store's items arrive).
    root.reconcilePending = true
    dl.reload()
    if (root.checkWanted) root.runCheck()
  }

  // What the check did, said in the status line, waiting for nothing.
  function sayChecked(out) {
    var gone = out.cancelled || [], back = out.restored || []
    if (gone.length === 1) root.showHint("“" + gone[0].title + "” cancelled: its line is gone · " + root.keyName("undo") + " brings it back")
    else if (gone.length > 1) root.showHint(gone.length + " deadlines cancelled with their lines · " + root.keyName("undo") + " brings them back")
    else if (back.length === 1) root.showHint("“" + back[0].title + "” is back")
    else if (back.length > 1) root.showHint(back.length + " deadlines are back")
    else if ((out.hidden || []).length === 1) root.showHint("“" + out.hidden[0].title + "” stepped aside, a fortnight past its date")
    else if ((out.hidden || []).length > 1) root.showHint(out.hidden.length + " deadlines stepped aside, a fortnight past their dates")
  }

  Timer {
    id: checkTimer
    interval: 500
    onTriggered: root.startCheck()
  }

  // A check that never answers (not installed, stuck) must not hold the
  // note back from its own catch-up.
  Timer {
    id: checkGuard
    interval: 8000
    onTriggered: { if (root.checking) { console.warn("longhand.page: longhand-check did not answer"); root.checkDone("") } }
  }

  Process {
    id: checkProc
    stdout: StdioCollector { id: checkOut; onStreamFinished: root.checkDone(checkOut.text) }
    stderr: StdioCollector { id: checkErr; onStreamFinished: if (checkErr.text.trim() !== "") console.warn("longhand.page " + checkErr.text.trim()) }
  }

  // ------------------------------------------------------------ sidebar

  // The seal in the header, clicked: counted apart from the key, so the
  // stats can say whether the mark is found.
  function sealClicked() {
    root.used("seal")
    root.toggleSidebar()
  }

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
    var id = root.pendingGoto
    var r = root.rowByDeadline(id)
    root.pendingGoto = 0
    if (r) editor.setCursor(r.bodyEnd, true)
    else if (dl.byId[id]) root.showHint("“" + dl.byId[id].title + "” has no line in this note any more")
  }

  // Into the calendar, its cursor on the day in the sheet.
  function focusSidebar() {
    var p = svc.configured && svc.noteDate !== "" ? Days.parse(svc.noteDate, svc.dailyFormat()) : null
    root.calFocus = p ? p.date : new Date()
    root.dueFocus = -1
    root.projFocus = -1
    root.refreshProjects()
    sidebar.sidebarKeysRef.forceActiveFocus()
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

  // Today's note, from wherever the keys are: the dashboard and the margin
  // close, the calendar's cursor comes home too.
  function goToday() {
    root.used("today")
    root.calFocus = new Date()
    root.openNote(svc.todayStamp())
    root.backToNote()
  }

  // The day before or after the open one that has a note, as Obsidian's
  // previous/next daily note: a day without one has nothing to read. Past
  // the last note, forward goes on to today, which is always there to
  // write in.
  function stepDay(d) {
    if (!svc.configured) return
    var fmt = svc.dailyFormat()
    var cur = Days.parse(svc.noteDate, fmt)
    if (!cur) return
    var best = null
    for (var i = 0; i < root.dayStems.length; i++) {
      var p = Days.parse(root.dayStems[i], fmt)
      if (!p) continue
      var t = p.date - cur.date
      if (d < 0 ? t >= 0 : t <= 0) continue
      if (!best || Math.abs(t) < Math.abs(best.t)) best = { stem: root.dayStems[i], t: t, date: p.date }
    }
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    if (!best && d > 0 && cur.date < today) best = { stem: svc.todayStamp(), date: today }
    if (!best) { root.showHint(d < 0 ? "no note before this day" : "this is the last day"); return }
    root.calFocus = best.date
    root.openNote(best.stem)
    root.backToNote()
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
    if (root.searchOpen) root.closeSearch("back")
    root.leftLine(root.lastLine)
    root.flush()
    var p = svc.configured ? Days.parse(stamp, svc.dailyFormat()) : null
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    root.used("day", p ? Math.round((today - p.date) / 86400000) : "")
    root.marginOpen = false
    root.dashOpen = false
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
  // `how`: "select" lands on the match selected (Ctrl+Enter), "stay" with
  // the cursor at it (Esc, as browsers and editors leave you), "back" where
  // the search began (Shift+Esc). Without a match every way goes back.
  function closeSearch(how) {
    var m = root.matches[root.matchIndex]
    root.searchOpen = false
    root.matches = []
    root.matchIndex = -1
    if (how === "select" && m) editor.select(m.start, m.end)
    else if (how === "stay" && m) editor.setCursor(m.start, true)
    else editor.setCursor(root.searchFrom, true)
  }

  function sendChat() {
    var msg = margin.chatFieldRef.text.trim()
    if (msg === "" || root.currentHash === "") return
    margin.chatFieldRef.text = ""
    root.pendingChat = { hash: root.currentRec, text: msg }
    root.requestChat(root.currentRec, msg, root.currentHash)
  }

  // The runner has written the turn the page was holding: let go of it, so
  // the message is never drawn twice.
  function settleChat() {
    var p = root.pendingChat
    if (!p) return
    var rec = agent.record(p.hash)
    var turns = (rec && rec.chat) || []
    for (var i = turns.length - 1; i >= 0; i--)
      if (turns[i].role === "student" && turns[i].text === p.text) { root.pendingChat = null; return }
  }

  // ------------------------------------------------------------ services

  Service {
    id: svc
    onLoaded: { root.applyText(svc.body); root.reconcilePending = true; root.startCheck(); root.reconcile(); root.openPass() }
    onExternalChange: { root.applyText(svc.body, true); root.reconcilePending = true; root.startCheck(); root.reconcile() }
    onSavedNow: {
      root.runCheck()
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
    onItemsChanged: { root.reconcile(); root.checkAccept(); if (!tickSettle.running) { root.doneNow = ({}); root.justTicked = "" } }
    onChanged: root.scheduleCheck()
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
    onStateChanged: { root.scheduleRepaint(); root.checkAccept(); root.settleChat() }
  }

  Process {
    id: runner
    property string said: ""
    stderr: StdioCollector {
      onStreamFinished: {
        runner.said = text.trim()
        if (runner.said !== "") console.warn("longhand.page runner: " + runner.said)
      }
    }
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.log("longhand.page runner: " + text.trim())
    }
    // A run that fails says so. It used to fail in silence: opencode moved
    // its flags under the runner on 2026-10-15 and every pass of that day
    // died unseen, the page looking exactly as it does when the agent has
    // nothing to say. Silence is now only ever an answer, never a fault.
    onExited: function (code, status) {
      root.running = false
      root.runningHash = ""
      if (code !== 0) Qt.callLater(root.runnerFailed)
      agent.reload()
      root.launchQueued()
      if (!root.running) root.doneSending()
    }
  }

  Process {
    id: acceptProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page accept: " + text.trim()) }
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
        // The list now says what was drawn ahead of it.
        root.doneNow = ({})
        root.justTicked = ""
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
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page sections: " + text.trim()) }
  }

  Process {
    id: dismissProc
    onExited: function (code, status) { root.refreshTasks(); agent.reload() }
  }

  // A box kept or put aside: the clock is written, then the list read again.
  Process {
    id: boxProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page box: " + text.trim()) }
    onExited: function (code, status) { root.refreshTasks() }
  }

  // One-line rewrite of another day's note when a task is ticked from
  // the panel. Atomic, and only ever the line the student pointed at.
  // Another day's note, rewritten for the facts the dashboard changes: a
  // tick, a do-date, a priority, a drop. One line, atomic, and never a line the student did not point at.
  FileView {
    id: editFile
    // Edits waiting, in the order asked: { task, how, arg }. One file is
    // open at a time; the edits for it are applied together, and the next
    // file is opened once it is written.
    property var queue: []
    property bool busy: false   // a file open or being written
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var mine = editFile.queue.filter(function (q) { return q.task.file === editFile.path })
      if (mine.length === 0) { editFile.nextFile(); return }
      editFile.queue = editFile.queue.filter(function (q) { return q.task.file !== editFile.path })
      var lines = text().split("\n")
      var changed = false
      for (var k = 0; k < mine.length; k++) {
        var tk = mine[k].task
        var tagged = tk.anchor > 0 ? Bound.anchors(lines.join("\n"))[tk.anchor] : null
        var at = tk.anchor > 0 ? (tagged ? tagged.line : -1) : Task.findWords(lines, tk.line, tk.text)
        if (at < 0) continue
        var next = root.applyEdit(lines[at], mine[k].how, mine[k].arg)
        if (next !== lines[at]) { lines[at] = next; changed = true }
      }
      if (changed) setText(lines.join("\n"))
      // (setText writes at once; waiting for a saved signal left the queue
      // stuck after the first file.)
      Qt.callLater(editFile.nextFile)
    }
    onLoadFailed: { editFile.queue = editFile.queue.filter(function (q) { return q.task.file !== editFile.path }); editFile.nextFile() }

    function add(task, how, arg) {
      editFile.queue = editFile.queue.concat([{ task: task, how: how, arg: arg }])
      if (!editFile.busy) editFile.open(task.file)
    }
    function nextFile() {
      editFile.busy = false
      Qt.callLater(root.refreshTasks)
      root.scheduleCheck()
      if (editFile.queue.length > 0) editFile.open(editFile.queue[0].task.file)
    }
    function open(file) {
      editFile.busy = true
      if (editFile.path === file) editFile.reload()
      else editFile.path = file
    }
  }


  // The student's word on a reply: helpful or not (the improvement loop,
  // docs/agent.md). The same word again takes it back. Shown at once, kept
  // by the runner with the prompt and model that made the reply.
  property var ratingNow: ({})   // block hash -> "up" | "down" | "none", until the state says so
  function rateReply(value) {
    var rec = root.currentRecord
    if (!rec || !rec.reply || root.currentRec === "") return
    var was = root.ratingNow[root.currentRec] || (rec.rating ? rec.rating.value : "")
    var v = was === value ? "none" : value
    var m = {}
    for (var k in root.ratingNow) m[k] = root.ratingNow[k]
    m[root.currentRec] = v
    root.ratingNow = m
    rateProc.command = [svc.runner, "rate", v, "--hash", root.currentRec, "--date", svc.noteDate]
    rateProc.running = true
    root.used("rate", v)
  }
  function ratingOf(hash) {
    if (root.ratingNow[hash] !== undefined) return root.ratingNow[hash] === "none" ? "" : root.ratingNow[hash]
    var rec = agent.record(hash)
    return rec && rec.rating ? rec.rating.value : ""
  }
  Process { id: rateProc; onExited: function (code, status) { agent.reload() } }

  // Looking at a reply for a moment marks it read — nothing else needs to.
  Process { id: ackProc }
  Timer {
    id: ackTimer
    interval: 1200
    onTriggered: {
      var rec = root.currentRecord
      if (rec && rec.state === "reply" && !rec.read && root.currentRec !== "") {
        ackProc.command = [svc.runner, "ack", "--hash", root.currentRec, "--date", svc.noteDate]
        ackProc.running = true
      }
    }
  }
  // One handler for the cursor's block changing: what the header may offer
  // to send, and the timer that marks a reply read once it has been looked at.
  onCurrentHashChanged: {
    root.refreshRec()
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

  // keys.json: the keys the student moved (Shortcuts.js). A choice, so
  // beside config.json rather than with the machine's state; written by the
  // keys sheet, and read again when edited by hand.
  FileView {
    id: keysFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/longhand/keys.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { Sc.load(JSON.parse(text())) } catch (e) { console.warn("longhand.page keys.json: " + e) }
      root.keysVersion++
    }
    onFileChanged: reload()
  }

  // settings.json: what the Settings sheet set. The page's own file, as
  // keys.json is; the runner reads only the keys it allows from it.
  FileView {
    id: settingsFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/longhand/settings.json"
    blockLoading: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.settingsData = root.readSettings()
    atomicWrites: true
    printErrors: false
    onSaved: {
      var then = root.settingsPending
      root.settingsPending = null
      if (then) root.runTimetable(then)
    }
    onSaveFailed: function (err) { root.settingsNote = "could not write settings.json: " + FileViewError.toString(err) }
  }

  Process { id: tickSoundProc }

  // The weekly review of the agent (docs/agent.md, the improvement loop):
  // written when the page opens and a week has passed, said once.
  Process {
    id: reviewProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var r = JSON.parse(text)
          if (r.written) root.showHint("this week's review of the agent is ready — Settings → The agent")
        } catch (e) {}
      }
    }
  }

  Process {
    id: notebookProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.notebookData = JSON.parse(text) } catch (e) { root.notebookNote = "the runner did not answer" }
        var rows = root.notebookList
        if (root.notebookFocus >= rows.length || (rows[root.notebookFocus] && rows[root.notebookFocus].kind === "head"))
          root.notebookFocus = root.nextNotebookRow(Math.min(root.notebookFocus, rows.length), -1)
        if (root.notebookFocus < 0 || !rows[root.notebookFocus] || rows[root.notebookFocus].kind === "head")
          root.notebookFocus = root.nextNotebookRow(-1, 1)
      }
    }
  }
  Process {
    id: notebookActProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "") root.notebookNote = root.notebookPendingNote
        root.loadNotebook()
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.notebookNote = text.trim().replace(/^longhand-agent: /, "") }
  }

  // What Settings says about the agent: which prompts and models have
  // passed their evals, and the latest review.
  property var agentChecks: null
  Process {
    id: agentChecksProc
    stdout: StdioCollector { onStreamFinished: { try { root.agentChecks = JSON.parse(text) } catch (e) { root.agentChecks = null } } }
  }
  function sayEvalState(job) {
    var c = root.agentChecks
    if (!c) return ""
    var row = c.rows.filter(function (r) { return r.job === job && r.prompts === "installed" })[0]
    if (!row) return ""
    return (job === "margin" ? "Replies" : "Planning") + " · " + row.model + " · "
      + (row.checked === "passed" ? "passed its evals" : row.checked === "failed" ? "failed its last evals" : "never checked")
  }

  Process {
    id: planProc
    stdout: StdioCollector {
      onStreamFinished: {
        var r = null
        try { r = JSON.parse(text) } catch (e) {}
        root.planError = r && r.error ? root.sayPlanError(r.error) : (r && r.ran === false ? root.planError : "")
        if (root.planError !== "" && r && r.error) root.showHint("the agent could not plan: " + root.planError)
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page plan: " + text.trim()) }
    onExited: function (code, status) {
      root.planning = false
      root.refreshProposals()
      if (root.planAgain) { root.planAgain = false; root.runPlan(true) }
    }
  }

  Process {
    id: proposalsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var p = JSON.parse(text)
          root.proposals = p.open || []
          var d = {}
          for (var i = 0; i < (p.accepted || []).length; i++) d[p.accepted[i].key] = p.accepted[i].date
          root.agentDates = d
        } catch (e) {}
      }
    }
  }

  Process {
    id: proposalProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page proposal: " + text.trim()) }
    onExited: function (code, status) { root.nextProposal() }
  }

  // authors.json: who made each box and bullet, by day (docs/agent.md). The
  // layer's, beside the deadline store — never in the notes.
  FileView {
    id: authorsFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/authors.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { root.authorsStore = JSON.parse(text()) || {} } catch (e) { root.authorsStore = {} }
      if (svc.ready) root.restoreAuthors(editor.text)
    }
  }
  Timer {
    id: authorsSave
    interval: 800
    onTriggered: authorsFile.setText(JSON.stringify(root.authorsStore, null, 1) + "\n")
  }

  Process {
    id: settingsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.settingsState = JSON.parse(text) } catch (e) { root.settingsNote = "the runner did not answer" }
        root.settingsBusy = false
        root.settingsBusyIndex = -1
        root.refreshProjects()
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page timetable: " + text.trim()) }
  }

  Process {
    id: hyprProc
    property string kind: ""          // state, adopt or set
    stdout: StdioCollector {
      onStreamFinished: {
        var st = null
        try { st = JSON.parse(text) } catch (e) { console.warn("longhand.page hyprkeys: " + text.trim()) }
        root.hyprDone(st)
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page hyprkeys: " + text.trim()) }
  }
  Process { id: submapProc }
  Process { id: raiseProc }
  // The sheet stops waiting a little before Hyprland would leave the submap.
  Timer {
    id: hyprListenTimer
    interval: 25000
    onTriggered: if (root.keysListen && root.keysListen.hypr) { root.stopListening(); root.keysNote = "stopped waiting for a key — Enter to try again" }
  }

  // The zoom step survives restarts. Machine state, not config, and never
  // in the vault.
  FileView {
    id: zoomFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/page.json"
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
    interval: 6000
    onTriggered: { root.noSignHint = false; root.hint = "" }
  }

  // ------------------------------------------------------------ window

  PanelWindow {
    id: panel
    visible: root.overlayOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "longhand-page"
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
      text: "on the overlay · " + root.keyName("close") + " brings it back"
      color: root.faint
      font.family: root.fontFamily
      font.styleName: root.fontStyle
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

    // The dashboard. It takes the sheet's place rather than sitting beside
    // it: a list is not prose and does not want the 72-character measure, so
    // it gets the width the window has. (Dashboard.qml)
    Dashboard { id: dash; page: root }

    // Settings (Ctrl+, or "settings" at the sidebar's foot): drawn like the keys
    // sheet, in the same column: calendars, the agent, sound. (SettingsSheet.qml)
    SettingsSheet { id: settingsSheet; page: root }

    // What the agent knows: Settings' second view, in its place. (NotebookSheet.qml)
    NotebookSheet { id: notebookSheet; page: root }

    // The keys sheet (Ctrl+/, or "keys" at the sidebar's foot): every key the page
    // answers to, under where it works, each one movable. A list, so it
    // takes the dashboard's shape rather than the note's measure. (KeysSheet.qml)
    KeysSheet { id: keysSheet; page: root }

    BorderSurface {
      id: sheet
      visible: !root.dashOpen && !root.keysOpen && !root.settingsOpen
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

          // The seal: Longhand's own mark, and the door to the sidebar — the
          // calendar, the projects, the keys and the settings (2026-10-17).
          // It hangs in the margin so the date stays in line with the
          // writing; quiet until pointed at, lit while the sidebar is open.
          // It identifies Longhand and opens the sidebar, nothing else: never
          // a sign that the agent answered or that something is due
          // (docs/brand/README.md).
          LogoMark {
            id: seal
            anchors.right: dateText.left
            anchors.rightMargin: root.sp(12)
            anchors.verticalCenter: dateText.verticalCenter
            width: Math.round(dateText.implicitHeight * 1.05)
            height: width
            color: sealArea.containsMouse ? root.accent : root.sidebarOpen ? root.foreground : root.faint
            Behavior on color { ColorAnimation { duration: 240 } }
            MouseArea {
              id: sealArea
              anchors.fill: parent
              anchors.margins: -root.sp(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.sealClicked()
              PanelToolTip {
                visible: parent.containsMouse
                text: root.tip(root.sidebarOpen ? "Close the sidebar" : "The sidebar: calendar, projects, keys and settings", "sidebar")
              }
            }
          }

          Text {
            id: dateText
            // The status line takes the date's place while it speaks.
            opacity: root.status === "" ? 1 : 0
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: root.dateLabel
            color: svc.isToday ? root.dim : root.foreground
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          // On another day: the way back to today.
          Text {
            id: backToday
            visible: !svc.isToday && svc.noteDate !== "" && root.status === ""
            anchors.left: dateText.right
            anchors.leftMargin: root.sp(12)
            anchors.verticalCenter: dateText.verticalCenter
            textFormat: Text.PlainText
            text: root.agentDay ? "back to today" : "back to today · agent off for this note"
            color: root.faint
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: root.goToday()
              PanelToolTip {
                visible: parent.containsMouse
                text: root.tips([["Today's note", "today"], ["The day before, with a note", "dayPrev"], ["The day after", "dayNext"]])
              }
            }
          }

          // The status line: what the page says in passing, in the date's
          // place for the moment it speaks, in the accent so it is seen,
          // and cut short rather than wrapped (the whole of it on hover).
          Text {
            id: statusText
            visible: root.status !== ""
            anchors.left: parent.left
            anchors.right: headerRight.left
            anchors.rightMargin: root.sp(16)
            anchors.verticalCenter: dateText.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.status
            color: root.accent
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              PanelToolTip { visible: parent.containsMouse && statusText.truncated; text: root.status }
            }
          }

          Row {
            id: headerRight
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
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }

            // The pin: which shape you are in. Ctrl+P or a click flips it.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "pin"
              color: root.alongside ? root.foreground : root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePin()
                PanelToolTip { visible: parent.containsMouse; text: root.tip(root.alongside ? "Back to the overlay" : "Pin it as a window beside your work", "pin") }
              }
            }

            // Private: the one place that says whether the agent can see
            // this note, and the one control that changes it. Always in
            // sight, because a guarantee you cannot see is not one
            // (2026-10-15). When it is on, "ask" and the agent mark are not
            // dimmed but gone — there is nothing to offer.
            Text {
              visible: root.agentDay
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: svc.notePrivate ? "private · the agent sees nothing here" : "private"
              color: svc.notePrivate ? root.foreground : (privateArea.containsMouse ? root.accent : root.faint)
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                id: privateArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.togglePrivate(); editor.focusNote() }
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.tip(svc.notePrivate ? "Let the agent see this note again" : "Make this note private: the agent sees nothing", "private")
                }
              }
            }

            // Ask: the agent's visible way in, and the reason the "send to
            // agent?" prompt could go (2026-10-15). It sends the block the
            // cursor is in — the same path as Ctrl+Enter — and sits in the
            // header, outside the canvas, so nothing marks the student's
            // own words. Dim when this block carries a sign for the agent,
            // faint when it does not; a click then says why in one line.
            Text {
              visible: svc.header !== "" && root.agentOn
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              // Once the block has an answer the word is not "ask" any
              // more: the key opens the conversation on it instead of
              // paying to be told the same thing twice.
              text: root.answered(root.currentRecord) ? "reply" : "ask"
              color: askArea.containsMouse ? root.accent
                : (root.currentTrigger !== "" || root.answered(root.currentRecord) ? root.dim : root.faint)
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                id: askArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.sendCurrent(); editor.focusNote() }
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.tip(root.answered(root.currentRecord) ? "Open the conversation on this block" : "Ask the agent about this block", "ask")
                }
              }
            }

            // The agent mark: faint at rest, brighter from the moment
            // something is asked until it comes back, accent while a reply
            // in this note is still unread.
            Text {
              visible: svc.header !== "" && root.agentOn
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "agent"
              color: root.replyWaiting ? root.accent : (root.working ? root.foreground : root.faint)
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.tips([[root.replyWaiting ? "A reply is waiting in this note" : root.working ? "The agent is thinking" : "The agent reads what you ask it", ""],
                                   ["The margin for this block", "margin"]])
                }
              }
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
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.body)
            foreground: root.foreground
            onTextChanged: if (root.searchOpen) root.runSearch()
            Keys.onPressed: function (event) {
              if (root.anywhereKey(event)) { event.accepted = true; return }
              if (Sc.hit(event, "findGo")) root.closeSearch("select")
              else if (Sc.hit(event, "findNext")) root.stepMatch(1)
              else if (Sc.hit(event, "findPrev")) root.stepMatch(-1)
              else if (Sc.hit(event, "findClose")) root.closeSearch("stay")
              else if (Sc.hit(event, "findBack")) root.closeSearch("back")
              else if (Sc.hit(event, "find")) searchField.selectAll()
              else return
              event.accepted = true
            }
          }

          Text {
            id: searchCount
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: searchField.text === "" ? root.keyName("findNext") + " next · " + root.keyName("findPrev") + " back · " + root.keyName("findGo") + " go"
              : (root.matches.length === 0 ? "no match" : (root.matchIndex + 1) + " / " + root.matches.length)
            color: root.dim
            font.family: root.fontFamily
            font.styleName: root.fontStyle
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
          font.styleName: root.fontStyle
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

          // Gutter marks: a block in flight, a light travelling down it
          // for as long as the agent has it; a block with a reply, accent
          // until it has been read and dim after. Nothing else is marked —
          // a block that could be sent is every block, and saying so was
          // noise (2026-10-15).
          Repeater {
            model: root.paint
            Item {
              required property var modelData
              visible: modelData.reply || modelData.sending
              x: root.sp(2)
              y: modelData.y
              width: root.sp(3)
              height: modelData.h
              clip: true

              Rectangle {
                anchors.fill: parent
                radius: width
                color: parent.modelData.sending ? root.dim
                  : parent.modelData.unread ? root.accent : root.dim
                opacity: parent.modelData.sending ? 0.3 : 1
                Behavior on color { ColorAnimation { duration: 240 } }
                Behavior on opacity { NumberAnimation { duration: 240 } }
              }

              // The light. It only runs while the block is away, so a mark
              // that moves means "still thinking" and a mark that rests
              // means "answered" — the two are never the same thing.
              Rectangle {
                id: spark
                width: parent.width
                height: Math.max(root.sp(20), parent.height * 0.5)
                radius: width
                visible: parent.modelData.sending
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
                  GradientStop { position: 0.5; color: root.accent }
                  GradientStop { position: 1.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
                }
                SequentialAnimation on y {
                  running: spark.visible
                  loops: Animation.Infinite
                  NumberAnimation { from: -spark.height; to: spark.parent.height
                                    duration: 1500; easing.type: Easing.InOutSine }
                }
              }
            }
          }

          NoteEditor {
            id: editor
            // What the page shows under a line opens room there, so the
            // lines below move down rather than being drawn over.
            roomRow: whenBox.visible || mentionBox.visible ? root.lineIndexAt(editor.cursorPosition) : -1
            roomHeight: (whenBox.visible ? whenBox.height : mentionBox.visible ? mentionBox.height : 0) + root.sp(12)
            boxTip: Component { Item { PanelToolTip { visible: true; text: root.tip("Tick or untick it", "checkbox") } } }
            onBoxTicked: function (lineIndex, done) { if (done) root.tickSound() }
            authors: root.shownAuthors
            x: root.gutter
            width: flick.width - root.gutter
            height: implicitHeight
            enabled: svc.ready
            fontFamily: root.fontFamily
            fontStyle: root.fontStyle
            codeFamily: root.codeFamily
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
            onCursorPositionChanged: {
              root.currentHash = root.hashNearLine(root.lineIndexAt(cursorPosition))
              Qt.callLater(root.trackLine)
              Qt.callLater(root.updateMention)
            }
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
              if (root.applying) { root.restoreAuthors(text); return }
              root.carryAuthors(text)
              svc.markPending(text)
              saveTimer.restart()
              if (root.quiet) return
              root.boundEdited(was, root.bound)
              root.tickedCount = root.countTicked(text)
              root.scheduleRepaint()
              Qt.callLater(root.updateMention)
            }
          }

          // Below the last line: a click goes to the end of the note.
          MouseArea {
            y: editor.height
            width: flick.width
            height: Math.max(0, flick.contentHeight - editor.height)
            onClicked: editor.setCursor(editor.length, true)
          }

          // `@`: the projects, under the line, narrowing as you type. In
          // the room the line opens for it, so it covers nothing.
          Rectangle {
            id: mentionBox
            visible: !!root.mention && root.mention.items.length > 0
            x: root.gutter
            y: editor.roomRow >= 0 ? editor.roomTop + root.sp(4) : editor.cursorRect.y + editor.cursorRect.height + root.sp(4)
            width: Math.min(editor.width, root.sp(260))
            height: mentionCol.implicitHeight + root.sp(10)
            radius: Style.cornerRadius
            color: root.background
            border.width: 1
            border.color: root.faint
            z: 4
            Column {
              id: mentionCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: root.sp(6)
              anchors.rightMargin: root.sp(6)
              Repeater {
                model: root.mention ? root.mention.items : []
                Rectangle {
                  required property var modelData
                  required property int index
                  width: mentionCol.width
                  height: mentionRow.implicitHeight + root.sp(4)
                  radius: Style.cornerRadius
                  color: root.mentionFocus === index ? Style.selectedFill : "transparent"
                  Text {
                    id: mentionRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: root.sp(4)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: "#" + modelData.tag + "  " + modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.styleName: root.fontStyle
                    font.pixelSize: root.fs(Style.font.bodySmall)
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: { root.mentionFocus = index; root.acceptMention(false) }
                    PanelToolTip { visible: parent.containsMouse; text: root.tips([["Write its #tag", "mentionPick"], ["Start the class", "mentionClass"]]) }
                  }
                }
              }
              Text {
                width: parent.width
                topPadding: root.sp(4)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.mention && root.mention.atLineStart
                  ? root.keyName("mentionPick") + " its tag · " + root.keyName("mentionClass") + " starts the class · " + root.keyName("mentionClose") + " leaves it"
                  : root.keyName("mentionPick") + " its tag · " + root.keyName("mentionClose") + " leaves it"
                color: root.faint
                font.family: root.fontFamily
                font.styleName: root.fontStyle
                font.pixelSize: root.fs(Style.font.caption)
              }
            }
          }

          // Ctrl+D's question: when? Under the line, in the page's own words,
          // in the room the line opens for it.
          Row {
            id: whenBox
            visible: !!root.whenFor
            x: root.gutter
            y: editor.roomRow >= 0 ? editor.roomTop + root.sp(4) : editor.cursorRect.y + editor.cursorRect.height + root.sp(4)
            spacing: root.sp(8)
            z: 3
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "when?"
              color: root.dim
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            TextField {
              id: whenField
              width: root.sp(220)
              placeholderText: root.whenFor && root.whenFor.id > 0 ? "empty: no deadline" : "fri 17:00 · in 3 days · 20 oct"
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.body)
              foreground: root.foreground
              Keys.onPressed: function (event) {
                if (root.anywhereKey(event)) { event.accepted = true; return }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitWhen(); event.accepted = true }
                else if (event.key === Qt.Key_Escape) { root.closeWhen(); event.accepted = true }
              }
            }
          }

        }
      }
    }

    // The sidebar, only while asked for: the calendar, the day's deadlines,
    // the projects, keys and settings at its foot. (Sidebar.qml)
    Sidebar { id: sidebar; page: root }

    // The margin: the agent's side of the page, a narrower sheet beside the
    // note. Shows whatever it has to say about the block under the cursor,
    // and the field to talk back. (Margin.qml)
    Margin { id: margin; page: root }
  }
}
