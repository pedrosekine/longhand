import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QC
import QtQuick.Shapes
import Qt.labs.folderlistmodel
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import qs.Ui
import "Blocks.js" as Blocks
import "Bound.js" as Bound
import "Queue.js" as Queue
import "Next.js" as Next
import "Dates.js" as Dates
import "Days.js" as Days
import "Task.js" as Task
import "Authorship.js" as Authorship
import "Threads.js" as Threads
import "Tags.js" as Tags
import "Switch.js" as Switch
import "Where.js" as Where
import "Shortcuts.js" as Sc
import "Say.js" as Say
import "Focus.js" as Focus
import "Layout.js" as Layout
import "Links.js" as Links
import "ProjectView.js" as PV

// The page: today's note as a blank sheet in the shell, with the agent in
// the margin. Two shapes of the same sheet, not two equals: the overlay
// is quick capture (a layer over everything, Esc leaves), the window is
// where the work stays (a normal window you tile or Snap next to slides or
// a PDF; Esc does nothing there). F11 or the overlay's "window" keeps the
// sheet as a window; in the window F11 fills the screen and back, as it
// does in every other program (2026-11-27, the shape pass).
//
// Where the keys are, and how they move between the sidebar, the middle and
// the agent's pane, is docs/navigation.md (and "panes", below).
//
// The two live side by side. With the window open somewhere else (another
// workspace, another monitor), SUPER+ALT+= still brings the overlay up
// where you are; the sheet moves into it (one sheet, one editor, nothing
// to keep in sync) and the window says where it went. Esc or the same key
// again puts it back in the window. With the window in front, holding the
// keys, the overlay does not come over it: the window stays. The shell's
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
// item leaves the list, Tab nests. Ctrl+Up/Down walk the blocks — the
// same block splitting the agent uses, so the navigation unit and the reply
// unit are one thing; Alt+Up/Down move a line.
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
// screen until asked: Ctrl+Enter on an answered block opens its margin —
// the reply, its proposals (Enter accepts one; local code runs the CLI, the
// model never does), and the chat about that block; Esc closes it again,
// the cursor back where it was. Ctrl+2 opens the dashboard: every open checkbox
// across the daily notes, carried while it is alive (a box goes quiet after
// 7 days of silence, a task after 30 — agent/lifespan.py — and waits under
// "set aside"; it is never rewritten, the page being the one program that
// edits notes) and, below, what the agent has raised — suggestions with
// their evidence, observations from open passes — where Enter waves one off
// and the runner remembers that.
//
// Ctrl+F finds in today's note, as you type, in the words you see (not
// the markdown under them). Enter goes to the next match, Shift+Enter to
// the previous, both wrapping; Ctrl+Enter puts the cursor on the match with
// it selected and closes the search; Esc closes it on the match, Shift+Esc
// back where the cursor was.
//
// Ctrl+[ opens the sidebar: a month calendar of the daily notes. It is
// never there unless asked — the page still opens blank on today. A day's
// number is full where a note exists and faded where none does; a dot marks
// today, an outline the day in the sheet. Arrows move a day (left/right) or
// a week (up/down), Ctrl+Left/Right or PageUp/PageDown a month, Home goes
// to today; Enter (or a click) opens the day in the same sheet, editable
// like today. A day without a note opens empty and gets its file only when
// something is written. Alt+Left goes back into the sidebar, Alt+Right to
// the note with the sidebar left open, Esc or Ctrl+[ closes it. A note whose file name is not in
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
  // On Windows the host stands in for the shell (windows/): what the page
  // says of the system, it says in Windows' words there.
  readonly property bool onWindows: Sc.onWindows
  readonly property string themeName: onWindows ? "Windows colours" : "Omarchy theme"
  property var shell: null
  property var manifest: null

  property string windowTitle: "Page — today's note"

  // Handles for a test harness driving the page over IPC.
  readonly property alias editorItem: editor

  // The vault's notes and pictures, as paths (Links.js): read when a note
  // first needs them — a picture or a link in it — and read again on a
  // fresh open. One `find`, a few thousand short strings; dropped on close.
  property var vaultIndex: null
  property int vaultIndexVersion: 0
  property double vaultIndexAt: 0     // when it was read (ms): the switcher reads it again when it is old
  readonly property bool vaultIndexReading: indexProc.running
  property var missedNames: ({})      // names not found, each read again once
  Timer { id: reindexTimer; interval: 1200; onTriggered: { root.vaultIndex = null; root.needIndex() } }
  readonly property string pageFsPy: Links.fromFileUrl(Qt.resolvedUrl("page_fs.py").toString())
  function needIndex() {
    if (root.vaultIndex !== null || indexProc.running || !svc.configured) return
    indexProc.command = ["python3", root.pageFsPy, "index", svc.config.vault]
    indexProc.running = true
  }
  // The names again when those read are older than a few seconds: a note
  // made or filed since the page opened is found by Ctrl+O. The old ones
  // stand until the new are read, so nothing empties under the keys.
  function freshIndex() {
    if (root.vaultIndex === null) { root.needIndex(); return }
    if (indexProc.running || !svc.configured || Date.now() - root.vaultIndexAt < 5000) return
    indexProc.command = ["python3", root.pageFsPy, "index", svc.config.vault]
    indexProc.running = true
  }
  // Following links (docs/files.md, 2026-10-27). Where it leads: a day's
  // note opens as a day, a note of the agent's to read, any other note in
  // the sheet; a file that is not a note opens in its own application, a
  // web address in the browser. Every jump is remembered, so the way back
  // (and on again) returns to the place, the cursor where it was.
  property var backStack: []
  property var foreStack: []
  property var pendingLink: null       // { heading, block }: where to land once the note is read
  function linkKnown(l) {
    if (l.url || l.target === "") return true
    if (root.vaultIndex === null) { root.needIndex(); return true }
    return Links.resolve(root.vaultIndex, l.target, root.noteRel, l.kind !== "md") !== ""
  }
  function placeNow() {
    return { stem: svc.noteDate, file: svc.filePath, readOnly: svc.readOnly, at: editor.cursorPosition, pdf: root.pdfRel,
             dash: root.dashOpen }
  }
  function samePlace(a, b) {
    return a.stem === b.stem && a.file === b.file && (a.pdf || "") === (b.pdf || "") && !!a.dash === !!b.dash
  }
  // A step in the middle's history (docs/keys-proposal.md slice 4,
  // 2026-10-28): where the middle was is remembered before it moves, from
  // whichever way it moves (openNote, openFile, openPdf, toggleDash, a
  // link). One step per thing done: a move made of several (the dashboard
  // closing to go to a line on another day) is remembered once, as it was
  // before the first. Never while going back or on, nor before a note is
  // shown.
  property bool travelling: false
  property bool stepNoted: false
  function remember() {
    if (root.travelling || root.stepNoted || (!svc.ready && root.pdfRel === "")) return
    var here = root.placeNow()
    var last = root.backStack[root.backStack.length - 1]
    if (!last || !root.samePlace(last, here)) root.backStack = root.backStack.concat([here]).slice(-50)
    root.foreStack = []
    root.stepNoted = true
    Qt.callLater(function () { root.stepNoted = false })
  }
  function goTo(place) {
    root.travelling = true
    if (place.pdf) { root.openPdf(place.pdf); root.travelling = false; return }
    // Off a paper onto the note under it opens nothing, yet the middle moved.
    if (root.pdfRel !== "" || place.stem !== svc.noteDate || place.file !== svc.filePath) root.middleMoves()
    pdfPane.keep()
    root.pdfRel = ""
    root.pendingLink = { at: place.at }
    if (place.stem !== "") { if (place.stem === svc.noteDate) root.landOnLink(); else root.openNote(place.stem) }
    else if (place.file === svc.filePath) root.landOnLink()
    else root.openFile(place.file, place.readOnly)
    if (place.dash) { if (!root.dashOpen) root.toggleDash() }
    else root.showNote()
    root.travelling = false
  }
  // A dashboard row's line, its first link followed (Alt+Enter, as in the
  // note): a task that links its paper opens it where it was left (plan.md
  // item 15, step 3).
  // The links in a dashboard row's line (its task's, or the line a
  // deadline stands for).
  function rowLinks(row) {
    var t = !row ? null : row.task ? row.task : row.deadline ? root.taskOfAnchor(row.deadline.id) : null
    return t && t.text ? Links.inLine(t.text).filter(function (l) { return l.url !== "" || l.target !== "" }) : []
  }
  function followRowLink() {
    var row = root.taskRows[root.taskFocus]
    var t = !row ? null : row.task ? row.task : row.deadline ? root.taskOfAnchor(row.deadline.id) : null
    var links = root.rowLinks(row)
    if (links.length === 0) { root.showHint("no link in its line"); return }
    var daily = svc.configured ? String(svc.config.daily.dir).replace(/^\/+|\/+$/g, "") : ""
    root.pdfFromTagNext = t.project || ""
    root.followLink(links[0], t.date && daily !== "" ? daily + "/" + t.date + ".md" : "")
  }
  property var followAgain: null        // { link, from }: waiting for the vault's names, read again
  function followLink(l, from, retried) {
    root.used("link", l.url ? "web" : l.kind)
    if (l.url) { Qt.openUrlExternally(l.url); return }
    if (l.target === "") { root.pendingLink = { heading: l.heading }; root.landOnLink(); return }
    if (root.vaultIndex === null) { root.needIndex(); root.showHint("reading the vault's names…"); return }
    var rel = Links.resolve(root.vaultIndex, l.target, from || root.noteRel, l.kind !== "md")
    if (rel === "" && !retried) {
      root.followAgain = { link: l, from: from || "" }
      root.vaultIndex = null
      root.needIndex()
      return
    }
    if (rel === "") { root.showHint("no note “" + l.target + "” in the vault"); return }
    if (/\.pdf$/i.test(rel)) {
      root.remember()
      root.openPdf(rel)
      // [[paper.pdf#page=12|p. 12]], as every mark in a reading note links
      // its page: opened there (2026-11-27: the page was left out).
      var pm = /^page=(\d+)$/.exec(l.heading)
      if (pm) pdfPane.pageAfter = { page: parseInt(pm[1]) - 1, y: 0 }
      return
    }
    if (!/\.md$/i.test(rel)) { Qt.openUrlExternally(Links.fileUrl(svc.config.vault + "/" + rel)); return }
    root.remember()
    var heading = l.heading.charAt(0) === "^" ? "" : l.heading
    var block = l.heading.charAt(0) === "^" ? l.heading.substring(1) : ""
    var daily = String(svc.config.daily.dir).replace(/^\/+|\/+$/g, "")
    var stem = rel.replace(/^.*\//, "").replace(/\.md$/i, "")
    root.pendingLink = { heading: heading, block: block }
    if (rel === daily + "/" + stem + ".md" && Days.parse(stem, svc.dailyFormat())) {
      if (stem === svc.noteDate) root.landOnLink(); else root.openNote(stem)
    } else if (rel === svc.filePath) root.landOnLink()
    else root.openFile(rel, svc.agentRoot !== "" && rel.indexOf(svc.agentRoot + "/") === 0)
    root.showNote()
  }
  function goBack(d) {
    var from = d < 0 ? root.backStack : root.foreStack
    if (from.length === 0) { root.showHint(d < 0 ? "nowhere to go back to" : "nowhere on to go"); return }
    var place = from[from.length - 1]
    if (d < 0) { root.backStack = from.slice(0, -1); root.foreStack = root.foreStack.concat([root.placeNow()]) }
    else { root.foreStack = from.slice(0, -1); root.backStack = root.backStack.concat([root.placeNow()]) }
    root.used("link", d < 0 ? "back" : "forward")
    root.goTo(place)
  }
  // The note read: to the heading, the block or the place the link meant.
  function landOnLink() {
    var p = root.pendingLink
    if (!p || !svc.ready) return
    root.pendingLink = null
    var rows = editor.rows
    if (p.at !== undefined) { editor.setCursor(Math.min(p.at, editor.length), true); return }
    var want = String(p.heading || "").trim().toLowerCase()
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if ((want !== "" && r.kind === "heading" && r.body.trim().toLowerCase() === want)
          || (p.block && new RegExp("\\s\\^" + p.block.replace(/[^\w-]/g, "") + "\\s*$").test(r.raw))) {
        editor.setCursor(r.start + r.prefixLen, true)
        return
      }
    }
    if (want !== "" || p.block) root.showHint("“" + (p.heading || "^" + p.block) + "” is not in this note")
  }

  // A picture's own size, from its file's header (`file`, one call for the
  // pictures a note shows, batched), so its room is kept before it loads and
  // it is decoded no larger than it is drawn: Qt's own reading of a size is
  // the size it decoded at, not the picture's.
  property var imageSizes: ({})        // file url -> { w, h }, or { none: true } when `file` cannot tell
  property int imageSizesVersion: 0
  property var sizeQueue: []
  property var sizeAsked: ({})
  function imageSize(src) {
    var s = root.imageSizes[src]
    if (s) return s.none ? null : s
    if (!root.sizeAsked[src] && root.sizeQueue.indexOf(src) < 0) { root.sizeQueue = root.sizeQueue.concat([src]); sizeTimer.restart() }
    return null
  }
  function sizeUnknown(src) { var s = root.imageSizes[src]; return !!s && !!s.none }
  function probeSizes() {
    if (sizeProc.running || root.sizeQueue.length === 0) return
    var batch = root.sizeQueue.slice(0, 200)
    root.sizeQueue = root.sizeQueue.slice(200)
    for (var i = 0; i < batch.length; i++) root.sizeAsked[batch[i]] = true
    sizeProc.batch = batch
    sizeProc.command = ["python3", root.pageFsPy, "sizes"].concat(batch.map(Links.fromFileUrl))
    sizeProc.running = true
  }

  // A picture's file url, "" when the vault has none such, "?" while the
  // index is still being read.
  function resolveImage(target, wiki) {
    if (!svc.configured) return ""
    if (root.vaultIndex === null) { root.needIndex(); return "?" }
    var rel = Links.resolve(root.vaultIndex, target, root.noteRel, wiki)
    // Not among the names read: they are read again, a moment later (a
    // picture added since the page opened) — once for each name missed, so
    // a name that is truly missing does not keep the vault being read.
    if (rel === "") {
      if (!root.missedNames[target]) { var m = root.missedNames; m[target] = true; root.missedNames = m; reindexTimer.restart() }
      return ""
    }
    return Links.fileUrl(svc.config.vault + "/" + rel)
  }
  readonly property alias sidebarItem: sidebar
  readonly property alias pdfItem: pdfPane
  readonly property alias contentItem: content    // what is drawn, for tests to photograph
  readonly property alias noteService: svc
  readonly property alias whenInput: whenField
  readonly property alias projectNameInput: nameField
  readonly property alias searchInput: searchField
  readonly property alias palette: pal
  // For the sheets that live in files of their own (tools/extract_sheet.py).
  readonly property alias sheetItem: sheet
  readonly property alias agentState: agent
  readonly property alias sectionsProcess: sectionsProc
  readonly property alias notebookSheetItem: notebookSheet
  readonly property alias settingsSheetItem: settingsSheet
  readonly property alias dashItem: dash
  readonly property alias marginItem: margin
  readonly property alias dayPaneItem: dayPane
  readonly property alias paper: paperPart
  readonly property alias readToday: readTodayPart
  property bool overlayOpen: false
  property bool windowOpen: false
  readonly property bool opened: overlayOpen          // what the shell's toggle asks
  readonly property bool showing: overlayOpen || windowOpen
  readonly property bool alongside: !overlayOpen      // where the sheet is drawn
  // The window in front, with the keys (read through the content's
  // attached Window, as `content` does: Quickshell's FloatingWindow has no
  // `active` of its own).
  readonly property bool windowActive: windowOpen && !overlayOpen && content.Window.active

  readonly property color background: Commons.Color.menu.background
  // Text at the contrast the theme chose. It was softened a fifth of the way
  // back toward the background on 2026-10-15, to fight a heaviness that
  // turned out to be the font *cut*, not the contrast (see `fontStyle`);
  // against a genuine Regular the softening only cost legibility.
  readonly property color foreground: Commons.Color.menu.text
  readonly property color border: Commons.Color.menu.border
  readonly property color scrim: Commons.Color.menu.scrim
  // The Omarchy theme's palette, by role (ThemeColors.qml): secondary and faint
  // text in the theme's own tuned greys, headings and marks in its colours.
  readonly property color accent: pal.accentText
  readonly property color dim: pal.dim
  readonly property color faint: pal.faint
  readonly property color urgent: pal.redText
  readonly property color magenta: pal.magentaText   // private things' lock
  // The overlay's cards (the sheet, the side panes, the lists): a quiet
  // hairline, none in the window. The theme's border, on all three at once,
  // left the focus frame (frameSpec) hard to tell from the rest; now only
  // the pane with the keys is lit (2026-11-27, the shape pass).
  readonly property var cardSpec: root.alongside ? Border.none()
    : Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16), 1)
  // The page's one face: the note, the chrome, the chat. The page drew in
  // the shell's monospace until 2026-10-15, then in iA Writer Quattro S, a
  // face for writing; since 2026-11-19 in a face for reading, Adwaita Sans
  // (Inter's design, shipped with GNOME): proportional, a tall x-height, the
  // kind of face Claude's and Obsidian's interfaces read in. Quattro's
  // near-even widths gave the chat pane 44 characters a line. `font` in the
  // config names another; otherwise the first of these the machine has.
  // Fenced code and frontmatter keep a monospace, where columns mean
  // something — the editor already draws those rows apart.
  //
  // Adwaita Sans comes with the page (fonts/, 2026-11-27), so the page reads
  // the same on every machine: Windows drew it in Segoe UI Variable, which
  // has no italic of its own. A machine that has the face installed (GNOME,
  // Omarchy) uses its own; the page's is loaded only where there is none.
  // The page's are fixed cuts, made from GNOME's variable files
  // (tools/font-cuts.py): Windows' font engine names a variable font's cuts
  // "Text Bold" and the like, and a heading asking for "Bold" by name got
  // the Regular.
  //
  // Loaded as the face is first asked for, before anything is laid out in
  // it: loaded after, every text the page had drawn changed face under its
  // own layout (binding loops in the fields' heights).
  readonly property bool bundledFace: Qt.fontFamilies().indexOf("Adwaita Sans") < 0
  function loadOwnFace() {
    if (!root.bundledFace || Qt.fontFamilies().indexOf("Adwaita Sans") >= 0) return
    var cuts = ["Regular", "Italic", "SemiBold", "SemiBoldItalic", "Bold", "BoldItalic"]
    // A FontLoader reads a local file there and then; kept, as the page's.
    for (var i = 0; i < cuts.length; i++)
      Qt.createQmlObject("import QtQuick; FontLoader { source: \"" + Qt.resolvedUrl("fonts/AdwaitaSans-" + cuts[i] + ".ttf") + "\" }", root)
  }
  readonly property var proseChoices: [svc.pageFont, "Adwaita Sans", "Inter", "Noto Sans", "Segoe UI Variable Text", "Segoe UI", "iA Writer Quattro S", Style.font.family]
  readonly property string fontFamily: {
    root.loadOwnFace()
    var have = Qt.fontFamilies()
    for (var i = 0; i < root.proseChoices.length; i++)
      if (root.proseChoices[i] !== "" && have.indexOf(root.proseChoices[i]) >= 0) return root.proseChoices[i]
    return Style.font.family
  }
  // The cut of the prose face. The iA Writer families ship with every style
  // declaring the same weight, so asking for a normal weight hands back the
  // Bold file: the page came out uniformly heavy, and `**bold**` had nowhere
  // heavier to go. Naming the style picks the real Regular. Only for them
  // (2026-11-27): a face named "Regular" keeps to that one cut, so `*a*`
  // and `**a**` in Adwaita Sans were the Regular slanted and thickened by
  // Qt, not its own Italic and Bold (seen on Windows and on Linux).
  readonly property string fontStyle: /^iA Writer/.test(root.fontFamily) ? "Regular" : ""

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

  // The conversations' rhythm (2026-11-19, chat readability,
  // docs/explorations/chat-readability/): a little smaller than the note,
  // so a 620 px pane holds about 60 characters a line, at 1.6 leading with
  // a paragraph's space between paragraphs — what Claude's chat reads at.
  // Qt's markdown gave 1.2 and no space between paragraphs at all (Chat.js).
  // The page's leading, in ems: the note's prose (NoteEditor.leading) and
  // the chat's (2026-11-19). 1.5 and 1.6 were rendered on a class note:
  // a face with Adwaita's tall x-height, light on a dark ground, at a
  // measure in the 70s wants the top of the usual 1.5–1.6, and one number
  // for the whole page keeps the note and its chat in one rhythm.
  readonly property real leading: 1.6
  readonly property int chatSize: Math.round(root.textSize * 0.9)
  // Qt's rich-text line-height is a share of the font's own line, not of
  // its size: the leading in ems is asked for in the face's terms.
  FontMetrics { id: chatMetrics; font.family: root.fontFamily; font.pixelSize: root.chatSize }
  readonly property int chatLeading: chatMetrics.height > 0 ? Math.round(100 * root.leading * root.chatSize / chatMetrics.height) : 130
  readonly property int chatGap: Math.round(root.chatSize * 0.7)          // after a paragraph
  readonly property int chatTurnGap: Math.round(root.chatSize * 1.8)      // between turns

  // The measure: a line of text holds at most `measureChars` characters,
  // the reading length typography settles on (45–75). It is counted in the
  // page's own type, so it follows the zoom and the font: zoomed in, the
  // column widens with the letters and still holds 72; zoomed out, the
  // space beside it grows, never the lines. A window narrower than the
  // measure just wraps. The same in the window and on the overlay.
  readonly property int measureChars: 72
  FontMetrics { id: bodyMetrics; font.family: root.fontFamily; font.styleName: root.fontStyle; font.pixelSize: root.textSize }
  // One character of this face, as prose spends them: measured on ordinary
  // sentences, spaces and punctuation and capitals included, because that
  // is what "72 characters a line" counts. Until 2026-11-19 it was the
  // lowercase alphabet: right for a monospace, and near enough for Quattro,
  // but in a proportional sans a line of real prose then held about 80 —
  // past the 45–75 the eye likes. English and German, the languages the
  // notes are written in most; for a monospace this is still exactly the
  // advance. Qt's own averageCharacterWidth over-counts, weighing capitals
  // the same as letters nobody types as often.
  readonly property string measureSample: "The point that stuck was that neither is more valid on its own: it depends on "
    + "the claim you want to make. Die Daten sind reich, aber die Route war fest, also wählten die Fahrer nie, wohin sie fuhren."
  readonly property real chWidth: {
    // Reading the metrics' own font first is what makes this a binding:
    // advanceWidth is a method call, so without it QML sees no dependency
    // and the measure would stop following the zoom and the face.
    var px = bodyMetrics.font.pixelSize, fam = bodyMetrics.font.family
    return px > 0 && fam !== "" ? bodyMetrics.advanceWidth(root.measureSample) / root.measureSample.length : 1
  }
  readonly property int measure: Math.round(root.chWidth * root.measureChars)
  // The overlay's sheet has a border, inside which the padding starts:
  // without it the overlay held 71½ characters, and a line of 72 wrapped
  // there and not in the window (found by run.py --overlay, 2026-10-25).
  readonly property int sheetFor: root.measure + 2 * root.sheetPadding
    + Math.ceil(Border.left(root.cardSpec) + Border.right(root.cardSpec))
  // Where the note sits: one rule for both shapes, both sides and every
  // view in the middle (Layout.js, 2026-11-25). The note is centred in the
  // room the panes leave, as the dashboard and the lists already were. From
  // 2026-10-24 it was centred in the window instead, so with the agent's
  // pane open it sat beside the chat with an empty strip on its other side.
  // A pane opening slides it (`sheet`'s x).
  readonly property int sheetMargin: root.sp(28)
  // The focus frame's border: Hyprland's active border as the theme gives
  // it, at the width of Hyprland's (2 px, or the shell's spacing).
  readonly property var frameSpec: {
    var g = Border.resolvedGradient(pal.activeBorder, root.accent, 1)
    var spec = Border.flat(g.colors.length > 0 ? g.colors[0] : root.accent, Math.max(2, Style.space(2)))
    if (g.enabled) spec.gradient = g
    return spec
  }
  // What is kept clear at the window's edges: nothing in the window, the
  // overlay's margin on the overlay. The side panes stand against it.
  readonly property int edge: root.alongside ? 0 : root.sheetMargin
  // One at a time (Layout.paneRange), the middle keeps its own width: the
  // chat is drawn over it, or waits in a strip at the window's edge.
  readonly property int rightSpace: !((root.marginOpen && !root.wideOpen) || root.dayBesideNote) ? 0
    : root.paneAlone ? (root.paneTucked ? root.paneStrip : 0) : root.marginWidth + root.marginGap
  // A PDF is not prose: its lines are its own, so it is given more than the
  // note's measure (2026-11-15: in the note's column a paper's text was
  // too small to read), up to the room the window has.
  readonly property int pdfFor: Math.round(root.sheetFor * 1.8)
  readonly property var notePlace: Layout.note(content.width, root.pdfShown ? root.pdfFor : root.sheetFor, root.edge, root.sideSpace, root.rightSpace)
  readonly property int sheetWidth: root.notePlace.width
  readonly property int sheetX: root.notePlace.x
  // The dashboard and the keys sheet are lists, so they take the width the
  // sheet does not use — but never the sidebar's, drawn beside them.
  readonly property bool wideOpen: root.dashOpen || root.keysOpen || root.settingsOpen
  readonly property int wideX: root.sideSpace + (root.alongside ? 0 : root.sheetMargin)
  readonly property int wideWidth: (root.alongside ? content.width : content.width - root.sheetMargin * 2) - root.sideSpace
  readonly property int sheetPadding: alongside ? root.sp(28) : root.sp(44)
  readonly property int marginGap: root.sp(18)
  readonly property int gutter: root.sp(18)
  // The right pane beside the note: takes the room the note leaves, up to
  // 440 px, never dropping the note below 340 px (returns 0 on ultra-narrow
  // windows so the "too narrow" guard works instead of crushing the editor).
  // Below ~970 px (when both side panes would squeeze the note under 420 px),
  // side panes are mutually exclusive via `ensureRoomFor`.
  readonly property bool canBothPanes: Layout.bothFit(content.width, root.edge, root.sidebarWidth + root.marginGap, root.sp(300) + root.marginGap, root.sp(420))
  // The sidebar widening for a project's view can leave no room for both
  // panes with the window's width unchanged: the pane not in use makes
  // room, as when the window narrows (2026-11-28).
  onCanBothPanesChanged: if (!root.canBothPanes && root.sidebarOpen && root.rightView !== "") root.ensureRoomFor(root.here === "left" ? "left" : "right")
  // Today's width, before any is remembered: what the note leaves, 300 to
  // 440 px (Layout.rightPane).
  readonly property int paneReading: Layout.rightPane(content.width, root.edge, root.sheetFor,
    root.canBothPanes ? root.sideSpace : 0, root.marginGap, root.sp(300), root.sp(440), root.sp(340))

  // ------------------------------------------------ the agent's pane, sized by hand
  // (docs/explorations/chat-width, 2026-11-22.) Three ways, all kept: drag
  // its edge, nudge it (Alt+Shift+←/→), flip between two remembered splits
  // (Alt+Z): *reading*, the middle wide, and *discussing*, the chat wide.
  // A drag or a nudge moves the split you are in. Each screen width keeps
  // its own two splits, beside a paper apart from beside a note
  // (pane-widths.json). Nothing changes place: only the edge moves.
  readonly property string paneKind: root.pdfShown ? "paper" : "note"
  // The overlay keeps its own, apart from the window's: a split made over a
  // whole screen does not suit a window tiled beside slides (2026-11-27).
  readonly property string paneScreen: (root.alongside ? "" : "overlay ") + String(Math.round(panel.screen ? panel.screen.width : content.width))
  property var paneWidths: ({})         // screen width → kind → { at, reading, discussing }
  readonly property var paneSaved: {
    var s = root.paneWidths[root.paneScreen]
    return s && s[root.paneKind] ? s[root.paneKind] : ({})
  }
  readonly property string paneSplit: root.paneSaved.at === "discussing" ? "discussing" : "reading"
  // The chat's measure: an answer's line, about 70 characters of its type.
  readonly property int chatMeasure: root.sp(580)
  readonly property int railGap: root.sp(28)
  readonly property int railWidth: root.sp(240)
  readonly property int paneStrip: root.sp(30)
  // A paper's floor: the column where its body text is still about 11 px
  // (Layout.paperFloor, from the words' usual height), the sheet's padding
  // with it. A note's: the least it narrows to beside both panes.
  readonly property int paperFloor: Layout.paperFloor(pdfPane.read ? pdfPane.read.span : null, 612, root.fs(11), 2 * root.sheetPadding)
  readonly property var paneOpts: ({
    room: content.width - 2 * root.edge - (root.canBothPanes ? root.sideSpace : 0) - root.marginGap,
    min: root.sp(300),
    // The most the chat can use: its measure and its padding, and beside a
    // paper the rail of the words it quotes.
    ceiling: root.chatMeasure + 2 * root.sp(24) + (root.paneKind === "paper" ? root.railGap + root.railWidth : 0),
    // A note's least is today's (Layout.rightPane's 340): prose rewraps.
    floor: root.paneKind === "paper" ? root.paperFloor : root.sp(340),
    hardFloor: root.paneKind === "paper" ? root.sp(360) : root.sp(340),
    reading: root.paneReading
  })
  // The middle's floor and the pane's least do not fit side by side: the
  // two show one at a time, Alt+Z between them.
  readonly property bool paneAlone: Layout.paneRange(root.paneOpts).alone
  property bool paneTucked: false       // one at a time, the middle shown
  property int paneSeen: 0              // the day's turns when the chat was tucked away
  onPaneTuckedChanged: if (root.paneTucked) root.paneSeen = root.dayTurns.length
  property int paneLive: 0              // while the edge is dragged
  readonly property int marginWidth: root.paneAlone ? Math.max(0, root.paneOpts.room - root.paneStrip)
    : root.paneLive > 0 ? root.paneLive
    : Layout.paneWidth(root.paneOpts, root.paneSplit, root.paneSaved[root.paneSplit] || 0)
  // A pane over the dashboard keeps its own width (talkWidth).
  readonly property bool paneSizable: root.rightView === "day" ? !root.dayBesideDash : root.rightView === "margin"

  function paneKeep(at, width) {
    var all = JSON.parse(JSON.stringify(root.paneWidths))
    var scr = all[root.paneScreen] = all[root.paneScreen] || {}
    var k = scr[root.paneKind] = scr[root.paneKind] || {}
    k.at = at
    if (width > 0) k[at] = Math.round(width)
    root.paneWidths = all
    paneWidthsFile.setText(JSON.stringify(all, null, 1) + "\n")
  }
  // Alt+Z, or a click on the split's word: reading ↔ discussing. One at a
  // time, the middle ↔ the chat.
  function flipPane() {
    if (root.rightView === "" || !root.paneSizable) { root.showHint("the agent's pane is not open"); return }
    root.used("pane", "flip")
    // One at a time, the side shown follows the keys (onHereChanged).
    if (root.paneAlone) {
      if (root.here === "right") root.focusCenter(); else root.focusPane("right")
      return
    }
    root.paneKeep(root.paneSplit === "reading" ? "discussing" : "reading", 0)
  }
  // Alt+Shift+←/→: the edge by about 100 px (Omarchy's Super+−/= for a
  // window). Wider stops at the middle's floor; a drag goes further.
  function nudgePane(by) {
    if (root.rightView === "" || !root.paneSizable || root.paneAlone) return
    root.used("pane", "nudge")
    // sp() never goes under 1: the step is scaled, then given its way.
    root.paneKeep(root.paneSplit, Layout.nudge(root.paneOpts, root.marginWidth, (by < 0 ? -1 : 1) * root.sp(Math.abs(by))))
  }
  // The edge dragged to `x` in the window: the pane from there to the
  // window's edge, as far as it may go; kept when let go.
  function dragPane(x) {
    if (root.paneAlone) return
    root.paneLive = Layout.drag(root.paneOpts, content.width - root.edge - x)
  }
  function endPaneDrag() {
    if (root.paneLive <= 0) return
    root.used("pane", "drag")
    var w = root.paneLive
    root.paneKeep(root.paneSplit, w)
    root.paneLive = 0
    // Under its floor a paper's text is small: allowed by hand, and said.
    if (root.paneKind === "paper" && root.paneOpts.room - w < root.paneOpts.floor)
      root.showHint("small text · " + root.keyName("paneFlip"))
  }
  // A double click on the edge: the split back to where it starts.
  function resetPane() {
    var all = JSON.parse(JSON.stringify(root.paneWidths))
    var k = all[root.paneScreen] && all[root.paneScreen][root.paneKind]
    if (!k) return
    delete k[root.paneSplit]
    root.paneWidths = all
    paneWidthsFile.setText(JSON.stringify(all, null, 1) + "\n")
  }
  // What the split's word says on hover: its three ways.
  readonly property string paneTip: root.paneAlone
    ? root.tips([[root.paneTucked ? "Show the chat: the paper waits in a strip" : "Show the middle: the chat waits in a strip", "paneFlip"]])
    : root.tips([[root.paneSplit === "reading" ? "To discussing: the chat wide, the middle at its least" : "Back to reading: the middle wide", "paneFlip"],
                 ["Nudge the edge", "paneWider"],
                 ["Drag the edge: any width, " + root.paneSplit + " remembers it", ""]])
  // One at a time, what shows is where the keys are: the chat while they
  // are in it, the middle (the chat in its strip) otherwise.
  onPaneAloneChanged: root.paneTucked = root.paneAlone && root.here !== "right"
  function ensureRoomFor(side) {
    if (root.canBothPanes) return
    if (side === "right" && root.sidebarOpen) root.sidebarOpen = false
    else if (side === "left" && root.rightView !== "") {
      root.marginOpen = false
      root.marginFocus = -1
      root.dayOpen = false
      root.noteRoom = false
      root.closeTalk(false)
    }
  }

  // The margin beside the dashboard, while a proposal is talked about: the
  // dashboard gives up the room, since a list has more width than it needs.
  readonly property int talkWidth: Math.max(0, Math.min(root.sp(440), Math.round(root.wideWidth * 0.42)))
  readonly property int dashWidth: root.wideWidth - (root.talkOpen || root.dayBesideDash ? root.talkWidth + root.marginGap : 0)

  readonly property string dateLabel: svc.noteDate !== "" && svc.configured
    ? Days.longLabel(svc.noteDate, svc.dailyFormat()) : ""
  // A day in the sheet, or a file of the notes (docs/files.md). Everything
  // a day has that a file does not — its deadlines bound to lines, who made
  // each line, the agent's records and runs, the check — asks this first.
  readonly property bool dayNote: svc.noteDate !== ""
  // Whether the note's last save is still on its way to the disk (the check
  // waits for it; the tests ask).
  readonly property bool noteSaving: svc.saving
  // A PDF in the middle, in the note's place (PdfPane.qml, step 5): the note
  // stays loaded under it, and Esc goes back to it.
  property string pdfRel: ""
  readonly property bool pdfShown: root.pdfRel !== ""
  readonly property real barLane: root.sp(10)   // a scroll bar's width beside the note (ScrollMark)

  // How private looks (docs/files.md, B · Paper, chosen 2026-10-27): what
  // the agent may not see is sunk into a darker paper — a private block as
  // an inset of it with a lock in the gutter, the agent's lane; a private
  // day, or a day before the horizon, as the whole sheet. An answer keeps
  // its solid bar in the gutter, so private and answered never share a look.
  readonly property color sunk: pal.sunk
  readonly property bool sheetSunk: svc.ready && !root.pdfShown && (svc.notePrivate || root.beforeHorizon)
  readonly property color sheetColor: root.sheetSunk ? root.sunk : root.background
  // The corners of what floats over the page: the card in the overlay
  // shape and its sheets, the switcher, a hover tip. A shell with a radius
  // of its own for those (Windows: 8, its windows' and flyouts', against
  // 4 for controls) says it as `overlayRadius`; omarchy-shell has one
  // radius for both, Hyprland's rounding, and that stands.
  readonly property int overlayRadius: Style.overlayRadius !== undefined ? Style.overlayRadius : Style.cornerRadius
  property var privatePaint: []         // [{ y, h }]: the private blocks, in editor coordinates
  function openPdf(rel) {
    if (rel === "") return
    // The paper already in the middle (back to it from the dashboard, a
    // link to it): no step, and the agent's pane is left as it is.
    if (rel !== root.pdfRel) { root.remember(); root.middleMoves() }
    if (root.searchOpen) root.closeSearch("back")
    root.leftLine(root.lastLine)
    root.flush()
    root.used("pdf", "open")
    root.exportOpen = false
    root.marginOpen = false
    root.closeTalk(false)
    root.dashOpen = false
    root.marginFocus = -1
    pdfPane.keep()
    root.pdfFromTag = root.pdfFromTagNext
    root.pdfFromTagNext = ""
    if (root.refFiles.length === 0) root.loadRefFiles()   // the names its chat's quotes are said by
    root.pdfRel = rel
    root.showNote()
  }
  // The project a paper belongs to (plan.md item 15, step 1), guessed when
  // it is plain: the project of the line its link was followed from, else
  // the project whose documents hold it, else one whose tag is a folder on
  // its way. "" when none is plain: then it is asked, once.
  property string pdfFromTagNext: ""   // the line a link is being followed from
  property string pdfFromTag: ""       // …for the PDF open now
  function paperProject(rel) {
    var known = function (t) { return root.projects.some(function (p) { return p.tag === t }) }
    if (root.pdfFromTag !== "" && known(root.pdfFromTag)) return root.pdfFromTag
    var abs = svc.configured ? svc.config.vault + "/" + rel : ""
    for (var i = 0; i < root.projects.length; i++)
      if ((root.projects[i].docs || []).some(function (d) { return d.path === abs })) return root.projects[i].tag
    var parts = rel.toLowerCase().split("/").slice(0, -1)
    for (var k = 0; k < root.projects.length; k++)
      if (parts.indexOf(String(root.projects[k].tag).toLowerCase()) >= 0) return root.projects[k].tag
    return ""
  }
  function closePdf() {
    if (!root.pdfShown) return
    root.middleMoves()
    pdfPane.keep()
    root.pdfRel = ""
    root.showNote()
  }

  // The agent's pane when the middle moves (the student's rule,
  // 2026-11-22). It never opens by itself: closed, it stays closed. Open,
  // it follows what is in the middle: beside a paper, the paper's chat
  // (its "about this", docs/agent.md "One conversation"); beside a note
  // from Files, the note's; beside a day, the day's. A paper or note the
  // agent may not be given (private, a PDF with no words) has the day's
  // chat beside it, never its own. Words typed in the box and not sent
  // keep the pane where it is: nothing is switched under the hand. The
  // follow never takes the keys: they go where the move puts them, and
  // stay in the pane only when they were in it as it turns.
  // What the middle is decides it only once it is known (the paper read,
  // the note loaded): until then the pane is left as it was.
  readonly property string paneFits: root.pdfShown
    ? (!root.paper.shown ? "day" : pdfPane.read.pdf !== root.pdfRel ? "" : root.paper.askable ? "room" : "day")
    : root.dayNote ? "day" : !svc.ready || root.noteRel === "" ? "" : root.noteAskable && !svc.notePrivate ? "room" : "day"
  property bool paneFollows: false      // the middle moved with the pane open: it follows once paneFits is known
  // A paper's or note's chat with words in its box, the middle moved
  // away: the chat it was, held (its path), until the middle comes back
  // to it, the pane is closed or the middle moves again with the box empty.
  property string paneHeld: ""
  onNoteRoomChanged: if (!root.noteRoom) root.paneHeld = ""
  readonly property string middleRel: root.paper.shown ? root.pdfRel : root.noteRel
  onMiddleRelChanged: if (root.paneHeld !== "" && root.middleRel === root.paneHeld) root.paneHeld = ""
  // Words in the box are what is held — and so are replies attached, the
  // chips `@` added and a paper's marks (2026-11-28: three replies to a
  // paper's answer went when the note was glanced at, the box empty).
  function paneWords() {
    var f = dayPane.dayFieldRef
    return (!!f && String(f.text).trim() !== "") || root.dayReplies.length > 0 || !!root.dayReplying
      || (root.noteRoom && root.dayRefs.length > 0) || (root.paper.room && root.paper.marks.length > 0)
  }
  function middleMoves() {
    var words = root.paneWords()
    if (root.dayOpen && words && root.noteRoom && root.paneHeld === "") root.paneHeld = root.roomRel
    root.paneFollows = root.dayOpen && !words
    if (root.paneFollows) Qt.callLater(root.followMiddle)
  }
  onPaneFitsChanged: if (root.paneFollows) Qt.callLater(root.followMiddle)
  // Run after the move, never in the middle of it (a move is made of
  // several steps, each changing what fits).
  function followMiddle() {
    if (root.paneFollows && (!root.dayOpen || root.paneWords())) root.paneFollows = false
    if (!root.paneFollows || root.paneFits === "") return
    root.paneFollows = false
    var keys = root.here === "right"
    var held = root.paneHeld
    root.paneHeld = ""
    if (held !== "") root.paneSubject = held
    root.paneTo(root.paneFits === "room")
    // The keys in the pane as it turns: in it still (its box, or a paper's list).
    if (keys) root.dayKeysItem().forceActiveFocus()
  }
  // The pane to the day's chat or the middle's own, as openRoom does it,
  // without taking the keys. What the box held for the other subject goes.
  property string paneSubject: ""       // what the pane's own chat was about, when it was one
  function paneTo(room) {
    var subject = room ? root.roomRel : ""
    if (room !== root.noteRoom || subject !== root.paneSubject) {
      root.dayPending = null
      root.dayRefs = []
      root.dayAutoHeld = null
      root.paper.marks = []
      root.clearReplies("day")
    }
    root.noteRoom = room
    root.paneSubject = subject
    if (room) root.loadRefFiles()
  }

  // Export as a PDF (ExportSheet.qml; docs/plan.md item 13, slice 2): in
  // the note's place, the section the cursor is in — or the blocks a
  // selection touches — each block in or out. The runner lists them and
  // writes the PDF (`longhand-agent export`); it reads the note from disk,
  // so the note is saved first. Written, the PDF opens where the note was.
  property bool exportOpen: false
  property var exportData: null         // `export --list`: title, author, course, date, look, pdf, blocks
  property var exportPicks: ({})        // hash → true: the blocks in
  property int exportFocus: 0
  property string exportTitle: ""
  property string exportLook: "minimal"
  property string exportError: ""
  property bool exportBusy: false
  property bool exportAfterSave: false
  property var exportArgs: []           // the note and where in it, for both runs
  property string exportFor: ""         // the note it was opened on
  property bool exportFromDash: false   // a deadline's: Esc goes back to the dashboard
  // The title row is the title field, not a block to pick.
  readonly property var exportRows: root.exportData && root.exportData.blocks
    ? root.exportData.blocks.filter(function (b) { return b.why !== "the title" }) : []
  readonly property int exportWords: {
    var n = 0, p = root.exportPicks
    root.exportRows.forEach(function (r) { if (p[r.hash]) n += r.words || 0 })
    return n
  }
  readonly property string exportWhere: root.exportData && root.exportData.pdf
    ? root.exportData.pdf.replace(Quickshell.env("HOME") + "/", "~/").replace(/\/[^\/]*$/, "") : ""
  onNoteRelChanged: if (root.exportOpen && root.noteRel !== root.exportFor) root.closeExport()

  function openExport() {
    if (!svc.ready || root.pdfShown || root.noteRel === "" || root.pageOutside || root.problem !== "") { root.showHint("nothing here to export"); return }
    var body = editor.text
    var whole = svc.joinHeader(body)
    var before = whole.substring(0, whole.length - body.length)
    var t = before + body
    var where
    var sel = editor.selected()              // across lines, or inside one
    if (sel && sel.b > sel.a) {
      // The file's lines (0-based), as Where.at counts them for a path.
      var a = Where.lineAt(t, before.length + sel.a) - 1
      var end = before.length + sel.b
      var b = Where.lineAt(t, end) - 1
      if (b > a && t.charAt(end - 1) === "\n") b--
      where = ["--select", a + ":" + b]
    } else where = ["--line", String(Where.lineAt(t, before.length + editor.cursorPosition) - 1)]
    if (root.searchOpen) root.closeSearch("back")
    root.exportFromDash = false
    root.startExport((root.dayNote ? ["--date", svc.noteDate] : ["--file", svc.filePath]).concat(where),
                     where[0] === "--select" ? "selection" : "section")
  }
  // From a deadline's row on the dashboard (slice 3): its section found
  // among its course's by its name and day, the PDF named after it. A box
  // with a date is a deadline here too; the deadline is never closed.
  function exportFocused() {
    var row = root.taskRows[root.taskFocus]
    var d = row && row.kind === "deadline" ? row.deadline : null
    var t = row && row.kind === "task" ? row.task : null
    var title = d ? d.title : t ? t.title : ""
    var tag = d ? d.project : t ? t.project : ""
    var due = d ? Qt.formatDate(new Date(d.due * 1000), "yyyy-MM-dd") : t ? (t.due || "") : ""
    if (title === "") { root.showHint("a deadline or a task to export for"); return }
    if (!tag) { root.showHint("no course on it (#tag) to find its section in"); return }
    root.closePdf()
    root.toNote()
    root.exportFromDash = true
    root.startExport(["--for", title, "--tag", tag].concat(due !== "" ? ["--due", due] : [], ["--pick", "0"]), "deadline")
  }
  function startExport(args, how) {
    root.exportArgs = args
    root.exportFor = root.noteRel
    root.exportData = null
    root.exportPicks = ({})
    root.exportError = ""
    root.exportFocus = 0
    root.exportBusy = true
    root.exportOpen = true
    root.used("export", how)
    root.focusCenter()
    root.flush()
    if (svc.saving) root.exportAfterSave = true
    else root.listExport()
  }
  function listExport() {
    exportListProc.command = [svc.runner, "export"].concat(root.exportArgs, ["--list"])
    exportListProc.running = true
    if (!exportDepsProc.running) exportDepsProc.running = true
  }
  function exportListed(code, out, err) {
    root.exportBusy = false
    if (!root.exportOpen) return
    var got = null
    try { got = JSON.parse(out) } catch (e) {}
    if (code !== 0 || !got) { root.exportError = err.trim().replace(/^longhand-agent: /, "") || "the note could not be read"; return }
    var picks = {}
    got.blocks.forEach(function (b) { if (b.in) picks[b.hash] = true })
    var kept = root.exportData && root.exportData.from ? root.exportTitle : ""   // a title written over stays
    root.exportData = got
    root.exportPicks = picks
    root.exportTitle = kept || got.title || ""
    root.exportLook = got.look === "omarchy" ? "omarchy" : "minimal"
  }
  function closeExport() {
    if (!root.exportOpen) return
    root.exportOpen = false
    root.exportAfterSave = false
    root.exportBusy = false
    if (exportProc.running) exportProc.signal(15)
    if (exportListProc.running) exportListProc.signal(15)
    if (root.exportFromDash) { root.exportFromDash = false; root.showDash() }
    else root.focusCenter()
  }
  // A deadline's other sections (← →): listed again, the picks with it.
  function exportSection(dir) {
    var f = root.exportData && root.exportData.from
    if (!f || root.exportBusy) return
    var k = Math.max(0, Math.min(f.of - 1, f.pick + dir))
    if (k === f.pick) return
    var a = root.exportArgs.slice()
    a[a.indexOf("--pick") + 1] = String(k)
    root.exportArgs = a
    root.exportBusy = true
    root.exportFocus = 0
    root.listExport()
  }
  Process {
    id: exportDepsProc
    command: ["python3", root.pageFsPy, "which", "pandoc", "xelatex"]
    stdout: StdioCollector {
      onStreamFinished: {
        var m = text.trim()
        if (m !== "" && root.exportOpen && root.exportError === "")
          root.exportError = "PDF export needs " + m + " installed on PATH"
      }
    }
  }
  function exportToggle(i) {
    var r = root.exportRows[i]
    if (!r) return
    var p = Object.assign({}, root.exportPicks)
    if (p[r.hash]) delete p[r.hash]
    else p[r.hash] = true
    root.exportPicks = p
    root.exportError = ""
  }
  function exportKey(event) {
    if (root.anywhereKey(event)) return true
    var n = root.exportRows.length
    if (Sc.hit(event, "exportDown")) root.exportFocus = Math.max(0, Math.min(n - 1, root.exportFocus + 1))
    else if (Sc.hit(event, "exportUp")) root.exportFocus = Math.max(0, root.exportFocus - 1)
    else if (Sc.fromEvent(event) === "Home") root.exportFocus = 0
    else if (Sc.fromEvent(event) === "End") root.exportFocus = Math.max(0, n - 1)
    else if (Sc.hit(event, "keysHere")) root.toggleKeys()
    else if (Sc.hit(event, "exportPick")) root.exportToggle(root.exportFocus)
    else if (Sc.hit(event, "exportPrevSection")) root.exportSection(-1)
    else if (Sc.hit(event, "exportNextSection")) root.exportSection(1)
    else if (Sc.hit(event, "exportLook")) root.exportLook = root.exportLook === "omarchy" ? "minimal" : "omarchy"
    else if (Sc.hit(event, "exportTitle")) exportSheet.titleRef.forceActiveFocus()
    else if (Sc.hit(event, "exportWrite")) root.writeExport()
    else if (Sc.hit(event, "exportClose")) root.closeExport()
    else return false
    return true
  }
  function writeExport() {
    if (root.exportBusy || !root.exportData) return
    var picked = root.exportRows.filter(function (r) { return root.exportPicks[r.hash] }).map(function (r) { return r.hash })
    if (picked.length === 0) { root.exportError = "nothing is in: " + root.keyName("exportPick") + " puts a block in"; return }
    root.exportError = ""
    root.exportBusy = true
    exportProc.command = [svc.runner, "export"].concat(root.exportArgs, ["--blocks", picked.join(","),
      "--title=" + (root.exportTitle.trim() || root.exportData.title), "--look", root.exportLook])
    exportProc.running = true
  }
  function exportWritten(code, out, err) {
    root.exportBusy = false
    if (!root.exportOpen) return
    var got = null
    try { got = JSON.parse(out) } catch (e) {}
    if (code !== 0 || !got || !got.pdf) { root.exportError = err.trim().replace(/^longhand-agent: /, "") || "the PDF could not be made"; return }
    root.used("export", root.exportLook)
    root.exportFromDash = false
    root.openPdf(got.pdf)
    root.showHint("written to " + got.pdf.replace(Quickshell.env("HOME") + "/", "~/"))
  }
  // The header's name for what is in the sheet: the day, a paper's name
  // ("Moser et al. 2023", agent/names.py), or a note's file name (where it
  // is, the Files tree shows).
  readonly property string noteLabel: root.pdfShown ? (pdfPane.read.name || root.fileName(root.pdfRel))
    : root.dayNote ? root.dateLabel
    : svc.filePath === "" ? "" : svc.filePath.replace(/^.*\//, "").replace(/\.md$/i, "")

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
  readonly property bool agentOn: root.agentDay && !svc.notePrivate && !root.beforeHorizon

  // The agent's horizon (docs/files.md, 2026-10-26): a daily note from
  // before it is private, whatever its frontmatter says, so years of
  // journaling are not the agent's. The runner holds the rule and refuses
  // such a day; this is the page not offering. Moved in Settings → what the
  // agent may search, kept as `horizon` in settings.json.
  property var horizonData: null       // `longhand-agent horizon`
  readonly property bool beforeHorizon: {
    if (!root.horizonData || svc.noteDate === "" || !svc.configured) return false
    var p = Days.parse(svc.noteDate, svc.dailyFormat())
    return !!p && Days.format(p.date, "YYYY-MM-DD") < root.horizonData.horizon
  }

  function loadHorizon() {
    if (!svc.configured) return
    if (horizonProc.running) { horizonProc.again = true; return }   // read again once it ends: what changed meanwhile counts
    horizonProc.command = [svc.runner, "horizon"]
    horizonProc.running = true
  }

  // A date ("YYYY-MM-DD"), or "" for the default: the first day the agent
  // kept. Never later than today.
  function setHorizon(iso) {
    var cur = root.readSettings()
    if (iso === "") delete cur.horizon
    else cur.horizon = iso
    root.settingsData = cur
    settingsFile.setText(JSON.stringify(cur, null, 2) + "\n")
    root.used("horizon", iso === "" ? "default" : iso)
    root.showHint(iso === "" ? "the horizon is back to the first day the agent kept"
      : "the agent sees daily notes from " + root.sayHorizon(iso) + " on")
    var d = JSON.parse(JSON.stringify(root.horizonData || {}))
    d.horizon = iso === "" ? d["default"] : iso
    d.set = iso !== ""
    root.horizonData = d
    Qt.callLater(root.loadHorizon)
  }

  function moveHorizon(months) {
    if (!root.horizonData) return
    var p = Days.parse(root.horizonData.horizon, "YYYY-MM-DD")
    if (!p) return
    var d = Days.addMonths(p.date, months)
    var today = new Date()
    if (d > today) d = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    root.setHorizon(Days.format(d, "YYYY-MM-DD"))
  }

  function sayHorizon(iso) {
    var p = Days.parse(String(iso || ""), "YYYY-MM-DD")
    return p ? Qt.formatDate(p.date, "d MMMM yyyy") : ""
  }

  // Ctrl+Shift+P, and the header's own word. Writes `agent: false` into the
  // note's frontmatter, which is what the runner reads; taking it off puts
  // the day back as it was.
  function togglePrivate() {
    if (!svc.ready) return
    // Said, not silently refused (2026-11-26, the header pass): the header
    // offers no "private" where the key would change nothing true.
    if (!root.dayNote) { root.showHint("a note from Files is private already: the agent sees it only in its chat"); return }
    var on = !svc.notePrivate
    svc.setPrivate(on)
    root.flush()
    // The block's chat cannot send once the note is private: it closes,
    // its words kept in its box.
    if (on && root.marginOpen) { root.backToNote(); if (root.here === "right") editor.focusNote() }
    root.used("private", on ? "on" : "off")
    // Before the horizon the rule holds either way, and the hint says so
    // rather than promise what the agent will not do.
    root.showHint(root.beforeHorizon ? (on ? "private — and before the horizon, the agent sees nothing of it either way"
                                          : "not private, but before the horizon: the agent still sees nothing")
      : on ? "private — the agent sees nothing in this note" : "the agent can be asked about this note again")
  }
  // Ctrl+P: the block the cursor is in — or every block a selection spans —
  // made private, wrapped in a `> [!private]` callout; on a private block,
  // unwrapped. Only the markers are written, never a word, and one undo
  // takes it back. A quote already is one: it only gains the line that
  // names it. A callout touching it is kept apart by a blank line, so the
  // two never run together.
  function togglePrivateBlock() {
    if (!svc.ready || svc.readOnly) return
    var text = editor.text
    var lines = text.split("\n")
    var lineOf = function (pos) { return text.substring(0, pos).split("\n").length - 1 }
    var blocks = Blocks.split(text).filter(function (b) { return b.kind !== "frontmatter" })
    var cur = editor.cursorPosition
    var la = lineOf(editor.spanning ? editor.selStart : cur)
    var lb = lineOf(editor.spanning ? editor.selEnd : cur)
    var first = -1, last = -1
    for (var k = 0; k < blocks.length; k++)
      if (blocks[k].end > la && blocks[k].start <= lb) { if (first < 0) first = k; last = k }
    if (first < 0) { root.showHint("no block here to make private"); return }
    var start = blocks[first].start, end = blocks[last].end
    var curLine = lineOf(cur)
    var curCol = cur - (text.lastIndexOf("\n", cur - 1) + 1)
    var unwrap = first === last && blocks[first].private && blocks[first].kind === "callout"
    var out = [], at = -1, shift = 0
    if (unwrap) {
      for (var i = start; i < end; i++) {
        var m = lines[i].match(i === start ? /^>[ \t]?\[!private\][+-]?[ \t]?/i : /^>[ \t]?/)
        var cut = m ? m[0].length : 0
        var rest = lines[i].substring(cut)
        if (i === start && rest.trim() === "") { if (curLine === i) { at = out.length; shift = -curCol } continue }
        if (curLine === i) { at = out.length; shift = -Math.min(cut, curCol) }
        out.push(rest)
      }
    } else {
      var quoted = true
      for (var q = start; q < end; q++) if (lines[q].trim() !== "" && !/^>/.test(lines[q])) quoted = false
      out.push("> [!private]")
      for (var j = start; j < end; j++) {
        var pre = quoted ? "" : lines[j].trim() === "" ? ">" : "> "
        if (curLine === j) { at = out.length; shift = pre.length }
        out.push(pre + lines[j])
      }
      if (start > 0 && /^>/.test(lines[start - 1])) { out.unshift(""); if (at >= 0) at++ }
      if (end < lines.length && /^>/.test(lines[end])) out.push("")
    }
    var from = 0
    for (var s = 0; s < start; s++) from += lines[s].length + 1
    var to = from + lines.slice(start, end).join("\n").length
    var pos = from
    if (at >= 0) {
      for (var o = 0; o < at; o++) pos += out[o].length + 1
      pos += Math.max(0, Math.min(out[at].length, curCol + shift))
    }
    editor.clearSelection()
    editor.snapshot(true)
    editor.replace(from, to, out.join("\n"))
    editor.setCursor(pos, true)
    root.flush()
    root.used("private-block", unwrap ? "off" : "on")
    // A box that is already a deadline stays one: the deadline list keeps
    // its title and date, which the agent reads. Said, not undone.
    var bound = false
    for (var bl = start; bl < end; bl++) if (/\s\^d\d+\s*$/.test(lines[bl])) bound = true
    root.showHint(unwrap ? "not private: the agent can be asked about it again"
      : bound ? "private, but its deadline stays a deadline: the agent still sees that"
      : "private: this block is never sent")
  }
  property string pendingStamp: ""   // a day to open once the save in flight lands
  property var pendingFile: null     // or a file: { rel, readOnly }

  // The sidebar: a month calendar.
  property bool sidebarOpen: false
  // Its spaces (docs/files.md, 2026-10-26), after Zen's workspaces: "time"
  // (the calendar, the day's deadlines, the projects) and "files" (the
  // notes as folders). A page opened from nothing lands on time.
  readonly property var spaces: ["time", "files"]
  property string sidebarSpace: "time"
  property int spaceStep: 0            // the way the last switch went, for the slide

  // To the space before or after, wrapping around; the sidebar opens (and
  // takes the keys) if it was closed.
  function switchSpace(d) {
    var i = (root.spaces.indexOf(root.sidebarSpace) + d + root.spaces.length) % root.spaces.length
    root.setSpace(root.spaces[i], d)
  }
  function setSpace(name, d) {
    if (!root.sidebarOpen) root.toggleSidebar()
    else if (root.here !== "left") root.focusPane("left")
    if (name === root.sidebarSpace) return
    root.spaceStep = d || (root.spaces.indexOf(name) > root.spaces.indexOf(root.sidebarSpace) ? 1 : -1)
    // A project being named is let go with its space; the keys go to what
    // the new space shows (2026-11-28: a field left behind, hidden, kept
    // them, and the filter's did when Time came back).
    root.addingProject = false
    root.sidebarSpace = name
    root.used("space", name)
    root.focusPane("left")
  }
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
  readonly property int sidebarWidth: root.projectOpen && root.sidebarSpace === "time"
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
  // The tasks the open note's day is for, written on any day (2026-11-14):
  // a box given a due day (📅) or a do-day (⏳) is shown on that day's
  // page too, not only on the page it was written on. `longhand-agent
  // dated`, read when a note opens or is saved and after the dashboard's
  // list is read again: { "2026-11-16": [rows] }, rows open first.
  property var dated: ({})
  readonly property string noteIso: {
    var p = svc.configured && svc.noteDate !== "" ? Days.parse(svc.noteDate, svc.dailyFormat()) : null
    return p ? Days.format(p.date, "YYYY-MM-DD") : ""
  }
  readonly property var dayTasks: root.noteIso !== "" ? (root.dated[root.noteIso] || []) : []
  readonly property int dayTasksDone: root.dayTasks.filter(function (t) { return t.done }).length
  property bool dayTasksOpen: false
  property int dueFocus: -1          // in the list under the calendar (-1: the grid has the keys)
  property int projFocus: -1         // in the projects list (-1: not there)
  property var projects: []          // [{ tag, name, next: { at, room } }], the most used first (orderProjects)
  property var projectsListed: []    // as the runner lists them: soonest session first
  property int pendingGoto: 0        // a deadline whose line to land on once its note is open
  property var pendingTask: null     // { text, line }: a task's line to land on, the same way
  readonly property int sideSpace: root.sidebarOpen && root.problem === "" ? root.sidebarWidth + root.marginGap : 0
  property bool applying: false

  // Runner plumbing: one process at a time, the last request wins.
  property var queued: []      // runner commands waiting, oldest first
  property bool running: false
  property string runningHash: ""
  // The running run's answer is in: the turn it was asked for is written
  // and drawn, and the run is only ending (its process still closing, for
  // most of a second on Windows). It thinks no more, and Esc there is no
  // stop: it closes, as it would a moment later (2026-11-25: Esc right as
  // an answer landed stopped a run that had finished, and put the message
  // back in the box under its own answer).
  property bool runAnswered: false
  property string runnerPhase: ""
  property string talkPhase: ""
  property string planPhase: ""
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
  property string barHover: ""   // the answered block whose gutter bar is under the hand
  property bool marginOpen: false
  property int marginFocus: -1   // -1 note; 0..n-1 proposal rows; n = chat field
  property bool dashOpen: false
  // Whose turn (2026-10-23): what the agent proposed since the dashboard was
  // last left is new until it is left again. By the ledger's ids, which
  // only grow — not by `at`, which is when a plan began, so a plan that
  // ends after the dashboard was left would never be new.
  property int dashSeenId: 0         // the highest id on the list when the dashboard was last left
  property int newAfterId: 0         // …as it was when this visit began
  onDashOpenChanged: {
    if (root.dashOpen) { root.newAfterId = root.dashSeenId; root.dashNow = Date.now(); return }
    var top = root.dashSeenId
    for (var i = 0; i < root.proposals.length; i++) top = Math.max(top, Number(root.proposals[i].id) || 0)
    root.dashSeenId = top
    root.savePageState()
  }
  function isNewAsk(x) { return !!x && (Number(x.id) || 0) > root.newAfterId }

  // A row's chat, in brief (docs/keys-proposal.md slice 2, 2026-10-28):
  // `longhand-agent next` gives each task its chat's size and last turn; a
  // deadline's is its box's. What the gutter bar says, as the note's does:
  // "thinking" while the agent answers it, "unread" while its last word is
  // the agent's and newer than the last time the chat was open (or, from
  // the margin, read there), "read", or nothing for a box never talked
  // about. The last opening per chat is kept in page.json.
  property var chatSeen: ({})          // a chat's thread key -> the last turn's `at` seen
  function chatOf(row) {
    if (!row) return null
    var t = row.kind === "task" ? row.task : row.kind === "deadline" ? root.taskOfAnchor(row.deadline.id) : null
    return t && !t.private && t.chat ? t.chat : null
  }
  // The rows a chat's last word is said under: the first of the rows that
  // share it (2026-11-18, the UX evaluation's F5: three ticked boxes under
  // one box each repeated its chat's line). Every row keeps its gutter bar.
  readonly property var chatLeads: {
    var out = {}, seen = {}, rows = root.taskRows
    for (var i = 0; i < rows.length; i++) {
      var c = root.chatOf(rows[i])
      // A row done or dropped says nothing more of its chat: its last line
      // was about it being open (the re-run of the UX evaluation, F5).
      if (!c || seen[c.thread] || root.rowClosed(rows[i])) continue
      seen[c.thread] = true
      out[root.dashRowIds[i] || ""] = true
    }
    return out
  }
  function rowClosed(row) {
    if (!row) return false
    if (row.kind === "deadline") return !!row.deadline && row.deadline.status !== "open"
    if (row.kind === "task") return !!row.task && (row.task.done || row.task.cancelled)
    return false
  }
  // A chat's words as a row says them: a deadline the agent named by its
  // number (#61) by its words instead, and the row's own as "its" / "this".
  function sayChat(text, row) {
    var own = row && row.kind === "deadline" ? row.deadline.id
      : row && row.kind === "task" && row.task.anchor > 0 ? row.task.anchor : -1
    return String(text || "").replace(/#(\d+)(['’]s)?(?![\w-])/g, function (m, n, poss) {
      var id = parseInt(n, 10)
      if (id === own) return poss ? "its" : "this one"
      var d = dl.items.filter(function (x) { return x.id === id })[0]
      return d ? "“" + d.title + "”" + (poss || "") : m
    })
  }
  function chatState(row) {
    var c = root.chatOf(row)
    if (!c) return ""
    if ((c.hash && (root.runningHash === c.hash || root.queued.some(function (q) { return q.hash === c.hash })))
        || (root.talking && root.talkData && root.talkData.thread === c.thread)) return "thinking"
    if (c.role !== "agent" || (c.who === "margin" && c.read)) return "read"
    var seen = Date.parse(root.chatSeen[c.thread] || "")
    return isNaN(seen) || Date.parse(c.at) > seen ? "unread" : "read"
  }
  function markChatSeen(d) {
    var turns = d && d.turns ? d.turns : []
    var at = ""
    for (var i = 0; i < turns.length; i++) if (turns[i].at && (at === "" || Date.parse(turns[i].at) > Date.parse(at))) at = turns[i].at
    if (!d || !d.thread || at === "" || root.chatSeen[d.thread] === at) return
    var m = JSON.parse(JSON.stringify(root.chatSeen))   // a new object, so the rows hear it
    m[d.thread] = at
    root.chatSeen = m
    root.savePageState()
  }
  property bool projectOpen: false   // the sidebar is showing one project's view
  property var sections: []          // [{ date, line, heading, title, sub, preview, open, done }]
  property string projectTag: ""
  property string projectFolder: ""   // its folder in the vault (`projects/thesis_itu`), "" when none
  property string projectName: ""
  property int sectionFocus: 0
  // The project's filed documents above its sections (docs/agent.md, slice
  // 4): -1 while the keys are on the sections, else the document picked.
  property int docFocus: -1
  // The open project's papers (plan.md item 5's first part, 2026-11-16):
  // every reading note carrying its tag (`longhand-read papers`), between
  // its documents and its sections; -1 when the keys are not on them.
  property var projectPapers: []
  property int projectPaperFocus: -1
  // The project's view as one list (ProjectView.js, 2026-11-16): its page,
  // what is open, then this week's page and its writing and reading, the
  // days before folded (2026-11-21), then the shelf and the files folded.
  // The selection is a row's key, so it holds when the list is read again.
  // The day is read when the list is: the sections are read again often
  // enough that a week turning over at midnight shows by morning.
  property string projectRowKey: ""
  property var projectFolds: ({ shelf: false, files: false, open: false, earlier: false })
  readonly property var projectRows: PV.rows(root.sections, root.projectPapers, root.projectOpen ? root.projectDocs() : [],
    { shelf: root.projectFolds.shelf, files: root.projectFolds.files, open: root.projectFolds.open,
      earlier: root.projectFolds.earlier, iso: root.sectionIso, name: root.projectName,
      today: Qt.formatDate(new Date(root.sideNow), "yyyy-MM-dd") })
  readonly property var projectRow: PV.find(root.projectRows, root.projectRowKey)
  // Nothing in it but its two pages; and while its lists are being read.
  readonly property bool projectBare: root.projectRows.every(function (r) { return r.kind === "page" || r.kind === "cap" })
  readonly property bool projectReading: sectionsProc.running || projectPapersProc.running
  readonly property string projectFocusKey: root.projectRow ? root.projectRow.key : ""
  function sectionIso(s) {
    var p = svc.configured ? Days.parse(s.date, svc.dailyFormat()) : null
    return p ? Qt.formatDate(p.date, "yyyy-MM-dd") : String(s.date)
  }
  // A day given as YYYY-MM-DD, said as a section's day is.
  function isoWhen(iso) {
    var d = new Date(iso + "T12:00:00")
    if (isNaN(d.getTime())) return iso
    return root.dayWhen(d)
  }
  // "Thu 26 Nov · yesterday", by the sidebar's minute, so a list left open
  // past midnight says it again.
  function dayWhen(d) {
    var now = new Date(root.sideNow)
    var age = Math.round((new Date(now.toDateString()) - new Date(d.toDateString())) / 86400000)
    return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "ddd d MMM" : "ddd d MMM yyyy")
      + (age === 0 ? " · today" : age === 1 ? " · yesterday" : "")
  }
  // The row picked, by its key; the older foci follow it (the live tests
  // and the sections' refresh read them).
  function pickProjectRow(key) {
    root.projectRowKey = key
    var r = PV.find(root.projectRows, key)
    root.docFocus = -1
    root.projectPaperFocus = -1
    if (r && (r.kind === "section" || r.kind === "box")) root.sectionFocus = r.index
  }
  function refreshProjectPapers() {
    if (!root.projectOpen || root.projectTag === "") { root.projectPapers = []; return }
    if (projectPapersProc.running) { projectPapersAgain.restart(); return }
    projectPapersProc.tag = root.projectTag
    // With the project's folder, its PDFs too, marked or not (2026-11-16).
    projectPapersProc.command = [pdfPane.readPath, "papers", "--tag", root.projectTag]
      .concat(root.projectFolder !== "" ? ["--dir", root.projectFolder] : [])
    projectPapersProc.running = true
  }
  Timer { id: projectPapersAgain; interval: 300; onTriggered: root.refreshProjectPapers() }
  Process {
    id: projectPapersProc
    property string tag: ""
    stdout: StdioCollector {
      id: projectPapersOut
      onStreamFinished: {
        if (projectPapersProc.tag !== root.projectTag) return
        // All of them: ProjectView sorts papers from the folder's own
        // documents, and leaves out a note whose PDF is gone.
        try { root.projectPapers = JSON.parse(projectPapersOut.text).papers || [] } catch (e) { /* kept as they were */ }
      }
    }
  }
  property var pendingSection: null  // a heading to land on once its note is open
  property var tasks: []
  property var raised: []
  // What the dashboard changed, newest last, for Ctrl+Z: a tick, a drop, a
  // priority, a day, words, a grade, a box set aside, a document filed —
  // each with the words that say it (`say`), so taking it back says what
  // came back. Until 2026-11-27 only ticks, drops and filing were kept,
  // and Ctrl+Z after anything else silently took back an older tick.
  property var tickHistory: []
  function rememberUndo(entry) { root.tickHistory = root.tickHistory.concat([entry]).slice(-100) }
  property bool showShelf: false      // the "set aside" band unfolded
  // A tick from the dashboard is drawn at once, before the note is written
  // and the list read again (rowKey → true), and the row that was just
  // ticked plays the tick; the list waits for it (holdTasksUntil).
  // What the agent proposes or asks, open (`longhand-agent proposals`), and
  // the do-dates it proposed that were accepted lately (key -> date), whose
  // pills carry its tint. docs/agent.md, slice 2.
  property var proposals: []
  property var agentDates: ({})

  // The day conversation (docs/agent.md, "The day conversation",
  // 2026-10-21): the student talks to the day, not to a line, in the right
  // pane — from anywhere (Ctrl+J), from a block pointing at it
  // (Ctrl+Shift+Enter), or by the seal. The day is the pane's home: a
  // block's or a task's conversation is a room stepped into on purpose, and
  // leaving it comes back here. The open note's day is shown (a past day's,
  // read-only); only today's is talked in.
  property bool dayOpen: false
  // What the next message points at (docs/agent.md, "One conversation",
  // slice 2, 2026-11-18): the chips above the box, each seen before it is
  // sent and removable. `dayRefs` are the ones put there (`@`, or a block
  // pointed at): { date, hash | line, head, kind }, a block of the open
  // note or a task from another day's; or { file, head, kind }, a note or
  // a paper. Before them, dimmer, what the student is looking at (`dayAuto`):
  // the selected task beside the dashboard, the block under the cursor in
  // the note. It follows the selection until typing starts, is then fixed
  // for that message, and can be let go like any other.
  property var dayRefs: []
  function refKey(r) { return !r ? "" : r.file ? "f:" + r.file : (r.date || "") + ":" + (r.hash || ("L" + r.line)) }
  function refToday(r) { return !!r && !!r.hash && (!r.date || r.date === svc.noteDate) }
  readonly property string dayBlock: { for (var i = 0; i < root.dayRefs.length; i++) if (root.refToday(root.dayRefs[i])) return root.dayRefs[i].hash; return "" }
  readonly property string dayBlockText: { for (var i = 0; i < root.dayRefs.length; i++) if (root.refToday(root.dayRefs[i])) return root.dayRefs[i].head; return "" }
  property bool dayAutoOff: false       // the automatic chip was let go, until the selection moves
  property var dayAutoHeld: null        // …or fixed, since typing started
  readonly property var dayAutoNow: {
    if (!root.dayShown || root.noteRoom || root.paper.room || !root.dayCanSend) return null
    if (root.dashOpen) {
      var row = root.taskRows[root.taskFocus]
      var t = !row ? null : row.kind === "task" ? row.task : row.kind === "deadline" ? root.taskOfAnchor(row.deadline.id) : null
      return t && t.key && !t.private && t.date ? { date: t.date, line: t.line, head: root.taskName(t), kind: "task", auto: true } : null
    }
    if (root.centerView !== "note" || !root.dayNote || root.currentHash === "" || !root.agentOn) return null
    // The block under the cursor, whatever it is (the student's call,
    // 2026-11-18: a paragraph too, not only a box) — never an empty one, a
    // private one, or the frontmatter.
    var b = root.blockBounds(root.currentHash)
    if (!b || b.private || b.kind === "frontmatter" || b.text.trim() === "") return null
    return { date: svc.noteDate, hash: root.currentHash, head: root.blockHead(root.currentHash),
             kind: /^\s*[-*+] \[.\] /.test(b.text.split("\n")[0]) ? "task" : "block", auto: true }
  }
  readonly property string dayAutoKey: root.refKey(root.dayAutoNow)
  onDayAutoKeyChanged: root.dayAutoOff = false
  readonly property var dayAuto: root.dayAutoHeld ? root.dayAutoHeld : root.dayAutoOff ? null : root.dayAutoNow
  readonly property var dayChips: {
    var a = root.dayAuto, k = root.refKey(a)
    var own = root.dayRefs
    return (a && !own.some(function (r) { return root.refKey(r) === k || (r.hash && r.hash === a.hash) }) ? [a] : []).concat(own)
  }
  function addDayRef(r) {
    var k = root.refKey(r)
    if (root.dayRefs.some(function (x) { return root.refKey(x) === k })) return
    // A note's own chat points at one block of it (`note --block`), and at
    // other notes and papers besides (`note --refs`, 2026-11-19).
    root.dayRefs = !root.noteRoom ? root.dayRefs.concat([r]).slice(-6)
      : r.file ? root.dayRefs.concat([r]).slice(-6)
      : root.dayRefs.filter(function (x) { return !!x.file }).concat([r])
  }
  // A click on a chip: it goes, and its name from the sentence (ChatField).
  function dropDayChipAt(i) {
    var r = (root.noteRoom ? root.dayRefs : root.dayChips)[i]
    if (r) dayPane.dayFieldRef.dropMention(root.refKey(r))
    if (root.noteRoom) root.dayRefs = root.dayRefs.filter(function (x, k) { return k !== i })
    else root.dropDayChip(i)
  }
  function dropDayChip(i) {
    var c = root.dayChips[i]
    if (!c) return false
    if (c.auto) { root.dayAutoHeld = null; root.dayAutoOff = true; root.used("chip", "auto-removed") }
    else { var k = root.refKey(c); root.dayRefs = root.dayRefs.filter(function (r) { return root.refKey(r) !== k }); root.used("chip", "removed") }
    return true
  }
  // Typing fixes the automatic chip: what was being looked at when the
  // message began is what it is about, wherever the selection goes next.
  function dayTyped(text) {
    if (String(text) === "") { root.dayAutoHeld = null; return }
    if (!root.dayAutoHeld && !root.dayAutoOff && root.dayAutoNow) root.dayAutoHeld = root.dayAutoNow
  }
  // The pane's two views (the same design). "Everything" is the day's
  // chat grown: above its turns, the earlier days folded to a line each
  // (unfolded: that day's places, a line each); among them, in the order
  // said, today's other places — a task's chat, a paper's — folded to
  // their last words. A line opens what it is about ("about this": a
  // task's chat beside the dashboard, a paper's, a note's). From
  // `longhand-agent conversation --view`, read when the pane shows and
  // after each answer.
  property var convoView: null
  property string dayFoldKey: ""        // the folded line the keys are on; "": the box
  readonly property bool convoShown: root.dayShown && !root.noteRoom && !root.paper.room && svc.isToday && svc.configured
  onConvoShownChanged: {
    root.dayFoldKey = ""
    root.historyShown = root.historyStep
    if (root.convoShown) { root.loadConvoView(); root.loadRefFiles() }
  }
  // The notes and papers `@` may point at in the day's chat: those the
  // agent may see anyway (`conversation --files`), read each time the pane
  // shows. A private note is talked about in its own chat only.
  property var refFiles: []
  // Each one's name as it is shown everywhere (agent/names.py, 2026-11-19):
  // "Moser et al. 2023", a note's heading. A quote of another paper and a
  // file the agent read are said by it; the file's name until it is read.
  readonly property var refNames: {
    var out = {}
    for (var i = 0; i < root.refFiles.length; i++) out[root.refFiles[i].rel] = root.refFiles[i].name
    return out
  }
  function fileName(rel) {
    var p = String(rel || "")
    // Either separator: an export's whole path on Windows has "\" (the
    // header said "C:\Users\…\Downloads\Diary 1" for "Diary 1").
    return root.refNames[p] || p.replace(/^.*[\\\/]/, "").replace(/\.(md|pdf)$/i, "")
  }
  // One `@` row: its kind, its name, a paper's title where there is room.
  function refItem(f) {
    return { file: f.rel, kind: f.kind, name: f.name, head: f.kind + " · " + f.name + (f.title ? " · " + f.title : "") }
  }
  function refMatches(f, q) {
    return q === "" || [f.name, f.title || "", f.rel].some(function (x) { return String(x).toLowerCase().indexOf(q) >= 0 })
  }
  onRefFilesChanged: if (root.dayMention) Qt.callLater(function () { root.updateDayMention(!!root.dayMention && !!root.dayMention.margin) })
  function loadRefFiles() {
    if (refFilesProc.running) return
    refFilesProc.command = [svc.runner, "conversation", "--files"]
    refFilesProc.running = true
  }
  onWorkingChanged: if (!root.working && root.convoShown) root.loadConvoView()
  function loadConvoView() {
    if (convoViewProc.running) return
    convoViewProc.command = [svc.runner, "conversation", "--view"]
    convoViewProc.running = true
  }
  readonly property var convoDays: root.convoShown && root.convoView ? (root.convoView.days || []) : []
  // One chat that scrolls up into the days before (2026-11-21, the
  // grilling's "one conversation, continuous, with a divider between
  // days"; it had become fourteen folded lines of counts above today). The
  // last few days are drawn whole above today's turns, a rule between
  // days; scrolling to the top brings HISTORY_STEP more, up to the days
  // the runner gives. Display only: today's session starts fresh, and the
  // agent looks back itself (`recall`) when a message points at them.
  readonly property int historyStep: 3
  property int historyShown: historyStep
  readonly property var historyDays: root.convoDays.slice(Math.max(0, root.convoDays.length - root.historyShown))
  readonly property bool historyMore: root.historyShown < root.convoDays.length
  function moreHistory() {
    if (!root.historyMore) return false
    root.historyShown = Math.min(root.convoDays.length, root.historyShown + root.historyStep)
    root.used("view", "history-more")
    return true
  }
  // What the history draws, in order: a rule for each day, then its own
  // chat's turns and its other places (a line each), as they were said.
  readonly property var historyRows: {
    var out = []
    root.historyDays.forEach(function (d) {
      out.push({ kind: "day", label: d.label, date: d.date })
      var rows = []
      ;(d.said || []).forEach(function (t, i) { rows.push({ at: String(t.at || ""), n: i, row: { kind: "turn", t: t } }) })
      ;(d.groups || []).forEach(function (g, i) {
        rows.push({ at: String(g.at || ""), n: 1000 + i, row: { kind: "fold", g: g, key: "g:" + d.date + ":" + g.thread } })
      })
      rows.sort(function (a, b) { return a.at < b.at ? -1 : a.at > b.at ? 1 : a.n - b.n })
      rows.forEach(function (x) { out.push(x.row) })
    })
    return out
  }
  readonly property var historyTurns: root.historyRows.filter(function (r) { return r.kind === "turn" }).map(function (r) { return r.t })
  readonly property string todayLabel: "Today · " + Qt.formatDate(new Date(), "ddd d MMM")
  readonly property var convoToday: root.convoShown && root.convoView ? (root.convoView.groups || []) : []
  // Today's other places said before the day's turn `i` (after the one
  // before it); `i` past the last: those said since.
  function convoBefore(i) {
    var turns = root.dayTurns, gs = root.convoToday
    if (gs.length === 0) return []
    var lower = i > 0 && turns[i - 1] ? String(turns[i - 1].at || "") : ""
    var upper = i < turns.length ? String(turns[i].at || "9") : "9"
    // A turn with no time yet (sent, not written): nothing is before it
    // that is not before the end.
    if (i < turns.length && !turns[i].at) return []
    if (i >= turns.length) for (var j = turns.length - 1; j >= 0 && lower === ""; j--) lower = String(turns[j].at || "")
    return gs.filter(function (g) { return String(g.at) > lower && String(g.at) <= upper })
  }
  // The folded lines the keys go up through from the box: the shown days'
  // other places, then today's.
  readonly property var convoRows: {
    var out = []
    root.historyRows.forEach(function (r) { if (r.kind === "fold") out.push({ key: r.key, group: r.g }) })
    root.convoToday.forEach(function (g) { out.push({ key: "g::" + g.thread, group: g }) })
    return out
  }
  function sayFold(g) {
    if (g.kind === "proposals") return "proposals · " + g.name + " · " + g.turns + " waiting"
    return (g.kind ? g.kind + " · " : "") + (g.name || "…") + " · " + g.turns + (g.turns === 1 ? " turn" : " turns")
  }
  function sayFoldLast(g) { return g.text ? (g.role === "agent" ? "◇ " : "you: ") + g.text : "" }
  function convoAct(key) {
    var row = null
    for (var i = 0; i < root.convoRows.length; i++) if (root.convoRows[i].key === key) row = root.convoRows[i]
    if (!row) return
    root.openConvo(row.group.open)
  }
  // "About this": what a folded line is about, opened where it is talked
  // about — a task's chat beside the dashboard, a paper's or a note's
  // room, a day's note.
  function openConvo(o) {
    if (!o || !o.kind) { root.showHint("nothing to open for this"); return }
    root.used("view", "about-" + o.kind)
    root.dayFoldKey = ""
    // What planning proposed: settled where it is listed, the dashboard.
    if (o.kind === "asks") {
      if (!root.dashOpen) root.toggleDash()
      root.clickAgentChip()
      return
    }
    if (o.kind === "task") {
      var t = null
      for (var i = 0; i < root.tasks.length && !t; i++) if (root.tasks[i].key === o.key) t = root.tasks[i]
      if (t && !t.private) {
        if (!root.dashOpen) root.toggleDash()
        root.openTaskTalk(t)
      } else if (o.date) { root.openNote(o.date); root.showHint("that task is closed: this is its note") }
      else root.showHint("that task is closed")
      return
    }
    if (o.kind === "file") { if (/\.pdf$/i.test(o.rel)) root.openPdf(o.rel); else root.openFile(o.rel, false); return }
    if (o.date) root.openNote(o.date)
  }

  // What was said elsewhere about the task or block a chat is about (the
  // same design: "about this" is every turn that mentions the thing, not
  // only this place's): the day's chat pointing at it, another day's
  // margin for the same task. `longhand-agent conversation --elsewhere`.
  property var elsewhere: null
  readonly property string elsewhereWant: {
    if (root.talkOpen) {
      var d = root.talkData
      if (!d || !d.thread || "?~#".indexOf(String(d.thread).charAt(0)) >= 0) return ""
      return d.thread + "|" + (d.chat ? d.chat.date + "|" + d.chat.hash : "|")
    }
    if (root.marginOpen && root.dayNote && (root.currentRec !== "" || root.currentHash !== ""))
      return "|" + svc.noteDate + "|" + (root.currentRec !== "" ? root.currentRec : root.currentHash)
    return ""
  }
  property string elsewhereFor: ""
  onElsewhereWantChanged: root.loadElsewhere()

  // The margin's box is one box for every block and task, so what is
  // written in it is kept per thing (2026-11-28, the agent pane pass): the
  // cursor moved to another block took the draft along, a reply half
  // written was dropped and its words left in the next block's box. Moving
  // away keeps the words, the chips and the replies with what they were
  // about; coming back gives them back. A block whose words are edited is
  // still the same block: its draft stays in the box. Kept while the page
  // is open, as the box's words always were.
  readonly property string marginSubject: root.talkOpen ? (root.talkThread !== "" ? "talk:" + root.talkThread : "")
    : root.marginOpen && root.currentHash !== "" ? "block:" + svc.noteDate + ":" + root.currentHash : ""
  property var marginDrafts: ({})
  property string marginDraftFor: ""
  onMarginSubjectChanged: root.swapMarginDraft()
  function marginDraftNow() {
    var f = margin.chatFieldRef
    var d = { text: String(f.text), mentions: f.liveMentions.slice(), refs: root.marginRefs.slice(), replies: root.marginReplies.slice(),
              replying: root.marginReplying, stash: root.marginStash }
    return d.text.trim() !== "" || d.refs.length > 0 || d.replies.length > 0 || d.replying ? d : null
  }
  function swapMarginDraft() {
    var now = root.marginSubject, was = root.marginDraftFor
    if (now === was) return
    root.marginDraftFor = now
    // The same block, its words edited (its hash is its words): the box
    // stays as it is.
    if (was.indexOf("block:") === 0 && now.indexOf("block:") === 0) {
      var wasHash = was.slice(was.lastIndexOf(":") + 1)
      if (was.split(":")[1] === now.split(":")[1] && root.blockBounds(wasHash) === null) return
    }
    var all = {}
    for (var k in root.marginDrafts) all[k] = root.marginDrafts[k]
    if (was !== "") { var d = root.marginDraftNow(); if (d) all[was] = d; else delete all[was] }
    var back = now !== "" ? all[now] : null
    if (back) delete all[now]
    root.marginDrafts = all
    var f = margin.chatFieldRef
    f.mentions = []
    f.text = back ? back.text : ""
    f.cursorPosition = f.text.length
    if (back && back.mentions.length > 0) f.mentions = back.mentions
    root.marginRefs = back ? back.refs : []
    root.setReplies("margin", back ? back.replies : [])
    root.setReplying("margin", back ? back.replying : null, back ? back.stash : "")
  }
  // A message that failed while the margin was on something else: kept
  // with what it was about, before whatever was written there since.
  function keepMarginDraft(subject, p) {
    if (!subject || !p) return
    var all = {}
    for (var k in root.marginDrafts) all[k] = root.marginDrafts[k]
    var old = all[subject] || { text: "", mentions: [], refs: [], replies: [], replying: null, stash: "" }
    var text = p.raw !== undefined ? p.raw : p.text
    all[subject] = { text: old.text.trim() === "" ? text : text + "\n" + old.text,
                     mentions: old.text.trim() === "" ? (p.mentions || []) : [],
                     refs: (p.savedRefs || []).concat(old.refs), replies: (p.replies || []).concat(old.replies),
                     replying: old.replying, stash: old.stash }
    root.marginDrafts = all
  }
  function loadElsewhere() {
    var w = root.elsewhereWant
    if (w === root.elsewhereFor && root.elsewhere) return
    if (w.split("|")[0] !== root.elsewhereFor.split("|")[0] || w === "") root.elsewhere = null
    if (w === "" || !svc.configured) { root.elsewhereFor = ""; return }
    var parts = w.split("|")
    var cmd = [svc.runner, "conversation", "--elsewhere"]
    if (parts[0] !== "") cmd = cmd.concat(["--task", parts[0]])
    if (parts[1] !== "" && parts[2] !== "") cmd = cmd.concat(["--date", parts[1], "--hash", parts[2]])
    elsewhereProc.wanted = w
    if (elsewhereProc.running) return
    elsewhereProc.asked = w
    elsewhereProc.command = cmd
    elsewhereProc.running = true
  }
  readonly property var elsewhereTurns: root.elsewhere && root.elsewhereFor === root.elsewhereWant ? (root.elsewhere.turns || []) : []
  // "About this", one stream: a task's or a block's own turns, and those
  // said about it anywhere else (from the log), in the order said. A turn
  // with no time keeps its place after the one before it.
  function streamed(own, wrap) {
    var rows = [], last = ""
    own.forEach(function (r, i) {
      var at = r.turn ? String(r.turn.at || "") : r.at !== undefined ? String(r.at || "") : ""
      last = at || last
      rows.push({ at: last, n: i, row: r })
    })
    root.elsewhereTurns.forEach(function (e, i) {
      rows.push({ at: String(e.at || ""), n: -1000 + i, row: wrap(Object.assign({ elsewhere: true }, e)) })
    })
    rows.sort(function (a, b) { return a.at < b.at ? -1 : a.at > b.at ? 1 : a.n - b.n })
    return rows.map(function (x) { return x.row })
  }
  readonly property var talkStream: root.talkOpen ? root.streamed(root.talkTurns, function (e) { return e }) : []
  readonly property var marginStream: root.marginOpen ? root.streamed(root.marginRows, function (e) { return { turn: e } }) : root.marginRows

  // What a task's or a block's chat is about, as its one chip; letting it
  // go leaves for the day's chat with what was typed.
  readonly property var aboutChip: {
    if (root.talkOpen) {
      if (!root.talkData) return null
      return { kind: root.talkItem ? (root.talkItem.kind === "question" ? "question" : "proposal") : "task", head: root.talkData.title || "", auto: true }
    }
    if (root.marginOpen && root.dayNote && root.currentHash !== "") {
      var b = root.blockBounds(root.currentHash)
      return { kind: b && /^\s*[-*+] \[.\] /.test(b.text.split("\n")[0]) ? "task" : "block", head: root.blockHead(root.currentHash), auto: true }
    }
    return null
  }
  // What was written goes with it, after what the day's box held — and
  // the chips and replies too (2026-11-28: the day's own draft was written
  // over, and the rest dropped).
  function aboutToDay() {
    if (root.marginReplying) root.cancelReply("margin")
    var text = String(margin.chatFieldRef.text || "")
    var refs = root.marginRefs.slice(), replies = root.marginReplies.slice()
    margin.chatFieldRef.text = ""
    root.marginRefs = []
    root.setReplies("margin", [])
    root.used("chip", "about-removed")
    root.openDay("")
    Qt.callLater(function () {
      root.dayAutoHeld = null
      root.dayAutoOff = true
      var f = dayPane.dayFieldRef
      if (text.trim() !== "") {
        var had = String(f.text)
        f.text = had.trim() === "" ? text : had + (/\s$/.test(had) ? "" : " ") + text
        f.cursorPosition = f.text.length
      }
      if (refs.length > 0) root.giveBackSent("day", { raw: "", savedRefs: refs })
      if (replies.length > 0) root.setReplies("day", root.dayReplies.concat(replies))
    })
  }

  // Replying to passages of the agent's (2026-11-18; design A, chosen the
  // same evening after the first try lost a reply and had two boxes that
  // looked alike). Words picked in one of its answers make the pane's one
  // box a reply to them: a bar inside it says so, the passage stays lit and
  // numbered in the answer, and the box's keys change — Enter attaches,
  // Esc cancels. An attached reply is a pill over the box (click: edit it
  // again; ×: let it go) and the passage keeps its number; what the box
  // held before is set aside meanwhile and comes back. Enter with no reply
  // open sends the box's words with every reply attached, each under its
  // passage (`> …`). Per pane: the day's (with a note's and a paper's) and
  // the margin's (a block's, a task's). Kept by replacing the lists, never
  // in a copy (the first try's reply vanished so).
  property var dayReplies: []          // attached: [{ quote, text, at }]
  property var marginReplies: []
  property var dayReplying: null       // the reply the box is: { quote, at }
  property var marginReplying: null
  property string dayStash: ""         // what the box held before it was a reply
  property string marginStash: ""
  function repliesOf(pane) { return pane === "margin" ? root.marginReplies : root.dayReplies }
  function replyingOf(pane) { return pane === "margin" ? root.marginReplying : root.dayReplying }
  function replyField(pane) { return pane === "margin" ? margin.chatFieldRef : dayPane.dayFieldRef }
  function setReplies(pane, list) { if (pane === "margin") root.marginReplies = list; else root.dayReplies = list }
  function setReplying(pane, r, stash) {
    if (pane === "margin") { root.marginReplying = r; if (stash !== undefined) root.marginStash = stash }
    else { root.dayReplying = r; if (stash !== undefined) root.dayStash = stash }
  }
  function stashOf(pane) { return pane === "margin" ? root.marginStash : root.dayStash }
  // The number the reply being written will have: its place among them —
  // its own, while one attached is written again.
  function replyNumber(pane) {
    var r = root.replyingOf(pane)
    return r && r.was ? r.was.index + 1 : root.repliesOf(pane).length + 1
  }
  // "REPLY 2", or "REPLY 1 OF 3" while an earlier one is changed ("REPLY 2
  // OF 2" said nothing the first word did not).
  function replyLabel(pane) {
    var n = root.replyNumber(pane), all = root.repliesOf(pane).length + 1
    return "REPLY " + n + (n < all ? " OF " + all : "")
  }
  function addReply(pane, passage, at) {
    var q = String(passage || "").replace(/\s+/g, " ").trim()
    if (q === "") return
    if (q.length > 400) q = q.slice(0, 400).replace(/\s+\S*$/, "") + " …"
    var f = root.replyField(pane)
    var open = root.replyingOf(pane)
    if (open && String(f.text).trim() !== "" && !root.attachReply(pane)) return
    open = root.replyingOf(pane)
    // One being changed, left empty for another: back where it was.
    if (open && open.was) {
      var back = root.repliesOf(pane).slice()
      back.splice(Math.min(open.was.index, back.length), 0, { quote: open.quote, text: open.was.text, at: open.at })
      root.setReplies(pane, back)
      root.setReplying(pane, { quote: open.quote, at: open.at, was: null })
    }
    var stash = open ? root.stashOf(pane) : String(f.text)
    // A passage already answered: its reply back in the box, to change.
    var list = root.repliesOf(pane), had = -1
    for (var i = 0; i < list.length; i++) if (list[i].quote === q) had = i
    var text = had >= 0 ? list[had].text : ""
    if (had >= 0) root.setReplies(pane, list.filter(function (r, k) { return k !== had }))
    // An attached one taken back to change keeps its place: Esc puts it
    // back as it was, Enter where it was (2026-11-28: Esc lost it, Enter
    // moved it last and renumbered the others).
    root.setReplying(pane, { quote: q, at: String(at || (had >= 0 ? list[had].at : "")),
                             was: had >= 0 ? { index: had, text: list[had].text } : null }, stash)
    f.text = text
    f.cursorPosition = text.length
    Qt.callLater(function () { root.replyField(pane).forceActiveFocus() })
    root.used("reply", had >= 0 ? "edit" : pane)
  }
  // Enter while the box is a reply: attached, the box given back.
  function attachReply(pane) {
    var r = root.replyingOf(pane), f = root.replyField(pane)
    if (!r) return false
    var text = String(f.text).trim()
    if (text === "") { root.showHint("write your reply first · " + root.keyName("marginBack") + " cancels it"); return false }
    var list = root.repliesOf(pane).slice(), one = { quote: r.quote, text: text, at: r.at }
    if (r.was) list.splice(Math.min(r.was.index, list.length), 0, one)
    else list.push(one)
    root.setReplies(pane, list)
    var stash = root.stashOf(pane)
    root.setReplying(pane, null, "")
    f.text = stash
    f.cursorPosition = stash.length
    root.showHint("reply attached · " + root.keyName("chatSend") + " sends")
    root.used("reply", "attached")
    return true
  }
  function cancelReply(pane) {
    var r = root.replyingOf(pane)
    if (!r) return false
    if (r.was) {
      var list = root.repliesOf(pane).slice()
      list.splice(Math.min(r.was.index, list.length), 0, { quote: r.quote, text: r.was.text, at: r.at })
      root.setReplies(pane, list)
    }
    var f = root.replyField(pane), stash = root.stashOf(pane)
    root.setReplying(pane, null, "")
    f.text = stash
    f.cursorPosition = stash.length
    return true
  }
  function editReply(pane, i) {
    var r = root.repliesOf(pane)[i]
    if (r) root.addReply(pane, r.quote, r.at)
  }
  function dropReply(pane, i) {
    root.setReplies(pane, root.repliesOf(pane).filter(function (r, k) { return k !== i }))
    root.used("reply", "removed")
  }
  // The message, as sent and as kept: the box's words first (under no
  // quote, so never read as part of a reply), then each reply under its
  // passage. A reply still open in the box is attached first.
  function composed(pane, text) {
    var bits = root.repliesOf(pane).map(function (r) { return "> " + r.quote + "\n" + String(r.text).trim() })
    var main = String(text || "").trim()
    if (main !== "") bits.unshift(main)
    return bits.join("\n\n")
  }
  function clearReplies(pane) {
    root.setReplies(pane, [])
    root.setReplying(pane, null, "")
  }
  // The pane's box keys while it is a reply: Enter attaches, Esc cancels.
  function replyKey(pane, event) {
    if (!root.replyingOf(pane)) return false
    if (Sc.hit(event, "chatSend")) { root.attachReply(pane); return true }
    if (Sc.hit(event, "marginBack")) { root.cancelReply(pane); return true }
    return false
  }
  // The passages of one answer the student is replying to, or has: lit
  // while written, numbered once attached, and once sent, numbered as the
  // message numbered them — for its words to be marked in the answer.
  function passageMarks(pane, at) {
    if (!at) return []
    var out = []
    root.repliesOf(pane).forEach(function (r, i) { if (r.at === at) out.push({ quote: r.quote, n: i + 1, state: "attached" }) })
    var open = root.replyingOf(pane)
    if (open && open.at === at) out.push({ quote: open.quote, n: root.replyNumber(pane), state: "open" })
    var sent = (pane === "margin" ? root.marginSent : root.daySent)[at] || []
    var hov = root.hoverQuote && root.hoverQuote.pane === pane ? root.hoverQuote.quote : null
    sent.forEach(function (s) {
      if (!out.some(function (o) { return o.quote === s.quote })) out.push({ quote: s.quote, n: s.n, state: s.quote === hov ? "hover" : "sent" })
    })
    return out
  }
  // Passages answered in sent messages, by the answer they came from (the
  // nearest before the message whose words hold them).
  function sentOf(turns) {
    var map = {}
    for (var i = 0; i < turns.length; i++) {
      var t = turns[i]
      if (!t || t.role === "agent" || !/(^|\n)> \S/.test(t.text || "")) continue
      var n = 0
      root.passageParts(t.text).forEach(function (p) {
        if (p.quote === "") return
        n++
        var want = root.plainWords(p.quote).replace(/ …$/, "")
        for (var k = i - 1; k >= 0; k--) {
          var a = turns[k]
          if (a && a.role === "agent" && a.at && root.plainWords(a.text).indexOf(want) >= 0) {
            (map[a.at] = map[a.at] || []).push({ quote: p.quote, n: n })
            break
          }
        }
      })
    }
    return map
  }
  // An answer to several replies, in its parts (2026-11-18, design A2):
  // the agent begins each with the passage's first words quoted (`> …`,
  // the runner's PASSAGES); each part is matched to the reply it answers —
  // the student's message just before, by the passage's words, else in
  // order — and drawn under a small bubble of the student's words. Null
  // when the answer has no such parts.
  function turnsOf(pane) {
    return pane === "margin" ? (root.talkOpen ? root.talkStream : root.marginStream.map(function (r) { return r.turn || {} }))
      : root.historyTurns.length > 0 ? root.historyTurns.concat(root.dayTurns) : root.dayTurns
  }
  function answerParts(pane, t) {
    if (!t || t.role !== "agent" || !/(^|\n)> \S/.test(t.text || "")) return null
    var turns = root.turnsOf(pane), at = -1
    for (var i = turns.length - 1; i >= 0; i--)
      if (turns[i] && turns[i].role === "agent" && turns[i].at === t.at && turns[i].text === t.text) { at = i; break }
    var asked = null
    for (var k = at - 1; k >= 0 && !asked; k--) if (turns[k] && turns[k].role !== "agent") asked = turns[k]
    var replies = asked ? root.passageParts(asked.text).filter(function (x) { return x.quote !== "" }) : []
    if (replies.length === 0) return null
    // The answer, cut at its quote lines.
    var intro = [], parts = [], cur = null
    String(t.text).split("\n").forEach(function (line) {
      var m = /^> ?(.*)$/.exec(line)
      if (m) {
        if (!cur || cur.text.trim() !== "") { cur = { quote: "", text: "" }; parts.push(cur) }
        cur.quote = (cur.quote ? cur.quote + " " : "") + m[1].trim()
      } else if (cur) cur.text = cur.text === "" ? line : cur.text + "\n" + line
      else intro.push(line)
    })
    if (parts.length === 0) return null
    var used = {}
    parts.forEach(function (p, i) {
      var want = root.plainWords(p.quote).replace(/[ .,;:…]+$/, "")
      var hit = -1
      for (var r = 0; r < replies.length && hit < 0; r++) {
        var q = root.plainWords(replies[r].quote)
        if (!used[r] && want !== "" && (q.indexOf(want) === 0 || q.indexOf(want) >= 0 || want.indexOf(q) >= 0)) hit = r
      }
      for (var r2 = 0; r2 < replies.length && hit < 0; r2++) if (!used[r2]) hit = r2
      if (hit >= 0) { used[hit] = true; p.n = hit + 1; p.reply = replies[hit].text; p.passage = replies[hit].quote }
      else { p.n = 0; p.reply = ""; p.passage = p.quote }
      p.text = p.text.trim()
    })
    return { intro: intro.join("\n").trim(), parts: parts }
  }
  // A part's bubble under the pointer: the passage it answers lit in the
  // answer it came from, nothing scrolled, nothing moved.
  property var hoverQuote: null        // { pane, quote }
  // The earlier days' answers too: a reply to yesterday's lost its number
  // there once sent.
  readonly property var daySent: root.sentOf(root.turnsOf("day"))
  readonly property var marginSent: root.sentOf(root.talkOpen ? root.talkStream : root.marginStream.map(function (r) { return r.turn || {} }))
  // A sent message read back as its parts: { quote, text } each.
  function passageParts(text) {
    var parts = [], cur = null
    String(text || "").split("\n").forEach(function (line) {
      var m = /^> ?(.*)$/.exec(line)
      if (m) {
        if (!cur || cur.text !== "") { cur = { quote: "", text: "" }; parts.push(cur) }
        cur.quote = (cur.quote ? cur.quote + " " : "") + m[1].trim()
      } else {
        if (!cur) { cur = { quote: "", text: "" }; parts.push(cur) }
        cur.text = cur.text === "" ? line : cur.text + "\n" + line
      }
    })
    parts.forEach(function (x) { x.text = x.text.trim() })
    return parts.filter(function (x) { return x.quote !== "" || x.text !== "" })
  }
  // A quote followed back: the agent's answer it came from, lit a moment
  // and shown (Turn.qml), found by its words.
  property string litPassage: ""
  Timer { id: litPassageTimer; interval: 2600; onTriggered: root.litPassage = "" }
  function plainWords(s) {
    return String(s || "").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/[*_`#>]/g, "").replace(/\s+/g, " ").trim().toLowerCase()
  }
  property string litQuote: ""          // the words followed back, for the part of a split answer that has them
  function showPassage(pane, quote) {
    var turns = root.turnsOf(pane)
    var want = root.plainWords(quote).replace(/ …$/, "")
    for (var i = turns.length - 1; i >= 0; i--) {
      var t = turns[i]
      if (t && t.role === "agent" && t.at && root.plainWords(t.text).indexOf(want) >= 0) {
        // In an earlier session folded away: unfolded first, so it can be
        // shown. Followed again while still lit: shown again.
        var inDay = pane === "day" ? i - (root.historyTurns.length > 0 ? root.historyTurns.length : 0) : -1
        var unfold = inDay >= 0 && dayPane.folded && inDay < dayPane.earlier
        if (unfold) dayPane.earlierOpen = true
        var lit = t.at + "|" + pane
        root.litPassage = ""
        root.litQuote = want
        var show = function () { root.litPassage = lit; litPassageTimer.restart() }
        if (unfold) Qt.callLater(show); else show()
        root.used("answer", "followed")
        return
      }
    }
    root.showHint("that answer is not in this chat")
  }
  // Ctrl+R in a box: answer the words selected in one of the agent's answers.
  function answerSelected(event) {
    if (!Sc.hit(event, "chatAnswer")) return false
    var s = root.chatSelection
    // Words left selected in a chat since closed or turned away from are
    // not what Ctrl+R means (2026-11-28: it attached a reply in the hidden
    // pane and took the keys into it).
    if (!s || !s.visible || s.selectedText === "" || !s.parent || !s.parent.answerSelection) return false
    return s.parent.answerSelection()
  }
  // The same two keys from the panes beside a chat that hold the keys
  // themselves — the PDF, a paper's marks (2026-11-19): words dragged over
  // in an answer leave the keys where they were, so Ctrl+R and Ctrl+C on
  // them did nothing there. `hasOwn`: that pane has words of its own
  // selected, which Ctrl+C leaves alone.
  function chatSelectionKey(event, hasOwn) {
    if (!hasOwn && root.copyChatSelection(event, null)) return true
    return root.answerSelected(event)
  }

  function taskName(t) { return String((t && (t.title || t.text)) || "").replace(/\s+/g, " ").trim() }
  // What was left out of an answer, as the student would say it: the
  // runner keeps it in its own words for the agent ("do-date · no such
  // box", "move deadline #7 …"); here, what it would have done.
  function sayLeftOut(list) {
    var words = { "do-date": "a day for", "drop": "dropping", "deadline": "a deadline for", "priority": "a priority for",
                  "steps": "steps for", "done": "ticking", "task": "adding", "project": "the project", "undone": "reopening" }
    return (list || []).map(function (s) {
      s = String(s)
      if (/^move deadline/.test(s)) return "moving a deadline that is not open, or to a day it cannot have"
      if (/^not filed: /.test(s)) return s
      var m = /^([\w-]+) · (.*)$/.exec(s)
      if (!m) return s
      var what = m[2]
      if (/^deadline #\d+$/.test(what)) return (words[m[1]] || m[1]) + " a deadline that is not open"
      if (/^no such box$/.test(what)) return (words[m[1]] || m[1]) + " a box that is not on the list"
      return (words[m[1]] || m[1]) + " “" + what + "”"
    }).join("; ")
  }
  function sayChip(r) { return (r.kind || "block") + " · " + (r.head || "a block") }
  property var dayPending: null         // { text, block }: sent, its turn not written yet
  // A note's own conversation (docs/files.md, "Talking about a note",
  // 2026-10-27): the same pane and view, another room. What the agent does
  // not otherwise see — a file, a day before the horizon, a day marked
  // private — it may be asked about, and asking is the consent. The runner
  // keeps it in the agent's folder by the md5 of the note's path; the page
  // only reads it, and the note is never written.
  property bool noteRoom: false
  readonly property string noteRel: svc.filePath !== "" ? svc.filePath
    : svc.noteDate !== "" && svc.configured ? String(svc.config.daily.dir).replace(/^\/+|\/+$/g, "") + "/" + svc.noteDate + ".md" : ""
  readonly property bool noteAskable: root.paper.shown ? root.paper.askable
    : svc.ready && root.noteRel !== "" && !root.pageOutside && (!root.dayNote || root.beforeHorizon || svc.notePrivate)
  // A note written outside the vault (a project's page): read, never asked
  // about or exported — it is gathered from notes that are.
  readonly property bool pageOutside: Links.isAbs(svc.filePath)
  // What the room talks about: the PDF open in the vault (plan.md item 15,
  // step 2), else the note.
  readonly property string roomRel: root.paneHeld !== "" ? root.paneHeld : root.paper.shown ? root.pdfRel : root.noteRel
  // The room's name in the pane: the middle's, or the one held there.
  readonly property string roomLabel: root.paneHeld === "" ? root.noteLabel : root.paneHeld.replace(/^.*\//, "").replace(/\.(md|pdf)$/i, "")
  readonly property string noteTalkPath: svc.agentDir !== "" && root.roomRel !== ""
    ? svc.agentDir + "/notes/" + Qt.md5(root.roomRel).slice(0, 16) + ".json" : ""
  property var noteTalk: null
  onNoteTalkPathChanged: if (root.noteTalkPath === "") root.noteTalk = null
  readonly property int noteTalkTurns: root.noteTalk && root.noteTalk.turns ? root.noteTalk.turns.length : 0

  // Read through the function, never the binding, from a handler of the
  // state (AgentState.qml): there the binding is still the state before.
  function dayStateNow() { return root.noteRoom ? root.noteTalk : agent.state && agent.state.day ? agent.state.day : null }
  readonly property var dayState: root.dayStateNow()
  readonly property var dayTurns: {
    var t = root.dayState && root.dayState.turns ? root.dayState.turns.slice() : []
    // Only in the chat it was sent in: switching from one note's chat to
    // another's drew it in both.
    var p = root.dayPending
    if (p && p.room === root.roomHash && (svc.isToday || root.noteRoom))
      t.push({ role: "student", text: p.text, block: p.block, marks: p.marks, refs: p.refs })
    return t
  }
  // The morning's observation is the conversation's opening line, waiting.
  readonly property var dayOpening: {
    if (root.noteRoom) return []
    var obs = agent.state && agent.state.observations ? agent.state.observations : []
    return obs.filter(function (o) { return o && o.text && o.trigger === "open" }).map(function (o) { return { text: o.text, at: String(o.at || "") } })
  }
  // What the agent said unasked on opening the page, in its place among
  // the day's turns (slice 3 of "One conversation": one voice, every word of
  // it a turn to answer): before turn `i`, after the one before it; `i`
  // past the last, those said since.
  function openingBefore(i) {
    var turns = root.dayTurns
    // Each goes before the first turn said after it (a turn not yet
    // written, no time: after everything), so each is shown once.
    return root.dayOpening.filter(function (o) {
      var at = turns.length
      for (var k = 0; k < turns.length; k++) if (String(turns[k].at || "9") > o.at) { at = k; break }
      return at === i
    })
  }

  readonly property string roomHash: root.noteRoom ? "note:" + root.roomRel : "day"
  readonly property bool dayThinking: (root.runningHash === root.roomHash && !root.runAnswered)
    || root.queued.some(function (q) { return q.hash === root.roomHash })
  readonly property bool dayCanSend: root.noteRoom ? root.paneHeld !== "" || root.noteAskable : svc.isToday && root.agentDay && !root.beforeHorizon
  readonly property bool dayShown: root.dayOpen && !root.marginOpen && !root.talkOpen && !root.keysOpen && !root.settingsOpen
  readonly property bool dayBesideNote: root.dayShown && !root.dashOpen
  readonly property bool dayBesideDash: root.dayShown && root.dashOpen

  function toggleDay(block) {
    if (root.dayShown && block === "") { root.closeDay(); return }
    root.openDay(block)
  }

  // A file has no day: its pane is its own conversation.
  function openDay(block) {
    root.openRoom(block, root.paper.shown ? root.paper.askable : !root.dayNote)
  }

  // "ask about this note" in the header, and the agent's pane on a file.
  function openRoom(block, note) {
    note = !!note
    if (note && !root.noteAskable) return
    if (!root.dashOpen && root.marginWidth <= 0) { root.showHint("the window is too narrow for the agent's pane"); return }
    root.ensureRoomFor("right")
    if (root.here !== "right") root.noteFrom("right", root.keysOpen || root.settingsOpen ? "center" : root.here)
    if (root.keysOpen) root.toggleKeys()
    if (root.settingsOpen) root.toggleSettings()
    root.marginOpen = false
    root.marginFocus = -1
    root.closeTalk(false)
    if (note !== root.noteRoom) { root.dayPending = null; root.dayRefs = []; root.dayAutoHeld = null; root.paper.marks = []; root.clearReplies("day") }
    root.noteRoom = !!note
    root.paneHeld = ""
    root.paneSubject = note ? root.roomRel : ""
    root.paneFollows = false                     // chosen: nothing left to follow
    if (note) root.loadRefFiles()                // what `@` offers there: other notes and papers
    root.dayOpen = true
    if (block) {
      var b = root.blockBounds(block)
      if (b) root.addDayRef({ date: root.noteRoom ? "" : svc.noteDate, hash: block, head: root.blockHead(block),
                              kind: /^\s*[-*+] \[.\] /.test(b.text.split("\n")[0]) ? "task" : "block" })
    }
    root.used(note ? (root.paper.shown ? "paper-talk" : "note-talk") : "day", block ? "block" : "")
    if (root.paper.room && root.paper.listing) Qt.callLater(function () { dayPane.paperKeysRef.forceActiveFocus() })
    else Qt.callLater(function () { dayPane.dayFieldRef.forceActiveFocus() })
  }

  function dayFieldItem() { return dayPane.dayFieldRef }
  // Where the keys go in the day's pane: the box, or the paper's list.
  function dayKeysItem() { return root.paper.room && root.paper.listing ? dayPane.paperKeysRef : dayPane.dayFieldRef }

  // A block's first words, for the "↳" a message carries; "a block" when
  // the note no longer has it as it was.
  function blockHead(hash) {
    var b = root.blockBounds(hash)
    // Its words, without the facts on its line (dates, priority, a
    // deadline's mark).
    return b ? b.text.split("\n")[0].replace(/^\s*([-*+] (\[.\] )?|#+ )/, "")
      .replace(/\s*(📅|⏳|✅|➕|❌)\s*\d{4}-\d{2}-\d{2}( \d{1,2}:\d{2})?/g, "").replace(/\s*(⏫|🔼|🔽|⏬)/g, "")
      .replace(/\s*\^d\d+\b/g, "").replace(/\s+/g, " ").trim().slice(0, 80) : "a block"
  }

  function closeDay() {
    var was = root.here
    root.dayOpen = false
    root.noteRoom = false
    root.dayRefs = []
    root.dayAutoHeld = null
    root.giveBack("right", was, "right")
  }

  // Stopping the agent mid-answer (2026-11-18, plan item 22's "stop"):
  // Esc while it thinks, or a click on "thinking". The run ends (the runner
  // takes SIGTERM as a stop: the model's process ended, the run logged as
  // stopped, no turn written), or a message still queued is taken out; what
  // was sent goes back in the box, to change and send again. `where`: the
  // pane — "day" (the day's, a note's or a paper's chat), "margin" (a
  // block's), "talk" (a task's or a proposal's, beside the dashboard).
  property bool runnerStopAsked: false
  property bool talkStopAsked: false
  function agentBusy(where) {
    if (where === "talk") return talkProc.running
    var ids = where === "day" ? [root.roomHash] : [root.currentHash, root.currentRec]
    ids = ids.filter(function (x) { return x !== "" })
    var hit = function (h) { return String(h || "").split(",").some(function (x) { return ids.indexOf(x) >= 0 }) }
    return (root.running && !root.runAnswered && hit(root.runningHash)) || root.queued.some(function (q) { return hit(q.hash) })
  }
  function stopAgent(where) {
    if (!root.agentBusy(where)) return false
    var pending = null
    if (where === "talk") {
      pending = root.pendingTalk
      root.pendingTalk = null
      root.talkStopAsked = true
      talkProc.signal(15)
    } else {
      var ids = where === "day" ? [root.roomHash] : [root.currentHash, root.currentRec]
      var hit = function (h) { return String(h || "").split(",").some(function (x) { return x !== "" && ids.indexOf(x) >= 0 }) }
      root.queued = root.queued.filter(function (q) { return !hit(q.hash) })
      if (root.running && hit(root.runningHash)) { root.runnerStopAsked = true; runner.signal(15) }
      if (where === "day") { pending = root.dayPending; root.dayPending = null }
      else {
        pending = root.pendingChat
        root.pendingChat = null
        root.sending = root.sending.filter(function (h) { return ids.indexOf(h) < 0 })
        root.scheduleRepaint()
      }
    }
    root.thinkHeld = ""
    var back = root.giveBackSent(where, pending)
    root.showHint(back ? "stopped — what you wrote is back in the box" : "stopped")
    root.used("stop", where)
    return true
  }
  // What was sent and never answered — stopped, or the run failed — back
  // in its box: the words (before what was typed since, never in place of
  // it), the replies, the chips, a paper's marks, the names `@` put in the
  // words. One way back for every way a message can fail to land
  // (2026-11-28, the agent pane pass: a failed run used to lose them).
  // True when anything came back.
  function giveBackSent(where, pending) {
    if (!pending) return false
    var field = where === "day" ? dayPane.dayFieldRef : margin.chatFieldRef
    var pane = where === "day" ? "day" : "margin"
    var text = pending.raw !== undefined ? pending.raw : pending.text
    var back = false
    if (text !== "" && field) {
      var had = String(field.text)
      if (had.trim() === "") { field.text = text; field.cursorPosition = text.length }
      else field.insert(0, text + "\n")
      if (pending.mentions && pending.mentions.length > 0) field.mentions = field.mentions.concat(pending.mentions)
      back = true
    }
    if (pending.replies && pending.replies.length > 0) {
      root.setReplies(pane, pending.replies.concat(root.repliesOf(pane)))
      back = true
    }
    var merged = function (a, b) {
      var seen = {}, out = []
      a.concat(b).forEach(function (r) { var k = root.refKey(r); if (!seen[k]) { seen[k] = true; out.push(r) } })
      return out
    }
    if (pending.savedRefs && pending.savedRefs.length > 0) {
      if (where === "day") root.dayRefs = merged(pending.savedRefs, root.dayRefs)
      else root.marginRefs = merged(pending.savedRefs, root.marginRefs)
      back = true
    }
    if (where === "day" && root.paper.room && pending.marks && pending.marks.length > 0) {
      root.paper.marks = pending.marks.concat(root.paper.marks.filter(function (m) { return pending.marks.indexOf(m) < 0 }))
      back = true
    }
    return back
  }
  // "thinking" is seen for a moment at least, however soon a run ends: a
  // message that failed in a second once looked as if it never went.
  property string thinkHeld: ""
  Timer { id: thinkHoldTimer; interval: 700; onTriggered: root.thinkHeld = "" }
  function holdThinking(where) { root.thinkHeld = where; thinkHoldTimer.restart() }

  function sendDay(text) {
    // One message at a time (2026-11-28): a second, sent while the first
    // was answered, took its place on screen and Esc stopped both.
    if (root.dayThinking && String(text || "").trim() !== "") {
      root.showHint("the agent is still answering · " + root.keyName("marginBack") + " stops it")
      return false
    }
    var msg = root.composed("day", text)
    if (msg === "" || !root.dayCanSend) return false
    var mentions = dayPane.dayFieldRef.liveMentions.slice()
    var savedReplies = root.dayReplies.slice()
    var savedRefs = root.dayRefs.slice()
    root.clearReplies("day")
    var cmd = root.noteRoom ? [svc.runner, "note", "--file", root.roomRel, "--message", msg] : [svc.runner, "day", "--message", msg]
    var chips = root.noteRoom ? savedRefs : root.dayChips.slice()
    if (root.noteRoom) {
      if (root.dayBlock !== "") cmd = cmd.concat(["--block", root.dayBlock])
      var others = chips.filter(function (r) { return !!r.file })
      if (others.length > 0) cmd = cmd.concat(["--refs", JSON.stringify(others.map(function (r) { return { file: r.file } }))])
    }
    else if (chips.length > 0)
      cmd = cmd.concat(["--refs", JSON.stringify(chips.map(function (r) {
        var o = r.file ? { file: r.file } : r.hash ? { date: r.date, hash: r.hash } : { date: r.date, line: r.line }
        if (r.auto) o.auto = true                  // the chip that followed the cursor: the agent is told
        return o
      }))])
    var marks = root.paper.room ? root.paper.marks.slice() : []
    if (marks.length > 0) cmd = cmd.concat(["--marks", marks.join(",")])
    root.paper.marks = []
    var turnsNow = root.dayStateNow()
    root.dayPending = { text: msg, raw: String(text || ""), replies: savedReplies, savedRefs: savedRefs, mentions: mentions,
                        block: root.dayBlock, marks: marks, room: root.roomHash,
                        base: turnsNow && turnsNow.turns ? turnsNow.turns.length : 0,
                        refs: chips.map(function (r) { return { date: r.date || "", hash: r.hash || "", file: r.file || "", kind: r.kind, head: r.head } }) }
    if (chips.length > 0) root.used("chip", "sent-" + chips.length + (chips[0].auto ? "-auto" : ""))
    root.dayRefs = []
    root.dayAutoHeld = null
    root.flush()
    root.enqueue(cmd, root.roomHash)
    root.holdThinking("day")
    root.used(root.noteRoom ? "note-talk" : "day", "send")
    return true
  }

  // The runner has written the turn the page was holding. Called from the
  // state's own change, so it reads the state now, not `dayState`: that
  // binding still held the state before, the turn was not found, and the
  // held message stayed drawn under its answer (2026-11-19, the runner
  // writing the question and the answer in one save).
  function settleDay() {
    var p = root.dayPending
    var st = root.dayStateNow()
    if (!p || !st) return
    if (p.room !== root.roomHash) return
    var turns = st.turns || []
    // Only among the turns written since it was sent: an earlier "yes"
    // read again mid-run was taken for it, and "thinking" went away.
    for (var i = turns.length - 1; i >= Math.min(p.base || 0, turns.length); i--)
      if (turns[i].role === "student" && turns[i].text === p.text) {
        root.dayPending = null
        if (root.running && root.runningHash === root.roomHash && turns[i + 1]) root.runAnswered = true
        root.openFromTurn(turns[i + 1])
        return
      }
  }

  // What the agent opened for the student (slice 4 of "One conversation":
  // done at once): a note, a paper, a day, a task — when the answer that
  // says so arrives, never again on a later read. The pane stays; going
  // back is the history's, as after any opening.
  function openFromTurn(turn) {
    var o = turn && turn.role === "agent" && turn.open && turn.open[0]
    if (!o) return
    root.used("open", o.kind)
    if (o.kind === "file") { if (/\.pdf$/i.test(o.rel)) root.openPdf(o.rel); else root.openFile(o.rel, false) }
    else if (o.kind === "day") root.openNote(o.date)
    else if (o.kind === "task") {
      var t = root.taskOfKey(o.key)
      if (t && t.date) root.openNote(t.date)
    }
    root.showHint("opened " + (o.name || o.rel || o.date || ""))
  }

  // `@` in the day's box points at a block of the open note, as `@` in the
  // note calls a project: the list narrows as you type, newest writing
  // first, never a private block; Enter or Tab makes it the "↳" the next
  // message carries.
  property var dayMention: null         // { start, query, items: [{ hash, head }], margin }
  property int dayMentionFocus: 0
  // What a task's or a block's chat points at besides its own thing (its
  // chips after the fixed one): `@` adds tasks, notes and papers there too
  // (slice 2 of "One conversation").
  property var marginRefs: []
  readonly property bool marginCanPoint: root.marginOpen || (root.talkOpen && !root.talkToPlanner)
  // `@` and words nothing is called (2026-11-28): Enter sent "@typo" to the
  // agent, the list gone without a word. The first Enter closes the list
  // and says so; the next sends what is written, as written.
  function mentionNothing(event) {
    var m = root.dayMention
    if (!m || m.items.length > 0) return false
    if (Sc.hit(event, "mentionClose")) { root.dayMention = null; return true }
    if (!Sc.hit(event, "chatSend")) return false
    root.dayMention = null
    root.showHint("nothing here is called “@" + m.query + "” · " + root.keyName("chatSend") + " again sends it as written")
    return true
  }
  function updateMarginMention() { root.updateDayMention(true) }
  function updateDayMention(inMargin) {
    inMargin = inMargin === true
    var f = inMargin ? margin.chatFieldRef : dayPane.dayFieldRef
    if (!inMargin && root.paper.room) { root.paper.updateMention(); return }
    var m = f.text.substring(0, f.cursorPosition).match(/(^|\s)@([^\s@]*)$/)
    if (!m || (inMargin ? !root.marginCanPoint : !root.dayCanSend)) { root.dayMention = null; return }
    var q = m[2].toLowerCase()
    // Beside the dashboard the note in the sheet is not what is talked
    // about: its blocks are offered only from the note.
    var noteBlocks = !inMargin || (root.marginOpen && root.centerView === "note" && root.dayNote)
    var blockCap = q === "" ? (root.noteRoom ? 5 : 4) : (root.noteRoom ? 8 : 5)
    var items = (noteBlocks ? Blocks.split(editor.text) : []).filter(function (b) {
      return !b.private && b.kind !== "frontmatter" && b.text.trim() !== "" && (q === "" || b.text.toLowerCase().indexOf(q) >= 0)
    }).reverse().slice(0, blockCap).map(function (b) {
      return { hash: b.hash, head: root.blockHead(b.hash), kind: /^\s*[-*+] \[.\] /.test(b.text.split("\n")[0]) ? "task" : "block" }
    })
    // …and, in the day's chat, the open tasks of other days (slice 2 of
    // "One conversation"): a task is talked about from anywhere.
    if (inMargin || !root.noteRoom) {
      var seen = {}
      var taskCap = q === "" ? Math.max(0, 6 - items.length) : Math.max(0, 8 - items.length)
      items = items.concat(root.tasks.filter(function (t) {
        var name = root.taskName(t)
        if (!t.key || t.private || !t.date || t.date === svc.noteDate || seen[t.key] || name === "") return false
        if (q !== "" && name.toLowerCase().indexOf(q) < 0) return false
        seen[t.key] = true
        return true
      }).slice(0, taskCap).map(function (t) {
        var name = root.taskName(t).slice(0, 80)
        return { task: t, name: name, head: "task · " + name }
      }))
    }
    // …and the notes and papers it may see (shown on bare `@` too so papers
    // and notes are discoverable without already knowing their filenames).
    if (items.length < 8)
      items = items.concat(root.refFiles.filter(function (f) {
        return (inMargin || !root.noteRoom || f.rel !== root.roomRel) && (q === "" || root.refMatches(f, q))
      }).slice(0, 8 - items.length).map(root.refItem))
    root.dayMention = { start: f.cursorPosition - m[2].length - 1, query: m[2], items: items, margin: inMargin }
    if (root.dayMentionFocus > items.length - 1) root.dayMentionFocus = Math.max(0, items.length - 1)
  }
  function addMarginRef(r) {
    var k = root.refKey(r)
    if (root.marginRefs.some(function (x) { return root.refKey(x) === k })) return
    root.marginRefs = root.marginRefs.concat([r]).slice(-5)
  }
  function pickDayMention(i) {
    var m = root.dayMention
    var it = m && m.items[i]
    if (!it) return
    if (it.mark && !m.margin) {
      dayPane.dayFieldRef.remove(m.start, dayPane.dayFieldRef.cursorPosition)
      root.paper.attach(it.mark)
      root.dayMention = null
      root.used("paper-talk", "caret")
      return
    }
    var f = m.margin ? margin.chatFieldRef : dayPane.dayFieldRef
    var add = m.margin ? root.addMarginRef : root.addDayRef
    // A paper or a note keeps its name in the sentence, tied to its chip
    // (ChatField); a block or a task, whose head is a passage, the chip only.
    if (it.file) {
      var r = { file: it.file, head: it.name, kind: it.kind }
      add(r)
      f.pickMention(m.start, f.cursorPosition, it.name, root.refKey(r), m.query)
      root.dayMention = null
      root.used("day", "at-" + it.kind)
      return
    }
    f.remove(m.start, f.cursorPosition)
    if (it.task) add({ date: it.task.date, line: it.task.line, head: it.name, kind: "task" })
    else add({ date: root.noteRoom ? "" : svc.noteDate, hash: it.hash, head: it.head, kind: it.kind || "block" })
    root.dayMention = null
    root.used("day", it.task ? "at-task" : "at")
  }

  // The cards under the day's answers (slice 3): what it proposed, the
  // same items as the dashboard's rows, checked and recorded by the runner.
  // A card is open while the dashboard still has its item; once settled —
  // here, on its row, or by a plan since — it stays, faint, saying how.
  property var dayCardSettled: ({})     // id -> "accepted" | "declined" | "undone" | "kept"
  property var cardUndoMap: ({})        // id -> proposal snapshot (with prior `was`) for inline + Ctrl+Z undo
  property var cardUndoStack: []        // newest-last list of undoable accepted proposal ids
  property var declinedBlockCards: ({}) // "hash:index" -> true for non-ledger block cards declined in Margin
  property int dayCardFocus: -1         // which open card the keys act on; -1: the box

  function cardCanUndo(id) { return !!id && !!root.cardUndoMap[id] }
  function cardUndoIsLast(id) {
    return !!id && root.cardUndoStack.length > 0 && root.cardUndoStack[root.cardUndoStack.length - 1] === id
  }
  function blockCardDeclined(hash, idx) { return !!root.declinedBlockCards[String(hash || "") + ":" + String(idx)] }
  function dropCardUndo(id) {
    if (!root.cardUndoMap[id]) return
    var m = {}
    for (var k in root.cardUndoMap) if (String(k) !== String(id)) m[k] = root.cardUndoMap[k]
    root.cardUndoMap = m
    root.cardUndoStack = root.cardUndoStack.filter(function (x) { return x !== id })
  }
  function undoSettledCard(id) {
    var snap = root.cardUndoMap[id]
    if (!snap) return false
    root.undoProposal(snap)
    var s = {}
    for (var k in root.dayCardSettled) s[k] = root.dayCardSettled[k]
    s[id] = "undone"
    root.dayCardSettled = s
    root.dropCardUndo(id)
    root.used("card", "undo")
    root.showHint("undone: " + root.dayCardKind(snap))
    return true
  }
  function undoLastCard() {
    if (root.cardUndoStack.length === 0) return false
    return root.undoSettledCard(root.cardUndoStack[root.cardUndoStack.length - 1])
  }
  function dayCardLive(c) {
    for (var i = 0; i < root.proposals.length; i++) if (root.proposals[i].id === c.id) return root.proposals[i]
    return null
  }
  function dayCardState(c, at) {
    var live = root.dayCardLive(c)
    if (live) return live.told ? "done by itself" : "open"
    if (root.dayCardSettled[c.id]) return root.dayCardSettled[c.id]
    // Made after the list on screen was read: not settled, just not seen yet.
    return at && String(at) >= root.proposalsReadAt ? "arriving" : "settled"
  }
  readonly property var dayOpenCards: {
    var out = [], seen = {}
    var turns = root.dayTurns
    for (var t = 0; t < turns.length; t++) {
      var cards = turns[t].proposals || []
      for (var c = 0; c < cards.length; c++) {
        var live = root.dayCardLive(cards[c])
        if (live && !seen[live.id]) { seen[live.id] = true; out.push(live) }
      }
    }
    return out
  }
  function dayCardKind(x) {
    return ({ "do-date": "a day for it", "deadline": "a deadline", "priority": "priority", "steps": "first steps",
              "drop": "drop it", "done": x.auto || x.told ? "ticked" : "looks done", "project": "a new project",
              "task": "a new task", "move": "move the deadline", "undone": "reopened" })[x.kind] || x.kind
  }
  // What a card says beside its pill: the box, and what changes in it.
  function dayCardFacts(x) {
    if (x.kind === "priority") return (x.priority === 2 ? "▲ high" : x.priority === 1 ? "medium" : "▽ low") + " · " + (x.title || "")
    if (x.kind === "steps") return (x.title || "") + (x.steps || []).map(function (s, i) { return "\n" + (i + 1) + ". " + s }).join("")
    if (x.kind === "project") return (x.title || "") + " #" + x.project
    if (x.kind === "task") return (x.title || "") + (x.project ? " #" + x.project : "") + " · in today's note"
    if (x.kind === "move") return (x.title || "its deadline") + (x.was ? " · was " + Say.sayDate(x.was.slice(0, 10)) : "")
    return x.title || ""
  }
  function dayCardPill(x) {
    return x.kind === "do-date" && x.date ? "do " + Say.sayDate(x.date)
      : (x.kind === "deadline" || x.kind === "move") && x.date ? "📅 " + Say.sayDate(x.date) : ""
  }
  // One of the list's items, settled from a card — in the day's
  // conversation or a block's (2026-11-15) — as from its row: false when
  // it could not be (its box is not on the list any more).
  function settleCard(p, how) {
    var s = {}
    for (var k in root.dayCardSettled) s[k] = root.dayCardSettled[k]
    if (how === "accept" && p.told) {
      root.resolveProposal(p, "accept", "")              // what it did on its own: let it stand
      s[p.id] = "kept"
      root.dropCardUndo(p.id)
    } else if (how === "accept") {
      // Written by the page, the one writer of notes, as from its row; a
      // box no longer on the list leaves the card open, and says so.
      var t = p.key ? root.taskOfKey(p.key) : null
      var snap = Object.assign({}, p)
      if (p.kind === "do-date" && t && snap.was === undefined) snap.was = t.when || ""
      else if (p.kind === "priority" && t && snap.was === undefined) snap.was = t.priority || 0
      if (!root.applyProposal(p, t)) return false
      root.resolveProposal(p, "accept", "")
      s[p.id] = "accepted"
      if (p.kind !== "project") {
        var um = {}
        for (var u in root.cardUndoMap) um[u] = root.cardUndoMap[u]
        um[p.id] = snap
        root.cardUndoMap = um
        root.cardUndoStack = root.cardUndoStack.filter(function (x) { return x !== p.id }).concat([p.id])
      }
    } else if (p.told) {
      root.undoProposal(p)
      s[p.id] = "undone"
      root.dropCardUndo(p.id)
    } else {
      root.resolveProposal(p, "decline", "")
      s[p.id] = "declined"
      root.dropCardUndo(p.id)
    }
    root.dayCardSettled = s
    return true
  }
  function settleDayCardById(id, how) {
    var p = root.dayCardLive({ id: id })
    if (!p || !root.settleCard(p, how)) return
    root.used("day", "card-" + how)
    Qt.callLater(function () {
      var n = root.dayOpenCards.length
      root.dayCardFocus = n === 0 ? -1 : Math.min(root.dayCardFocus, n - 1)
    })
  }
  function settleDayCard(i, how) {
    var p = root.dayOpenCards[i]
    if (!p || !root.settleCard(p, how)) return
    root.used("day", "card-" + how)
    Qt.callLater(function () {
      var n = root.dayOpenCards.length
      root.dayCardFocus = n === 0 ? -1 : Math.min(root.dayCardFocus, n - 1)
    })
  }

  // The student's word on an answer in the day's conversation, as on a
  // reply in the margin: shown at once, kept on the turn by the runner with
  // the prompt and model that made it, read by the weekly review.
  // The day's answers and a note's (its room) are rated alike: the word
  // shows at once, and the runner keeps it on the turn.
  property var dayRatingNow: ({})       // "<note date>#<turn>" or "note:<path>#<turn>" -> "up" | "down" | "none", until the state says so
  function ratingKey(i) { return (root.noteRoom ? "note:" + root.roomRel : svc.noteDate) + "#" + i }
  function dayRatingOf(i) {
    var now = root.dayRatingNow[root.ratingKey(i)]
    if (now !== undefined) return now === "none" ? "" : now
    var t = root.dayState && root.dayState.turns ? root.dayState.turns[i] : null
    return t && t.rating ? t.rating.value : ""
  }
  function rateDay(i, value) {
    if (root.noteRoom && root.roomRel === "") return
    var turns = root.dayState && root.dayState.turns ? root.dayState.turns : []
    if (i < 0) for (var k = turns.length - 1; k >= 0 && i < 0; k--) if (turns[k].role === "agent" && !turns[k].error) i = k
    if (i < 0 || !turns[i] || turns[i].role !== "agent" || turns[i].error) return
    var v = root.dayRatingOf(i) === value ? "none" : value
    var m = {}
    for (var j in root.dayRatingNow) m[j] = root.dayRatingNow[j]
    m[root.ratingKey(i)] = v
    root.dayRatingNow = m
    if (root.noteRoom) root.runInTurn(rateProc, [svc.runner, "rate", v, "--note", root.roomRel, "--turn", String(i)])
    else root.runInTurn(rateProc, [svc.runner, "rate", v, "--day", String(i), "--date", svc.noteDate])
    root.used("rate", (root.noteRoom ? "note-" : "day-") + v)
  }

  // The words last selected in a conversation (ChatTurn): one selection
  // across the panes at a time, copied with Ctrl+C from wherever the keys
  // are in the pane — the turns never take them — unless the box has a
  // selection of its own.
  property Item chatSelection: null
  function chatSelected(edit) {
    if (root.chatSelection && root.chatSelection !== edit) root.chatSelection.deselect()
    root.chatSelection = edit
  }
  // A press anywhere in the page, at its place in the window: a box asking
  // something ("when?", "name?", the dashboard's, the PDF's) closes when the
  // press is outside it, as Esc does, the keys left where the click puts
  // them (2026-11-25, the mouse pass). Only what was open at the press, and
  // after the click is done, so a click that opens one does not close it.
  signal pressedAt(point at)
  onPressedAt: function (at) {
    var out = function (item) {
      if (!item || !item.visible) return true
      var q = item.mapFromItem(null, at.x, at.y)
      return q.x < 0 || q.y < 0 || q.x > item.width || q.y > item.height
    }
    // The `@` lists too, outside the list and the box typed in, and the
    // sidebar's "new project" (the second pass, 2026-11-25).
    var dm = root.dayMention
    var dmBox = dm ? (dm.margin ? margin.chatFieldRef : dayPane.dayFieldRef) : null
    var dmList = dm ? (dm.margin ? margin.mentionListRef : dayPane.mentionListRef) : null
    var was = { when: root.whenFor && out(whenBox) ? root.whenFor : null,
                name: root.newProject && out(nameBox) ? root.newProject : null,
                dash: root.dashWhenFor && out(dash.dashWhenRowRef) ? root.dashWhenFor : null,
                mention: root.mention && out(mentionBox) && out(editor) ? root.mention : null,
                dayMention: dm && out(dmBox) && out(dmList) ? dm : null,
                project: root.addingProject && out(sidebar.projectAskRef),
                strip: root.stripOpen && out(dash.unfoldedRef) }
    Qt.callLater(function () {
      if (was.when && root.whenFor === was.when) root.whenFor = null
      if (was.name && root.newProject === was.name) root.newProject = null
      if (was.dash && root.dashWhenFor === was.dash) { root.dashWhenFor = null; root.dashWhenText = "" }
      if (was.mention && root.mention === was.mention) root.mention = null
      if (was.dayMention && root.dayMention === was.dayMention) root.dayMention = null
      if (was.project && root.addingProject) root.addingProject = false
      if (was.strip) root.foldStrip()
    })
  }

  // The mouse's menu on words, for the chats' turns (ChatTurn.qml).
  function editMenuAt(over, x, y, list) { editMenu.openAt(over, x, y, list) }
  // A dashboard row's (2026-11-25, the second pass): what its keys do, so
  // rename, priority, set aside and the rest, keys only until then, are a
  // right click away too, each named with its key. The row comes under the
  // keys first, as a click puts it there.
  function dashMenu(index, over, x, y) {
    var row = root.taskRows[index]
    if (!row || row.kind === "head" || row.kind === "month") return
    dash.dashKeysRef.forceActiveFocus()
    dash.pointAt(index)
    root.used("edit-menu", "dash")
    var act = function (id, text, fn, on) {
      return { text: text, key: root.keyName(id), enabled: on !== false, run: function () { root.taskFocus = index; fn() } }
    }
    // What each row offers is what its keys do on it, named as they act
    // there (2026-11-27: a deadline's menu lacked rename, priority and the
    // rest its keys did; one not in a note offered to go to a line it does
    // not have; a box set aside offered to set it aside).
    var k = row.kind, list = []
    var noChat = root.noChatWhy(row) !== ""
    if (k === "task") {
      var t = row.task, shut = !!t.done || !!t.cancelled
      list = [act("dashOpen", "Go to its line", root.activateTask),
              act("dashDone", t.cancelled ? "Bring it back" : t.done ? "Not done after all" : "Done", root.tickFocused),
              act("dashWhen", t.when ? "Another day to work on it" : "A day to work on it", root.startDashWhen, !shut),
              act("dashNoDate", "Take its day off", root.noDateFocused, !shut && !!t.when),
              act("dashPriority", "Change its priority", root.cyclePriorityFocused, !shut), act("dashRename", "Rename", root.startDashRename),
              act("dashTalk", "Chat about it", root.talkFocused, !noChat), act("dashFollow", "Follow its link", root.followRowLink, root.rowLinks(row).length > 0),
              act("dashExport", "Export its section as a PDF", root.exportFocused, !!t.project)]
      if (t.life > 0 && !shut)
        list = list.concat([act("dashShelve", t.away ? "Bring it back" : "Set it aside", root.shelveFocused),
                            act("dashKeep", "Renew: its clock starts again", root.keepFocused)])
      list = list.concat([act("dashDrop", "Drop it", root.dropFocused, !t.cancelled)])
    } else if (k === "deadline") {
      var d = row.deadline, open = d.status === "open", line = root.taskOfAnchor(d.id)
      var unwritten = !Bound.parseLink(d.link)
      list = [act("dashOpen", unwritten ? "Write it into today's note" : "Go to its line", root.activateTask),
              act("dashDone", d.status === "cancelled" ? "Open it again" : open ? "Done" : "Not done after all", root.tickFocused)]
      if (d.status !== "cancelled")
        list = list.concat([act("dashWhen", line && line.when ? "Another day to work on it" : "A day to work on it", root.startDashWhen, open && !!line),
                            act("dashNoDate", "Take its day off", root.noDateFocused, open && !!line && !!line.when),
                            act("dashPriority", "Change its priority", root.cyclePriorityFocused, open && !!line),
                            act("dashRename", "Rename", root.startDashRename),
                            act("dashGrade", d.grade !== "" ? "Change its grade" : "Grade it", root.startDashGrade),
                            act("dashTalk", "Chat about it", root.talkFocused, !noChat),
                            act("dashFollow", "Follow its link", root.followRowLink, root.rowLinks(row).length > 0),
                            act("dashExport", "Export its section as a PDF", root.exportFocused, !!d.project),
                            act("dashDrop", "Cancel it", root.dropFocused)])
    } else if ((k === "proposal" || k === "told") && row.item.kind === "file") {
      list = [act("dashDone", k === "told" ? "Let it stand" : "File it", root.tickFocused),
              act("dashOpen", "Open it", root.activateTask),
              act("dashDrop", k === "told" ? "Put it back" : "Decline", root.dropFocused)]
    } else if (k === "proposal" || k === "question") {
      list = [act("dashDone", k === "question" ? "Accept the recommended answer" : "Accept", root.tickFocused),
              act("dashOpen", "Chat about it", root.activateTask), act("dashDrop", "Decline", root.dropFocused)]
    } else if (k === "told") {
      list = [act("dashDone", "Let it stand", root.tickFocused), act("dashOpen", "Chat about it", root.activateTask),
              act("dashDrop", "Undo it", root.dropFocused)]
    } else if (k === "raised") {
      list = [act("dashOpen", "Dismiss it", root.activateTask)]
    } else if (k === "band") {
      if (row.count === 0 || row.fixed) return
      list = [act("dashOpen", row.open ? "Fold it" : "Open it", root.activateTask, !row.forced)]
      if (!row.aside && root.dashOrder === "date")
        list = list.concat([act("dashFoldAll", "Collapse every band", function () { root.foldAll(false) }),
                            act("dashUnfoldAll", "Expand every band", function () { root.foldAll(true) })])
    } else return
    editMenu.openAt(over, x, y, list)
  }

  // The menu from the keys (Shift+F10 or the Menu key, 2026-11-25): the
  // same one, on the cursor or under the row, its first entry picked so
  // Enter does it at once.
  function menuKey() {
    // In the agent's pane, on words selected in an answer: their menu.
    var cs = root.chatSelection
    if (root.here === "right" && cs && cs.visible && cs.selectedText !== "" && cs.parent && cs.parent.menuOnSelection) {
      cs.parent.menuOnSelection()
    } else if (root.centerView === "dash") {
      var kids = dash.dashColumnRef.children
      for (var i = 0; i < kids.length; i++) {
        var row = kids[i]
        if (row.index === undefined || row.index !== root.taskFocus) continue
        root.dashMenu(root.taskFocus, row, root.sp(24), row.height)
        break
      }
    } else if (root.centerView === "note") {
      var c = editor.cursorRect
      root.noteMenu(c.x + c.width, c.y + c.height)
    }
    if (editMenu.opened) {
      for (var e = 0; e < editMenu.entries.length; e++)
        if (editMenu.entries[e].enabled !== false) { editMenu.current = e; break }
    }
  }

  // The note's, at (x, y) in the editor: its edits as their keys do them.
  function noteMenu(x, y) {
    root.used("edit-menu", "note")
    var sel = editor.hasSelection(), ro = editor.readOnly
    editMenu.openAt(editor, x, y, [
      { text: "Cut", key: "Ctrl+X", enabled: sel && !ro, run: function () { editor.editAct(Qt.Key_X) } },
      { text: "Copy", key: "Ctrl+C", enabled: sel, run: function () { editor.editAct(Qt.Key_C) } },
      { text: "Paste", key: "Ctrl+V", enabled: !ro && editor.pasteText() !== "", run: function () { editor.editAct(Qt.Key_V) } },
      { text: "Select more", key: "Ctrl+A", run: function () { editor.editAct(Qt.Key_A) } }
    ])
  }
  function copyChatSelection(event, box) {
    if (event.key !== Qt.Key_C || (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier)) !== Qt.ControlModifier) return false
    if (box && box.selectedText !== "") return false
    var s = root.chatSelection
    if (!s || !s.visible || s.selectedText === "") return false
    s.copy()
    return true
  }

  function dayKey(event) {
    root.keysSeen(event)
    if (root.copyChatSelection(event, dayPane.dayFieldRef)) return true
    if (root.answerSelected(event)) return true
    if (Sc.hit(event, "dayHelpful")) { root.rateDay(-1, "up"); return true }
    if (Sc.hit(event, "dayNotHelpful")) { root.rateDay(-1, "down"); return true }
    if (Sc.hit(event, "chatPrevQuestion")) { dayPane.jumpQuestion(-1); return true }
    if (Sc.hit(event, "chatNextQuestion")) { dayPane.jumpQuestion(1); return true }
    if (root.pageFlick(dayPane.flickRef, event)) return true
    if (Sc.hit(event, "menu") && root.chatSelection && root.chatSelection.visible && root.chatSelection.selectedText !== "") { root.menuKey(); return true }
    // On the cards: ↑↓ between them, Enter or Space does what one says, Del
    // declines it (a thing done by itself: undoes it), Esc or ↓ past the
    // last goes back to the box; typing goes back too.
    // On the folded lines of "everything" (earlier days, today's other
    // places): ↑↓ between them, Enter or Space unfolds a day or opens what
    // a line is about, Esc or ↓ past the last goes back to the box.
    if (root.dayFoldKey !== "") {
      var rows = root.convoRows, at = -1
      for (var r = 0; r < rows.length; r++) if (rows[r].key === root.dayFoldKey) at = r
      if (at < 0) root.dayFoldKey = ""
      else {
        if (Sc.hit(event, "marginUp")) { root.dayFoldKey = rows[Math.max(0, at - 1)].key; return true }
        if (Sc.hit(event, "marginDown")) {
          if (at < rows.length - 1) root.dayFoldKey = rows[at + 1].key
          else { root.dayFoldKey = ""; if (root.dayOpenCards.length > 0) root.dayCardFocus = 0 }
          return true
        }
        if (Sc.hit(event, "marginAccept")) { root.convoAct(root.dayFoldKey); return true }
        if (Sc.hit(event, "marginBack")) { root.dayFoldKey = ""; return true }
        root.dayFoldKey = ""
      }
    }
    if (root.dayCardFocus >= 0) {
      var n = root.dayOpenCards.length
      if (n === 0) root.dayCardFocus = -1
      else {
        if (Sc.hit(event, "marginUp") && root.dayCardFocus === 0 && root.convoRows.length > 0) {
          root.dayCardFocus = -1; root.dayFoldKey = root.convoRows[root.convoRows.length - 1].key; return true
        }
        if (Sc.hit(event, "marginUp")) { root.dayCardFocus = Math.max(0, root.dayCardFocus - 1); return true }
        if (Sc.hit(event, "marginDown")) { root.dayCardFocus = root.dayCardFocus >= n - 1 ? -1 : root.dayCardFocus + 1; return true }
        if (Sc.hit(event, "marginAccept")) { root.settleDayCard(root.dayCardFocus, "accept"); return true }
        if (Sc.hit(event, "marginDecline")) { root.settleDayCard(root.dayCardFocus, "decline"); return true }
        if (Sc.hit(event, "undo") && root.undoLastCard()) return true
        if (Sc.hit(event, "marginBack")) { root.dayCardFocus = -1; return true }
        root.dayCardFocus = -1
      }
    } else if (Sc.hit(event, "undo") && dayPane.dayFieldRef.text === "" && root.undoLastCard()) {
      return true
    } else if (Sc.hit(event, "marginUp") && dayPane.dayFieldRef.text === "" && !root.dayMention && root.dayOpenCards.length > 0) {
      root.dayCardFocus = root.dayOpenCards.length - 1
      return true
    } else if (Sc.hit(event, "marginUp") && dayPane.dayFieldRef.text === "" && !root.dayMention && root.convoRows.length > 0) {
      root.dayFoldKey = root.convoRows[root.convoRows.length - 1].key
      return true
    }
    if (root.dayMention && root.dayMention.items.length > 0) {
      if (Sc.hit(event, "mentionUp")) { root.dayMentionFocus = Math.max(0, root.dayMentionFocus - 1); return true }
      if (Sc.hit(event, "mentionDown")) { root.dayMentionFocus = Math.min(root.dayMention.items.length - 1, root.dayMentionFocus + 1); return true }
      if (Sc.hit(event, "mentionPick") || Sc.hit(event, "mentionClass")) { root.pickDayMention(root.dayMentionFocus); return true }
      if (Sc.hit(event, "mentionClose")) { root.dayMention = null; return true }
    }
    if (root.mentionNothing(event)) return true
    if (root.replyKey("day", event)) return true
    if (root.anywhereKey(event)) return true
    if (Sc.hit(event, "marginBack") && root.stopAgent("day")) return true
    if (root.paper.room && Sc.hit(event, "marginBack")) { root.paper.showList(); return true }
    if (Sc.hit(event, "marginBack")) { root.closeDay(); return true }
    if (Sc.hit(event, "chatSend")) { if (root.sendDay(dayPane.dayFieldRef.text)) { dayPane.dayFieldRef.text = ""; dayPane.toFoot() } return true }
    // Backspace in an empty box lets go of the last mark attached.
    if (event.key === Qt.Key_Backspace && dayPane.dayFieldRef.text === "" && root.paper.marks.length > 0) {
      root.paper.marks = root.paper.marks.slice(0, -1); return true
    }
    // Backspace in an empty box lets go of the block pointed at.
    if (event.key === Qt.Key_Backspace && dayPane.dayFieldRef.text === "" && root.dayChips.length > 0) {
      root.dropDayChip(root.dayChips.length - 1); return true
    }
    return false
  }

  // Talking with the agent about a task, or with the planner about one of
  // its proposals (2026-10-20): the margin opens beside the dashboard. Each
  // box has one conversation — what was said in the margin of its note and
  // what was said with the planner, merged by time (`talkData`, from
  // `longhand-agent thread`) — shared by the boxes under it. `threads` is
  // every box's conversation with the planner (thread key -> turns), for
  // the note's margin to show beside its own.
  property var threads: ({})
  property int talkId: -1             // the proposal talked about; follows a revision
  property string talkTask: ""        // or the task's key, summoned on its row (Alt+→)
  property string talkThread: ""
  property var talkData: null         // { thread, title, chat: { date, hash } | null, turns }
  property bool talkFetchAgain: false
  property var pendingTalk: null      // { thread, text }: sent, its answer not back yet
  property string talkSettled: ""     // "accepted" / "declined": how the conversation ended it
  property int acceptAfterRefresh: -1 // agreed in the conversation: accepted once its row is read again
  readonly property var talkItem: {
    for (var i = 0; i < root.proposals.length; i++) if (root.proposals[i].id === root.talkId) return root.proposals[i]
    return null
  }
  readonly property bool talkOpen: root.dashOpen && root.talkThread !== "" && !root.keysOpen && !root.settingsOpen
  readonly property var talkTurns: {
    var t = root.talkData ? root.talkData.turns.slice() : []
    if (root.pendingTalk && root.pendingTalk.thread === root.talkThread) t.push({ role: "student", text: root.pendingTalk.text, refs: root.pendingTalk.refs })
    return t
  }
  // Where a message goes: to the planner while the conversation is about
  // one of its proposals not yet settled — also in the moment after a
  // revision, before the list is read again; else to the margin, about the
  // task's block.
  readonly property bool talkToPlanner: root.talkId >= 0 && root.talkSettled === ""
  // The cards the margin agent made in the task's chat and the person has
  // not settled (2026-11-03), in the order drawn: the keys go through them
  // as through the note margin's, ↑ from the empty box onto the last.
  readonly property var talkCards: {
    var out = [], turns = root.talkTurns
    for (var t = 0; t < turns.length; t++)
      for (var c = 0; c < (turns[t].cards || []).length; c++) {
        var card = turns[t].cards[c]
        if (card.ledger ? !!root.dayCardLive({ id: card.ledger }) : (!card.accepted && !card.superseded && !card.declined)) out.push(card)
      }
    return out
  }
  property int talkCardFocus: -1      // which of talkCards the keys are on; -1: none
  readonly property bool talkCanSend: root.talkToPlanner || !!(root.talkData && root.talkData.chat)

  // The note's margin shows the box's one conversation too: its own turns
  // and, merged by time, what was said about the box with the planner.
  readonly property var noteTurns: {
    var own = root.chatTurns
    var b = root.blockBounds(root.currentHash)
    var key = b ? root.rootKeyOf(svc.noteDate, b.text.split("\n")[0]) : ""
    var planned = key !== "" ? (root.threads[key] || []) : []
    if (planned.length === 0) return own
    var rows = [], last = ""
    for (var i = 0; i < own.length; i++) { last = own[i].at || last; rows.push({ at: last, p: 0, i: i, t: own[i] }) }
    last = ""
    for (var j = 0; j < planned.length; j++) {
      last = planned[j].at || last
      rows.push({ at: last, p: 1, i: j, t: Object.assign({ who: "planner" }, planned[j]) })
    }
    // A turn not yet answered (no time) stays last, where it was typed.
    rows.sort(function (x, y) {
      var xa = x.at || "9999", ya = y.at || "9999"
      return xa < ya ? -1 : xa > ya ? 1 : x.p !== y.p ? x.p - y.p : x.i - y.i
    })
    return rows.map(function (r) { return r.t })
  }

  // The key of the box a line is (found by its words, as the page finds
  // a task: the note's lines and the editor's are not numbered alike), all
  // the way up to the box it is under in its note (the runner's
  // plan.root_key): whose conversation it shares.
  function rootKeyOf(date, line) {
    var byLine = {}, t = null
    for (var i = 0; i < root.tasks.length; i++) {
      var x = root.tasks[i]
      if (x.date !== date) continue
      byLine[x.line] = x
      if (!t && Task.sameWords(line, x.text)) t = x
    }
    var guard = 0
    while (t && t.parent >= 0 && byLine[t.parent] && guard++ < 50) t = byLine[t.parent]
    return t && t.key ? t.key : ""
  }
  readonly property bool talking: talkProc.running
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
  property string dashWhenError: ""       // why Enter did not take what is typed, said beside it
  onDashWhenTextChanged: root.dashWhenError = ""
  onDashWhenForChanged: root.dashWhenError = ""
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
  property var timetableAgain: null    // { flags, index } asked for while the runner was busy
  property int settingsFocus: 0        // the row ↑↓ picks: a calendar, then settingsKinds
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
    // A test run may count the ticks and play none (LONGHAND_SILENT set).
    // Unset, Quickshell hands back null, not "": compared with "", that
    // read as set, and the page never played a tick (2026-10-17 to -19).
    if (tickSoundProc.running || !!Quickshell.env("LONGHAND_SILENT")) return
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
      if (!Queue.answered(r)) continue
      // Records from before the key was kept: their first line(s) stand in.
      var ks = r.key ? [r.key]
        : r.head ? (r.group ? r.head.split(" / ") : [r.head]).map(function (t) { return Blocks.fnv1a(Task.identity(t)) })
        : []
      for (var i = 0; i < ks.length; i++)
        if (!idx[ks[i]] || String(r.at) > String(b[idx[ks[i]]].at)) idx[ks[i]] = h
    }
    return idx
  }
  // A block's conversation: under its own hash; else found by its words
  // (a tick, a date, a priority leave them); else the one its lines carry
  // through an edit of its words (Threads.js).
  function recordHash(hash, text, block) {
    if (hash === "" || Queue.answered(agent.record(hash))) return hash
    var byWords = root.recordKeys[Blocks.fnv1a(Task.identity(text))]
    if (byWords) return byWords
    var carried = Threads.find(root.threadMap, block)
    return carried !== "" && Queue.answered(agent.record(carried)) ? carried : hash
  }
  property string currentRec: ""
  function refreshRec() {
    var b = root.blockBounds(root.currentHash)
    root.currentRec = root.recordHash(root.currentHash, b ? b.text : "", b)
  }
  onRecordKeysChanged: { root.refreshRec(); Qt.callLater(root.pinThreads) }
  onThreadMapChanged: root.refreshRec()
  readonly property var currentRecord: agent.record(currentRec)
  // The conversation as the margin shows it: what the runner has written,
  // plus the turn that has not landed yet.
  readonly property var chatTurns: {
    var rec = root.currentRecord
    var turns = rec && rec.chat ? rec.chat.slice() : []
    if (root.pendingChat && root.pendingChat.hash === root.currentRec)
      turns.push({ role: "student", text: root.pendingChat.text, refs: root.pendingChat.refs })
    return turns
  }
  // This block is away: asked and not back. `runningHash` can name a whole
  // list submission.
  readonly property bool answering: root.currentHash !== ""
    && ((!root.runAnswered && (root.runningHash.split(",").indexOf(root.currentHash) >= 0
                               || root.runningHash.split(",").indexOf(root.currentRec) >= 0))
        || root.sending.indexOf(root.currentHash) >= 0)
  // "read: The Seven Deadly Myths… (p. 1, 4)": what the agent read for the
  // reply under the cursor; nothing when it read nothing.
  function sayReads(rec) {
    var ds = rec && rec.documents ? rec.documents.filter(function (d) { return d.found }) : []
    if (ds.length === 0) return ""
    return "read: " + ds.map(function (d) {
      return d.document + (d.words === "" ? (d.whole === false ? " (its beginning)" : " (whole)")
        : d.pages && d.pages.length ? " (p. " + d.pages.join(", ") + ")" : "")
    }).join(" · ")
  }

  readonly property var currentProposals: (currentRecord && currentRecord.proposals) ? currentRecord.proposals : []
  // The margin's conversation as it is drawn (2026-10-23): each proposal
  // as a card right under the answer that made it — the turn says which
  // (`proposals`, indexes into the block's) — so it reads as part of the
  // conversation; the first answer's own, and any from before turns said
  // so, under the first answer. `{ card: i }` or `{ turn: t }`, in order,
  // which is also the order the keys go through the cards.
  readonly property var marginRows: {
    var props = root.currentProposals, turns = root.noteTurns, claimed = {}, rows = []
    for (var a = 0; a < turns.length; a++)
      if (turns[a].role === "agent" && turns[a].who !== "planner") (turns[a].proposals || []).forEach(function (i) { claimed[i] = true })
    for (var i = 0; i < props.length; i++) if (!claimed[i]) rows.push({ card: i })
    for (var t = 0; t < turns.length; t++) {
      rows.push({ turn: turns[t] })
      if (turns[t].role !== "agent" || turns[t].who === "planner") continue
      var mine = turns[t].proposals || []
      for (var k = 0; k < mine.length; k++) if (mine[k] < props.length) rows.push({ card: mine[k] })
    }
    return rows
  }
  // A card's words: a new deadline, or one already there moved.
  function marginCardFacts(p) {
    var m = p.moves
    // A new one beside others that read the same says so: it is not a
    // move (2026-11-15: "do this by wed" added a third AI Literacy course).
    var alike = !m && p.alike && p.alike.length ? "\nbeside " + p.alike.map(function (d) {
      return "#" + d.id + " (" + Qt.formatDate(new Date(d.due * 1000), "d MMM") + ")" }).join(", ") : ""
    return (m ? m.title : p.title) + ((p.project || p.subject) && !m ? " · " + (p.project || p.subject) : "") + alike
  }
  // The day as the page says days ("Fri 20 Nov", "tomorrow"); words the
  // agent wrote that are not a date ("friday") as written.
  function marginCardPill(p) {
    var when = /^\d{4}-\d{2}-\d{2}( \d{1,2}:\d{2})?$/.test(p.when || "") ? Say.sayDate(p.when) : p.when
    return p.moves ? Qt.formatDate(new Date(p.moves.due * 1000), "ddd d MMM") + " → " + when : "📅 " + when
  }
  // What's next: the dashboard's rows, in the order they ask something of
  // you (Next.js).
  readonly property var taskRows: Next.rows({ deadlines: dl.items, tasks: root.tasks, projects: root.projects, raised: root.raised,
                                              proposals: root.proposals, showShelf: root.showShelf, showGrading: root.showGrading,
                                              lens: root.dashLens, query: root.dashQuery, order: root.dashOrder,
                                              folds: root.dashFolds, weekStart: root.firstDow, now: new Date(root.dashNow) })

  // The dashboard's minute (2026-11-27, as the note's since the editor
  // pass): what the clock changes — a deadline's hour passing, so its row
  // and pill turn late; midnight, so today's bands, "done today" and
  // "tomorrow" move on — is drawn without waiting for something else to
  // change. Read as the dashboard opens, then each minute while it is.
  property double dashNow: Date.now()
  Timer {
    interval: 60000
    running: root.dashOpen
    repeat: true
    onTriggered: root.dashNow = Date.now()
  }

  // The course strip above the dashboard's list (2026-11-03): a chip for
  // each course with something open, the ⌕ before them to type into, the
  // order after. Moving along it shows each course at once; Space adds
  // one; Enter unfolds it into every course with what it holds. The
  // courses picked and the order are kept (page.json); what is typed is
  // not.
  property var dashLens: []           // the courses shown; [] every one, "" no project
  property string dashQuery: ""       // what is typed into ⌕
  // By date since 2026-11-03: the order the student kept it in.
  property string dashOrder: "date"   // "ask" (what it asks of you), "course", "date"
  // By date, the bands folded or unfolded (Next.bandOpen): a band's id to
  // open or not, "*" for all at once. Kept in page.json.
  property var dashFolds: ({})
  // As drawn on the title row, by day first (2026-11-15); O goes round
  // them in this order.
  readonly property var dashOrders: ["date", "ask", "course"]
  property int stripAt: -1            // the strip's cursor: 0 ⌕, 1 All, the chips, then the order; -1 the list
  property bool stripOpen: false      // unfolded
  property int stripPick: 0           // unfolded: 0 ⌕, then a row per chip, then the orders
  // Space kept a course: moving along the strip no longer shows each one,
  // and Space on another adds it. Until then the strip shows where its
  // cursor is, so Space could never add (found writing its test).
  property bool stripPinned: false
  readonly property var dashCourses: Next.courses({ deadlines: dl.items, tasks: root.tasks, projects: root.projects,
                                                    proposals: root.proposals, raised: root.raised,
                                                    lens: root.dashLens, query: root.dashQuery })
  readonly property var stripChips: root.dashCourses.chips
  readonly property var stripChipTags: root.stripChips.map(function (c) { return c.tag })
  readonly property int stripEnd: root.stripChips.length + 2      // the order, last
  readonly property bool dashNarrowed: root.dashLens.length > 0 || root.dashQuery.trim() !== ""
  // The dashboard's cursor stays on the same row when the list is drawn
  // again — rows added above it (a plan, the agent's steps) must not move
  // the next key onto another row. Only when its row is gone does the
  // cursor keep its place in the list.
  property string taskFocusKey: ""
  onTaskFocusChanged: root.taskFocusKey = root.rowKey(root.taskRows[root.taskFocus])
  // The list as the dashboard draws it (2026-11-13): a model of keys, kept
  // in step with `taskRows` by key, so a row that is still there keeps its
  // drawn row. Drawn straight from `taskRows`, every letter typed into ⌕ —
  // or every course passed on the strip — threw every row away and drew
  // the list anew, about 1.6 ms a row: a quarter of a second a key for a
  // term's work. Now what the words leave out is only hidden, and comes
  // back as it was when they let it in again; the rows themselves are
  // compared as they are, so a row whose facts did not change is not
  // drawn again either. What is hidden is let go once nothing narrows the
  // list.
  ListModel { id: dashModelObj }
  property alias dashModel: dashModelObj
  property var dashEntries: ({})      // key -> { row, i }: the row, and where it is in taskRows
  property var dashSeen: ({})         // key -> { js, row }: each row drawn, hidden ones too, to keep one that did not change
  property var dashKeys: []           // the model's keys, in its order
  property var dashRowIds: []         // taskRows' keys, in its order
  readonly property string dashFocusId: root.dashRowIds[root.taskFocus] || ""
  function dashKeyOf(row) {
    var k = root.rowKey(row)
    if (k !== "") return k
    var it = row.item || {}
    return row.kind + "|" + (row.text || "") + "|" + (row.tag || "") + "|" + (it.id !== undefined ? it.id : (it.text || ""))
  }
  function syncDash() {
    var rows = root.taskRows
    var keys = [], count = {}
    var entries = {}
    var seen = root.dashSeen
    for (var i = 0; i < rows.length; i++) {
      var base = root.dashKeyOf(rows[i])
      var n = count[base] = (count[base] || 0) + 1
      var k = n > 1 ? base + "#" + n : base
      keys.push(k)
      var js = ""
      try { js = JSON.stringify(rows[i]) } catch (e) { js = "" }
      var was = seen[k]
      var row = was && js !== "" && was.js === js ? was.row : rows[i]
      seen[k] = { js: js, row: row }
      var old = root.dashEntries[k]
      var afterBand = i > 0 && rows[i - 1].kind === "band"
      entries[k] = old && old.row === row && old.i === i && old.afterBand === afterBand ? old : { row: row, i: i, afterBand: afterBand }
    }
    root.dashRowIds = keys
    root.dashEntries = entries
    // The model: every key in taskRows, in its order; keys it no longer
    // has stay (hidden) where they were, while the list is narrowed.
    var mk = root.dashKeys.slice()
    var pos = 0
    for (var j = 0; j < keys.length; j++) {
      var key = keys[j]
      var at = mk.indexOf(key, pos)
      if (at >= 0) { pos = at + 1; continue }
      var before = mk.indexOf(key)
      if (before >= 0) {
        dashModelObj.move(before, pos - 1, 1)
        mk.splice(before, 1)
        mk.splice(pos - 1, 0, key)
        continue
      }
      dashModelObj.insert(pos, { rowId: key })
      mk.splice(pos, 0, key)
      pos++
    }
    // Read from the lens and the words themselves: `dashNarrowed` may not
    // have caught up yet while taskRows tells of a letter just typed.
    var narrowedNow = root.dashLens.length > 0 || root.dashQuery.trim() !== ""
    if (!narrowedNow || mk.length > keys.length + 400) {
      for (var r = mk.length - 1; r >= 0; r--)
        if (!entries[mk[r]]) { dashModelObj.remove(r, 1); delete seen[mk[r]]; mk.splice(r, 1) }
    }
    root.dashKeys = mk
  }
  Component.onCompleted: root.syncDash()
  onDashNarrowedChanged: if (!root.dashNarrowed) Qt.callLater(root.syncDash)
  onTaskRowsChanged: {
    root.syncDash()
    var rows = root.taskRows
    if (root.taskFocusKey !== "") {
      for (var i = 0; i < rows.length; i++) {
        if (root.rowKey(rows[i]) !== root.taskFocusKey) continue
        // A row just closed from here sinks below the open ones: the
        // cursor stays where it was, on the next thing to do, rather than
        // following it down (ticking down a list is tick, tick, tick).
        if (root.justClosed === root.taskFocusKey && root.rowClosed(rows[i]) && i > root.taskFocus) break
        if (i !== root.taskFocus) root.taskFocus = i
        return
      }
      if (i < rows.length) { root.justClosed = ""; root.settleTaskFocus(); root.taskFocusKey = root.rowKey(rows[root.taskFocus]); return }
      // Gone from the list as drawn, though not from the notes: a day given
      // that puts it in a band folded, say. Where it went is said, so it
      // does not seem to have vanished (2026-11-27).
      root.sayWhereItWent(root.taskFocusKey)
    }
    root.settleTaskFocus()
  }
  // A row the cursor can be on: not a heading or a month, nor a band with
  // nothing to fold.
  function rowActs(row) {
    return !!row && row.kind !== "head" && row.kind !== "month"
      && !(row.kind === "band" && (row.count === 0 || row.fixed))
  }
  // The cursor where a row can be: in the list, on a row that acts —
  // nearest below, else above (2026-11-27: the last proposal declined took
  // its band's heading with it, and the cursor was left past the end, lit
  // nowhere, where ↑ climbed onto the strip; a band unfolded left it on
  // the heading that took the band's place).
  function settleTaskFocus() {
    var rows = root.taskRows
    if (rows.length === 0) { if (root.taskFocus !== 0) root.taskFocus = 0; return }
    var at = Math.max(0, Math.min(root.taskFocus, rows.length - 1))
    if (!root.rowActs(rows[at])) {
      var down = at, up = at
      while (down < rows.length && !root.rowActs(rows[down])) down++
      while (up >= 0 && !root.rowActs(rows[up])) up--
      at = down < rows.length ? down : up >= 0 ? up : at
    }
    if (at !== root.taskFocus) root.taskFocus = at
    else root.taskFocusKey = root.rowKey(rows[at])
  }
  // A box the cursor was on, now in a band folded (or set aside): its
  // band named, in passing.
  function sayWhereItWent(key) {
    if (key.charAt(0) !== "t" && key.charAt(0) !== "d") return
    var all = Next.rows({ deadlines: dl.items, tasks: root.tasks, projects: root.projects, raised: [], proposals: [],
                          showShelf: true, showGrading: true, lens: root.dashLens, query: root.dashQuery,
                          order: root.dashOrder, folds: { "*": true }, weekStart: root.firstDow, now: new Date(root.dashNow) })
    var band = null
    for (var i = 0; i < all.length; i++) {
      if (all[i].kind === "band") band = all[i]
      if (root.rowKey(all[i]) === key) {
        // Done today needs no word: the tick said it.
        if (band && !band.fixed && band.id !== "done") root.showHint("now under " + band.text.toLowerCase() + ", folded · " + root.keyName("dashOpen") + " on it opens it")
        return
      }
    }
  }
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
    } else if (root.windowActive) {
      // The window is in front with the keys: the overlay over it would
      // show the same sheet a little larger and leave the window empty
      // behind it ("on the overlay"). The window stays, and says what
      // fills the screen instead.
      root.showHint("already open here · " + root.keyName("pin") + " for full screen")
      return
    } else {
      root.overlayOpen = true
    }
    if (fresh) {
      pdfPane.keep()
      root.pdfRel = ""
      root.sidebarOpen = false
      root.sidebarSpace = "time"
      root.vaultIndex = null
      // The margin is on-demand only, so a page opened from nothing shows
      // the note alone — not the panel the last session left open.
      root.marginOpen = false
      root.dashOpen = false
      root.projectOpen = false
      root.marginFocus = -1
      root.projectOpen = false
      // `@` can call a project without the sidebar ever being opened.
      root.refreshProjects()
      root.loadHorizon()
      // The day's plan, at most once a day (the runner decides) — after the
      // calendars the opening fetches, so it plans around today's copy.
      root.afterFetch(function () { root.runPlan(false) })
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
    usageProc.command = ["python3", root.pageFsPy, "append", root.usagePath, root.usageBuf.join("\n")]
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
      root.ctrlLetGo()
      root.flushUsage()
      if (root.countKeys()) root.writeTaught()
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
    root.savePageState()
    root.scheduleRepaint()
  }

  function savePageState() {
    zoomFile.setText(JSON.stringify({ zoom: root.zoom, dashSeen: root.dashSeenId, chatSeen: root.chatSeen,
                                      dashLens: root.dashLens, dashOrder: root.dashOrder, dashFolds: root.dashFolds }) + "\n")
  }

  // The global keys: the page itself and where you are in it, wherever the
  // keyboard is — every place's handler asks this first, a box you type in
  // too. Every key the page answers to is named in Shortcuts.js, where the
  // student can move it (the keys sheet, below); the ones read here are
  // its "any" place.
  // The mouse's menu open: its keys first (EditMenu.key), for whatever runs
  // its own keys before the page's.
  function editMenuKey(event) { return editMenu.opened && editMenu.key(event) }
  function anywhereKey(event) {
    if (root.editMenuKey(event)) return true
    root.keysTook(event)   // every pane's keys come through here first
    if (Sc.hit(event, "zoomIn")) { root.zoomBy(1); return true }
    if (Sc.hit(event, "zoomOut")) { root.zoomBy(-1); return true }
    if (Sc.hit(event, "zoomReset")) { root.setZoom(1); return true }
    if (Sc.hit(event, "keys")) { root.toggleKeys(); return true }
    if (Sc.hit(event, "settings")) { root.toggleSettings(); return true }
    if (Sc.hit(event, "pane1")) { root.paneKey("left"); return true }
    if (Sc.hit(event, "pane2")) { root.paneKey("center"); return true }
    if (Sc.hit(event, "dashGo")) { root.showDash(); return true }
    if (Sc.hit(event, "pane3")) { root.paneKey("right"); return true }
    if (Sc.hit(event, "sidebar")) { root.toggleSidebar(); return true }
    if (Sc.hit(event, "dayChat")) { root.openDay(""); return true }
    if (Sc.hit(event, "linkBack")) { root.goBack(-1); return true }
    if (Sc.hit(event, "linkForward")) { root.goBack(1); return true }
    if (Sc.hit(event, "day")) { root.toggleRight(); return true }
    if (Sc.hit(event, "paneLeft")) { root.movePane(-1); return true }
    if (Sc.hit(event, "paneRight")) { root.movePane(1); return true }
    if (Sc.hit(event, "paneFlip")) { root.flipPane(); return true }
    if (Sc.hit(event, "paneWider")) { root.nudgePane(100); return true }
    if (Sc.hit(event, "paneNarrower")) { root.nudgePane(-100); return true }
    if (Sc.hit(event, "today")) { root.goToday(); return true }
    if (Sc.hit(event, "pin")) { root.togglePin(); return true }
    if (Sc.hit(event, "copyPath")) { root.copyPath(); return true }
    if (Sc.hit(event, "save")) { root.saveNow(); return true }
    if (Sc.hit(event, "switcher")) { root.toggleSwitcher(); return true }
    if (Sc.hit(event, "findAll")) { root.findAll(); return true }
    if (Sc.hit(event, "projectKey")) { root.projectByKey(event); return true }
    return false
  }

  // Ctrl+Shift+C: the path of what you are on, for an agent outside the
  // page (Where.js). A row of Files, the PDF open, a task on the dashboard
  // (its note and line), else the note, at the cursor's line or the lines
  // selected. The keys and settings are no file.
  function pathHere() {
    var vault = svc.config ? svc.config.vault : ""
    if (root.here === "left" && root.sidebarSpace === "files") {
      var fp = sidebar.filesPaneRef
      var r = fp.shown[fp.pick]
      return r && !r.none && vault !== "" ? vault + "/" + r.rel.replace(/\/$/, "") : ""
    }
    if (root.centerView === "dash") {
      var row = root.taskRows[root.taskFocus]
      return row && row.kind === "task" && row.task.file ? row.task.file + ":" + (row.task.line + 1) : ""
    }
    if (root.centerView !== "note") return ""
    if (root.pdfShown) return Links.isAbs(root.pdfRel) ? root.pdfRel : vault !== "" ? vault + "/" + root.pdfRel : ""
    if (svc.notePath === "" || !svc.ready) return ""
    var body = editor.text
    var whole = svc.joinHeader(body)
    var before = whole.substring(0, whole.length - body.length)
    return editor.spanning ? Where.at(svc.notePath, before, body, editor.selStart, editor.selEnd)
      : Where.at(svc.notePath, before, body, editor.cursorPosition)
  }

  // Ctrl+S: what is written is on disk already, or is now; said either way.
  function saveNow() {
    var dirty = saveTimer.running
    root.flush()
    // Short: a hint is one line (2026-11-26, on the ThinkPad the longer
    // words were cut off).
    root.showHint(!svc.ready || root.centerView !== "note" ? "saved as you write" : dirty ? "saved" : "already saved")
    root.used("save", dirty ? "dirty" : "clean")
  }

  function copyPath() {
    var p = root.pathHere()
    if (p === "") { root.showHint("no file here to copy"); return }
    editor.copyText(p)
    root.showHint("copied " + p.replace(Quickshell.env("HOME") + "/", "~/"))
    root.used("copy-path", root.here)
  }

  // ------------------------------------------------------------ panes
  //
  // docs/navigation.md. The page is at most three panes side by side: the
  // sidebar ("left"); the middle ("center": the note, or the dashboard,
  // the keys or settings in its place); and the agent's pane ("right": a
  // block's conversation beside the note, a task's beside the dashboard,
  // the day's beside either). The keyboard is in exactly one, `here`, and
  // the focus frame says which. Each pane keeps where its keys were (the
  // note its cursor, a list its row), so coming back lands there; a pane
  // closing gives the keys back to the pane they came from (`openedFrom`).
  // Moving between panes never closes one, and opens one only: Alt+→ in
  // the note with nothing to its right, the block's conversation.
  readonly property string centerView: root.keysOpen ? "keys" : root.settingsOpen ? "settings" : root.dashOpen ? "dash" : "note"
  readonly property string rightView: margin.visible ? (root.talkOpen ? "talk" : "margin") : dayPane.visible ? "day" : ""
  readonly property bool leftShown: sidebar.visible
  readonly property var panes: (root.leftShown ? ["left"] : []).concat(["center"], root.rightView !== "" ? ["right"] : [])
  // The keys' last pane, for the blip: from the middle into the agent's.
  property string hereWas: "center"
  property var blipRect: null
  property string blipWhat: ""          // what lit last: "sheet" or a block's hash (the tests read it)
  // What the agent's pane is about to be given, lit once in the note: the
  // block pointed at, else the block a margin conversation is on, else the
  // whole note when the room is the note's own (or today's, which the day
  // conversation reads). Nothing over the dashboard, keys or settings.
  function blipContext() {
    if (root.centerView !== "note" || !svc.ready || root.pdfShown) return
    var what = ""
    if (root.dayShown) what = root.dayBlock !== "" ? root.dayBlock : ((root.noteRoom && root.paneHeld === "") || (svc.isToday && root.agentOn)) ? "sheet" : ""
    else if (root.rightView === "margin" || root.rightView === "talk") what = root.currentRec || root.currentHash
    if (what === "") return
    var r = null
    if (what === "sheet") r = { y: Math.max(0, flick.contentY - editor.y), h: Math.min(editor.height, flick.height) }
    else {
      var b = root.blockBounds(what)
      if (b) r = editor.blockRect(b.start, b.end)
    }
    if (!r) return
    root.blipRect = r
    root.blipWhat = what
    blipAnim.restart()
  }
  readonly property string here: sidebar.sidebarKeysRef.activeFocus || sidebar.projectFieldRef.activeFocus || sidebar.filesFilterRef.activeFocus ? "left"
    : margin.marginKeysRef.activeFocus || margin.chatFieldRef.activeFocus || dayPane.dayFieldRef.activeFocus || dayPane.paperKeysRef.activeFocus ? "right"
    : "center"
  // Where the keys were when a pane ("left", "right") or a view of the
  // middle ("dash", "keys", "settings") opened.
  property var openedFrom: ({})

  function noteFrom(what, from) {
    var m = root.openedFrom
    m[what] = from !== undefined ? from : root.here
    root.openedFrom = m
  }

  // The keys into a pane, where they were in it. False when it is closed.
  function focusPane(p) {
    if (p === "left") {
      if (!root.leftShown) return false
      // Back to a filter with words in it: the words, so typing goes on.
      if (root.sidebarSpace === "files" && sidebar.filesPaneRef.query !== "") sidebar.filesFilterRef.forceActiveFocus()
      else if (root.addingProject && root.sidebarSpace === "time") sidebar.projectFieldRef.forceActiveFocus()
      else sidebar.sidebarKeysRef.forceActiveFocus()
      return true
    }
    if (p === "right") {
      var v = root.rightView
      if (v === "") return false
      if (v === "day") root.dayKeysItem().forceActiveFocus()
      else if (v === "talk") {
        if (root.marginFocus === 0 && root.talkItem) margin.marginKeysRef.forceActiveFocus()
        else { root.marginFocus = 1; margin.chatFieldRef.forceActiveFocus() }
      } else {
        var n = root.currentProposals.length
        if (root.marginFocus < 0 || root.marginFocus > n) root.marginFocus = n
        if (root.marginFocus === n) margin.chatFieldRef.forceActiveFocus()
        else margin.marginKeysRef.forceActiveFocus()
      }
      return true
    }
    root.focusCenter()
    return true
  }

  // The middle, with whatever box was open in it: find, "when?", a name.
  function focusCenter() {
    var v = root.centerView
    if (v === "keys") keysSheet.keysFieldRef.forceActiveFocus()
    else if (v === "settings") {
      var sv = root.settingsView
      if (sv === "notebook") (root.notebookCorrecting ? notebookSheet.notebookFieldRef : notebookSheet.notebookKeysRef).forceActiveFocus()
      else if (sv === "autonomy") autonomySheet.autonomyKeysRef.forceActiveFocus()
      else if (sv === "search") searchSheet.searchKeysRef.forceActiveFocus()
      else if (sv === "checkin") checkinSheet.checkinKeysRef.forceActiveFocus()
      else settingsSheet.focusActive()
    } else if (v === "dash") (root.dashWhenFor ? dash.dashWhenFieldRef : dash.dashKeysRef).forceActiveFocus()
    else if (root.searchOpen) searchField.forceActiveFocus()
    else if (root.whenFor) whenField.forceActiveFocus()
    else if (root.newProject) nameField.forceActiveFocus()
    else if (root.exportOpen) exportSheet.keysRef.forceActiveFocus()
    else if (root.pdfShown) (pdfPane.finding ? pdfPane.findRef : pdfPane.keysRef).forceActiveFocus()
    else editor.focusNote()
  }

  // A pane or view closing: if the keys were in it (`was`, read before it
  // closed), they go back where they came from — the pane, and in it the
  // place, the student left (the note's cursor is where it was).
  function giveBack(what, was, pane) {
    if (was !== pane) return
    var from = root.openedFrom[what] || "center"
    if (!root.focusPane(from)) root.focusCenter()
  }

  // A pane's own key (the brackets): there, opening it; in it, closing it.
  // The middle has nothing to close, so there it flips the note and the
  // dashboard (a sheet in its place closes instead).
  // Ctrl+1/2/3 (docs/keys-proposal.md, 2026-10-27): a pane's number takes
  // the keys there, opening it if it is closed; in it, the pane switches
  // between its two things. The sidebar: Time and Files. The middle: the
  // note and the dashboard (a keys or settings sheet in its place closes
  // instead). The agent's pane: the day's chat, its home, and this block's
  // chat beside the note or the selected task's beside the dashboard.
  function paneKey(p) {
    if (p === "left") {
      if (!root.sidebarOpen) root.toggleSidebar()
      else if (root.here !== "left") root.focusPane("left")
      else root.switchSpace(1)
      return
    }
    if (p === "right") {
      if (root.rightView === "") root.openRight()
      else if (root.here !== "right") root.focusPane("right")
      // The paper's room and the day's chat, one key between them.
      else if (root.rightView === "day") { if (root.paper.room) root.openRoom("", false); else root.openThisChat() }
      else root.openDay("")
      return
    }
    if (root.here !== "center") root.focusCenter()
    else if (root.keysOpen) root.toggleKeys()
    else if (root.settingsOpen) root.toggleSettings()
    else root.toggleDash()
  }

  // Ctrl+Alt+2: the dashboard, wherever the keys are. It only shows: the
  // keys or settings over the middle close, and pressed on the dashboard it
  // stays, so it can be pressed without looking (Ctrl+2 flips). Opening it
  // is a step in the history, through toggleDash.
  function showDash() {
    if (!root.dashOpen) { root.toggleDash(); return }
    if (root.keysOpen) root.toggleKeys()
    if (root.settingsOpen) root.toggleSettings()
    if (root.here !== "center") root.focusCenter()
  }

  // Ctrl+|: the agent's pane, opened on the day's chat (its home), or
  // closed, wherever the keys are. Ctrl+\ is the sidebar's (toggleSidebar).
  function toggleRight() {
    if (root.rightView !== "") root.closeRight()
    else root.openRight()
  }
  function openRight() {
    root.openDay("")
    if (root.rightView === "") root.showHint("the window is too narrow for the agent's pane")
  }

  // In the agent's pane on the day's chat, its number again: the chat of
  // what is selected in the middle, the block under the cursor beside the
  // note, the row beside the dashboard.
  function openThisChat() {
    if (root.centerView === "dash") {
      var row = root.taskRows[root.taskFocus]
      if (row && ["task", "deadline", "proposal", "question", "told"].indexOf(row.kind) >= 0) root.talkFocused()
      else root.showHint("this row has no chat")
    } else if (root.paper.shown) {
      if (!root.paper.askable) root.showHint(pdfPane.read.private ? "private: this PDF is never given to the agent" : "this PDF has no words for the agent to read")
      else root.openRoom("", true)
    } else if (root.centerView === "note" && root.dayNote && !root.pdfShown) {
      if (root.currentHash === "") root.showHint("no block under the cursor")
      else if (!root.agentOn) root.showHint("private: the agent sees nothing of this note")
      else if (root.blockPrivate(root.currentHash)) root.showHint("private: the agent sees nothing of this block")
      else root.openBlockChat("pane")
    } else root.showHint(root.dayNote ? "nothing here has a chat of its own" : "a note from Files has one chat: its own")
  }

  // Alt+←/→: the next open pane that way, as Hyprland moves between
  // windows. At the edge, nothing — a hint says what would open there.
  function movePane(d) {
    var i = root.panes.indexOf(root.here) + d
    if (i >= 0 && i < root.panes.length) { root.focusPane(root.panes[i]); return }
    // The one opening: at the right edge, in the note, Alt+→ steps into the
    // block's own conversation, as it did before the panes (the student
    // missed it, 2026-10-25). It opens without sending, to be asked in
    // your own words; Ctrl+Enter is the key that sends.
    if (d > 0 && root.here === "center" && root.centerView === "note"
        && root.currentHash !== "" && root.marginWidth > 0 && !root.pdfShown) { root.diveIn(); return }
    // Beside a paper, Alt+→ opens its room, as a block's chat beside a note.
    if (d > 0 && root.here === "center" && root.paper.askable && root.marginWidth > 0) { root.openRoom("", true); return }
    root.showHint(d < 0 ? "nothing to the left · " + root.keyName("pane1") + " opens the sidebar"
                        : "nothing to the right · " + root.keyName("pane3") + " opens the agent's pane")
  }

  // ------------------------------------------------------------ the pointer
  //
  // The pointer follows the keys, as Hyprland's does between windows
  // (2026-10-23): when the keys change pane it lands in the pane, on what
  // is selected there (the note: beside its cursor); with "every", also on
  // each row the keys move to. So where the pointer is, is where the keys
  // are, and a click never lands somewhere unexpected. Never while the
  // student's own hand is on the mouse (moved in the last moment), never
  // while typing in the note, and only while the page's window is the
  // active one. `pointer` in settings.json: "panes" (the default), "every",
  // "off".
  // Off by default on Windows (2026-11-25, the mouse pass): Windows shows
  // the pointer while the keys move, where Hyprland hides it on a key
  // (cursor:hide_on_key_press), so a warp there was seen as the pointer
  // jumping by itself. Settings → The pointer still turns it on.
  readonly property string pointerMode: ["panes", "every", "off"].indexOf(root.settingsData.pointer) >= 0 ? root.settingsData.pointer
    : root.onWindows ? "off" : "panes"
  property var marks: ({})          // pane -> the item selected in it, as rows say (`selected`)
  property real handMovedAt: 0      // the student's own pointer, last moved
  property real warpedAt: 0

  // Hints follow the hand (2026-10-30, docs/hints.md): a hover's hint shows
  // only while the hand is on the mouse. Any key but a modifier alone puts
  // them away until the hand moves the pointer again, as Hyprland hides the
  // pointer itself (cursor:hide_on_key_press). So typing never brings one
  // up: not a box the note's new lines slide under a still pointer, nor
  // the row a warp lands on. A modifier alone keeps them, for Ctrl-click.
  // The marks the mouse paints follow it too (2026-10-30): a row's faint
  // fill, a word's accent, a box's edge. While the keys move, only the
  // keys' own fill shows.
  property bool handOn: false
  property point handAt: Qt.point(-1, -1)
  function keysTook(event) {
    var k = event.key
    if (k === Qt.Key_Control && !event.isAutoRepeat) { if (!root.ctrlShown) ctrlWait.restart(); return }
    root.ctrlLetGo()
    if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta
        || k === Qt.Key_AltGr || k === Qt.Key_Super_L || k === Qt.Key_Super_R) return
    root.handOn = false
    root.tipWarm = false
    // A key puts the mouse's menu away, as it does the hints: the keys
    // went on typing while it stayed open (2026-11-25, on the ThinkPad).
    if (editMenu.opened) editMenu.close()
  }

  // For a pane whose own keys come before the page's (the note's lists,
  // the chats, a PDF's back): the hand's marks and Ctrl's keys go as the
  // key comes, not only when it reaches anywhereKey (2026-11-25). The
  // mouse's menu, open, still hears its keys first there.
  function keysSeen(event) { if (!editMenu.opened) root.keysTook(event) }

  // Hold Ctrl (2026-10-30, docs/hints.md F; the canvas's direction 5): Ctrl
  // held alone for a moment puts its keys on the things they act on
  // (KeyBadge.qml), and the rest in a strip at the foot of the middle. Any
  // other key, letting go, or the hand on the mouse puts them away; a quick
  // Ctrl+S never shows them. The keyboard's own hint, as hover is the
  // mouse's.
  property bool ctrlShown: false
  property var caretAt: null        // where the note's cursor was when they showed
  function ctrlLetGo() { ctrlWait.stop(); root.ctrlShown = false }
  function ctrlShow() {
    root.caretAt = null
    if (root.centerView === "note" && editor.focusedRow >= 0) {
      var r = editor.cursorRect
      root.caretAt = editor.mapToItem(content, editor.width, r.y + r.height / 2)
    }
    root.ctrlShown = true
  }
  // An action's key after Ctrl ("" when none of its keys holds Ctrl).
  function ctrlKey(id) {
    root.keysVersion
    var ks = Sc.keysOf(id)
    for (var i = 0; i < ks.length; i++) if (ks[i].indexOf("Ctrl+") === 0) return Sc.show(ks[i]).substring(5)
    return ""
  }
  // What Ctrl does here that no badge shows, most used first.
  readonly property var ctrlStripItems: {
    var v = root.centerView
    var rest = v === "note" ? [["pane2", "dashboard"], ["bold", "bold"], ["italic", "italic"], ["link", "link"], ["deadline", "a date"], ["privateBlock", "private"], ["find", "find"], ["undo", "undo"]]
      : v === "dash" ? [["pane2", "note"], ["dashPlan", "plan now"], ["dashUndo", "undo"]]
      : []
    return rest.concat([["switcher", "find anything"], ["linkBack", "back"], ["keys", "every key"]])
      .map(function (a) { return { key: root.ctrlKey(a[0]), words: a[1] } })
      .filter(function (a) { return a.key !== "" })
  }

  // Warm hints (Tip.qml): once one has opened, the next opens at once,
  // until 300 ms have passed with none open (Radix's skip window).
  property bool tipWarm: false
  property int tipsOpen: 0

  // The key after the click (2026-10-30, docs/hints.md C): when the mouse
  // does what a key also does, the status line names the key, once a day
  // for each action, and never again once that key has been used three
  // times. Only keys that work from where the student is (the page's own
  // and the note's), never a list's Enter. In the state folder,
  // taught.json: action → { keys: times it came by key, said: the day it
  // was last named }.
  property var taught: ({})
  property double hintAt: 0
  function mouseDid(id) { Qt.callLater(root.nameKey, id) }   // after the click's own hint
  function nameKey(id) {
    var a = Sc.byId[id]
    if (!a || (a.places.indexOf("any") < 0 && a.places.indexOf("note") < 0)) return
    var k = Sc.label(id)
    if (k === "—") return
    var counted = root.countKeys()
    var t = root.taught[id] || {}
    var day = Qt.formatDate(new Date(), "yyyy-MM-dd")
    if ((t.keys || 0) >= 3 || t.said === day) { if (counted) root.writeTaught(); return }
    var say = "next time: " + k
    root.showHint(root.hint !== "" && Date.now() - root.hintAt < 200 ? root.hint + " · " + say : say)
    t.said = day
    root.taught[id] = t
    root.used("taught", id)
    root.writeTaught()
  }
  // What came by key since last asked, into `taught`; true when anything did.
  function countKeys() {
    var u = Sc.takeUses(), any = false
    for (var id in u) {
      var t = root.taught[id] || {}
      t.keys = (t.keys || 0) + u[id]
      root.taught[id] = t
      any = true
    }
    return any
  }
  function writeTaught() { taughtFile.setText(JSON.stringify(root.taught) + "\n") }
  function tipOpened() { root.tipsOpen++; root.tipWarm = true; tipCool.stop() }
  function tipClosed() {
    root.tipsOpen = Math.max(0, root.tipsOpen - 1)
    if (root.tipsOpen === 0) tipCool.restart()
  }

  // A row the keys come to says so (`on`), and again when they leave it;
  // the pointer goes to it while its pane has the keys.
  // An item of a pane's conversation brought into view, as little as it
  // takes (2026-11-28: ↑↓ walked to cards and folded lines out of sight).
  function revealIn(flick, item) {
    if (!flick || !item || !item.visible) return
    var y = item.mapToItem(flick.contentItem, 0, 0).y, h = item.height, pad = root.sp(12)
    var top = Math.max(0, flick.contentHeight - flick.height)
    if (y - pad < flick.contentY) flick.contentY = Math.max(0, y - pad)
    else if (y + h + pad > flick.contentY + flick.height) flick.contentY = Math.min(top, Math.min(y - pad, y + h + pad - flick.height))
  }
  // PgUp / PgDn from a pane's box: a screen of its conversation.
  function pageFlick(flick, event) {
    var d = Sc.hit(event, "chatPageUp") ? -1 : Sc.hit(event, "chatPageDown") ? 1 : 0
    if (!flick || d === 0) return false
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + d * flick.height * 0.85))
    return true
  }

  function selected(item, pane, on) {
    if (on) root.marks[pane] = item
    else if (root.marks[pane] === item) delete root.marks[pane]
    else return
    if (root.pointerMode === "every" && pane === root.here) warpTimer.restart()
  }

  onHereChanged: {
    if (root.paneAlone) root.paneTucked = root.here !== "right"
    if (root.pointerMode !== "off") warpTimer.restart()
    if (root.hereWas === "center" && root.here === "right") Qt.callLater(root.blipContext)
    root.hereWas = root.here
  }
  onCenterViewChanged: if (root.pointerMode !== "off") warpTimer.restart()
  onRightViewChanged: if (root.pointerMode !== "off" && root.here === "right") warpTimer.restart()

  // Keep warp targets inside the page's own window so Hyprland follow_mouse
  // never steals focus to an adjacent window when an item sits off-screen.
  function clampTarget(t) {
    if (!t || content.width <= 0 || content.height <= 0) return t
    var pad = Math.min(8, Math.floor(Math.min(content.width, content.height) / 4))
    return {
      x: Math.max(pad, Math.min(content.width - pad, t.x)),
      y: Math.max(pad, Math.min(content.height - pad, t.y)),
      w: t.w,
      h: t.h
    }
  }

  // What the pointer goes to in the pane with the keys: the row selected,
  // the note's cursor, the box typed in; at worst the pane itself.
  function pointerTarget() {
    var pane = root.here
    if (pane === "center" && root.centerView === "note" && !root.searchOpen && !root.whenFor && !root.newProject) {
      var r = editor.cursorRect
      var at = editor.mapToItem(content, r.x + root.sp(14), r.y + r.height / 2)
      return root.clampTarget({ x: at.x, y: at.y, w: root.sp(28), h: r.height })
    }
    var it = root.marks[pane]
    var ok = false
    try { ok = !!it && it.visible && it.width > 0 && root.paneOf(it) === pane } catch (e) { ok = false }
    // No row: the box being typed in, else the pane itself (its middle,
    // as Hyprland's warp goes to a window's).
    if (!ok) it = root.boxes().filter(function (b) { return b.activeFocus })[0] || root.paneItem(pane)
    if (!it) return null
    var c = it.mapToItem(content, Math.min(it.width / 2, root.sp(160)), it.height / 2)
    return root.clampTarget({ x: c.x, y: c.y, w: Math.min(it.width, root.sp(320)), h: it.height })
  }

  function boxes() {
    return [searchField, whenField, nameField, sidebar.projectFieldRef, margin.chatFieldRef, dayPane.dayFieldRef,
            keysSheet.keysFieldRef, settingsSheet.settingsFieldRef, notebookSheet.notebookFieldRef, dash.dashWhenFieldRef]
  }

  // Which pane an item is drawn in.
  function paneOf(item) {
    for (var p = item; p; p = p.parent) {
      if (p === sidebar) return "left"
      if (p === margin || p === dayPane) return "right"
      if (p === content) return "center"
    }
    return ""
  }

  function paneItem(pane) {
    if (pane === "left") return root.leftShown ? sidebar : null
    if (pane === "right") return root.rightView === "day" ? dayPane : root.rightView !== "" ? margin : null
    var v = root.centerView
    if (v === "dash") return dash
    if (v === "keys") return keysSheet
    if (v === "settings") return root.settingsView === "notebook" ? notebookSheet : root.settingsView === "autonomy" ? autonomySheet
      : root.settingsView === "search" ? searchSheet : root.settingsView === "checkin" ? checkinSheet : settingsSheet
    return sheet
  }

  // Whether a point of the overlay is within the span of its cards — the
  // sidebar, the middle, the agent's pane — and not the screen around them.
  function amongCards(x, y) {
    var lo = Infinity, hi = -Infinity
    var cards = [root.paneItem("left"), root.paneItem("center"), root.paneItem("right")]
    for (var i = 0; i < cards.length; i++) {
      var c = cards[i]
      if (!c || !c.visible) continue
      lo = Math.min(lo, c.x)
      hi = Math.max(hi, c.x + c.width)
    }
    return x >= lo && x <= hi && y >= root.sheetMargin && y <= content.height - root.sheetMargin
  }

  function warpNow() {
    if (!root.showing || root.pointerMode === "off") return
    if (Date.now() - root.handMovedAt < 700) return
    // The window not the active one: the compositor would not move the
    // pointer, so its motion must not be taken for a warp's either — the
    // hand's real motion was ignored for a moment after a warp that never
    // happened (2026-11-25, the mouse pass).
    if (!root.overlayOpen && !content.Window.active) return
    var t = root.pointerTarget()
    if (!t) return
    // Already there: nothing to move.
    if (handHover.hovered) {
      var h = handHover.point.position
      if (Math.abs(h.x - t.x) <= t.w / 2 && Math.abs(h.y - t.y) <= t.h / 2) return
    }
    var x = Math.round(t.x), y = Math.round(t.y)
    var lua = root.overlayOpen
      ? 'local m = hl.get_monitor("' + String(panel.screen ? panel.screen.name : "").replace(/[^A-Za-z0-9_.-]/g, "") + '"); '
        + 'if m then hl.dispatch(hl.dsp.cursor.move({ x = m.position.x + ' + x + ', y = m.position.y + ' + y + ' })) end'
      : 'local w = hl.get_window("title:^' + root.windowTitle + '$"); '
        + 'if w and w.active then hl.dispatch(hl.dsp.cursor.move({ x = w.at.x + ' + x + ', y = w.at.y + ' + y + ' })) end'
    root.warpedAt = Date.now()
    warpProc.running = false
    warpProc.command = ["hyprctl", "eval", lua]
    warpProc.running = true
  }

  function cyclePointer() {
    var order = ["panes", "every", "off"]
    root.setPointer(order[(order.indexOf(root.pointerMode) + 1) % order.length])
  }

  function setPointer(mode) {
    var cur = root.readSettings()
    cur.pointer = mode
    root.settingsData = cur
    settingsFile.setText(JSON.stringify(cur, null, 2) + "\n")
    root.used("pointer", cur.pointer)
  }

  // The agent's pane, all of it: the room it was in and the day's.
  function closeRight() {
    var was = root.here
    root.marginOpen = false
    root.marginFocus = -1
    root.closeTalk(false)
    root.dayOpen = false
    root.noteRoom = false
    root.dayRefs = []
    root.dayAutoHeld = null
    root.giveBack("right", was, "right")
  }

  // What reads the calendars waits for the fetch the same opening started
  // (refreshProjects, at most hourly), so the first pass of the day does not
  // read the copy from before it — but not for ever: a fetch that hangs
  // (no network) lets them go after 20 seconds, with the copy there is.
  property var waitingForFetch: []
  function afterFetch(fn) {
    if (!projectsProc.running) { fn(); return }
    root.waitingForFetch = root.waitingForFetch.concat([fn])
    fetchPatience.restart()
  }
  function fetched() {
    var w = root.waitingForFetch
    root.waitingForFetch = []
    fetchPatience.stop()
    for (var i = 0; i < w.length; i++) w[i]()
  }
  Timer { id: fetchPatience; interval: 20000; onTriggered: root.fetched() }

  function openPass() {
    if (!root.openPassPending) return
    if (projectsProc.running) { root.afterFetch(root.openPass); return }
    root.openPassPending = false
    root.requestRun("open", "")
  }

  // What the shell calls to hide the page: the overlay goes, the window
  // (if open) stays and gets the sheet back.
  function close() {
    // Kept as a window, the sheet is the same sheet in the other shape: the
    // keys or settings open in it stay open, and the keys stay where they
    // were (togglePin puts them back). On Windows the shell's hide calls
    // this again, so `pinning` is read here, not only in dismiss.
    if (!root.pinning) {
      if (root.keysOpen) root.toggleKeys()
      if (root.settingsOpen) root.toggleSettings()
    }
    if (root.switcherOpen) root.switcherDone()
    root.leftLine(root.lastLine)
    root.flush()
    pdfPane.keep()
    root.overlayOpen = false
    if (root.windowOpen && !root.pinning) Qt.callLater(editor.focusNote)
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

  // F11, Ctrl+Alt+P, or the overlay's "window" (2026-11-27, the shape
  // pass). On the overlay: the same sheet, kept as a window, and the
  // overlay closes. In the window: the window fills the screen, and back —
  // the compositor's own full screen (Hyprland's; Windows' through
  // windows/compositor.py), so the tile, Snap, the taskbar and Alt+Tab keep
  // it. Until then F11 in the window closed it and brought the overlay
  // back, which lost the window's tile and its Snap, and the header's
  // "pin" was lit in the window and dim over everything: the opposite of
  // what pin means everywhere else. The id stays "pin", for the keys.json
  // files that moved it.
  // The keys stay in the pane they were in (2026-11-25, the keyboard
  // pass): F11 from the dashboard, a PDF or the sidebar sent them to the
  // note, hidden or not.
  property string pinFrom: "center"
  property bool pinning: false
  function togglePin() {
    if (!root.overlayOpen) { root.fillScreen(); return }
    root.used("pin", "to-window")
    root.pinFrom = root.here
    root.flush()
    root.windowOpen = true
    root.pinning = true
    root.dismiss()
    root.pinning = false
    // The window takes the keys, on Hyprland and on Windows alike — also
    // when it was open already, behind the overlay or on another
    // workspace.
    Qt.callLater(root.raiseWindow)
    Qt.callLater(root.focusPinned)
  }
  function fillScreen() {
    if (!root.windowOpen) return
    root.used("pin", "full-screen")
    fullProc.running = false
    fullProc.command = ["hyprctl", "eval",
      'hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", window = "title:^' + root.windowTitle + '$" }))']
    fullProc.running = true
  }
  function focusPinned() {
    var p = root.pinFrom
    root.pinFrom = "center"
    if (!root.focusPane(p)) root.focusCenter()
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
    if (keepCursor) editor.setCursor(Math.min(at, editor.length), editor.holdsFocus())
    root.tickedCount = Queue.countTicked(t)
    root.scheduleRepaint()
  }

  function flush() {
    saveTimer.stop()
    if (svc.ready) svc.save(editor.text)
  }

  // ------------------------------------------------------------ triggers

  function hashOfLine(lineIndex) {
    var blocks = Blocks.split(editor.text)
    var k = Blocks.blockAt(blocks, lineIndex)
    return k < 0 ? "" : blocks[k].hash
  }

  // For the margin: the block under the cursor, or the nearest one above.
  function hashNearLine(lineIndex) { return Queue.hashNear(Blocks.split(editor.text), lineIndex) }

  function requestRun(trigger, hash) {
    if (!root.agentOn) return
    root.flush()
    var cmd = [svc.runner, "run", "--trigger", trigger, "--date", svc.noteDate]
    if (hash) cmd.push("--hash", hash)
    root.enqueue(cmd, hash)
  }

  property string hint: ""   // a passing word (a date that did not read, what a check did, …)
  // What the page says in passing, in the header's status line. It used to
  // float under the cursor and print over the line below it (2026-10-17);
  // up there it covers nothing, so it can stay long enough to be read.
  readonly property string status: root.hint
  function showHint(t) { root.hint = t; root.hintAt = Date.now(); hintTimer.restart() }
  // Ctrl+Enter, and the header's "chat": this block's chat. A block with a
  // sign for the agent (a checkbox, a closing ?, a tick) is sent, and the
  // agent speaks first; any other block opens its chat with the box ready,
  // and you do (2026-10-27: a block without a sign used to be refused, while
  // Alt+→ opened the same chat). One answered already is not asked again.
  function sendCurrent() {
    if (!root.dayNote) return
    if (root.currentHash === "") { root.showHint("no block under the cursor"); return }
    if (!root.agentOn) { root.showHint("private: the agent sees nothing of this note"); return }
    if (root.blockPrivate(root.currentHash)) { root.showHint("private: the agent sees nothing of this block"); return }
    if (Queue.answered(root.currentRecord)) { root.openBlockChat("reopen"); return }
    if (root.currentTrigger === "") { root.openBlockChat("open"); return }
    // A dated item may still be binding. The agent has to see its dates as
    // deadlines, never as words to propose a second time (2026-10-13), so
    // the send waits for the queue — as the prompt used to before it went.
    root.markSending([root.currentHash])
    root.whenWritten(function () {
      var h = root.hashNearLine(root.lineIndexAt(editor.cursorPosition))
      if (h === "") { root.doneSending(); return }
      var trigger = root.triggerForBlock(h)
      if (trigger === "") { root.doneSending(); root.openBlockChat("open"); return }
      // A list of boxes is one submission however it is sent.
      root.send(trigger, trigger === "checkbox" || trigger === "tick" ? Queue.listAround(Blocks.split(editor.text), h) : [h], h)
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

  function openBlockChat(how) {
    if (root.marginWidth <= 0) { root.showHint("the window is too narrow for the chat"); return }
    root.used(how === "reopen" ? "reopen" : "chat", how)
    root.diveIn(true)
  }

  // The header's "chat" (2026-11-26, the header pass): what Ctrl+Enter
  // does, the keys left where it leaves them — in the chat's box when the
  // chat opens, in the note when the block was sent and the agent answers
  // first. Lit while the chat is open, it closes it, as Esc there does.
  function chatClicked() {
    if (root.marginOpen) {
      root.backToNote()
      editor.focusNote()
      return
    }
    root.sendCurrent()
    if (!root.marginOpen) editor.focusNote()
  }

  // The header's "a reply": the first block whose answer is unread, its
  // chat opened as a click on its gutter bar opens it.
  function openUnread() {
    var p = root.paint
    for (var i = 0; i < p.length; i++) {
      if (!p[i].unread) continue
      var r = editor.rows[p[i].line]
      if (!r) return
      editor.setCursor(r.start + r.prefixLen, true)
      root.sendCurrent()
      return
    }
  }

  function blockPrivate(hash) {
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++) if (blocks[i].hash === hash) return !!blocks[i].private
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
      if (!editor.isShown(blocks[i].start)) continue      // folded away (Focus.js)
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

  function triggerForBlock(hash) { return Queue.triggerOf(Blocks.split(editor.text), hash) }

  function markSending(hashes) {
    root.sending = Queue.away(root.sending, Blocks.split(editor.text), hashes)
    root.scheduleRepaint()
  }

  // `ran`: what the failed run was for (its hash, or a list's). Only the
  // message it carried is let go — another waiting for its own run stays —
  // and what was written comes back to its box: in it, if the pane is
  // still on what it was about; else kept for when it is (the margin's
  // drafts), or said to be lost (2026-11-28: every failure lost it).
  function runnerFailed(ran) {
    var first = Queue.failure(runner.said)
    runner.said = ""
    var hit = function (h) { return !ran || (!!h && String(ran).split(",").indexOf(h) >= 0) }
    var back = false, elsewhere = false
    var p = root.pendingChat
    if (p && (hit(p.mark) || hit(p.hash))) {
      root.pendingChat = null      // it never reached the agent; do not pretend it did
      if (p.subject === root.marginSubject) back = root.giveBackSent("margin", p)
      else { root.keepMarginDraft(p.subject, p); elsewhere = true }
    }
    var d = root.dayPending
    if (d && hit(d.room)) {
      root.dayPending = null
      if (d.room === root.roomHash) back = root.giveBackSent("day", d) || back
      else elsewhere = true
    }
    root.showHint("the agent could not run" + (first === "" ? "" : " — " + first)
      + (back ? " · what you wrote is back in the box" : elsewhere ? " · what you wrote waits in its chat's box" : ""))
  }

  function doneSending() {
    if (root.sending.length === 0) return
    root.sending = []
    root.scheduleRepaint()
  }

  // `hash` is the record's, `mark` the block's as the note has it now (they
  // differ once a box answered has been ticked): the record is asked, the
  // block is the one drawn as away.
  function requestChat(hash, message, mark, refs) {
    if (!root.agentOn) return
    root.markSending([mark || hash])
    root.flush()
    root.enqueue([svc.runner, "chat", "--hash", hash, "--message", message, "--date", svc.noteDate]
                 .concat(refs && refs.length > 0 ? ["--refs", JSON.stringify(refs)] : []), mark || hash)
    root.holdThinking("margin")
  }

  // In order, each once (Queue.added).
  function enqueue(cmd, hash) {
    var q = Queue.added(root.queued, cmd, hash)
    if (q === root.queued) return
    root.queued = q
    if (!svc.saving) root.launchQueued()
  }

  function launchQueued() {
    if (root.queued.length === 0 || root.running || svc.saving) return
    var q = root.queued[0]
    root.queued = root.queued.slice(1)
    root.running = true
    root.runningHash = q.hash
    root.runAnswered = false
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
      var rec = agent.record(root.recordHash(b.hash, b.text, b))
      var flying = root.sending.indexOf(b.hash) >= 0
      if (!rec && !flying) continue
      var r = editor.blockRect(b.start, b.end)
      if (!r) continue
      out.push({ hash: b.hash, line: b.start, y: r.y, h: r.h, sending: flying,
                 reply: !!rec && rec.state === "reply",
                 unread: !!rec && rec.state === "reply" && !rec.read })
    }
    root.paint = out
    // Private blocks one after another, only blank lines between, are one
    // sheet of paper with one lock (2026-11-13) — unless the cursor stands
    // on a blank line between them: what is written there is not private,
    // so it is never drawn on the paper. The lock stands by the first line
    // of words, where a reader starts, not by the `> [!private]` line,
    // which is only the paper's top edge.
    var priv = []
    var run = null
    for (var k = 0; k < blocks.length; k++) {
      if (!blocks[k].private || blocks[k].kind !== "callout") { run = null; continue }
      var pr = editor.blockRect(blocks[k].start, blocks[k].end)
      if (!pr) { run = null; continue }
      var cursorBetween = run && editor.focusedRow >= run.end && editor.focusedRow < blocks[k].start
      if (run && !cursorBetween && root.onlyBlank(run.end, blocks[k].start)) {
        run.h = pr.y + pr.h - run.y
        run.end = blocks[k].end
        continue
      }
      var first = blocks[k].start
      var head = editor.rowItem(first)
      if (head && head.sunkHead && first + 1 < blocks[k].end) first++
      var it = editor.rowItem(first)
      run = { y: pr.y, h: pr.h, end: blocks[k].end,
              lockY: it ? it.y + it.gapTop + it.firstLine / 2 : pr.y + pr.h / 2 }
      priv.push(run)
    }
    root.privatePaint = priv
    root.currentHash = root.hashNearLine(root.lineIndexAt(editor.cursorPosition))
  }

  // Lines [a, b) of the note are all blank, and drawn (none folded away).
  function onlyBlank(a, b) {
    var rows = editor.rows
    for (var i = a; i < b; i++) if (!rows[i] || !rows[i].blank || !editor.isShown(i)) return false
    return true
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
  // — `Queue.listAround` works that out from the cursor.
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
  // `#` does the same for any tag (2026-10-18, Tags.js): the tags that
  // exist, so a new tag is a choice and not a typo — once a letter follows
  // it, so starting a heading never flashes a list, and never once what is
  // written is a tag already.
  function updateMention() {
    if (!svc.ready || !root.showing) { root.mention = null; return }
    var pos = editor.cursorPosition
    var text = editor.text
    var before = text.substring(text.lastIndexOf("\n", pos - 1) + 1, pos)
    // Only at a word's start, so an address ("a@b") is never a call.
    var m = before.match(/(^|\s)([@#])([\w\/-]*)$/)
    if (!m) { root.mention = null; return }
    var q = m[3].toLowerCase()
    var items = []
    // Making a project (2026-10-22): when nothing matches, a tag nothing
    // goes by yet may become one. Under `@`, a call, Enter makes it; under
    // `#` only for a tag written nowhere yet — the moment a new tag is a
    // choice — and it waits for ↓: Enter stays a new line.
    var make = Tags.canMake(m[3]) && !Tags.isProject(root.projects, m[3]) ? { make: true, tag: m[3] } : null
    if (m[2] === "#") {
      // The note's tags, without the one being written (it would count as
      // written already, and close the list on its own first letter).
      var rest = text.substring(0, pos - m[3].length - 1) + text.substring(pos)
      var known = Tags.known(root.projects, root.tasks, rest)
      items = Tags.suggest(known, q)
      if (make && items.length === 0 && !known.some(function (t) { return t.tag.toLowerCase() === q })) items = [make]
      if (items.length === 0) { root.mention = null; return }
    } else {
      for (var i = 0; i < root.projects.length; i++) {
        var pr = root.projects[i]
        if (q === "" || pr.tag.toLowerCase().indexOf(q) >= 0 || String(pr.name || "").toLowerCase().indexOf(q) >= 0)
          items.push(pr)
      }
      if (make && items.length === 0) items.push(make)
    }
    var start = pos - m[3].length - 1
    var fresh = !root.mention || root.mention.start !== start
    var waits = m[2] === "#" && items.length === 1 && !!items[0].make
    root.mention = { start: start, query: m[3], items: items, sign: m[2],
                     atLineStart: m[1] === "" && m[2] === "@" }
    if (fresh) root.mentionFocus = waits ? -1 : 0
    else if (root.mentionFocus > items.length - 1) root.mentionFocus = waits ? Math.min(root.mentionFocus, 0) : Math.max(0, items.length - 1)
  }

  // Enter puts the project's tag where the `@` was. Shift+Enter starts the
  // class instead — only where the `@` opened the line, since a heading in
  // the middle of a sentence is not what anyone meant.
  function acceptMention(shift) {
    var m = root.mention
    if (!m || m.items.length === 0) return
    var pr = m.items[root.mentionFocus]
    if (!pr) return
    var to = editor.cursorPosition
    root.mention = null
    if (pr.make) {
      root.askProjectName({ start: m.start, end: to, tag: pr.tag, heading: shift && m.atLineStart })
      return
    }
    // A step of its own (2026-11-27): Ctrl+Z gives back what was typed,
    // `@wor`, not the line as it was before it.
    editor.snapshot(true)
    if (shift && m.atLineStart) {
      editor.replace(m.start, to, "# " + (pr.name || pr.tag) + " #" + pr.tag)
      root.used("mention", "class")
    } else {
      editor.replace(m.start, to, "#" + pr.tag + " ")
      root.used(m.sign === "#" ? "tag-suggested" : "mention", "tag")
    }
  }

  function mentionKey(event) {
    if (!root.mention || root.mention.items.length === 0) return false
    // The one row offering a new `#tag` as a project, not yet chosen: ↓
    // chooses it, Esc closes it, and every other key is the note's.
    if (root.mentionFocus < 0) {
      if (Sc.hit(event, "mentionDown")) { root.mentionFocus = 0; return true }
      if (Sc.hit(event, "mentionClose")) { root.mention = null; return true }
      return false
    }
    if (Sc.hit(event, "mentionUp") && root.mention.sign === "#" && root.mention.items.length === 1 && root.mention.items[0].make) {
      root.mentionFocus = -1
      return true
    }
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
    if (Sc.hit(event, "cueAccept") && root.acceptCue()) return true
    if (Sc.hit(event, "menu")) { root.menuKey(); return true }
    if (Sc.hit(event, "close")) {
      if (editor.focusTag !== "") root.unfocus()
      else if (!root.alongside) root.dismiss()
      return true
    }
    if (Sc.hit(event, "focusSection")) { root.toggleFocus(); return true }
    if (Sc.hit(event, "dayTasks")) { if (root.dayTasks.length > 0) root.dayTasksOpen = !root.dayTasksOpen; else root.showHint("no task is for this day"); return true }
    if (Sc.hit(event, "private")) { root.togglePrivate(); return true }
    if (Sc.hit(event, "privateBlock")) { root.togglePrivateBlock(); return true }
    if (Sc.hit(event, "exportPdf")) { root.openExport(); return true }
    if (Sc.hit(event, "ask")) { root.sendCurrent(); return true }
    // Selecting to the same edges is the editor's (selectToBlockEdge).
    if (Sc.hit(event, "blockStart")) { root.walkBlocks(-1); return true }
    if (Sc.hit(event, "blockEnd")) { root.walkBlocks(1); return true }
    if (Sc.hit(event, "dayPrev")) { root.stepDay(-1); return true }
    if (Sc.hit(event, "dayNext")) { root.stepDay(1); return true }
    if (Sc.hit(event, "find")) { root.openSearch(); return true }
    if (Sc.hit(event, "followLink")) {
      var l = editor.linkAtCursor()
      if (!l) { root.showHint("no link here"); return true }
      root.pdfFromTagNext = Focus.tagAt(editor.text, root.lineIndexAt(editor.cursorPosition))
      root.followLink(l)
      return true
    }
    // Emphasis, where every editor puts it. The sidebar moved to the
    // shifted pair on 2026-10-15 so that Ctrl+B could be bold.
    if (Sc.hit(event, "bold")) { editor.emphasise("**"); return true }
    if (Sc.hit(event, "italic")) { editor.emphasise("*"); return true }
    if (Sc.hit(event, "code")) { editor.emphasise("`"); return true }
    if (Sc.hit(event, "strike")) { editor.emphasise("~~"); return true }
    if (Sc.hit(event, "link")) { editor.makeLink(); return true }
    if (Sc.hit(event, "deadline")) {
      var dr = editor.rows[root.lineIndexAt(editor.cursorPosition)]
      if (dr && dr.priv) root.showHint("private: a box here never becomes a deadline")
      else if (root.dayNote) root.deadlineKey()
      return true
    }
    return false
  }

  // `toChat`: land in the box with the cursor in it, whatever else is
  // there — the way in when the answer already exists and the next thing
  // to do is reply to it.
  function diveIn(toChat) {
    root.used("margin")
    if (root.marginWidth <= 0 || root.currentHash === "") return
    root.ensureRoomFor("right")
    if (root.here !== "right") root.noteFrom("right")
    root.marginOpen = true
    if (root.refFiles.length === 0) root.loadRefFiles()   // what `@` offers here too: notes and papers
    if (root.marginLiveCards.length > 0 && toChat !== true) {
      root.marginFocus = root.marginLiveCards[0]
      margin.marginKeysRef.forceActiveFocus()
    } else {
      root.marginFocus = root.currentProposals.length
      margin.chatFieldRef.forceActiveFocus()
    }
  }

  // To the note, from wherever the keys are: what stands in the middle in
  // its place closes (the dashboard, the keys, settings), and the keys go
  // to the note — going to a line, a day or a section ends here. The
  // block's margin closes too with `toNote`, the cursor being on its way
  // to another block.
  function showNote() {
    if (root.keysOpen) root.toggleKeys()
    if (root.settingsOpen) root.toggleSettings()
    if (root.dashOpen) root.toggleDash()
    if (root.pdfShown) Qt.callLater(function () { pdfPane.keysRef.forceActiveFocus() })
    else editor.focusNote()
  }

  function toNote() {
    root.marginFocus = -1
    root.marginOpen = false
    root.showNote()
  }

  // Esc in a block's conversation. The day is the pane's home: out of a
  // block's room, back to the day; with no day open, the pane closes and
  // the keys go back where they were (the note's cursor where it was).
  function backToNote() {
    var was = root.here
    root.marginFocus = -1
    root.marginOpen = false
    if (was === "right" && root.rightView === "day") root.dayKeysItem().forceActiveFocus()
    else root.giveBack("right", was, "right")
  }

  // The margin's cards the keys walk: the open ones, in the order they are
  // drawn (2026-11-28: ↑↓ went by index through every card, those accepted,
  // declined or replaced too, as the day's and a task's never did).
  function marginCardLive(i) {
    var p = root.currentProposals[i]
    if (!p) return false
    if (p.ledger) return !!root.dayCardLive({ id: p.ledger })
    return !p.accepted && !p.superseded && !p.declined && !root.blockCardDeclined(root.currentRec, i)
  }
  readonly property var marginLiveCards: root.marginRows.filter(function (r) { return r.card !== undefined && root.marginCardLive(r.card) })
    .map(function (r) { return r.card })
  function moveMarginFocus(d) {
    var live = root.marginLiveCards, n = root.currentProposals.length
    var at = live.indexOf(root.marginFocus)
    var k = at < 0 ? (d < 0 ? live.length - 1 : live.length) : Math.max(0, at + d)
    if (k >= live.length) {
      root.marginFocus = n
      margin.chatFieldRef.forceActiveFocus()
      return
    }
    root.marginFocus = live[k]
    margin.marginKeysRef.forceActiveFocus()
  }

  // A card in the one list (a day for a box, or dropping one): settled as
  // the day's cards are, the item read from the list as it is now.
  function settleListedCard(c, how) {
    var live = c && c.ledger ? root.dayCardLive({ id: c.ledger }) : null
    if (!live) return false
    if (root.settleCard(live, how)) root.used("margin", "card-" + how)
    return true
  }

  function declineProposal(i) {
    var p = root.currentProposals[i]
    if (!p) return
    if (p.ledger) { root.settleListedCard(p, "decline"); return }
    if (p.accepted || p.superseded || p.declined || root.currentRec === "") return
    var m = {}
    for (var k in root.declinedBlockCards) m[k] = root.declinedBlockCards[k]
    m[root.currentRec + ":" + String(i)] = true
    root.declinedBlockCards = m
    root.saveDecline(root.currentRec, i, svc.noteDate)
    root.used("margin", "card-decline")
  }
  // A decline is kept on the card by the runner, as an accept is (`accept
  // --decline`): the page's own list above only draws it at once, and was
  // all there was until 2026-11-20, so a restart offered the card again.
  property var declinesWaiting: []
  function saveDecline(hash, index, date) {
    root.declinesWaiting = root.declinesWaiting.concat([[svc.runner, "accept", "--hash", String(hash), "--index", String(index), "--date", String(date), "--decline"]])
    root.nextDecline()
  }
  function nextDecline() {
    if (declineProc.running || root.declinesWaiting.length === 0) return
    declineProc.command = root.declinesWaiting[0]
    root.declinesWaiting = root.declinesWaiting.slice(1)
    declineProc.running = true
  }

  function acceptProposal(i) {
    var p = root.currentProposals[i]
    if (p && p.ledger) { root.settleListedCard(p, "accept"); return }
    if (!p || p.accepted || p.superseded || p.declined || root.blockCardDeclined(root.currentRec, i) || root.currentRec === "" || acceptProc.running) return
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
    var was = root.here
    if (!root.keysOpen) root.noteFrom("keys", root.settingsOpen ? root.openedFrom.settings : was)
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
    } else {
      root.giveBack("keys", was, "center")
    }
  }

  // Settings: one sheet, one section so far. Opening it reads the
  // timetable's state (no fetch); Enter in the field saves an address and
  // fetches at once, so whether it worked is seen, not hoped for.
  function toggleSettings() {
    var was = root.here
    if (!root.settingsOpen) root.noteFrom("settings", root.keysOpen ? root.openedFrom.keys : was)
    if (!root.settingsOpen && root.keysOpen) root.toggleKeys()
    root.settingsOpen = !root.settingsOpen
    root.settingsNote = ""
    root.settingsFieldKind = "add"
    root.settingsAsking = -1
    root.settingsView = "main"
    root.notebookCorrecting = false
    if (root.settingsOpen) {
      root.used("settings")
      settingsSheet.settingsFieldRef.text = ""
      root.settingsFocus = 0
      root.runTimetable([])
      root.loadNotebook()
      root.loadAutonomy()
      root.loadSearchFolders()
      root.loadHorizon()
      root.loadCheckin()
      if (!agentChecksProc.running) {
        agentChecksProc.command = [svc.runner, "eval", "status", "--json"]
        agentChecksProc.running = true
      }
      Qt.callLater(settingsSheet.focusActive)
    } else {
      root.giveBack("settings", was, "center")
    }
  }

  // Settings as a list (2026-10-28, docs/keys-proposal.md): ↑↓ walk every
  // setting in the order the sheet draws them, and Space or Enter changes
  // the picked one or opens it — the sound, the pointer and the agent's
  // three sheets each had a Ctrl letter of their own until then. The field
  // that adds a calendar is a row too: keys type into it while it is
  // picked, and typing from any row picks it.
  readonly property var settingsKinds: ["field", "notebook", "autonomy", "search", "checkin", "sound", "pointer"]
  readonly property int calendarCount: root.settingsState && root.settingsState.configured ? root.settingsState.calendars.length : 0
  property int settingsAsking: -1      // the calendar Del asked about, until Enter or Esc
  function settingsAt(kind) { return root.calendarCount + root.settingsKinds.indexOf(kind) }
  function settingsPicked() {
    if (root.settingsFocus < root.calendarCount) return "calendar"
    return root.settingsKinds[root.settingsFocus - root.calendarCount] || "field"
  }

  function changeSetting(kind) {
    root.used("setting", kind)        // by key: a click goes straight to its own
    if (kind === "calendar") root.fetchCalendar(root.settingsFocus)
    else if (kind === "notebook") root.openNotebook()
    else if (kind === "autonomy") root.openAutonomy()
    else if (kind === "search") root.openSearchFolders()
    else if (kind === "checkin") root.openCheckin(false)
    else if (kind === "sound") root.toggleTickSound()
    else if (kind === "pointer") root.cyclePointer()
  }

  // Del asks first, as a removal should: the calendar's address is gone
  // with it, and it was a paste away from a sign-in.
  function askRemoveCalendar(i) {
    if (i < 0 || i >= root.calendarCount) return
    root.settingsFocus = i
    root.settingsAsking = i
    root.settingsNote = ""
  }

  // The keys every list shares (2026-11-25, the keyboard pass; the fixed
  // row "In every list" in Shortcuts.js): ↑↓ and j k a row, Home and End
  // the first and last. The row the key goes to, kept between `first` and
  // `last`; -2 when it is none of them. `step(at, dir)` walks past rows
  // that are not picked (a heading), when a list has them.
  function listStep(seq, at, first, last, step) {
    var by = step || function (i, d) { return Math.max(first, Math.min(last, i + d)) }
    if (seq === "Up" || seq === "K") return by(at, -1)
    if (seq === "Down" || seq === "J") return by(at, 1)
    if (seq === "Home") return step ? step(first - 1, 1) : first
    if (seq === "End") return step ? step(last + 1, -1) : last
    return -2
  }

  function settingsKey(event) {
    if (root.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    if (root.settingsAsking >= 0) {
      var asked = root.settingsAsking
      root.settingsAsking = -1
      if (seq === "Enter") { root.removeCalendar(asked); return true }
      if (seq === "Esc") return true
    }
    if (seq === "Esc") {
      if (root.settingsFieldKind === "rename") { root.settingsFieldKind = "add"; settingsSheet.settingsFieldRef.text = "" }
      else root.toggleSettings()
      return true
    }
    if (root.settingsFieldKind === "rename") {
      if (seq === "Enter") { root.renameCalendar(settingsSheet.settingsFieldRef.text); return true }
      return false
    }
    var last = root.calendarCount + root.settingsKinds.length - 1
    var kind = root.settingsPicked()
    // The field's row types: only the arrows leave it (the letters, Home
    // and End are its own). The `k` and `j` here never matched: a key is
    // written as its capital (2026-11-25).
    var to = kind === "field" ? (seq === "Up" || seq === "Down" ? root.listStep(seq, root.settingsFocus, 0, last) : -2)
      : root.listStep(seq, root.settingsFocus, 0, last)
    if (to !== -2) { root.settingsFocus = to; return true }
    if (kind !== "field" && Sc.hit(event, "keysHere")) { root.toggleKeys(); return true }
    if (kind === "field") {
      if (seq === "Enter") { root.addCalendar(settingsSheet.settingsFieldRef.text); return true }
      return false
    }
    if (kind === "calendar") {
      if (Sc.hit(event, "settingsFetch")) { root.fetchCalendar(root.settingsFocus); return true }
      if (Sc.hit(event, "settingsForget")) { root.askRemoveCalendar(root.settingsFocus); return true }
      if (Sc.hit(event, "settingsShare")) { root.toggleShare(root.settingsFocus); return true }
      if (Sc.hit(event, "settingsRename")) { root.startRename(root.settingsFocus); return true }
    }
    if (Sc.hit(event, "settingsChange")) { root.changeSetting(kind); return true }
    return false
  }

  // What the agent may do (Settings → The agent, picked and Enter; docs/agent.md,
  // "Actions, and how far each may go"): each kind at ask me, do it and
  // tell me, or never — the person's to set, kept in settings.json — with
  // its record, and past 9 of the last 10 accepted, the suggestion that it
  // could do more. Nothing is ever raised but by the person.
  property var autonomyData: null          // `longhand-agent autonomy`
  property int autonomyFocus: 0
  readonly property var autonomyLevels: ["ask", "do", "never"]

  function loadAutonomy() {
    if (!svc.configured) return
    if (autonomyProc.running) { autonomyProc.again = true; return }   // read again once it ends: what changed meanwhile counts
    autonomyProc.command = [svc.runner, "autonomy"]
    autonomyProc.running = true
  }

  // How Longhand feels, once a week (2026-11-18, the UX evaluation's F7;
  // agent/checkin.py, CheckinSheet.qml): never a pop-up — the dashboard
  // says it is due, and F or a click opens it; Settings has it too.
  property var checkinData: null            // `longhand-agent checkin`
  property var checkinAnswers: [0, 0, 0, 0, 0, 0, 0, 0]
  property int checkinFocus: 0
  property bool checkinFromDash: false
  readonly property int checkinLeft: root.checkinAnswers.filter(function (a) { return !a }).length
  readonly property bool checkinDue: !!root.checkinData && root.checkinData.due
  readonly property var checkinWeeks: root.checkinData ? root.checkinData.weeks.slice().reverse() : []
  function loadCheckin() {
    if (checkinProc.running) { checkinProc.again = true; return }   // read again once it ends: what changed meanwhile counts
    checkinProc.command = [svc.runner, "checkin"]
    checkinProc.running = true
  }
  function openCheckin(fromDash) {
    if (!root.settingsOpen) root.toggleSettings()
    root.checkinFromDash = !!fromDash
    root.settingsView = "checkin"
    root.checkinAnswers = [0, 0, 0, 0, 0, 0, 0, 0]
    root.checkinFocus = 0
    root.used("checkin", fromDash ? "dash" : "settings")
    root.loadCheckin()
    Qt.callLater(checkinSheet.checkinKeysRef.forceActiveFocus)
  }
  function closeCheckin() {
    if (root.checkinFromDash) { root.checkinFromDash = false; root.toggleSettings() }   // back where it came from
    else root.closeNotebook()                                                           // to Settings' list
  }
  function setCheckin(i, step, advance) {
    var a = root.checkinAnswers.slice()
    a[i] = step
    root.checkinAnswers = a
    if (advance && i < a.length - 1) root.checkinFocus = i + 1
  }
  function checkinKey(event) {
    if (root.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    var f = root.checkinFocus, n = root.checkinAnswers.length
    if (seq === "Esc") { root.closeCheckin(); return true }
    var to = root.listStep(seq, f, 0, n - 1)
    if (to !== -2) { root.checkinFocus = to; return true }
    if (Sc.hit(event, "keysHere")) { root.toggleKeys(); return true }
    if (seq === "Left" || seq === "Right") {
      var cur = root.checkinAnswers[f] || 4
      root.setCheckin(f, Math.max(1, Math.min(7, cur + (seq === "Left" ? -1 : 1))), false)
      return true
    }
    if (/^[1-7]$/.test(seq)) { root.setCheckin(f, parseInt(seq, 10), true); return true }
    if (seq === "Enter") { root.keepCheckin(); return true }
    if (seq === "Del" || seq === "Backspace") { root.skipCheckin(); return true }
    return false
  }
  function keepCheckin() {
    if (root.checkinLeft > 0) {
      root.checkinFocus = root.checkinAnswers.indexOf(0)
      root.showHint(root.checkinLeft + (root.checkinLeft === 1 ? " line" : " lines") + " to go")
      return
    }
    checkinSaveProc.command = [svc.runner, "checkin", "--answers", root.checkinAnswers.join(",")]
    checkinSaveProc.kept = true
    checkinSaveProc.running = true
  }
  function skipCheckin() {
    checkinSaveProc.command = [svc.runner, "checkin", "--skip"]
    checkinSaveProc.kept = false
    checkinSaveProc.running = true
  }
  function signed(x) { return (x > 0 ? "+" : x < 0 ? "−" : "±") + Math.abs(x).toFixed(1) }
  function sayCheckinWeek(w) {
    var a = w.acted || {}
    var agent = a.made > 0 ? "the agent: " + a.acted + " of " + a.made + " acted on (" + Math.round(a.share * 100) + "%)" : "the agent proposed nothing"
    return w.week.replace("-W", " week ") + "    "
      + (w.skipped ? "skipped" : "practical " + root.signed(w.pragmatic) + " · pleasant " + root.signed(w.hedonic))
      + "    ·  " + agent
  }
  function sayCheckin() {
    var d = root.checkinData
    if (!d) return ""
    var last = d.weeks.length > 0 ? d.weeks[d.weeks.length - 1] : null
    return d.due ? "this week: not answered yet" + (last && !last.skipped ? " · last: practical " + root.signed(last.pragmatic) + ", pleasant " + root.signed(last.hedonic) : "")
      : last.skipped ? "this week: skipped" : "this week: practical " + root.signed(last.pragmatic) + " · pleasant " + root.signed(last.hedonic)
  }

  function openAutonomy() {
    root.settingsView = "autonomy"
    root.used("autonomy")
    root.loadAutonomy()
    Qt.callLater(autonomySheet.autonomyKeysRef.forceActiveFocus)
  }

  function sayLevel(level) { return level === "do" ? "do it and tell me" : level === "never" ? "never" : "ask me" }

  function sayRecord(k) {
    if (!k || k.answered === 0) return k && k.ask_only ? "a question only: ticking is yours" : "nothing answered yet"
    var r = "you accepted " + k.accepted + " of the last " + k.answered
    if (k.suggest && k.level === "ask") r += " — it could do this and tell you"
    return k.ask_only ? r + " · a question only" : r
  }

  function setAutonomy(kind, level) {
    var cur = root.readSettings()
    var a = {}
    var was = cur.autonomy || {}
    for (var k in was) a[k] = was[k]
    a[kind] = level
    cur.autonomy = a
    root.settingsData = cur
    settingsFile.setText(JSON.stringify(cur, null, 2) + "\n")
    root.used("autonomy", kind + "=" + level)
    // Shown at once; the runner's answer follows.
    var d = root.autonomyData ? JSON.parse(JSON.stringify(root.autonomyData)) : null
    if (d) d.kinds.forEach(function (x) { if (x.kind === kind) x.level = level })
    root.autonomyData = d
    Qt.callLater(root.loadAutonomy)
  }

  function stepAutonomy(d) {
    var ks = root.autonomyData ? root.autonomyData.kinds : []
    var k = ks[root.autonomyFocus]
    if (!k) return
    var levels = k.ask_only ? ["ask", "never"] : root.autonomyLevels
    var i = Math.max(0, levels.indexOf(k.level))
    var next = levels[Math.max(0, Math.min(levels.length - 1, i + d))]
    if (next !== k.level) root.setAutonomy(k.kind, next)
  }

  function autonomyKey(event) {
    if (root.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    var n = root.autonomyData ? root.autonomyData.kinds.length : 0
    if (seq === "Esc") { root.closeNotebook(); return true }
    var to = root.listStep(seq, root.autonomyFocus, 0, Math.max(0, n - 1))
    if (to !== -2) { root.autonomyFocus = to; return true }
    if (Sc.hit(event, "keysHere")) { root.toggleKeys(); return true }
    if (seq === "Left") { root.stepAutonomy(-1); return true }
    if (seq === "Right" || seq === "Space" || seq === "Enter") { root.stepAutonomy(1); return true }
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

  // What the agent may search (Settings, picked and Enter; docs/agent.md, "The day
  // conversation"): each folder of the vault, on or off, the student's to
  // set in settings.json (`searchFolders`). Private notes and blocks,
  // `_Secrets`, other types and documents of identity, money, health,
  // contracts or secrets are never searched, whatever is switched on.
  property var searchData: null         // `longhand-agent search --folders`
  property int searchFocus: 0

  function loadSearchFolders() {
    if (!svc.configured) return
    if (searchFoldersProc.running) { searchFoldersProc.again = true; return }   // read again once it ends: what changed meanwhile counts
    searchFoldersProc.command = [svc.runner, "search", "--folders"]
    searchFoldersProc.running = true
  }

  function openSearchFolders() {
    root.settingsView = "search"
    root.used("search-folders")
    root.loadSearchFolders()
    Qt.callLater(searchSheet.searchKeysRef.forceActiveFocus)
  }

  function saySearchFolders() {
    var d = root.searchData
    if (!d) return ""
    var on = d.folders.filter(function (f) { return f.on })
    return "It may search " + on.length + " of " + d.folders.length + " folders."
  }

  function toggleSearchFolder(i) {
    var f = root.searchData ? root.searchData.folders[i] : null
    if (!f) return
    var cur = root.readSettings()
    var s = {}
    var was = cur.searchFolders || {}
    for (var k in was) s[k] = was[k]
    s[f.folder] = !f.on
    cur.searchFolders = s
    root.settingsData = cur
    settingsFile.setText(JSON.stringify(cur, null, 2) + "\n")
    root.used("search-folders", f.folder + "=" + (!f.on ? "on" : "off"))
    var d = JSON.parse(JSON.stringify(root.searchData))
    d.folders[i].on = !f.on
    root.searchData = d
    Qt.callLater(root.loadSearchFolders)
  }

  function searchFoldersKey(event) {
    if (root.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    var n = root.searchData ? root.searchData.folders.length : 0
    if (seq === "Esc") { root.closeNotebook(); return true }
    // Row -1 is the horizon, above the folders.
    var to = root.listStep(seq, root.searchFocus, -1, n - 1)
    if (to !== -2) { root.searchFocus = to; return true }
    if (Sc.hit(event, "keysHere")) { root.toggleKeys(); return true }
    if (root.searchFocus < 0) {
      if (seq === "Left" || seq === "Right") { root.moveHorizon(seq === "Left" ? -1 : 1); return true }
      if (seq === "Shift+Left" || seq === "Shift+Right") { root.moveHorizon(seq === "Shift+Left" ? -12 : 12); return true }
      if (seq === "Backspace" || seq === "Del") { root.setHorizon(""); return true }
      return seq === "Space" || seq === "Enter"
    }
    if (seq === "Space" || seq === "Enter") { root.toggleSearchFolder(root.searchFocus); return true }
    return false
  }

  // A reply's citations — `path` line N, or p. N — made links: a daily
  // note opens at that line, any other file in its own application.
  // A link's address with its parentheses written as %28 %29: a quote's
  // "(MOS)" closed the markdown link early and spilled the rest of it
  // into the answer (2026-11-16).
  function linkPart(s) { return encodeURIComponent(s).replace(/\(/g, "%28").replace(/\)/g, "%29") }
  // Not inside a fenced block of code (2026-11-28): a path written there
  // came out as "[name](cite:…)" in the code.
  function linkCitations(text) {
    var parts = String(text || "").split(/(^\s*(?:```|~~~)[^\n]*\n[\s\S]*?(?:\n\s*(?:```|~~~)[^\n]*(?=\n|$)|(?![\s\S])))/m)
    return parts.map(function (part, i) { return i % 2 === 1 ? part : root.linkCitationsIn(part) }).join("")
  }
  function linkCitationsIn(text) {
    var t = String(text || "")
    // The agent writes the page first as often as the path first:
    // “its words” (p. 8, `path.pdf`) was left a bare link to the file, no
    // page, no words (2026-11-22, every quote with a path in the log was
    // written so). Put in the one order before reading it.
    t = t.replace(/(“[^”\n]{3,300}”\s*)\(p\.\s*(\d+),?\s*(`[^`\n]+\.pdf`)\)/g, "$1($3, p. $2)")
    // Another paper's words, “its exact words” (`path.pdf`, p. 12), in any
    // chat (2026-11-19, a paper pointed at with `@`): it opens there, the
    // words lit a moment. The paper whose room this is: its own quote,
    // shown on its page and beside the answer.
    t = t.replace(/“([^”\n]{3,300})”\s*\(`([^`\n]+\.pdf)`,?\s*p\.\s*(\d+)\)/g, function (m, words, path, n) {
      if (root.paper.room && path === root.pdfRel)
        return "[“" + words + "” (p. " + n + ")](quote:" + n + ":" + root.linkPart(words) + ")"
      return "[“" + words + "” (" + root.fileName(path) + ", p. " + n + ")](pquote:"
        + n + ":" + root.linkPart(path) + ":" + root.linkPart(words) + ")"
    })
    // In a paper's chat, “its exact words” (p. 12) shows them on the page
    // (not one made a link above: its label ends "(p. 12)]").
    if (root.paper.room)
      t = t.replace(/“([^”\n]{3,300})”\s*\(p\.\s*(\d+)\)(?!\])/g, function (m, words, n) {
        return "[“" + words + "” (p. " + n + ")](quote:" + n + ":" + root.linkPart(words) + ")"
      })
    return t.replace(/`([^`\n]+\.(?:md|txt|pdf))`(?:,?\s*(line|p\.)\s*(\d+))?/g, function (m, path, kind, n) {
      var label = (/\.txt$/i.test(path) ? path.replace(/^.*\//, "") : root.fileName(path)) + (n ? (kind === "line" ? " · line " : " · p. ") + n : "")
      return "[" + label + "](cite:" + root.linkPart(path) + (n ? "#" + n : "") + ")"
    })
  }

  property int pendingLine: -1
  function openCitation(link) {
    var q = /^quote:(\d+):(.*)$/.exec(String(link))
    if (q) { root.used("paper-talk", "quote"); pdfPane.flash(parseInt(q[1]), decodeURIComponent(q[2])); return }
    var pq = /^pquote:(\d+):([^:]+):(.*)$/.exec(String(link))
    if (pq) {
      var prel = decodeURIComponent(pq[2]), ppage = parseInt(pq[1]), pwords = decodeURIComponent(pq[3])
      root.used("paper-talk", "quote-other")
      if (root.pdfShown && prel === root.pdfRel) { pdfPane.flash(ppage, pwords); return }
      root.openPdf(prel)
      pdfPane.flashAfter = { page: ppage, words: pwords }
      return
    }
    var m = /^cite:([^#]+)(?:#(\d+))?$/.exec(String(link))
    if (!m) return
    var path = decodeURIComponent(m[1])
    var line = m[2] ? parseInt(m[2]) : -1
    var daily = svc.config && svc.config.daily ? svc.config.daily.dir : ""
    root.used("citation")
    if (daily !== "" && path.indexOf(daily + "/") === 0 && /\.md$/.test(path) && path.slice(daily.length + 1).indexOf("/") < 0) {
      var stem = path.slice(daily.length + 1).replace(/\.md$/, "")
      root.pendingLine = line
      if (stem === svc.noteDate && svc.ready) root.landOnLine()
      else root.openNote(stem)
      return
    }
    if (/\.md$/i.test(path)) {
      root.pendingLine = line
      var ro = svc.agentRoot !== "" && (path === svc.agentRoot || path.indexOf(svc.agentRoot + "/") === 0)
      if (path === svc.filePath && svc.ready) { root.showNote(); root.landOnLine() }
      else root.openFile(path, ro)
      return
    }
    if (/\.pdf$/i.test(path)) {
      root.openPdf(path)
      // Kept until it is open and fitted (2026-11-27: a PDF not open yet
      // dropped the jump, its pages not read by the next moment).
      if (line > 0) pdfPane.pageAfter = { page: line - 1, y: 0 }
      return
    }
    Qt.openUrlExternally(Links.fileUrl(svc.config.vault + "/" + path))
  }

  function jumpToMark(id) {
    if (id && root.pdfShown) pdfPane.showMark(id)
  }

  function jumpToRef(r) {
    if (!r) return
    if (r.file) {
      if (/\.pdf$/i.test(r.file)) root.openPdf(r.file)
      else root.openFile(r.file, svc.agentRoot !== "" && (r.file === svc.agentRoot || r.file.indexOf(svc.agentRoot + "/") === 0))
      return
    }
    if (r.date && r.line !== undefined && r.line >= 0) {
      root.pendingLine = r.line + 1
      if (r.date === svc.noteDate && svc.ready) { root.showNote(); root.landOnLine() }
      else root.openNote(r.date)
      return
    }
    if (r.hash) {
      // Another day's block: that day's note, then the block once it has
      // loaded (2026-11-28: it opened at the top).
      if (r.date && r.date !== svc.noteDate) { root.pendingHash = r.hash; root.openNote(r.date); return }
      var blks = Blocks.split(editor.text)
      for (var i = 0; i < blks.length; i++) {
        if (blks[i].hash === r.hash) {
          root.showNote()
          var row = editor.rows[blks[i].start]
          if (row) editor.setCursor(row.start, true)
          return
        }
      }
    }
  }

  property string pendingHash: ""
  function landOnLine() {
    if (root.pendingHash !== "" && svc.ready) {
      var h = root.pendingHash
      root.pendingHash = ""
      var b = root.blockBounds(h)
      var row = b ? editor.rows[b.start] : null
      if (row) { editor.setCursor(row.start, true); return }
      root.showHint("that block is no longer in this note as it was")
    }
    if (root.pendingLine < 0) root.pendingWords = ""
    if (root.pendingLine < 0 || !svc.ready) return
    var i = Math.min(root.pendingLine - 1, editor.rows.length - 1)
    root.pendingLine = -1
    var words = root.pendingWords
    root.pendingWords = ""
    var r = editor.rows[Math.max(0, i)]
    if (!r) return
    editor.setCursor(r.start, true)
    // From the switcher's `? words`: the first of them selected in the
    // line, so the eye lands on it, not somewhere in a long paragraph.
    if (words === "") return
    var end = editor.text.indexOf("\n", r.start)
    var m = Switch.firstSpan(editor.text.slice(r.start, end < 0 ? editor.text.length : end), words)
    if (m) editor.select(r.start + m.a, r.start + m.b)
  }
  property string pendingWords: ""

  // Under an answer of the day's: what it searched for and read.
  function sayFetched(t) {
    if (!t) return ""
    var bits = []
    ;(t.searched || []).forEach(function (s) { bits.push("searched “" + s.words + "”" + (s.hits && s.hits.length ? "" : " (nothing)")) })
    ;(t.files || []).forEach(function (f) { bits.push("read " + root.fileName(f.path)) })
    // What it looked back at in the conversation (2026-11-21).
    ;(t.recalled || []).forEach(function (r) {
      var when = r.day ? new Date(r.day + "T12:00:00") : null
      bits.push("looked back" + (when ? " at " + Qt.formatDate(when, "ddd d MMM") : "") + (r.words ? " for “" + r.words + "”" : "")
        + (r.turns ? "" : " (nothing)"))
    })
    var docs = root.sayReads(t)
    if (docs !== "") bits.push(docs)
    // Documents it was asked to file: moved at once, so said, not a card.
    ;(t.filed || []).forEach(function (f) { bits.push("filed “" + f.name.replace(/\.pdf$/i, "") + "” in #" + f.project) })
    ;(t.unfiled || []).forEach(function (x) { bits.push("not filed: " + x) })
    var held = Say.sayWithheld(t.withheld)
    if (held !== "") bits.push(held)
    return bits.join(" · ")
  }

  function sayAutonomy() {
    var d = root.autonomyData
    if (!d) return ""
    var done = d.kinds.filter(function (k) { return k.level === "do" }).length
    var never = d.kinds.filter(function (k) { return k.level === "never" }).length
    return done === 0 && never === 0 ? "It asks before every action."
      : "It asks before most actions" + (done ? "; " + done + " it does and tells you" : "") + (never ? "; " + never + " never" : "") + "."
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
    if (notebookProc.running) { notebookProc.again = true; return }   // read again once it ends: what changed meanwhile counts
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
    root.notebookAsking = false
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
    root.notebookAsking = false
    Qt.callLater(settingsSheet.focusActive)
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

  // One at a time, in the order asked: a second forget or correction while
  // the first was written was dropped (2026-11-26, Windows CI).
  function notebookAct(args, note, event) {
    notebookActProc.queue = notebookActProc.queue.concat([{ args: args, note: note }])
    root.used("notebook", event)
    root.nextNotebookAct()
  }
  function nextNotebookAct() {
    if (notebookActProc.running || notebookActProc.queue.length === 0) return
    var j = notebookActProc.queue[0]
    notebookActProc.queue = notebookActProc.queue.slice(1)
    root.notebookPendingNote = j.note
    notebookActProc.command = [svc.runner, "notebook"].concat(j.args)
    notebookActProc.running = true
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

  // Del asks first ("Forget this note? Enter / Esc"), as removing a
  // calendar does: forgotten stays forgotten.
  property bool notebookAsking: false
  function askForgetNote() {
    var row = root.notebookList[root.notebookFocus]
    if (!row || (row.kind !== "line" && row.kind !== "answer" && row.kind !== "correction")) return
    root.notebookNote = ""
    root.notebookAsking = true
  }

  function forgetNote() {
    root.notebookAsking = false
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
    if (root.notebookAsking) {
      root.notebookAsking = false
      if (seq === "Enter") { root.forgetNote(); return true }
      if (seq === "Esc") return true
    }
    if (seq === "Esc") { root.closeNotebook(); return true }
    var to = root.listStep(seq, root.notebookFocus, 0, root.notebookList.length - 1, root.nextNotebookRow)
    if (to !== -2) { root.notebookFocus = to; return true }
    if (Sc.hit(event, "keysHere")) { root.toggleKeys(); return true }
    if (seq === "Enter" || Sc.hit(event, "notebookCorrect")) { root.startCorrect(); return true }
    if (Sc.hit(event, "notebookForget")) { root.askForgetNote(); return true }
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
    settingsSheet.settingsFieldRef.forceActiveFocus()
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
    // Asked while the state is still being read (opening settings reads
    // it): after, not instead. A calendar added at once was never fetched
    // (2026-10-25). A fetch wins over a plain read.
    if (settingsProc.running) {
      if (root.timetableAgain === null || flags.indexOf("--fetch") >= 0)
        root.timetableAgain = { flags: flags, index: root.settingsBusyIndex }
      return
    }
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
      root.keysNote = row.where === Sc.systemName
        ? (Sc.onWindows ? "Windows' key, not the page's: the row above lets the page keep it"
           : "Hyprland's key, not the page's: the row above lets the page keep it, or change it in your Hyprland bindings (~/.config/hypr/bindings.lua)")
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
  readonly property string hyprKeysPy: Links.fromFileUrl(Qt.resolvedUrl("hyprkeys.py").toString())
  // A call asked while another runs is made when that one ends; a state
  // read is not, since every call answers with the state (2026-11-24: the
  // second Enter that lets the page keep the six came while the sheet was
  // still reading them, and was lost, the note left at "…" — on Windows,
  // where the read takes most of a second).
  property var hyprNext: null
  function hypr(args) {
    if (hyprProc.running) {
      if (args[0] !== "state") root.hyprNext = args
      return false
    }
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

  // Ctrl+2 (Ctrl+Alt+2 straight): the dashboard. Every open box and every deadline in one place,
  // full width, worked with keys — the pinned twin of the bar's deadline
  // popup (SUPER+ALT+D), which stays the glance. It takes the sheet's place
  // rather than sitting beside it: a list is not prose and does not want the
  // 72-character measure. Decided 2026-10-15, and it replaces the narrow
  // what's-next panel the margin used to hold, because two surfaces for one
  // list is part of what made the list easy to ignore.
  function toggleDash() {
    if (!root.dashOpen) root.loadCheckin()
    root.remember()
    var was = root.here
    if (!root.dashOpen) root.noteFrom("dash")
    root.dashOpen = !root.dashOpen
    // A task's chat belongs to the dashboard (docs/navigation.md): it goes
    // with it and comes back with it, as a block's does with the note
    // (`talkOpen` asks for the dashboard). Until 2026-11-27 it was closed.
    root.dashWhenFor = null
    root.dashWhenText = ""
    root.stripAt = -1
    root.stripOpen = false
    if (root.dashOpen) {
      root.used("dashboard")
      // Back on the row it was left on, when it is still there (2026-11-27:
      // Enter to look at a line and back again was row 0, twenty rows up).
      var at = -1
      for (var i = 0; root.taskFocusKey !== "" && i < root.taskRows.length; i++)
        if (root.rowKey(root.taskRows[i]) === root.taskFocusKey) { at = i; break }
      if (at >= 0) root.taskFocus = at
      else { root.taskFocus = 0; root.moveTaskFocus(0) }
      root.refreshTasks()
      root.refreshProposals()
      root.runPlan(false)
      if (root.talkThread !== "") root.fetchTalk()
      if (root.keysOpen) root.toggleKeys()
      if (root.settingsOpen) root.toggleSettings()
      dash.dashKeysRef.forceActiveFocus()
      Qt.callLater(dash.revealFocused)
    } else {
      // What was unfolded for a look is folded again; the words typed and
      // the courses picked stay, for the way back from a line looked at.
      root.showShelf = false
      root.showGrading = false
      root.giveBack("dash", was, "center")
    }
  }

  // What the last list reads were asked in, for a test that finds a line
  // missing to say why (the newest last; plan.md item 17).
  property var tasksTrace: []
  function traceTasks(what) {
    root.tasksTrace = root.tasksTrace.slice(-11).concat([Qt.formatTime(new Date(), "hh:mm:ss.zzz") + " " + what
      + " pending=" + svc.pending + " saving=" + svc.saving + " queued=" + svc.queued + " running=" + tasksProc.running])
  }
  function refreshTasks() {
    root.traceTasks("asked")
    // Not while a tick is still being drawn: the list read again rebuilds
    // every row, which would cut the tick short.
    var wait = root.holdTasksUntil - Date.now()
    if (wait > 0) { tasksHold.interval = Math.ceil(wait); tasksHold.restart(); return }
    // The list is read from the files, so today's note is written first:
    // read before its save landed, the newest line was missing until
    // something else asked again (2026-10-25). A save that cannot happen,
    // or finds nothing to write, waits for nothing.
    if (svc.ready && svc.error === "" && svc.pending && !svc.saving) root.flush()
    if (svc.saving) { root.tasksAfterSave = true; return }
    // Asked again while a read is under way: once more when it ends, or
    // the later question is lost and the earlier answer stands.
    if (tasksProc.running) { root.tasksAgain = true; return }
    tasksProc.command = [svc.runner, "next", "--days", "7"]
    tasksProc.running = true
    root.traceTasks("read")
  }
  property bool tasksAfterSave: false
  property bool tasksAgain: false

  function refreshDated() {
    if (!svc.configured) return
    if (datedProc.running) { root.datedAgain = true; return }
    datedProc.command = [svc.runner, "dated"]
    datedProc.running = true
  }
  property bool datedAgain: false

  Timer { id: tasksHold; onTriggered: root.refreshTasks() }

  // A row's identity across the list being read again.
  function rowKey(row) {
    if (!row) return ""
    if (row.kind === "deadline") return "d" + row.deadline.id
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") return "p" + row.item.id
    // By its words alone, never its facts: a priority, a day or a tick
    // changed its key until 2026-11-27, and the cursor fell to the next
    // row, where the second `p` changed the wrong box.
    if (row.kind === "task") return "t" + root.taskKey(row.task.date, Task.wordsOf(row.task.text))
    if (row.kind === "band") return "b" + row.id
    return ""
  }

  property string justClosed: ""   // the row key of what was just ticked or dropped from here
  function taskKey(date, words) { return date + "|" + String(words).replace(/\s+/g, " ").trim() }

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
    root.used("project-notes", pr.tag)
    root.reached(pr.tag)
    root.projectTag = pr.tag
    root.projectFolder = pr.folder || ""
    root.projectName = pr.name || pr.tag
    root.sections = []
    root.sectionFocus = 0
    root.docFocus = -1
    root.projectPaperFocus = -1
    root.projectRowKey = ""
    root.projectFolds = ({ shelf: false, files: false, open: false, earlier: false })
    root.projectPapers = []
    if (!root.sidebarOpen) root.ensureRoomFor("left")
    root.sidebarOpen = true
    root.projectOpen = true
    root.refreshSections()
    root.refreshProjectPapers()
    sidebar.sidebarKeysRef.forceActiveFocus()
  }

  // The project's list read again whenever a note may have changed under
  // it (2026-11-11): the page's own save, the open note changed outside,
  // a box ticked or moved from the dashboard, the sidebar shown again. It
  // was read only when the project was opened, so a heading renamed or a
  // box ticked in the note stayed as it was until the list was opened
  // again. A save comes 300 ms after the typing stops and the runner
  // answers in about a quarter second, so the list follows as you write.
  function notesChanged() {
    if (root.projectOpen) sectionsAgainTimer.restart()
  }
  Timer { id: sectionsAgainTimer; interval: 120; onTriggered: root.refreshSections() }
  property bool sectionsAgain: false
  function refreshSections() {
    if (!root.projectOpen || root.projectTag === "" || !svc.configured) return
    // Asked again while a read is under way: once more when it ends.
    if (sectionsProc.running) { root.sectionsAgain = true; return }
    sectionsProc.tag = root.projectTag
    sectionsProc.command = [svc.runner, "sections", "--tag", root.projectTag]
    sectionsProc.running = true
  }
  onSidebarOpenChanged: if (root.sidebarOpen) { root.sideNow = Date.now(); root.notesChanged(); root.refreshProjectPapers(); root.readToday.refresh() }
  // Marks made while reading show in the project's view (OPEN, THIS WEEK,
  // off the shelf) without leaving the project and coming back (2026-11-28).
  Connections { target: pdfPane; function onReadChanged() { if (root.projectOpen) projectPapersAgain.restart() } }
  // The sidebar's minute, as the dashboard's (dashNow): a deadline's hour
  // passing turns it late, midnight moves "today" and this week.
  property double sideNow: Date.now()
  Timer { interval: 60000; repeat: true; running: root.sidebarOpen && root.showing; onTriggered: root.sideNow = Date.now() }

  // The day's deadline list in the sidebar; false for a key it does not
  // use. A function, as projectsKey is, so the page can be driven without
  // a keyboard (tests/page/run.py).
  function dueKey(event) {
    if (Sc.hit(event, "listOpen")) root.goToDeadline(root.focusDue[root.dueFocus])
    else if (Sc.hit(event, "listDone")) root.sideTick(root.focusDue[root.dueFocus])
    else return false
    return true
  }

  // A deadline of the day, ticked from the sidebar: done; done, open
  // again; dropped or hidden, open again, said (it was silent, and looked
  // like a done one untick).
  function sideTick(d) {
    if (!d) return
    if (d.status === "open") root.tickSound()
    else if (d.status !== "done") root.showHint("“" + d.title + "” was " + (d.status === "cancelled" ? "dropped" : "hidden") + ": open again")
    root.tickDeadline(d)
  }

  // The projects list's keys, in one function so the page can be driven
  // without a keyboard. Enter (or Right) opens the project's own notes —
  // the list is there to find them. Writing into the note is a key each,
  // Todoist's: `s` a new section, `#` the tag at the cursor (2026-10-28;
  // Shift+Enter and Ctrl+Enter until then). `@` in the note is the way to
  // write one.
  function projectsKey(event) {
    // The row after the last project makes a new one.
    var pr = root.projects[root.projFocus]
    if (Sc.hit(event, "listPage")) { if (pr) root.openProjectPage(pr.tag) }
    else if (Sc.hit(event, "listWeek")) { if (pr) root.openProjectWeek(pr.tag) }
    else if (Sc.hit(event, "listTag")) { if (pr) root.insertTag(pr) }
    else if (Sc.hit(event, "listClass")) { if (pr) root.startClass(pr) }
    else if (Sc.hit(event, "listOpen")) { if (pr) { root.used("reach", "walk"); root.openProject(pr) } else root.openSidebarProject() }
    else if (Sc.hit(event, "listInto")) { if (pr) { root.used("reach", "walk"); root.openProject(pr) } }
    else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) { root.projFocus = -1; return false }
    else return false
    return true
  }
  // The project whose view is open, as the list of projects has it.
  function projectHere() {
    var i = root.projectIndex(root.projectTag)
    return i >= 0 ? root.projects[i] : (root.projectTag !== "" ? { tag: root.projectTag, name: root.projectName } : null)
  }

  // ---------------------------------------- reaching a project (plan.md item 19)

  // The lists under the calendar as one walk (2026-11-17, the student: "I
  // would expect the rest to be navigated through arrows"): the arrows go
  // on from the day's deadlines into what was read and on into the
  // projects; Tab only skips a list, and Tab is still how the calendar is
  // left, its own arrows being the days. Which lists have rows, in order:
  function sideLists() {
    var l = []
    if (root.focusDue.length > 0) l.push("due")
    if (root.readToday.rows.length > 0) l.push("read")
    l.push("proj")
    return l
  }
  // How many rows a list has; the projects' last is the one that makes a new one.
  function sideRows(list) {
    return list === "due" ? root.focusDue.length : list === "read" ? root.readToday.rows.length : root.projects.length + 1
  }
  // Where the keys are under the calendar ("" in the calendar itself).
  readonly property string sideList: root.dueFocus >= 0 ? "due" : root.readToday.at >= 0 ? "read" : root.projFocus >= 0 ? "proj" : ""
  function sideAt() {
    return root.sideList === "due" ? root.dueFocus : root.sideList === "read" ? root.readToday.at : root.projFocus
  }
  // The keys onto a list's row; "" is the calendar.
  function sidePut(list, row) {
    root.dueFocus = list === "due" ? row : -1
    root.readToday.at = list === "read" ? row : -1
    root.projFocus = list === "proj" ? row : -1
    if (list === "") root.sideLast = null
  }
  // The walk's keys, the same in every list; false for a key it leaves to
  // the list (Enter, done, a new section…).
  function listWalk(event) {
    var lists = root.sideLists(), here = root.sideList, i = lists.indexOf(here), at = root.sideAt()
    if (i < 0) return false
    if (Sc.hit(event, "listDown")) {
      if (at < root.sideRows(here) - 1) root.sidePut(here, at + 1)
      else if (i < lists.length - 1) root.sidePut(lists[i + 1], 0)
    } else if (Sc.hit(event, "listUp")) {
      // At the top of the first list the walk stops: the calendar is left
      // and come back to by Tab, so ↑ held down never starts moving days.
      if (at > 0) root.sidePut(here, at - 1)
      else if (i > 0) root.sidePut(lists[i - 1], root.sideRows(lists[i - 1]) - 1)
    } else if (Sc.hit(event, "listFirst")) root.sidePut(lists[0], 0)
    else if (Sc.hit(event, "listLast")) root.sidePut("proj", Math.max(0, root.projects.length - 1))
    else if (Sc.hit(event, "listNext")) root.sidePut(i < lists.length - 1 ? lists[i + 1] : "", 0)
    else if (Sc.hit(event, "listPrev")) root.sidePut(i > 0 ? lists[i - 1] : "", 0)
    else if (Sc.hit(event, "listBack")) root.sidePut("", -1)
    else return false
    return true
  }

  // The sidebar opened again comes back to the row it was left on (item
  // 19's "remembering the last list and row"): a project by its tag, a
  // deadline or a paper only while the calendar is on the same day. Backing
  // out to the calendar forgets it, so the calendar is where Esc left you.
  property var sideLast: null        // { list, key, day }
  function noteSide() {
    // From the rows themselves: inside their change handlers the sideList
    // binding may not have caught up yet.
    var l = root.dueFocus >= 0 ? "due" : root.readToday.at >= 0 ? "read" : root.projFocus >= 0 ? "proj" : ""
    if (l === "") return
    var day = Days.key(root.calFocus)
    if (l === "proj") {
      if (root.projects.length === 0) return
      var pr = root.projects[root.projFocus]
      root.sideLast = { list: l, key: pr ? pr.tag : "+", day: day }
    } else if (l === "due") {
      var d = root.focusDue[root.dueFocus]
      if (d) root.sideLast = { list: l, key: d.id, day: day }
    } else {
      var r = root.readToday.rows[root.readToday.at]
      if (r) root.sideLast = { list: l, key: r.pdf, day: day }
    }
  }
  onProjFocusChanged: root.noteSide()
  onDueFocusChanged: root.noteSide()
  Connections { target: root.readToday; function onAtChanged() { root.noteSide() } }
  function restoreSide() {
    var s = root.sideLast
    if (!s) return
    if (s.list === "proj") {
      var i = s.key === "+" ? root.projects.length : root.projects.findIndex(function (p) { return p.tag === s.key })
      if (i >= 0) root.sidePut("proj", i)
      return
    }
    if (s.day !== Days.key(root.calFocus)) return
    if (s.list === "due") {
      var j = root.focusDue.findIndex(function (d) { return d.id === s.key })
      if (j >= 0) root.sidePut("due", j)
    } else {
      var k = root.readToday.rows.findIndex(function (r) { return r.pdf === s.key })
      if (k >= 0) root.sidePut("read", k)
    }
  }

  // The projects, the most used first (Tags.byUse); the keys stay on the
  // project they were on while the list is read again.
  property var projectUses: ({})     // projects-used.json: { tag: [epoch seconds] }
  // A project just made from the sidebar: the keys land on it.
  property string projectToFocus: ""
  function orderProjects() {
    var on = root.projects[root.projFocus]
    var tag = root.projectToFocus !== "" ? root.projectToFocus : root.projFocus >= 0 && on ? on.tag : ""
    // On "+ new project" before the list was read (Tab at once): the
    // first project once it is, not the new row.
    var wasNew = root.projFocus >= 0 && root.projFocus === root.projects.length && root.projects.length > 0
    root.projects = Tags.byUse(root.projectsListed, root.projectUses, Math.floor(Date.now() / 1000))
    if (tag !== "") {
      var i = root.projects.findIndex(function (p) { return p.tag === tag })
      if (i >= 0 && tag === root.projectToFocus) root.projectToFocus = ""
      root.projFocus = i >= 0 ? i : Math.min(root.projFocus, root.projects.length)
    } else if (wasNew) root.projFocus = root.projects.length
    else root.projFocus = Math.min(root.projFocus, root.projects.length)
  }
  // One more use of a project, whichever way it was reached. The order
  // moves the next time the list is read (the sidebar opened), never under
  // the keys.
  function reached(tag) {
    if (!tag) return
    root.projectUses = Tags.used(root.projectUses, tag, Math.floor(Date.now() / 1000))
    projectUsesFile.setText(JSON.stringify(root.projectUses) + "\n")
  }

  // To a project's notes in the sidebar from wherever the keys are, by the
  // way it was reached (logged, so the ways can be weighed: plan.md item
  // 19 measures keys pressed): "type", "key", "switcher".
  function reachProject(pr, how) {
    if (!pr) return
    root.used("reach", how)
    // From the switcher, the way back is where the keys were before it
    // (`here` is the middle while its field has them).
    var from = root.switcherOpen ? root.switcherFrom : root.here
    if (root.switcherOpen) root.switcherDone()
    root.sideTyping = false
    if (!root.sidebarOpen) root.noteFrom("left", from)
    if (root.sidebarSpace !== "time") { root.spaceStep = -1; root.sidebarSpace = "time" }
    root.openProject(pr)
  }
  // Alt+1…9: the sidebar's first, second… project, as numbered there.
  function projectByKey(event) {
    var n = event.key - Qt.Key_0
    var pr = root.projects[n - 1]
    if (pr) root.reachProject(pr, "key")
    else root.showHint(root.projects.length === 0 ? "no projects yet" : "the sidebar lists " + root.projects.length + (root.projects.length === 1 ? " project" : " projects"))
  }

  // Type to go: `#` and the letters, in the calendar or its lists, with no
  // field to open (`#`, since bare letters are the lists' own keys and
  // #thesis starts with the calendar's T). The keys go to the first match
  // as each letter is typed, the rest dim; ↑↓ step through the matches,
  // Enter opens, Esc or Backspace past the # stops where it is.
  property bool sideTyping: false
  property string sideTyped: ""
  readonly property var sideMatches: root.sideTyping ? Tags.reach(root.projects, root.sideTyped) : []
  // By tag: a project handed to QML (a row's modelData) is a copy, never
  // the same object as the list's.
  readonly property var sideMatchTags: root.sideMatches.map(function (p) { return p.tag })
  function projectIndex(tag) { return root.projects.findIndex(function (p) { return p.tag === tag }) }
  function sideReachStart() {
    root.sideTyping = true
    root.sideTyped = ""
    // `#` alone, on a project: the keys stay on it until a letter is typed.
    // It went to the first project, and so off the row it was on whenever
    // the order by use had moved it (plan.md item 19; the live check
    // "letters nothing has keep the row" failed so, 2026-11-17).
    if (!root.projects[root.projFocus]) root.sideToMatch(0)
  }
  function sideToMatch(i) {
    var m = root.sideMatches[i]
    if (m) root.sidePut("proj", root.projectIndex(m.tag))
  }
  // Find by typing (2026-11-22, the student: "easier to make searches
  // while typing, instead of first having to press tab and then #"): in
  // the calendar or its lists, a letter or digit starts finding a
  // project, with no key before it. The lists' own letter keys moved off
  // letters for it (Shortcuts.js: s and t to Shift+Enter and Ctrl+Enter,
  // as Shift- and Ctrl-click; p and w to Alt+P and Alt+W; j k to the
  // arrows; the calendar's t to Home).
  function sideFindStart(event) {
    if (!root.typing(event)) return false
    var ch = event.text || ""
    if (ch.length !== 1 || !/[A-Za-z0-9\u00C0-\u024F_\-\/]/.test(ch)) return false
    root.sideTyping = true
    root.sideTyped = ch
    root.sideToMatch(0)
    return true
  }
  function sideTypeKey(event) {
    var mods = !root.typing(event)
    var ch = event.text || ""
    var on = root.projects[root.projFocus]
    var at = on ? root.sideMatchTags.indexOf(on.tag) : -1
    if (event.key === Qt.Key_Escape) { root.sideTyping = false; return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var pr = at >= 0 ? root.sideMatches[at] : root.sideMatches[0]
      var typed = root.sideTyped
      root.sideTyping = false
      // Shift+Enter a new section for it, Ctrl+Enter its tag at the
      // cursor, as on a row of the list; letters nothing has: a new
      // project, its name already in.
      if (!pr) { root.sidePut("proj", root.projects.length); root.openSidebarProject(typed); return true }
      if (event.modifiers & Qt.ShiftModifier) root.startClass(pr)
      else if (event.modifiers & Qt.ControlModifier) root.insertTag(pr)
      else root.reachProject(pr, "type")
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      if (root.sideTyped === "") root.sideTyping = false
      else { root.sideTyped = root.sideTyped.slice(0, -1); root.sideToMatch(0) }
      return true
    }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      var n = root.sideMatches.length
      if (n > 0) root.sideToMatch(((at < 0 ? 0 : at) + (event.key === Qt.Key_Down ? 1 : n - 1)) % n)
      return true
    }
    if (!mods && ch.length === 1 && (/[\w\/\-\u00C0-\u024F]/.test(ch) || (ch === " " && root.sideTyped !== ""))) {
      root.sideTyped += ch
      root.sideToMatch(0)
      return true
    }
    if (!mods && ch === "#") return true
    // Anything else ends the typing and is the key it always was.
    root.sideTyping = false
    return false
  }

  // The switcher (Ctrl+O, docs/keys-proposal.md's "find anything"):
  // projects first (preserving `#th` and Alt+1..9), plus vault notes/PDFs,
  // core views/actions, and `? <words>` full-text search across all notes
  // (including private notes, local-only). Esc gives the keys back.
  property bool switcherOpen: false
  readonly property var switcherField: switcherBox.fieldRef
  readonly property string switcherStatus: switcherBox.statusText   // what it says under the field (the tests read it)
  property string switcherText: ""
  property int switcherPick: 0
  property string switcherPickKey: ""     // the row picked, by what it is: kept when rows arrive above it
  property string switcherFrom: "center"
  property var switcherFindHits: []
  property string switcherHitsFor: ""     // the words switcherFindHits were found for
  property int switcherFindTotal: 0       // lines that matched in all, the hits being the best of them
  property bool switcherFinding: false    // a search for the words typed is waiting or running
  property string switcherFindError: ""
  property bool switcherGoWhenFound: false
  readonly property bool switcherAsking: root.switcherText.trim().charAt(0) === "?"
  readonly property string switcherWords: root.switcherAsking ? root.switcherText.trim().slice(1).trim() : ""
  // The hits on screen were found for other words (typing goes on): Enter
  // waits for these words' own.
  readonly property bool switcherStale: root.switcherWords !== "" && root.switcherHitsFor !== root.switcherWords

  Timer {
    id: switcherFindTimer
    interval: 160
    onTriggered: root.runSwitcherFind()
  }

  // One search at a time (2026-11-28: typing fast stopped a run and read
  // its empty answer as the new words', "no note holds…"). A run for words
  // no longer typed is stopped, and the words typed are searched once it
  // has ended (switcherFound).
  Process {
    id: switcherFindProc
    property string query: ""       // the words this run was started for
    property bool stopped: false
    stdout: StdioCollector { id: switcherFindOut }
    stderr: StdioCollector { id: switcherFindErr }
    onExited: function (code) {
      var q = switcherFindProc.query
      var stopped = switcherFindProc.stopped
      switcherFindProc.stopped = false
      Qt.callLater(function () { root.switcherFound(q, stopped, code, switcherFindOut.text, switcherFindErr.text) })
    }
  }

  function switcherFound(q, stopped, code, out, err) {
    if (!root.switcherOpen) { root.switcherFinding = false; return }
    if (stopped || q !== root.switcherWords) {
      if (root.switcherWords !== "" && root.switcherStale) root.runSwitcherFind()
      else root.switcherFinding = false
      return
    }
    root.switcherFinding = false
    var parsed = null
    try { parsed = JSON.parse(out) } catch (e) {}
    root.switcherHitsFor = q
    // A run that failed says so: it is not a search that found nothing.
    if (code !== 0 || !parsed) {
      var said = String(err || "").trim().split("\n").pop().replace(/^longhand-agent: /, "")
      root.switcherFindError = said || (code !== 0 ? "the runner stopped (" + code + ")" : "the runner gave no answer")
      root.switcherFindHits = []
      root.switcherFindTotal = 0
      root.switcherGoWhenFound = false
      return
    }
    root.switcherFindError = ""
    root.switcherFindHits = (parsed.hits || []).map(function (h) {
      return {
        kind: "hit", tag: "", path: h.path, line: h.line, bodyLine: h.body_line || h.line, date: h.date || "",
        heading: h.heading || "", text: h.text || "",
        title: h.text || h.path,
        sub: (h.date || root.fileName(h.path)) + (h.heading ? " · " + h.heading : "") + " · line " + h.line,
        hint: h.date ? "day" : "note"
      }
    })
    root.switcherFindTotal = parsed.total !== undefined ? parsed.total : root.switcherFindHits.length
    root.switcherPick = 0
    root.switcherPickKey = ""
    if (root.switcherGoWhenFound) {
      root.switcherGoWhenFound = false
      if (root.switcherFindHits.length > 0) root.switcherGo(false)
    }
  }

  function runSwitcherFind() {
    switcherFindTimer.stop()
    var q = root.switcherOpen ? root.switcherWords : ""
    if (q === "") {
      root.switcherFindHits = []
      root.switcherHitsFor = ""
      root.switcherFindError = ""
      root.switcherFinding = false
      return
    }
    if (switcherFindProc.running) {
      if (switcherFindProc.query !== q && !switcherFindProc.stopped) { switcherFindProc.stopped = true; switcherFindProc.signal(15) }
      root.switcherFinding = true
      return
    }
    if (!root.switcherStale && root.switcherFindError === "") { root.switcherFinding = false; return }   // found already
    root.flush()   // what was typed a moment ago is in what is searched
    switcherFindProc.query = q
    root.switcherFinding = true
    switcherFindProc.command = [svc.runner, "find", "--words", q, "--limit", "12"]
    switcherFindProc.running = true
  }

  function switcherViews() {
    return [
      { kind: "view", id: "dash", tag: "", title: "the dashboard", sub: "tasks, deadlines and what the agent proposes", keywords: "dashboard tasks deadlines proposals plan", hint: root.keyName("dashGo") || root.keyName("pane2") },
      { kind: "view", id: "today", tag: "", title: "today's note", sub: "back to today", keywords: "today home daily note", hint: root.keyName("today") },
      { kind: "view", id: "settings", tag: "", title: "settings", sub: "calendars, autonomy, search, sound, the pointer", keywords: "settings preferences calendar autonomy sound pointer", hint: root.keyName("settings") },
      { kind: "view", id: "keys", tag: "", title: "keys", sub: "every key the page answers to, and moving one", keywords: "keys shortcuts bindings help", hint: root.keyName("keys") },
      { kind: "view", id: "export", tag: "", title: "export as a PDF", sub: "this section, or what is selected; on the dashboard, the deadline's", keywords: "export pdf print hand in", hint: root.keyName("exportPdf") },
      { kind: "view", id: "files", tag: "", title: "files", sub: "your notes and papers, as folders in the sidebar", keywords: "files folders vault sidebar", hint: root.keyName("pane1") },
      { kind: "view", id: "time", tag: "", title: "calendar and projects", sub: "the sidebar's time space", keywords: "calendar time sidebar projects", hint: root.keyName("pane1") },
      { kind: "view", id: "agent", tag: "", title: "the agent", sub: "the day's conversation (beside a note from Files, the note's)", keywords: "agent chat day conversation", hint: root.keyName("dayChat") || root.keyName("pane3") }
    ]
  }

  // A paper's name and title as the rest of the page says them ("Moser et
  // al. 2023"), where the agent's list of files has them.
  readonly property var switcherNames: {
    var out = {}
    for (var i = 0; i < root.refFiles.length; i++) {
      var f = root.refFiles[i]
      if (f.kind === "paper" || /\.pdf$/i.test(f.rel)) out[f.rel] = { name: f.name || "", title: f.title || "" }
    }
    return out
  }
  function switcherFileMatches(q) {
    var _v = root.vaultIndexVersion
    if (!root.vaultIndex || !root.vaultIndex.paths) return []
    var fmt = svc.configured ? svc.dailyFormat() : ""
    return Switch.files(root.vaultIndex.paths, q, {
      daily: svc.config && svc.config.daily ? String(svc.config.daily.dir || "").replace(/^\/+|\/+$/g, "") : "",
      agentRoot: svc.agentRoot,
      names: root.switcherNames,
      // A note in the daily folder is a day when its name is one (a README there is a note).
      isDay: function (stem) { return fmt !== "" && !!Days.parse(stem, fmt) },
      max: 6
    })
  }

  readonly property var switcherMatches: {
    if (!root.switcherOpen) return []
    var raw = root.switcherText.trim()
    // Empty query: projects only (clean open, exact Alt+1..9 order).
    if (raw === "") {
      return Tags.reach(root.projects, "").map(function (p) {
        return Object.assign({ kind: "project" }, p)
      })
    }
    // Full-text search across all user notes (`? <words>`).
    if (raw.charAt(0) === "?") return root.switcherFindHits
    // `#` prefix: projects only.
    if (raw.charAt(0) === "#") {
      return Tags.reach(root.projects, raw).map(function (p) {
        return Object.assign({ kind: "project" }, p)
      })
    }
    var out = []
    var projs = Tags.reach(root.projects, raw)
    for (var i = 0; i < projs.length && i < 6; i++) out.push(Object.assign({ kind: "project" }, projs[i]))
    var views = root.switcherViews()
    var vcount = 0
    for (var j = 0; j < views.length && vcount < 4; j++) {
      if (Switch.viewMatches(views[j], raw)) { out.push(views[j]); vcount++ }
    }
    var files = root.switcherFileMatches(raw)
    for (var k = 0; k < files.length; k++) out.push(files[k])
    out.push({
      kind: "search", tag: "", query: raw,
      title: "search all notes for “" + raw + "”",
      sub: "full-text across every note, including private",
      hint: "? " + raw
    })
    return out
  }
  function switcherKeyOf(it) {
    return it ? [it.kind || "project", it.tag || it.id || it.path || "", it.line || "", it.query || ""].join("\u0001") : ""
  }
  onSwitcherPickChanged: root.switcherPickKey = root.switcherKeyOf(root.switcherMatches[root.switcherPick])
  // Rows arriving while one is picked (the names read, the papers' names):
  // the pick stays on what it was, not on the row now at its place.
  onSwitcherMatchesChanged: {
    var m = root.switcherMatches
    if (root.switcherPickKey !== "") {
      for (var i = 0; i < m.length; i++) {
        if (root.switcherKeyOf(m[i]) === root.switcherPickKey) { if (i !== root.switcherPick) root.switcherPick = i; return }
      }
    }
    if (root.switcherPick >= m.length) root.switcherPick = Math.max(0, m.length - 1)
    root.switcherPickKey = root.switcherKeyOf(m[root.switcherPick])
  }

  onSwitcherTextChanged: {
    root.switcherPick = 0
    root.switcherPickKey = ""
    root.switcherFindError = ""
    root.switcherGoWhenFound = false
    if (root.switcherOpen && root.switcherWords !== "") {
      // Searching from the first letter: never "no note holds…" before
      // the words were looked for.
      if (root.switcherStale) { root.switcherFinding = true; switcherFindTimer.restart() }
      else { switcherFindTimer.stop(); root.switcherFinding = switcherFindProc.running && switcherFindProc.query === root.switcherWords && !switcherFindProc.stopped }
    } else {
      switcherFindTimer.stop()
      root.switcherFinding = false
      if (root.switcherAsking) { root.switcherFindHits = []; root.switcherHitsFor = ""; root.switcherFindTotal = 0 }
    }
  }

  function openSwitcher(prefill) {
    // Open already (Ctrl+Shift+O over it): where the keys were stays the way back.
    if (!root.switcherOpen) root.switcherFrom = root.here
    root.used("switcher")
    root.switcherFindHits = []
    root.switcherHitsFor = ""
    root.switcherFindTotal = 0
    root.switcherFindError = ""
    root.switcherFinding = false
    root.switcherGoWhenFound = false
    root.switcherText = prefill || ""
    root.switcherPick = 0
    root.switcherPickKey = ""
    root.switcherOpen = true
    if (root.projectsListed.length === 0) root.refreshProjects()
    if (root.refFiles.length === 0) root.loadRefFiles()   // papers by their names, as the sidebar shows them
    root.freshIndex()
    switcherBox.fieldRef.text = prefill || ""
    switcherBox.fieldRef.cursorPosition = switcherBox.fieldRef.text.length
    switcherBox.fieldRef.forceActiveFocus()
  }

  function toggleSwitcher() {
    if (root.switcherOpen) { root.closeSwitcher(); return }
    root.openSwitcher("")
  }
  // Ctrl+Shift+O: the switcher on `?`. Over it on `?` already, it closes,
  // as Ctrl+O does over its own; over other letters, they become the words.
  function findAll() {
    if (!root.switcherOpen) { root.openSwitcher("? "); return }
    if (root.switcherAsking) { root.closeSwitcher(); return }
    var w = root.switcherText.trim().replace(/^#/, "")
    switcherBox.fieldRef.text = "? " + w
    switcherBox.fieldRef.cursorPosition = switcherBox.fieldRef.text.length
  }
  // The switcher gone, however it goes (Esc, a pick, a click elsewhere, the
  // page closing): no search left running or waiting for it.
  function switcherDone() {
    switcherFindTimer.stop()
    if (switcherFindProc.running && !switcherFindProc.stopped) { switcherFindProc.stopped = true; switcherFindProc.signal(15) }
    root.switcherFinding = false
    root.switcherGoWhenFound = false
    root.switcherOpen = false
  }
  function closeSwitcher() {
    root.switcherDone()
    if (!root.focusPane(root.switcherFrom)) root.focusCenter()
  }

  // Where a note or a hit leads: a day as a day (the calendar's cursor
  // with it), any other note as a file, a paper in the reader; to the line
  // when there is one, the words lit. What was over the middle (the
  // dashboard, keys, settings, a paper, the export) gives way to it, and
  // a jump inside the note open is a step back too (Ctrl+[).
  function switcherLand(item, line, words) {
    if (root.exportOpen) { root.exportFromDash = false; root.closeExport() }
    if (/\.pdf$/i.test(item.path || "")) { root.openPdf(item.path); return }
    var same = svc.ready && (item.date ? item.date === svc.noteDate && root.dayNote : item.path === svc.filePath)
    root.pendingLine = line
    root.pendingWords = line > 0 ? (words || "") : ""
    if (same && line > 0) root.remember()
    if (item.date) {
      var d = svc.configured ? Days.parse(item.date, svc.dailyFormat()) : null
      if (d) root.calFocus = d.date
      root.openNote(item.date)
    } else root.openFile(item.path, false)
    root.showNote()
    if (same) root.landOnLine()
  }
  function switcherGo(asPage) {
    // Enter while the hits are for words typed before: these words' own, once found.
    if (root.switcherAsking && root.switcherStale) {
      root.switcherGoWhenFound = true
      root.runSwitcherFind()
      return
    }
    var item = root.switcherMatches[root.switcherPick]
    if (!item) return
    if (item.kind === "project") {
      if (asPage) {
        root.closeSwitcher()
        root.used("reach", "switcher-page")
        root.openProjectPage(item.tag)
      } else root.reachProject(item, "switcher")
      return
    }
    if (item.kind === "search") {
      switcherBox.fieldRef.text = "? " + item.query
      switcherBox.fieldRef.cursorPosition = switcherBox.fieldRef.text.length
      switcherBox.fieldRef.forceActiveFocus()
      root.runSwitcherFind()   // now, not after the typing pause too (it ran twice)
      return
    }
    if (item.kind === "view") {
      root.closeSwitcher()
      // A view is opened, never closed: picked while it is open, the keys go to it.
      if (item.id === "dash") root.showDash()
      else if (item.id === "today") root.goToday()
      else if (item.id === "settings") { if (!root.settingsOpen) root.toggleSettings(); else root.focusCenter() }
      else if (item.id === "keys") { if (!root.keysOpen) root.toggleKeys(); else root.focusCenter() }
      else if (item.id === "export") {
        if (root.centerView === "dash") root.exportFocused()
        else { root.showNote(); root.openExport() }
      }
      else if (item.id === "files" || item.id === "time") root.setSpace(item.id)
      else if (item.id === "agent") root.openDay("")
      return
    }
    if (item.kind === "file") {
      root.closeSwitcher()
      root.switcherLand(item, -1, "")
      return
    }
    if (item.kind === "hit") {
      var words = root.switcherWords
      root.closeSwitcher()
      root.switcherLand(item, item.bodyLine || item.line || 1, words)
      return
    }
  }
  // Ctrl+Shift+C over the switcher: the path of the row picked (a hit's
  // with its line), not of what is behind it.
  function switcherCopyPath() {
    var it = root.switcherMatches[root.switcherPick]
    var vault = svc.config ? String(svc.config.vault || "").replace(/[\/\\]+$/, "") : ""
    if (!it || !it.path || vault === "") return false
    var p = vault + "/" + it.path + (it.kind === "hit" ? ":" + it.line : "")
    editor.copyText(p)
    root.showHint("copied " + p.replace(Quickshell.env("HOME") + "/", "~/"))
    root.used("copy-path", "switcher")
    return true
  }
  // Keys the switcher answers before the page's: those that would act on
  // what is behind it.
  function switcherFirst(event) {
    if (Sc.hit(event, "copyPath")) return root.switcherCopyPath()
    return false
  }
  function switcherKey(event) {
    var n = root.switcherMatches.length
    if (Sc.hit(event, "switchUp")) { if (n > 0) root.switcherPick = (root.switcherPick + n - 1) % n }
    else if (Sc.hit(event, "switchDown")) { if (n > 0) root.switcherPick = (root.switcherPick + 1) % n }
    else if (Sc.hit(event, "switchScreenUp")) { if (n > 0) root.switcherPick = Math.max(0, root.switcherPick - switcherBox.screenRows()) }
    else if (Sc.hit(event, "switchScreenDown")) { if (n > 0) root.switcherPick = Math.min(n - 1, root.switcherPick + switcherBox.screenRows()) }
    else if (Sc.hit(event, "switchGo")) root.switcherGo(false)
    else if (Sc.hit(event, "switchPage")) root.switcherGo(true)
    else if (Sc.hit(event, "switchClose")) root.closeSwitcher()
    else return false
    return true
  }

  // Back out of a project to the list it came from.
  function leaveProject() {
    root.projectOpen = false
    root.docFocus = -1
    root.projectPaperFocus = -1
    root.sections = []
    var i = -1
    for (var k = 0; k < root.projects.length; k++) if (root.projects[k].tag === root.projectTag) i = k
    root.projFocus = Math.max(0, i)
    sidebar.sidebarKeysRef.forceActiveFocus()
  }

  // Up and down through the project's view, one list (ProjectView.js).
  function moveSectionFocus(d) {
    var k = PV.step(root.projectRows, root.projectFocusKey, d)
    if (k !== "") root.pickProjectRow(k)
  }

  // The open project's documents, as the runner listed them with the
  // projects; opened in the PDF viewer, never in the page.
  function projectDocs() {
    for (var k = 0; k < root.projects.length; k++)
      if (root.projects[k].tag === root.projectTag) return root.projects[k].docs || []
    return []
  }

  // A project's page (plan.md item 5, 2026-11-16): everything of it in one
  // scroll — next session, deadlines, its folder's "Now", its papers and
  // the questions waiting in them, its working files, every section of its
  // tag in the daily notes — written by the runner (`project-page`) into the
  // state folder and shown read-only; its links go where each thing is
  // written. Written again each time it is opened.
  function openProjectPage(tag) {
    if (!tag) return
    root.used("project-page", tag)
    root.reached(tag)
    root.showHint("gathering #" + tag + "…")
    projectPageProc.what = "the project's page"
    projectPageProc.command = [svc.runner, "project-page", "--tag", tag]
    projectPageProc.running = true
  }
  // The project's week (2026-11-17): done, written, read, what is coming
  // and what to ask — gathered by the runner (`week --page`), read-only, the
  // same way as the project's page.
  function openProjectWeek(tag) {
    if (!tag) return
    root.used("project-week", tag)
    root.reached(tag)
    root.showHint("gathering #" + tag + "'s week…")
    projectPageProc.what = "the project's week"
    projectPageProc.command = [svc.runner, "week", "--tag", tag, "--page"]
    projectPageProc.running = true
  }
  Process {
    id: projectPageProc
    property string what: "the project's page"
    stdout: StdioCollector {
      id: projectPageOut
      onStreamFinished: {
        var o = null
        try { o = JSON.parse(projectPageOut.text) } catch (e) { o = null }
        if (o && o.path) { root.hint = ""; root.openFile(o.path, true) }
        else root.showHint(projectPageProc.what + " could not be made")
      }
    }
  }

  // A project's document: a PDF in the vault opens in the page's reader
  // (since the reader, 2026-11-16), anything else in its own application.
  function openDocument(d) {
    if (!d) return
    root.used("document", "open")
    var vault = svc.configured ? svc.config.vault + "/" : ""
    if (vault !== "" && String(d.path).indexOf(vault) === 0 && /\.pdf$/i.test(d.path)) {
      root.remember()
      root.openPdf(String(d.path).slice(vault.length))
      return
    }
    Qt.openUrlExternally(Links.fileUrl(d.path))
  }

  // Enter in a project, by what the row is: the project's or the week's
  // page opens; a fold opens or closes; a section or an open box goes to
  // the note; a paper opens where it was left, a waiting question opens it
  // on that mark; a file opens.
  function openInProject() {
    var r = root.projectRow
    if (!r) return
    if (r.kind === "page") {
      if (r.page === "week") root.openProjectWeek(root.projectTag)
      else root.openProjectPage(root.projectTag)
      return
    }
    if (r.kind === "fold") {
      var f = Object.assign({}, root.projectFolds)
      f[r.fold] = !f[r.fold]
      root.projectFolds = f
      return
    }
    if (r.kind === "section" || r.kind === "box") { root.sectionFocus = r.index; root.openSection(r.section, r.box || null); return }
    if (r.kind === "doc") {
      if (r.doc) root.openDocument(r.doc)
      else { root.remember(); root.openPdf(r.pdf) }
      return
    }
    if (r.paper) {
      root.used("project-paper")
      root.remember()
      if (r.kind === "question") pdfPane.showAfter = r.id
      root.openPdf(r.paper.pdf)
    }
  }

  // Enter: the note itself, the cursor on the section's own heading. The
  // list stays in the sidebar, as the calendar does after opening a day, so
  // the next section is one key away.
  // `box`: an open box of it (the OPEN band), landed on by its words.
  function openSection(s, box) {
    if (!s) return
    // Only the project's part of that day is drawn (Focus.js), once the
    // day is in the sheet and the cursor is on it.
    root.pendingFocus = { tag: s.tag, date: s.date }
    // Boxes of the tag written outside its sections have no heading to
    // land on: the first open one (else the first), found by its words.
    var stray = s.boxes || []
    var to = box || (stray.length > 0 ? (stray.filter(function (b) { return (b.state || " ") === " " })[0] || stray[0]) : null)
    if (to) {
      root.goToTask({ text: to.text, line: to.line, date: s.date })
      if (s.date === svc.noteDate && svc.ready) root.landOnFocus()
      return
    }
    root.pendingSection = s
    var here = s.date === svc.noteDate && svc.ready
    root.openNote(s.date)
    if (here) { root.landOnSection(); root.landOnFocus() }
    root.showNote()
  }

  // ------------------------------------------------- one project's part of the day
  //
  // The sheet drawing only the lines one project's tag claims in the day
  // (Focus.js, 2026-11-11): opened from a project's list, or with its key
  // on any line of a tagged section. The rest of the day folds to a line
  // saying how much, and the note is the whole note underneath — saved,
  // sent and synced as ever. Esc, the band's "whole day", a fold's mark or
  // a cursor sent into a folded line (a search, a link) give the whole day
  // back; another note does too.
  property var pendingFocus: null     // { tag, date }: to focus on once that day is in the sheet

  function landOnFocus() {
    var f = root.pendingFocus
    if (!f || !svc.ready || f.date !== svc.noteDate) return
    root.pendingFocus = null
    root.focusOn(f.tag)
  }

  function focusOn(tag) {
    editor.focusTag = tag
    if (editor.focusTag === "") { root.showHint("nothing under #" + tag + " in this note"); return }
    root.used("focus", "on")
    // The cursor stays where it was when that is drawn; else the first line drawn.
    var i = root.lineIndexAt(editor.cursorPosition)
    if (!editor.isShown(i)) editor.setCursor(editor.rows[editor.nearestShown(i, 1)].bodyEnd, true)
    root.scheduleRepaint()
  }

  function unfocus() {
    if (editor.focusTag === "") return
    editor.focusTag = ""
    root.scheduleRepaint()
  }

  // The key: the section the cursor is in, or the whole day again.
  function toggleFocus() {
    if (editor.focusTag !== "") { root.unfocus(); return }
    var tag = Focus.tagAt(editor.text, root.lineIndexAt(editor.cursorPosition))
    if (tag === "") { root.showHint("not in a project's section — a “# Heading #tag” starts one"); return }
    root.focusOn(tag)
  }

  readonly property string focusName: editor.focusTag === "" ? "" : Say.courseLabel(editor.focusTag, root.projects)

  // By its words, not its line number: the note may have been written in
  // since the list was gathered (the same reason tasks are found by words).
  // The same heading twice in a day: the one nearest the line it was on.
  function landOnSection() {
    if (!root.pendingSection || !svc.ready) return
    var want = root.pendingSection.heading, line = root.pendingSection.line || 0
    root.pendingSection = null
    var re = new RegExp("^#{1,6} +" + want.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + " *$", "gm")
    var text = editor.text, m, best = null, bestFar = Infinity
    while ((m = re.exec(text)) !== null) {
      var far = Math.abs(text.slice(0, m.index).split("\n").length - 1 - line)
      if (far < bestFar) { best = m; bestFar = far }
    }
    if (best) editor.setCursor(best.index + best[0].length, true)
  }

  // When a section was written, for its row in a project's list: the
  // day, the year too when it is not this one's.
  function sectionWhen(s) {
    var p = svc.configured ? Days.parse(s.date, svc.dailyFormat()) : null
    return p ? root.dayWhen(p.date) : s.date
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

  // A deadline row's second line (Say.deadlineWhere).
  function deadlineWhere(d) {
    return Say.deadlineWhere(d, root.taskOfAnchor(d.id), root.projects, root.origins[String(d.id)], root.dueDates[String(d.id)],
                             new Date(root.dashNow))
  }

  function taskOfAnchor(id) { return Next.taskOfAnchor(root.tasks, id) }
  function taskOfKey(key) { return Next.taskOfKey(root.tasks, key) }

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

  // Why a plan or chat run failed, in words that say what to do.
  function sayPlanError(err) {
    var e = String(err)
    if (/api_key_expired|has expired/.test(e)) return "its model key has expired — renew it or sign in again"
    if (/401|authentication|unauthori|not logged in|sign in/i.test(e)) return "its model login was refused — sign in again"
    if (/rate.?limit|quota|usage limit|429|overloaded/i.test(e)) return "the model hit its limit — try again in a moment"
    if (/timed out/i.test(e)) return "the model timed out before answering"
    if (/ENOTFOUND|network|connect|ECONNREFUSED|offline/i.test(e)) return "the model could not be reached"
    if (/dropped|offered tools|called a tool|auto-memory|AGENTS\.md|attached/i.test(e)) return "answer held back by privacy check: " + e.slice(0, 140)
    if (/^Claude Code refused the run: /.test(e)) return "Claude Code refused it: " + e.replace(/^Claude Code refused the run: (Error: )?/, "").slice(0, 140)
    return "the model said: " + e.slice(0, 140)
  }

  // Asked for while one is under way: once more right after it, so what
  // changed meanwhile (a document just downloaded) is not missed.
  property bool proposalsAgain: false
  // When the list on screen was read (local time, as the runner writes
  // `at`): a day's card made after it is not known to be settled yet.
  property string proposalsAsked: ""
  property string proposalsReadAt: ""
  function refreshProposals() {
    if (!svc.configured) return
    if (proposalsProc.running) { root.proposalsAgain = true; return }
    root.proposalsAsked = Qt.formatDateTime(new Date(), "yyyy-MM-ddTHH:mm:ss")
    proposalsProc.command = [svc.runner, "proposals"]
    proposalsProc.running = true
  }

  // The person's answer: the row goes at once, the runner records it in
  // order.
  // What the page settled this session: a list read already on its way
  // when the answer was given would bring the item back as open (found
  // 2026-11-15, a card declined beside another accepted). A settled item
  // never opens again, so it stays left out.
  property var settledHere: ({})
  function resolveProposal(item, how, answer) {
    root.settledHere[item.id] = true
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

  // Enter on one of the planner's proposals, questions, or things it did:
  // the margin opens beside the dashboard, on the box's conversation, with
  // it pinned at the top — the way a block's conversation opens beside the
  // note.
  function openTalk(item) {
    if (!item || item.kind === "file") return
    root.talkId = item.id
    root.talkTask = ""
    root.talkThread = item.thread || ("#" + item.id)
    root.startTalk("open")
  }

  // C or Ctrl+Enter on a task's row, or the row's "chat" (2026-10-27): the
  // agent, summoned to think the task through, on the task's one chat.
  function openTaskTalk(t) {
    if (!t || !t.key) return
    if (t.private) { root.showHint("private: the agent sees nothing of this box"); return }
    root.talkId = -1
    root.talkTask = t.key
    root.talkThread = "task:" + t.key
    root.startTalk("task")
  }

  function startTalk(how) {
    if (root.here !== "right") root.noteFrom("right")
    root.talkSettled = ""
    root.talkCardFocus = -1
    root.talkData = null
    root.used("talk", how)
    root.fetchTalk()
    if (root.refFiles.length === 0) root.loadRefFiles()   // what `@` offers here too: notes and papers
    root.marginFocus = 1
    Qt.callLater(function () { margin.chatFieldRef.forceActiveFocus() })
  }

  function talkFocused() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    // What has no chat says why, and what to do instead (2026-11-27: C did
    // nothing on these, under a key that offered it).
    var why = root.noChatWhy(row)
    if (why !== "") { root.showHint(why); return }
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") root.openTalk(row.item)
    else if (row.kind === "task") root.openTaskTalk(row.task)
    else if (row.kind === "deadline") root.openTaskTalk(root.taskOfAnchor(row.deadline.id))
  }
  // Why a row has no chat to open, in words; "" when it has one.
  function noChatWhy(row) {
    if (!row) return " "
    if ((row.kind === "proposal" || row.kind === "told") && row.item.kind === "file")
      return "a document: " + root.keyName("dashOpen") + " opens it, " + root.keyName("dashDone") + " files it"
    var t = row.kind === "task" ? row.task : row.kind === "deadline" ? root.taskOfAnchor(row.deadline.id) : null
    if (row.kind === "deadline" && !t)
      return Bound.parseLink(row.deadline.link) ? "its line is in a note not read yet — " + root.keyName("dashOpen") + " goes to it"
        : "not in a note yet — " + root.keyName("dashOpen") + " writes it into today's note, then it can be talked about"
    if (t && t.private) return "private: the agent sees nothing of this box"
    if (row.kind !== "task" && row.kind !== "deadline" && row.kind !== "proposal" && row.kind !== "question" && row.kind !== "told") return " "
    return ""
  }

  function fetchTalk() {
    if (root.talkThread === "") return
    if (threadProc.running) { root.talkFetchAgain = true; return }
    threadProc.command = [svc.runner, "thread"].concat(root.talkId >= 0 ? ["--id", String(root.talkId)] : ["--key", root.talkTask])
    threadProc.running = true
  }

  // Back to the rows (Esc), or the dashboard closed with it.
  function closeTalk(focusRows) {
    if (root.talkThread === "") return
    root.talkId = -1
    root.talkTask = ""
    root.talkThread = ""
    root.talkData = null
    root.talkSettled = ""
    root.talkCardFocus = -1
    root.marginFocus = -1
    if (focusRows !== false) dash.dashKeysRef.forceActiveFocus()
  }

  // Esc in a task's conversation: to the day's, when it is open beside
  // the dashboard (the pane's home), else back where the keys came from.
  function leaveTalk() {
    var was = root.here
    root.closeTalk(false)
    if (was === "right" && root.rightView === "day") root.dayKeysItem().forceActiveFocus()
    else root.giveBack("right", was, "right")
  }

  function sendTalk() {
    var raw = String(margin.chatFieldRef.text || "")
    if (root.talking && raw.trim() !== "") {
      root.showHint("the agent is still answering · " + root.keyName("marginBack") + " stops it")
      return
    }
    var msg = root.composed("margin", raw)
    if (msg === "" || root.talking || !root.talkCanSend) return
    var savedReplies = root.marginReplies.slice()
    var savedRefs = root.talkToPlanner ? [] : root.marginRefs.slice()
    var mentions = root.talkToPlanner ? [] : margin.chatFieldRef.liveMentions.slice()
    root.clearReplies("margin")
    root.pendingTalk = { thread: root.talkThread, text: msg, raw: raw, replies: savedReplies, savedRefs: savedRefs, mentions: mentions,
                         refs: savedRefs.map(function (r) { return { date: r.date || "", hash: r.hash || "", file: r.file || "", kind: r.kind, head: r.head } }) }
    margin.chatFieldRef.text = ""
    var c = root.talkData ? root.talkData.chat : null
    var refs = root.talkToPlanner ? [] : root.takeMarginRefs()
    talkProc.command = root.talkToPlanner ? [svc.runner, "talk", "--id", String(root.talkId), "--message", msg]
      : [svc.runner, "chat", "--hash", c.hash, "--message", msg, "--date", c.date]
        .concat(refs.length > 0 ? ["--refs", JSON.stringify(refs)] : [])
    talkProc.running = true
    root.holdThinking("talk")
    root.used("talk", root.talkToPlanner ? "send" : "chat")
  }

  // What the planner answered: a revision takes the proposal's place (the
  // conversation follows it); an agreement settles it — a decline is
  // recorded by the runner, an accept written by the page like any accept.
  function talkAnswered(out) {
    if (out.current !== undefined && out.current !== root.talkId && root.talkId === out.id) root.talkId = out.current
    var item = root.proposals.filter(function (x) { return x.id === out.current })[0]
    if (out.kind === "question" && out.resolved) {
      root.proposals = root.proposals.filter(function (x) { return x.id !== out.current })
      root.talkSettled = out.settle === "accept" ? "answered" : "declined"
      root.showHint(out.settle === "accept" ? "answered, as you agreed" : "set aside, as you agreed")
    } else if (item && item.told) {
      // What it did on its own: let stand by the runner, undone by the page.
      if (out.settle === "decline") { root.undoProposal(item); root.talkSettled = "undone"; root.showHint("undone, as you agreed") }
      else if (out.settle === "accept") {
        root.proposals = root.proposals.filter(function (x) { return x.id !== out.current })
        root.talkSettled = "kept"
      }
    } else if (out.settle === "decline") {
      root.proposals = root.proposals.filter(function (x) { return x.id !== out.current })
      root.talkSettled = "declined"
      root.showHint("declined, as you agreed")
    } else if (out.settle === "accept") {
      root.acceptAfterRefresh = out.current
      root.talkSettled = "accepted"
    }
    root.refreshProposals()
  }

  // Space / Ctrl+Enter in the margin, on the proposal pinned there; Del
  // declines it. The same verbs as on its row.
  function acceptTalked() {
    var p = root.talkItem
    if (!p) return
    root.acceptPlanned({ kind: Say.askKind(p), item: p, task: root.taskOfKey(p.key) })
    root.talkSettled = p.kind === "question" ? "answered" : p.told ? "kept" : "accepted"
  }

  // The keys on the pinned proposal, in one function so they can be
  // driven without a keyboard (tests/page/run.py).
  function talkKey(e) {
    if (Sc.hit(e, "marginBack") && root.stopAgent("talk")) return true
    if (Sc.hit(e, "marginBack")) { root.leaveTalk(); return true }
    // The Ctrl+Z its settled cards show (2026-11-28: shown, not taken).
    if (Sc.hit(e, "undo") && root.undoLastCard()) return true
    if (root.talkCardFocus >= 0) {
      var n = root.talkCards.length
      if (Sc.hit(e, "marginAccept")) { root.acceptTalkCard(root.talkCards[root.talkCardFocus]); return true }
      if (Sc.hit(e, "marginUp")) {
        if (root.talkCardFocus > 0) root.focusTalkCard(root.talkCardFocus - 1)
        else if (root.talkItem) { root.talkCardFocus = -1; root.marginFocus = 0 }
        return true
      }
      if (Sc.hit(e, "marginDown")) {
        if (root.talkCardFocus < n - 1) root.focusTalkCard(root.talkCardFocus + 1)
        else { root.talkCardFocus = -1; root.marginFocus = 1; margin.chatFieldRef.forceActiveFocus() }
        return true
      }
      if (Sc.hit(e, "marginDecline")) { root.declineTalkCard(root.talkCards[root.talkCardFocus]); return true }
      return false
    }
    if (Sc.hit(e, "marginAccept")) { root.acceptTalked(); return true }
    if (Sc.hit(e, "marginDecline")) { root.declineTalked(); return true }
    if (Sc.hit(e, "marginDown")) {
      if (root.talkCards.length > 0) { root.focusTalkCard(0); return true }
      root.marginFocus = 1; margin.chatFieldRef.forceActiveFocus(); return true
    }
    return Sc.hit(e, "marginUp")
  }

  function focusTalkCard(i) {
    if (i < 0 || i >= root.talkCards.length) return
    root.talkCardFocus = i
    root.marginFocus = 1
    margin.marginKeysRef.forceActiveFocus()
  }

  // Space on a card in the task's chat, or a click: the runner does what it
  // says (`accept`, as from the note's margin), on the block the chat is
  // filed under; the chat is read again, and the card says what came of it.
  // The box's line is bound only from its note, where the page has it.
  function acceptTalkCard(c) {
    if (c && c.ledger) { root.settleListedCard(c, "accept"); return }
    var chat = root.talkData ? root.talkData.chat : null
    if (!c || !chat || c.accepted || c.superseded || c.declined || acceptProc.running) return
    root.pendingAccept = null
    acceptProc.command = [svc.runner, "accept", "--hash", chat.hash, "--index", String(c.index), "--date", chat.date]
    acceptProc.running = true
    root.used("talk", "card")
  }
  // …and its decline: one the dashboard lists is settled there; the
  // runner's own is kept on the card, and the chat read again.
  function declineTalkCard(c) {
    if (c && c.ledger) { root.settleListedCard(c, "decline"); return }
    var chat = root.talkData ? root.talkData.chat : null
    if (!c || !chat || c.accepted || c.superseded || c.declined) return
    root.saveDecline(chat.hash, c.index, chat.date)
    root.used("talk", "card-decline")
  }

  function declineTalked() {
    var p = root.talkItem
    if (!p) return
    if (p.told) { root.undoProposal(p); root.talkSettled = "undone"; return }
    root.resolveProposal(p, "decline", "")
    root.talkSettled = "declined"
  }

  // Space / Ctrl+Enter on a proposal: the do-date is written on the box's
  // line — by the page, the one writer of notes — and the acceptance
  // recorded. On a question: the recommended answer.
  function acceptPlanned(row) {
    var p = row.item
    if (row.kind === "question") { root.resolveProposal(p, "accept", ""); return }
    // What the agent did on its own: Space lets it stand.
    if (row.kind === "told") { root.resolveProposal(p, "accept", ""); return }
    // A document: the runner moves it into the course's folder.
    // A document: the runner moves it into the course's folder; Ctrl+Z
    // puts it back (2026-11-18: filed by a key pressed in passing, and
    // nothing could take it back).
    if (p.kind === "file") {
      root.resolveProposal(p, "accept", "")
      root.rememberUndo({ unfile: p.id, say: "filing “" + String(p.name || "").replace(/\.pdf$/i, "") + "”" })
      root.showHint("filed “" + String(p.name || "").replace(/\.pdf$/i, "") + "” in " + (p.title || p.project)
                    + " · " + root.keyName("dashUndo") + " puts it back")
      return
    }
    if (p.kind === "project") { root.resolveProposal(p, "accept", ""); root.showHint("#" + p.project + " is a project now"); return }
    if (!root.applyProposal(p, row.task)) return
    root.resolveProposal(p, "accept", "")
  }

  // The agent's actions (docs/agent.md, slices 2 and 5): what each does
  // when the person accepts it — or, at "do it and tell me", when it
  // arrives — written by the page, the one writer of notes; and how each is
  // undone. Facts on a box leave it the person's (a do-date's pill is
  // tinted); new lines — steps, a deadline's box — are the agent's (◇).
  function applyProposal(p, task) {
    var t = task || (p.key ? root.taskOfKey(p.key) : null)
    if (p.kind === "project") return true          // made by the runner, on accepting it
    // A deadline with no line (2026-11-15): cancelled in the store, as Del
    // on its row does.
    if (p.kind === "drop" && !p.key && p.deadline) {
      var d = dl.items.filter(function (x) { return x.id === p.deadline })[0]
      if (!d || d.status !== "open") { root.showHint("deadline #" + p.deadline + " is not open any more"); return false }
      root.dropDeadline(d)
      return true
    }
    // A deadline moved (slice 4 of "One conversation"): its date in the
    // store, the line catching up as with any move.
    if (p.kind === "move") {
      var dm = dl.items.filter(function (x) { return x.id === p.deadline })[0]
      if (!dm || dm.status !== "open") { root.showHint("deadline #" + p.deadline + " is not open any more"); return false }
      dl.set(p.deadline, [p.date])
      return true
    }
    // A task the student asked for: written into today's note, under its
    // course, marked as the agent's line.
    if (p.kind === "task") {
      var tl = "- [ ] " + p.title + (/^[\w\/-]+$/.test(p.project || "") ? " #" + p.project : "")
      root.addToToday(tl, p.project)
      root.markAgentLine(svc.todayStamp(), tl)
      return true
    }
    if (p.kind !== "deadline" && !t) { root.showHint("its box is not on the list any more"); return false }
    // A day already gone is not accepted (the runner settles it as moot on
    // the next list): it would put a past date on the line.
    if ((p.kind === "do-date" || p.kind === "deadline") && p.date && p.date < Qt.formatDate(new Date(), "yyyy-MM-dd")) {
      root.showHint("its day has passed, so it is not written")
      return false
    }
    if (p.kind === "do-date") {
      root.editTask(t, "when", p.date)
      var d = {}
      for (var k in root.agentDates) d[k] = root.agentDates[k]
      d[p.key] = p.date
      root.agentDates = d
    } else if (p.kind === "priority") root.editTask(t, "prio", p.priority)
    else if (p.kind === "drop") root.editTask(t, "drop", "")
    else if (p.kind === "done") { if (!t.done) root.tickTask(t) }
    else if (p.kind === "undone") { if (t.done) root.editTask(t, "undone", "") }
    else if (p.kind === "steps") {
      root.editTask(t, "steps", p.steps)
      var lead = root.leadOf(t.text)
      for (var i = 0; i < p.steps.length; i++) root.markAgentLine(t.date, lead + "  - [ ] " + p.steps[i])
    } else if (p.kind === "deadline") {
      var line = root.deadlineLine(p)
      root.addToToday(line, p.project)
      root.markAgentLine(svc.todayStamp(), line)
    } else return false
    return true
  }

  function undoProposal(p) {
    var t = p.key ? root.taskOfKey(p.key) : null
    if (p.kind === "move") dl.set(p.deadline, [p.was || ""])
    // Undoing a tick or a reopening: the box as the list has it may be a
    // read behind the note, so its state is not asked; the edit is.
    else if (p.kind === "done" && t) root.editTask(t, "undone", "")
    else if (p.kind === "undone" && t) root.editTask(t, "done", "")
    else if (p.kind === "task") {
      var tl = "- [ ] " + p.title + (/^[\w\/-]+$/.test(p.project || "") ? " #" + p.project : "")
      var nt = root.tasks.filter(function (x) { return Task.sameWords(x.text, tl) })[0]
      if (nt) root.editTask(nt, "remove", "")
    } else if (p.kind === "do-date" && t) root.editTask(t, "when", p.was || "")
    else if (p.kind === "priority" && t) root.editTask(t, "prio", p.was || 0)
    else if (p.kind === "drop" && !p.key && p.deadline) dl.reopen(p.deadline)
    else if (p.kind === "drop" && t) root.editTask(t, "undrop", "")
    else if (p.kind === "steps" && t) {
      var lead = root.leadOf(t.text)
      for (var i = 0; i < p.steps.length; i++)
        root.editTask({ date: t.date, file: t.file, line: t.line + 1 + i, text: lead + "  - [ ] " + p.steps[i], anchor: 0 }, "remove", "")
    } else if (p.kind === "deadline") {
      // Its line is a deadline's now: cancelled through it, as any deadline
      // is (docs/tasks.md), so the note still says what was decided.
      var line = root.deadlineLine(p)
      var d = root.tasks.filter(function (x) { return Task.sameWords(x.text, line) })[0]
      if (d) root.editTask(d, "drop", "")
    }
    root.resolveProposal(p, "undo", "")
  }

  function leadOf(text) { var m = /^\s*/.exec(text || ""); return m ? m[0] : "" }

  // The box a deadline found in the writing becomes: its words, its tag,
  // its date (longhand-check binds it into the store).
  function deadlineLine(p) {
    return "- [ ] " + p.title + (/^[\w\/-]+$/.test(p.project || "") ? " #" + p.project : "") + " 📅 " + p.date
  }

  // Where a new box goes in today's note: at the end of its course's
  // section when today has one, else at the top (Bound.placeAt).
  function insertAt(lines, tag) {
    return Bound.placeAt(lines, tag)
  }

  // A line written into the open note where it goes, as one undo step.
  function placeLine(line, tag) {
    var lines = editor.text.split("\n")
    var at = root.insertAt(lines, tag)
    var pos = lines.slice(0, at).join("\n").length
    editor.snapshot(true)
    root.quiet = true
    editor.insert(pos, (at > 0 ? "\n" : "") + line + (at === 0 && editor.text !== "" ? "\n" : ""))
    root.quiet = false
  }

  // Today's note open but being read again (a check just rewrote it): wait
  // for it, rather than write the file under the open note, whose own
  // save would then lose the line.
  property var todayWaiting: []
  Timer {
    id: todayRetry
    interval: 150
    onTriggered: {
      var w = root.todayWaiting
      root.todayWaiting = []
      for (var i = 0; i < w.length; i++) root.addToToday(w[i].line, w[i].tag)
    }
  }

  function addToToday(line, tag) {
    if (svc.noteDate === svc.todayStamp() && !svc.ready) {
      root.todayWaiting = root.todayWaiting.concat([{ line: line, tag: tag }])
      todayRetry.restart()
      return
    }
    if (svc.isToday && svc.ready) {
      root.placeLine(line, tag)
      Qt.callLater(root.flush)
      Qt.callLater(root.refreshTasks)
      root.scheduleCheck()
      return
    }
    editFile.add({ file: svc.pathFor(svc.todayStamp()), date: svc.todayStamp(), line: -1, text: "", anchor: 0 },
                 "insert", { line: line, tag: tag })
  }

  // A line the agent wrote, kept as the agent's in the layer.
  function markAgentLine(stem, raw) {
    if (stem === svc.noteDate) {
      Qt.callLater(function () {
        for (var i = 0; i < editor.rows.length; i++)
          if (editor.rows[i].raw === raw) { root.markAuthor(i, "agent"); return }
      })
      return
    }
    var st = {}
    for (var k in root.authorsStore) st[k] = root.authorsStore[k]
    st[stem] = (st[stem] || []).concat([{ id: Authorship.key(raw), author: "agent" }])
    root.authorsStore = st
    authorsSave.restart()
  }

  // At "do it and tell me": what arrives marked for the page is done at
  // once, then told — a row the person lets stand (Space) or undoes (Del).
  property var autoApplied: ({})
  function applyAuto(list) {
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p.auto || p.status !== "open" || root.autoApplied[p.id] || p.kind === "file") continue
      var a = {}
      for (var k in root.autoApplied) a[k] = root.autoApplied[k]
      a[p.id] = true
      root.autoApplied = a
      if (!root.applyProposal(p, null)) continue
      root.proposalQueue = root.proposalQueue.concat([[svc.runner, "proposal", "applied", "--id", String(p.id)]])
      root.nextProposal()
      root.used("proposal", "auto-" + p.kind)
    }
  }

  // The dates a row carries, drawn the way the note draws them: a bordered
  // date at the line's end. The day it is owed is bare, as in the note; the
  // day I mean to work on it says so and is filled rather than outlined.
  // A deadline's row reads the rest from its line, as a task's does: the
  // day agreed to work on it and the estimate were drawn for plain boxes
  // only until 2026-10-25, and every ⏳ in use was on a dated line.
  function pillsFor(row) {
    var out = []
    if (row.kind === "deadline") {
      var d = row.deadline
      var lt = root.taskOfAnchor(d.id)
      if (lt && lt.when && d.status === "open") out.push(root.doPill(lt))
      var at = new Date(d.due * 1000)
      var timed = !(at.getHours() === 23 && at.getMinutes() === 59)
      // Closed: nothing owed, so no day to say (it said "3 days late").
      if (d.status !== "open") return []
      out.push({ text: Say.sayDue(Qt.formatDateTime(at, timed ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"), new Date(root.dashNow)),
                 tone: d.due * 1000 < root.dashNow ? "late" : "due" })
      if (lt && lt.est) out.push({ text: lt.est, tone: "est" })
      return out
    }
    // What the agent raised is dismissed on purpose, by a word of its own
    // or Enter, never by a click on the row that only meant to look
    // (2026-11-25, the mouse pass).
    if (row.kind === "raised") return [{ text: "dismiss", tone: "act" }]
    if (row.kind !== "task") return out
    var t = row.task
    if (t.done || t.cancelled) return out
    if (t.when) out.push(root.doPill(t))
    // A box's own due date gone by is late, as a deadline's is: it stood in
    // LATE drawn as nothing owed (2026-11-27).
    if (t.due) out.push({ text: Say.sayDue(t.due, new Date(root.dashNow)), tone: root.taskLate(t) ? "late" : "due" })
    if (t.est) out.push({ text: t.est, tone: "est" })
    return out
  }

  function doPill(t) {
    return { text: Say.sayDo(t.when, new Date(root.dashNow)) + (root.agentDates[t.key] === t.when ? " ◇" : ""), tone: "do" }
  }
  // A box past the day it was due (📅): its day over, or its hour passed.
  function taskLate(t) {
    if (!t || !t.due || t.done || t.cancelled) return false
    var ms = Say.taskMs({ due: t.due })
    var hm = String(t.due).split(" ")[1]
    var end = hm ? ms + (parseInt(hm.split(":")[0], 10) * 60 + parseInt(hm.split(":")[1], 10)) * 60000 : ms + 86400000
    return end < root.dashNow
  }

  // Heads and month bands are passed over: they are not rows you act on.
  // A date band is (it folds), unless it has nothing to fold. A move of 0
  // is how the cursor lands on a real row to begin with.
  function moveTaskFocus(d) {
    if (d !== 0) root.justClosed = ""
    var rows = root.taskRows
    var step = d === 0 ? 1 : d
    var i = root.taskFocus + d
    while (i >= 0 && i < rows.length && (rows[i].kind === "head" || rows[i].kind === "month"
                                         || (rows[i].kind === "band" && (rows[i].count === 0 || rows[i].fixed)))) i += step
    if (i >= 0 && i < rows.length) root.taskFocus = i
  }

  // ------------------------------------------- the date bands, folded
  // (2026-11-03): ← on a row climbs to its band, ← on a band folds it;
  // → opens a folded band, or steps into an open one; Enter toggles; fold
  // all and unfold all, by Shift and the arrows or the two words above
  // the list.
  // The band a row is in; none past a heading (what the agent raised is
  // in no band, though it comes after one).
  function bandAt(i) {
    for (var j = i; j >= 0; j--) {
      var r = root.taskRows[j]
      if (r && r.kind === "band") return j
      if (r && r.kind === "head") return -1
    }
    return -1
  }
  function setFold(id, open) {
    var f = {}
    for (var k in root.dashFolds) f[k] = root.dashFolds[k]
    f[id] = open
    root.dashFolds = f
    root.savePageState()
  }
  function foldAll(open) {
    if (root.dashOrder !== "date") return
    // The cursor stays on the band it was in.
    var b = root.taskRows[root.bandAt(root.taskFocus)]
    root.dashFolds = { "*": open }
    root.savePageState()
    root.used("dash-fold", open ? "all open" : "all shut")
    if (!b) return
    for (var i = 0; i < root.taskRows.length; i++) if (root.taskRows[i].kind === "band" && root.taskRows[i].id === b.id) root.taskFocus = i
    if (root.taskRows[root.taskFocus].fixed || root.taskRows[root.taskFocus].count === 0) root.moveTaskFocus(0)
  }
  function toggleBand(row) {
    if (row.fixed || row.count === 0) return
    // Set aside and waiting for a grade: unfolded for a look, folded again
    // when the dashboard closes; never kept with the date bands.
    if (row.id === "shelf") { root.showShelf = !row.open; return }
    if (row.id === "grading") { root.showGrading = !row.open; return }
    // Held open by what is searched: folding it would change nothing on
    // screen, and be found folded later (2026-11-27).
    if (row.forced) { root.showHint("open while the list is narrowed · " + root.keyName("dashAll") + " shows all, folded as it was"); return }
    root.setFold(row.id, !row.open)
    root.used("dash-fold", row.open ? "shut" : "open")
  }
  function foldLeft() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    if (row.kind === "band") { if (row.open) root.toggleBand(row); return }
    var at = root.bandAt(root.taskFocus)
    if (at < 0) return
    // Late never folds: ← there stays where it is.
    if (root.taskRows[at].fixed) return
    root.taskFocus = at
  }
  function foldRight() {
    var row = root.taskRows[root.taskFocus]
    if (!row || row.kind !== "band") return
    if (!row.open) root.toggleBand(row)
    else root.moveTaskFocus(1)
  }

  // What the agent is doing, beside the dashboard's name: planning, or why
  // it could not. Until 2026-11-14 the name had a line of counts too ("5
  // open · 5 with a date to meet · 1 done today · 25 from the agent"),
  // which read like a second row of chips and disagreed with them: it
  // counted only the rows of unfolded bands, so "5 open" stood over "All
  // 40". The chips are the counts now, and the agent has a chip of its own.
  readonly property string dashStatus: root.planning ? (root.planPhase !== "" && root.planPhase !== "thinking" ? "planning · " + root.planPhase + "…" : "planning…")
    : root.planError !== "" ? "the agent could not plan: " + root.planError : ""
  // The agent's chip: what it asks or has done, of what the strip keeps,
  // and how much of that arrived since the dashboard was last left.
  readonly property var dashAgent: {
    var asks = root.dashCourses.asks || []
    return { asks: asks.length, fresh: asks.filter(root.isNewAsk).length }
  }
  // The agent's chip clicked: to the next thing it asks, as N.
  function clickAgentChip() {
    dash.dashKeysRef.forceActiveFocus()
    if (root.stripAt >= 0) root.leaveStrip()
    root.focusAsk(1)
  }

  // Enter: go to the task's line, on any day; the dashboard closes. A
  // deadline no line stands for yet is written into today's note — the
  // person's act, which is what makes its words theirs (docs/tasks.md).
  function activateTask() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    // Enter on anything the agent offers — a proposal, a question, what it
    // did on its own — is a conversation with it (2026-10-20: writing back
    // means there is something to talk about). A document to file opens.
    if ((row.kind === "proposal" || row.kind === "told") && row.item.kind === "file") {
      Qt.openUrlExternally(Links.fileUrl(row.item.filed || row.item.src)); root.used("document", "open"); return
    }
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") { root.openTalk(row.item); return }
    if (row.kind === "band") { root.toggleBand(row); return }
    if (row.kind === "task") root.goToTask(row.task)
    if (row.kind === "deadline") {
      var d = row.deadline
      if (Bound.parseLink(d.link)) { root.toNote(); root.goToDeadline(d); return }
      root.writeIntoToday(d)
    }
    if (row.kind === "raised") {
      root.runInTurn(dismissProc, [svc.runner, "dismiss", "--date", row.item.date, "--kind", row.item.kind, "--index", String(row.item.index)])
    }
  }

  function focusedTask() {
    var row = root.taskRows[root.taskFocus]
    return row && row.kind === "task" ? row.task : null
  }

  // The line under the row for what a line holds (its priority, the day to
  // work on it): a task's own, or the line an open deadline stands for.
  function focusedLine() {
    var row = root.taskRows[root.taskFocus]
    if (row && row.kind === "deadline" && row.deadline.status === "open") return root.taskOfAnchor(row.deadline.id)
    return root.focusedTask()
  }

  // Delete: dropping something is an answer, and the only honest one for a
  // box that is never going to happen. The line keeps its words and becomes
  // `- [-] … ❌ <today>`, so the note still says what was decided. A
  // deadline is cancelled the same way, through its line — words are only
  // ever deleted in the note — and one with no line yet is cancelled in the
  // store.
  function dropFocused() {
    var row = root.taskRows[root.taskFocus]
    if (row && row.kind === "told") { root.rememberSettled(row.item, "undone"); root.undoProposal(row.item); return }
    if (row && (row.kind === "proposal" || row.kind === "question")) {
      root.rememberSettled(row.item, "declined")
      root.resolveProposal(row.item, "decline", "")
      root.showHint("declined")
      return
    }
    if (row && row.kind === "deadline") { root.dropDeadline(row.deadline); return }
    var t = root.focusedTask()
    if (!t) return
    // Dropped already (it stays until tomorrow): Del again does nothing,
    // and says how it comes back.
    if (t.cancelled) { root.showHint("dropped already · " + root.keyName("dashDone") + " or " + root.keyName("dashUndo") + " brings it back"); return }
    root.justClosed = root.rowKey({ kind: "task", task: t })
    root.rememberUndo({ drop: t, say: "dropping “" + Say.taskTitle(t) + "”" })
    root.editTask(t, "drop", "")
    root.showHint("dropped “" + Say.taskTitle(t) + "” · " + root.keyName("dashUndo") + " brings it back")
    root.used("drop")
  }

  function dropDeadline(d) {
    if (d.status === "cancelled") { root.showHint("cancelled already · " + root.keyName("dashUndo") + " brings it back"); return }
    var t = root.lineTaskOf(d)
    var say = "cancelling “" + d.title + "”"
    root.justClosed = "d" + d.id
    if (t) {
      root.rememberUndo({ drop: t, say: say })
      root.editTask(t, "drop", "")
    } else {
      root.rememberUndo({ uncancel: d.id, say: say })
      dl.cancel(d.id)
    }
    root.showHint("cancelled “" + d.title + "” · " + root.keyName("dashUndo") + " brings it back")
    root.used("drop", "deadline")
  }

  // The agent's answer is the ledger's, and the runner takes none back:
  // Ctrl+Z after one says so, rather than reaching past it to an older
  // change (2026-11-27). One that wrote on a box (a day, a priority)
  // leaves the box as it is now; the box's own keys change it.
  function rememberSettled(item, how) {
    root.rememberUndo({ settled: true, say: how + " “" + Say.sayAsk(item, false) + "”" })
  }

  // `p`: none → high → low → none. One key for the whole scale, because
  // three levels are offered where five are read.
  function cyclePriorityFocused() {
    var t = root.focusedLine()
    if (!t) {
      var row = root.taskRows[root.taskFocus]
      if (row && row.kind === "deadline" && row.deadline.status === "open")
        root.showHint("not in a note yet — Enter writes it into today's note")
      return
    }
    // From what was asked last, while the list has not caught up: `p p`
    // quicker than the list is read went none → high, none → high.
    var key = root.taskKey(t.date, Task.wordsOf(t.text))
    var was = root.pendingPrio[key] !== undefined ? root.pendingPrio[key] : (t.priority || 0)
    var next = Task.nextPriority(was)
    var pp = Object.assign({}, root.pendingPrio)
    pp[key] = next
    root.pendingPrio = pp
    root.rememberUndo({ field: "prio", task: t, arg: was, say: "the priority of “" + Say.taskTitle(t) + "”" })
    root.editTask(t, "prio", next)
    root.touchBox(t, "keep")
    root.showHint(next === 2 ? "high priority" : next === -1 ? "low priority" : "no priority")
    root.used("priority")
  }
  property var pendingPrio: ({})   // a box's key -> the priority asked, until the list is read again

  // `s`: set aside. The box goes where quiet ones go, and nothing is written
  // into the note; `s` again (or `r`) brings it back. Its clock is the
  // layer's (agent/lifespan.py).
  function shelveFocused() {
    var t = root.focusedTask()
    if (!t || t.life === 0) { root.whyNoClock(); return }
    root.rememberUndo({ box: t, how: t.away ? "shelve" : "keep", say: (t.away ? "bringing back “" : "setting aside “") + Say.taskTitle(t) + "”" })
    root.touchBox(t, t.away ? "keep" : "shelve")
    root.showHint(t.away ? "back on the list" : "set aside · " + root.keyName("dashShelve") + " on it, in set aside, brings it back")
    root.used(t.away ? "keep" : "shelve")
  }

  // `r`: renewed on purpose — its clock starts again, and it is back if it was
  // away.
  function keepFocused() {
    var t = root.focusedTask()
    if (!t || t.life === 0) { root.whyNoClock(); return }
    // A clock started again cannot be set back; one brought back from
    // set aside can be put there again.
    root.rememberUndo(t.away ? { box: t, how: "shelve", say: "bringing back “" + Say.taskTitle(t) + "”" }
                             : { settled: true, say: "renewing “" + Say.taskTitle(t) + "” (its clock is not set back)" })
    root.touchBox(t, "keep")
    root.showHint(t.away ? "back on the list, its clock started again" : "renewed: its clock starts again")
    root.used("keep")
  }
  // `s` or `r` where there is no clock to set: said, not ignored.
  function whyNoClock() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    if (row.kind === "deadline") root.showHint("a deadline is judged by its date, not set aside · " + root.keyName("dashWhen") + " gives it a day to work on it")
    else if (row.kind === "task") root.showHint("a box with a date never goes quiet: nothing to set aside or renew")
  }

  function touchBox(t, how) {
    if (!t || !t.key || t.life === 0) return
    root.runInTurn(boxProc, [svc.runner, "box", how, "--key", t.key])
  }

  // A write to the runner, in the order asked. Setting `running` on a
  // process already running does nothing, so a second press while the
  // first was being written was lost (2026-10-25): two boxes put aside in
  // a row kept only the first. Each process here keeps its own `queue`.
  function runInTurn(proc, args) {
    proc.queue = proc.queue.concat([args])
    root.nextInTurn(proc)
  }
  function nextInTurn(proc) {
    if (proc.running || proc.queue.length === 0) return
    proc.command = proc.queue[0]
    proc.queue = proc.queue.slice(1)
    proc.running = true
  }

  // `g`: the grade, typed on a deadline's row, as in the popup. A grade on
  // one still open hands it in (pomo); empty clears it.

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
    var t = root.focusedLine()
    if (!t) {
      var row = root.taskRows[root.taskFocus]
      if (row && row.kind === "deadline" && row.deadline.status === "open")
        root.showHint("not in a note yet — Enter writes it into today's note")
      return
    }
    // The day it has, to change: an empty field hid it (2026-11-27).
    root.dashFieldKind = "when"
    root.dashFieldStart = t.when ? Qt.formatDate(new Date(Say.taskMs({ when: t.when })), "d MMM") : ""
    root.dashWhenText = root.dashFieldStart
    root.dashWhenFor = t
  }

  // Shift+T: the day to work on it taken off again (Todoist's key), the
  // other half of `t`. A deadline's own date is not this: it is changed
  // where it was given, in the note.
  function noDateFocused() {
    var t = root.focusedLine()
    if (!t) return
    if (!t.when) { root.showHint("no day to work on it: " + root.keyName("dashWhen") + " gives it one"); return }
    root.rememberUndo({ field: "when", task: t, arg: t.when, say: "taking the day off “" + Say.taskTitle(t) + "”" })
    root.editTask(t, "when", "")
    root.showHint("its day is off · " + root.keyName("dashUndo") + " puts it back")
    root.used("when", "removed")
  }

  // Ctrl+E or F2: the task's words, rewritten on its row (Todoist's key for it).
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
    if (t.deadline) {
      root.rememberUndo({ retitle: t.deadline.id, arg: t.deadline.title, say: "renaming “" + t.deadline.title + "”" })
      dl.set(t.deadline.id, ["--title", words])
    } else {
      var line = Task.setWords("- [ ] " + t.text, words)
      root.authorRenamed(t.date, "- [ ] " + t.text, line)
      // Its words are its key: the cursor follows them to the row renamed.
      var renamed = Object.assign({}, t, { text: line.replace(/^- \[ \] /, "") })
      if (root.focusedTask() === t || root.focusedLine() === t) {
        var row = root.taskRows[root.taskFocus]
        if (row && row.kind === "task") root.taskFocusKey = "t" + root.taskKey(t.date, Task.wordsOf(renamed.text))
      }
      root.rememberUndo({ field: "rename", task: renamed, arg: root.dashFieldStart, say: "renaming “" + root.dashFieldStart + "”" })
      root.editTask(t, "rename", words)
    }
    root.used("rename")
  }

  function commitDashWhen() {
    if (root.dashFieldKind === "rename") { root.commitDashRename(); return }
    if (root.dashFieldKind === "grade") {
      var g = root.dashWhenFor
      var mark = root.dashWhenText.replace(/\s+/g, " ").trim()
      root.dashWhenFor = null
      root.dashWhenText = ""
      if (g && g.deadline && mark !== root.dashFieldStart) {
        root.rememberUndo({ regrade: g.deadline.id, arg: root.dashFieldStart, say: "the grade of “" + g.deadline.title + "”" })
        dl.grade(g.deadline.id, mark)
        root.used("grade")
      }
      return
    }
    var t = root.dashWhenFor
    var phrase = root.dashWhenText.trim()
    if (!t || phrase === "" || phrase === root.dashFieldStart) {
      // Emptied, on one with a day: the day stays — taking it off is its
      // own key, said here rather than done by an Enter in passing.
      if (t && phrase === "" && t.when) root.showHint("its day stays · " + root.keyName("dashNoDate") + " takes it off")
      root.dashWhenFor = null
      root.dashWhenText = ""
      return
    }
    var read = Dates.read(phrase, new Date())
    // Not a date: the field stays open with the words, and its preview
    // says so in place (the line under the list is the field's while it
    // is open).
    if (!read) { root.dashWhenError = "no date in “" + phrase + "”"; return }
    root.dashWhenFor = null
    root.dashWhenText = ""
    // A do-date is a day, not a moment: the time a deadline carries is the
    // hour something is owed, and a day you mean to work on it has none.
    var day = read.iso.split(" ")[0]
    root.rememberUndo({ field: "when", task: t, arg: t.when || "", say: "the day of “" + Say.taskTitle(t) + "”" })
    root.editTask(t, "when", day)
    root.showHint("do on " + Qt.formatDate(new Date(read.ms), "ddd d MMM") + " · " + root.keyName("dashUndo") + " takes it back")
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
      if (!r) {
        root.showHint("“" + Say.taskTitle(t) + "” is not in the note as it was — nothing changed")
        Qt.callLater(root.refreshTasks)
        return
      }
      if (how === "remove") {
        // Only a line the agent wrote is ever removed (undoing its steps).
        editor.snapshot(true)
        root.quiet = true
        var end = Math.min(editor.text.length, r.start + r.raw.length + 1)
        editor.remove(r.start, end)
        root.quiet = false
        Qt.callLater(root.flush)
        Qt.callLater(root.refreshTasks)
        return
      }
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
    if (how === "drop") return Task.setField(Task.setField(Task.setState(line, "-"), "✅", ""), "❌", Qt.formatDate(new Date(), "yyyy-MM-dd"))
    if (how === "undrop") return Task.setField(Task.setState(line, " "), "❌", "")
    if (how === "prio") return Task.setPriority(line, arg)
    if (how === "when") return Task.setField(line, "⏳", arg)
    if (how === "state") return Task.setState(line, arg)
    if (how === "done") return Task.setField(Task.setField(Task.setState(line, "x"), "❌", ""), "✅", Qt.formatDate(new Date(), "yyyy-MM-dd"))
    if (how === "undone") return Task.setField(Task.setState(line, " "), "✅", "")
    if (how === "rename") return Task.setWords(line, arg)
    // Steps under a box: new boxes, one level in.
    if (how === "steps") return line + arg.map(function (x) { return "\n" + root.leadOf(line) + "  - [ ] " + x }).join("")
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
    // Words selected in an answer beside the dashboard: Ctrl+C copies them
    // (2026-11-25, the mouse pass). Ctrl+R stays the dashboard's own plan.
    if (root.copyChatSelection(e, null)) return true
    if (root.stripAt >= 0) return root.stripKey(e)
    if (Sc.hit(e, "menu")) { root.menuKey(); return true }
    // Esc backs out one step, as in the files and the PDF: the words
    // typed first, then the dashboard itself (the courses picked are kept
    // on purpose, and 0 shows all).
    if (Sc.hit(e, "dashBack")) {
      if (root.dashQuery !== "") { root.dashQuery = ""; root.showHint("search cleared · " + root.keyName("dashBack") + " again goes back to the note") }
      else root.toggleDash()
      return true
    }
    if (Sc.hit(e, "dashSearch")) { root.enterStrip(0); return true }
    if (Sc.hit(e, "dashCheckin")) { root.openCheckin(true); return true }
    if (Sc.hit(e, "dashStrip")) { root.enterStrip(root.lensChip()); return true }
    if (Sc.hit(e, "dashCourse")) { root.lensDigit(e); return true }
    if (Sc.hit(e, "dashAll")) { root.setLens([]); root.dashQuery = ""; return true }
    if (Sc.hit(e, "dashOrder")) { root.cycleOrder(); return true }
    if (Sc.hit(e, "dayPrev")) { root.stepDay(-1); return true }
    if (Sc.hit(e, "dayNext")) { root.stepDay(1); return true }
    if (Sc.hit(e, "dashUp")) {
      // Up from the first row: onto the strip, on the course shown.
      var was = root.taskFocus
      root.moveTaskFocus(-1)
      if (root.taskFocus === was) root.enterStrip(root.lensChip())
      return true
    }
    if (Sc.hit(e, "dashDown")) { root.moveTaskFocus(1); return true }
    if (Sc.hit(e, "dashFold")) { root.foldLeft(); return true }
    if (Sc.hit(e, "dashUnfold")) { root.foldRight(); return true }
    if (Sc.hit(e, "dashFoldAll")) { root.foldAll(false); return true }
    if (Sc.hit(e, "dashUnfoldAll")) { root.foldAll(true); return true }
    if (Sc.hit(e, "dashFirst")) { root.taskFocus = 0; root.moveTaskFocus(0); return true }
    if (Sc.hit(e, "dashLast")) { root.taskFocus = root.taskRows.length; root.moveTaskFocus(-1); return true }
    if (Sc.hit(e, "dashPageUp")) { dash.pageStep(-1); return true }
    if (Sc.hit(e, "dashPageDown")) { dash.pageStep(1); return true }
    // Enter goes to it, everywhere in the page; Ctrl+Enter is the act that
    // settles it. Decided 2026-10-15, and it ends Enter meaning "done" in
    // the deadline popup and "go to it" here.
    if (Sc.hit(e, "dashDone")) { root.tickFocused(); return true }
    if (Sc.hit(e, "dashOpen")) { root.activateTask(); return true }
    if (Sc.hit(e, "dashFollow")) { root.followRowLink(); return true }
    if (Sc.hit(e, "dashDrop")) { root.dropFocused(); return true }
    if (Sc.hit(e, "dashUndo")) { root.untickLast(); return true }
    if (Sc.hit(e, "dashPriority")) { root.cyclePriorityFocused(); return true }
    if (Sc.hit(e, "dashWhen")) { root.startDashWhen(); return true }
    if (Sc.hit(e, "dashNoDate")) { root.noDateFocused(); return true }
    if (Sc.hit(e, "dashRename")) { root.startDashRename(); return true }
    if (Sc.hit(e, "dashShelve")) { root.shelveFocused(); return true }
    if (Sc.hit(e, "dashKeep")) { root.keepFocused(); return true }
    if (Sc.hit(e, "dashGrade")) { root.startDashGrade(); return true }
    if (Sc.hit(e, "dashPlan")) { root.runPlan(true); return true }
    if (Sc.hit(e, "dashTalk")) { root.talkFocused(); return true }
    if (Sc.hit(e, "dashExport")) { root.exportFocused(); return true }
    if (Sc.hit(e, "dashNextAsk")) { root.focusAsk(1); return true }
    if (Sc.hit(e, "dashPrevAsk")) { root.focusAsk(-1); return true }
    if (Sc.hit(e, "keysHere")) { root.toggleKeys(); return true }
    return false
  }

  // ------------------------------------------------- the course strip

  function setLens(tags, pinned) {
    root.dashLens = tags
    root.stripPinned = !!pinned && tags.length > 0
    root.savePageState()
    root.taskFocus = 0
    root.moveTaskFocus(0)
  }
  function cycleOrder() {
    root.setOrder(root.dashOrders[(root.dashOrders.indexOf(root.dashOrder) + 1) % root.dashOrders.length])
  }
  function setOrder(order) {
    root.dashOrder = order
    root.savePageState()
    root.taskFocus = 0
    root.moveTaskFocus(0)
    root.used("dash-order", root.dashOrder)
  }
  // The chip of the course shown, when one is; else All.
  function lensChip() {
    if (root.dashLens.length === 0) return 1
    for (var i = 0; i < root.stripChips.length; i++) if (root.stripChips[i].tag === root.dashLens[0]) return i + 2
    return 1
  }
  function enterStrip(at) {
    root.stripAt = Math.max(0, Math.min(root.stripEnd, at))
    root.stripOpen = false
    root.stripCameWith = root.dashLens.slice()
    root.used("strip", at === 0 ? "search" : "chips")
  }
  // The courses shown when the strip was climbed onto: ⌕ and the order
  // show them again, so walking across the chips to reach either no longer
  // leaves the last chip passed as the lens (2026-11-27: #thesis, then ←
  // to ⌕, searched All).
  property var stripCameWith: []
  function leaveStrip() {
    root.stripAt = -1
    root.stripOpen = false
    root.stripPinned = false
    root.taskFocus = 0
    root.moveTaskFocus(0)
  }
  // 1–9: the strip's first course, second…; on the strip, its cursor goes
  // there too.
  function lensDigit(e) {
    var n = e.key - Qt.Key_0
    var chip = root.stripChips[n - 1]
    if (!chip) { root.showHint("the strip has " + root.stripChips.length + " courses"); return }
    root.setLens([chip.tag])
    if (root.stripOpen) root.stripPick = n
    else if (root.stripAt >= 0) root.stripAt = n + 1
  }
  // Where the strip's cursor is, as the list would show it: All, or a
  // course's chip, picks; ⌕ and the order leave the lens as it is.
  function stripMoved() {
    if (root.stripPinned) return
    if (root.stripAt === 1) root.setLens([])
    else if (root.stripAt >= 2 && root.stripAt < root.stripEnd) root.setLens([root.stripChips[root.stripAt - 2].tag])
    else if (String(root.dashLens) !== String(root.stripCameWith)) root.setLens(root.stripCameWith.slice())
  }
  function toggleLens(tag) {
    var on = root.dashLens.indexOf(tag) >= 0
    root.setLens(on ? root.dashLens.filter(function (t) { return t !== tag }) : root.dashLens.concat([tag]), true)
  }
  // What a key types into ⌕: a printable character with no Ctrl or Alt.
  function typedChar(e) {
    if (!root.typing(e)) return ""
    var t = e.text || ""
    return t.length === 1 && t >= " " ? t : ""
  }
  // A key that types (2026-11-25): no Ctrl, Alt or Super — or Ctrl and Alt
  // together with a letter to show, which is AltGr on a Windows keyboard
  // (@, \, [, { on a German one; measured on the ThinkPad). The page's
  // own Ctrl+Alt keys (Ctrl+Alt+P) are read before anything types.
  function typing(e) {
    var m = e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    if (m === 0) return true
    var t = e.text || ""
    return m === (Qt.ControlModifier | Qt.AltModifier) && t.length === 1 && t >= " "
  }
  // ⌕'s line of text (Dashboard.qml, 2026-11-13): what it holds is shown
  // at once, and the list narrowed to it a moment later, so the frame with
  // the letter is drawn before the list is worked out — the first letter
  // waited on the whole list to be narrowed before it was seen. Letters
  // typed quicker than that are taken together.
  property bool dashSearchPending: false
  property string dashSearchTyped: ""
  // After the frame that shows the letter (the timer only in case no frame
  // comes, the window hidden): a fixed delay was sometimes shorter than the
  // wait for the next frame, and the letter waited on the list again.
  Timer { id: dashSearchApply; interval: 60; onTriggered: root.applyDashSearch() }
  // A frame synchronised since the letter came holds it; once that one is
  // on screen, the list.
  property bool dashSearchSynced: false
  Connections {
    target: root.Window.window
    enabled: root.dashSearchPending
    function onAfterSynchronizing() { root.dashSearchSynced = true }
    function onFrameSwapped() { if (root.dashSearchSynced) Qt.callLater(root.applyDashSearch) }
  }
  function dashSearchEdited(text) {
    root.dashSearchTyped = text
    if (!root.dashSearchPending) root.dashSearchSynced = false
    root.dashSearchPending = true
    if (!dashSearchApply.running) dashSearchApply.start()
  }
  function applyDashSearch() {
    if (!root.dashSearchPending) return
    dashSearchApply.stop()
    root.dashSearchPending = false
    if (root.dashQuery === root.dashSearchTyped) return
    root.dashQuery = root.dashSearchTyped
    root.taskFocus = 0
    root.moveTaskFocus(0)
  }
  // A key in ⌕'s line before the line has it: the page's own keys, and the
  // strip's — Esc clears, then gives the list back; ↓ or Enter goes down
  // to the list; → past the last letter goes on to All. True when taken.
  function dashSearchKey(e, field) {
    if (root.anywhereKey(e)) return true
    var k = e.key, plain = !(e.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    if (Sc.hit(e, "stripClear")) {
      root.applyDashSearch()
      if (root.dashQuery !== "") root.dashQuery = ""
      else root.leaveStrip()
      return true
    }
    if (k === Qt.Key_Down || k === Qt.Key_Return || k === Qt.Key_Enter) { root.applyDashSearch(); root.leaveStrip(); return true }
    if (k === Qt.Key_Right && plain && field.selectedText === "" && field.cursorPosition === field.text.length) {
      root.applyDashSearch()
      root.stripAt = 1
      root.stripMoved()
      return true
    }
    return false
  }
  function typeInto(e) {
    // Ctrl+Backspace takes the word before the cursor, as in the note
    // (2026-11-13: it took a letter, so a search went letter by letter).
    if (e.key === Qt.Key_Backspace && (e.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
      root.dashQuery = root.dashQuery.replace(/\S+\s*$|\s+$/, "")
      return true
    }
    if (e.key === Qt.Key_Backspace) { root.dashQuery = root.dashQuery.slice(0, -1); return true }
    var t = root.typedChar(e)
    if (t === "") return false
    root.dashQuery += t
    root.taskFocus = 0
    root.moveTaskFocus(0)
    return true
  }

  // The strip's keys, folded and unfolded. Everything else waits: the
  // list's own keys (Space, T, Del…) are not for a row nobody is on.
  function stripKey(e) {
    if (Sc.hit(e, "keysHere")) { root.toggleKeys(); return true }
    if (root.stripOpen) return root.unfoldedKey(e)
    var at = root.stripAt
    if (at === 0) {
      if (Sc.hit(e, "stripClear")) { if (root.dashQuery !== "") root.dashQuery = ""; else root.leaveStrip(); return true }
      if (Sc.hit(e, "stripUnfold") || Sc.hit(e, "stripDown")) { root.leaveStrip(); return true }
      if (Sc.hit(e, "stripNext")) { root.stripAt = 1; root.stripMoved(); return true }
      if (root.typeInto(e)) return true
      return true
    }
    if (Sc.hit(e, "stripPrev")) { root.stripAt = Math.max(0, at - 1); root.stripMoved(); return true }
    if (Sc.hit(e, "stripNext")) { root.stripAt = Math.min(root.stripEnd, at + 1); root.stripMoved(); return true }
    if (Sc.hit(e, "stripDown")) { root.leaveStrip(); return true }
    if (Sc.hit(e, "stripAdd")) {
      if (at === 1) root.setLens([])
      else if (at === root.stripEnd) root.cycleOrder()
      else {
        // The course shown already: Space keeps it, and the next adds.
        var tag = root.stripChips[at - 2].tag
        if (!root.stripPinned && root.dashLens.length === 1 && root.dashLens[0] === tag) root.stripPinned = true
        else root.toggleLens(tag)
      }
      return true
    }
    if (Sc.hit(e, "stripUnfold")) {
      root.stripOpen = true
      root.stripPick = at === root.stripEnd ? root.stripChips.length + 1 + root.dashOrders.indexOf(root.dashOrder)
        : at >= 2 ? at - 1 : 1
      root.used("strip", "unfold")
      return true
    }
    if (Sc.hit(e, "stripClear")) {
      if (root.dashQuery !== "") root.dashQuery = ""
      else if (root.dashLens.length > 0) { root.setLens([]); root.stripAt = 1 }
      else root.leaveStrip()
      return true
    }
    if (Sc.hit(e, "dashSearch")) { root.stripAt = 0; return true }
    if (Sc.hit(e, "dashCourse")) { root.lensDigit(e); return true }
    if (Sc.hit(e, "dashAll")) { root.setLens([]); root.stripAt = 1; return true }
    if (Sc.hit(e, "dashOrder")) { root.cycleOrder(); return true }
    return true
  }

  // Unfolded: ⌕ at the top, a row per course, the three orders. Typing
  // anywhere in it goes into ⌕.
  function unfoldedKey(e) {
    var n = root.stripChips.length, last = n + root.dashOrders.length
    var p = root.stripPick
    if (Sc.hit(e, "stripClear")) { root.stripOpen = false; return true }
    // O, as its rows say beside them: the next order, the cursor with it.
    if (Sc.hit(e, "dashOrder")) { root.cycleOrder(); root.stripPick = n + 1 + root.dashOrders.indexOf(root.dashOrder); return true }
    if (Sc.hit(e, "stripUp")) { root.stripPick = Math.max(0, p - 1); return true }
    if (Sc.hit(e, "stripDown")) { root.stripPick = Math.min(last, p + 1); return true }
    if (p > 0 && Sc.hit(e, "dashCourse")) { root.lensDigit(e); return true }
    if (p > 0 && Sc.hit(e, "dashAll")) { root.setLens([]); return true }
    var add = Sc.hit(e, "stripAdd"), only = !add && Sc.hit(e, "stripUnfold")
    if ((add || only) && p >= 1 && p <= n) {
      var tag = root.stripChips[p - 1].tag
      if (add) root.toggleLens(tag)
      else { root.setLens([tag]); root.stripOpen = false; root.stripAt = p + 1 }
      return true
    }
    if ((add || only) && p > n) {
      root.setOrder(root.dashOrders[p - n - 1])
      if (only) root.stripOpen = false
      return true
    }
    if (only && p === 0) { root.stripOpen = false; root.leaveStrip(); return true }
    // Typing goes into ⌕ itself, folded, its line of text with every key a
    // line has (2026-11-27: unfolded, it was letters drawn, and Backspace
    // stopped once the cursor was on a course).
    var ch = root.typedChar(e)
    if (ch !== "" || (p === 0 && e.key === Qt.Key_Backspace)) {
      root.stripOpen = false
      root.stripAt = 0
      if (ch !== "") root.dashQuery += ch
      else root.dashQuery = root.dashQuery.slice(0, -1)
      return true
    }
    return true
  }
  // A press outside the strip unfolded folds it, as Esc does.
  function foldStrip() { if (root.stripOpen) root.stripOpen = false }

  // A chip clicked: the strip's cursor there, and what it picks.
  // A course clicked is shown alone, and the keys go back to the list
  // (2026-11-27: they stayed on the strip, where the list's keys did
  // nothing, and with a course kept by Space a click picked nothing at
  // all). All shows everything, the words typed too.
  function clickChip(at) {
    dash.dashKeysRef.forceActiveFocus()
    if (at === root.stripEnd) { root.cycleOrder(); return }
    if (at === 0) { root.enterStrip(0); return }
    if (at === 1) { root.dashQuery = ""; root.setLens([]) }
    else if (at >= 2 && at < root.stripEnd) root.setLens([root.stripChips[at - 2].tag])
    root.stripAt = -1
    root.stripOpen = false
    root.stripPinned = false
  }

  // The next thing the agent asks of you, past the cursor and round again:
  // processing the queue without walking to it (2026-10-23).
  function focusAsk(dir) {
    var rows = root.taskRows
    for (var n = 1; n <= rows.length; n++) {
      var i = ((root.taskFocus + dir * n) % rows.length + rows.length) % rows.length
      var k = rows[i].kind
      if (k === "proposal" || k === "question" || k === "told") { root.taskFocus = i; return }
    }
    root.showHint(root.planning ? "nothing from the agent yet — it is planning" : "nothing from the agent to settle")
  }

  function tickFocused() {
    var row = root.taskRows[root.taskFocus]
    if (row && (row.kind === "proposal" || row.kind === "question" || row.kind === "told")) {
      if (row.item.kind !== "file") root.rememberSettled(row.item, row.kind === "told" ? "let stand" : row.kind === "question" ? "answered" : "accepted")
      root.acceptPlanned(row)
      return
    }
    if (row && row.kind === "task") root.tickTask(row.task)
    if (row && row.kind === "deadline") {
      var d = row.deadline
      // Space again while its tick is still being drawn: not done after
      // all (2026-11-27: the second press ticked it a second time, from
      // the list as it was before the first).
      if (root.tickPending[d.id]) { root.cancelPendingTick(d.id); root.dropUndo(function (u) { return u.deadline === d.id }); return }
      if (d.status === "open") {
        // The store written once the tick has been seen: its change would
        // rebuild the list mid-tick. Kept for Ctrl+Z at once, so a Ctrl+Z
        // meanwhile takes back this tick, not the one before it.
        root.markTicked(root.rowKey(row))
        root.justClosed = root.rowKey(row)
        var p = Object.assign({}, root.tickPending)
        p[d.id] = true
        root.tickPending = p
        root.rememberUndo({ deadline: d.id, say: "ticking “" + d.title + "”" })
        root.afterTick = root.afterTick.concat([function () {
          if (!root.tickPending[d.id]) return
          root.cancelPendingTick(d.id, true)
          root.tickDeadline(d, true)
        }])
        tickSettle.restart()
      } else {
        root.tickDeadline(d)
      }
    }
  }
  property var tickPending: ({})   // a deadline's id -> true while its tick is drawn and the store not yet written
  // A tick not yet written, let go (`kept`: written now, so the row stays done).
  function cancelPendingTick(id, kept) {
    var p = Object.assign({}, root.tickPending)
    delete p[id]
    root.tickPending = p
    if (kept) return
    var d = Object.assign({}, root.doneNow)
    delete d["d" + id]
    root.doneNow = d
    if (root.justTicked === "d" + id) root.justTicked = ""
  }
  // The newest change kept for Ctrl+Z that `match`es, taken out.
  function dropUndo(match) {
    for (var i = root.tickHistory.length - 1; i >= 0; i--) {
      if (!match(root.tickHistory[i])) continue
      root.tickHistory = root.tickHistory.slice(0, i).concat(root.tickHistory.slice(i + 1))
      return
    }
  }

  // Done, or open again: from the dashboard and the sidebar's list alike,
  // the line that stands for it ticked to match (`kept`: Ctrl+Z has it
  // already).
  function tickDeadline(d, kept) {
    if (d.status === "open") {
      dl.markDone(d.id)
      if (!kept) root.rememberUndo({ deadline: d.id, say: "ticking “" + d.title + "”" })
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
    if (r) root.writeLine(r, Bound.ticked(r.raw, done, Qt.formatDate(new Date(), "yyyy-MM-dd")))
  }

  // A deadline no line stands for gets one in today's note, where a step's
  // would go (Bound.placeAt).
  property var pendingWrite: null
  function writeIntoToday(d) {
    root.pendingWrite = d
    root.toNote()
    if (svc.isToday && svc.ready) root.doPendingWrite()
    else root.openNote(svc.todayStamp())
  }

  function doPendingWrite() {
    var d = root.pendingWrite
    if (!d || !svc.isToday || !svc.ready) return
    root.pendingWrite = null
    // Never written until now: the agent's, which the check is told (it
    // writes that down only if it ran while the deadline waited).
    root.wroteIn = root.wroteIn.concat([String(d.id)])
    // Where a step's line goes, not at the end: the end of a note is inside
    // its last section, which then claims the line (2026-11-03).
    root.placeLine(Bound.lineFor(d), d.project)
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
  // The note under a PDF is still the one loaded: openNote puts it back in
  // the middle (2026-11-28, the sidebar pass: the cursor moved in the
  // hidden note and the PDF kept the keys).
  function goToTask(t) {
    root.pendingTask = { text: t.text, line: t.line }
    var here = t.date === svc.noteDate && svc.ready
    root.openNote(t.date)
    root.toNote()
    if (here) root.landOnTask()
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
    if (root.tickHistory.length === 0) { root.showHint("nothing to take back here"); return }
    var t = root.tickHistory[root.tickHistory.length - 1]
    root.tickHistory = root.tickHistory.slice(0, -1)
    var said = "took back " + (t.say || "the last tick")
    if (t.settled) {
      root.showHint(t.say + " stays: it cannot be taken back here · " + root.keyName("dashUndo") + " again for what came before")
      return
    }
    root.showHint(said)
    if (t.deadline) {
      if (root.tickPending[t.deadline]) { root.cancelPendingTick(t.deadline); return }
      dl.reopen(t.deadline); root.tickBoundLine(t.deadline, false); return
    }
    if (t.drop) { root.editTask(t.drop, "undrop", ""); return }
    if (t.uncancel) { dl.reopen(t.uncancel); return }
    if (t.unfile) { root.unfile(t.unfile); return }
    if (t.box) { root.touchBox(t.box, t.how); return }
    if (t.field) { root.editTask(t.task, t.field, t.arg); return }
    if (t.retitle) { dl.set(t.retitle, ["--title", t.arg]); return }
    if (t.regrade) { dl.grade(t.regrade, t.arg); return }
    root.editTask(t.tick || t, "undone", "")
  }
  // A document filed — from its row, or asked for in a chat — moved back
  // where it came from by the runner; it is not proposed again.
  property var unfiled: ({})
  function unfile(id) {
    if (root.unfiled[id]) return
    var u = Object.assign({}, root.unfiled)
    u[id] = true
    root.unfiled = u
    root.proposalQueue = root.proposalQueue.concat([[svc.runner, "proposal", "undo", "--id", String(id)]])
    root.nextProposal()
    root.used("proposal", "unfile")
    root.showHint("put back where it was")
    Qt.callLater(root.refreshProjects)
  }

  // Tick in the original note, through the one edit path, with the day it
  // was done (`✅`, as Obsidian Tasks writes it; the note draws it quietly),
  // which is how a box done today stays in the dashboard until tomorrow.
  // Ticked again: open again, the day taken off.
  function tickTask(t) {
    var key = root.rowKey({ kind: "task", task: t })
    // Dropped: Space brings it back, open, rather than ticking what was
    // decided against.
    if (t.cancelled) { root.editTask(t, "undrop", ""); root.showHint("back: open again"); return }
    // Done, or ticked a moment ago and the list not read again yet (Space
    // twice, quickly: the second is "not done").
    if (t.done || root.doneNow[key]) {
      if (root.doneNow[key]) {
        var d = Object.assign({}, root.doneNow)
        delete d[key]
        root.doneNow = d
        if (root.justTicked === key) root.justTicked = ""
        root.dropUndo(function (u) { return u.tick && root.rowKey({ kind: "task", task: u.tick }) === key })
      }
      root.editTask(t, "undone", "")
      return
    }
    root.markTicked(key)
    root.justClosed = key
    root.rememberUndo({ tick: t, say: "ticking “" + Say.taskTitle(t) + "”" })
    root.editTask(t, "done", "")
    root.used("tick")
  }

  // ------------------------------------------------------------ deadlines

  property var bound: ({})          // id -> { line, checked }: bound lines as last seen
  property bool quiet: false        // the page is writing (binding, catching up): not the student
  property var declined: ({})       // raw lines whose date stays words (Backspace, Ctrl+D, Ctrl+Z)
  property var autoBound: null      // { id, raw, made }: the line the page just bound as it was left
  property var unmade: []           // deadlines the page made for a line and took back (Ctrl+Z, the line gone)
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

  // `keep`: only what differs is written, so a cursor in the line's words
  // stays where it is (the line is being written on).
  function putLine(r, raw, keep) {
    root.quiet = true
    if (keep) editor.replaceLine(r, raw)
    else editor.replace(r.start, r.start + r.raw.length, raw)
    root.quiet = false
    root.bound = Bound.anchors(editor.text)
    root.tickedCount = Queue.countTicked(editor.text)
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
    root.writeLine(r, r.raw.substring(0, r.prefixLen) + head.replace(/\s+$/, "") + (r.marks || "") + Bound.tail(ms, id))
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
    var d = root.twinOf(head, project, phrase, ms)
    if (!d) return false
    root.writeBinding(raw, head, ms, d.id, auto, false)
    return true
  }

  // That deadline, given the line's date (and its #tag if it has none); null
  // when there is none.
  function twinOf(head, project, phrase, ms) {
    var d = Bound.twin(dl.items, head, ms)
    if (!d) return null
    var args = dl.words(phrase)
    if (project !== "" && d.project === "") args = ["--project", project].concat(args)
    dl.set(d.id, args)
    return d
  }

  // Tab on a date lit up as it is typed (2026-10-27, the student's): it
  // becomes the deadline there and then, and the cursor stays in the words
  // to go on writing, as in Todoist. Enter is still a new line, and binds
  // as the line is left. The store answers a moment later with the
  // deadline's number, and the typing does not wait for it: the line takes
  // its date at once, as a plain `📅 date` tail — out of the words, so
  // typing in them leaves it alone and Enter steps over it — and the
  // number is added at its end when it comes. Like every binding, an undo
  // step of its own: Ctrl+Z gives the words back and the deadline goes.
  property var binding: []          // [{ stem, raw, written, ms, line }]: lines Tab bound, their number on its way

  function acceptCue() {
    var i = root.lineIndexAt(editor.cursorPosition)
    var it = editor.rowItem(i)
    var r = editor.rows[i]
    if (!it || !it.pending || !r || editor.spanning || !svc.ready || root.quiet || !root.dayNote || r.priv) return false
    var c = Bound.cue(r.body)
    var w = c ? Dates.read(c.phrase) : null
    if (!w) return false
    var words = c.head.replace(/\s+$/, "")
    // A space after the words, for the next ones; the tail keeps its own.
    // The marks the line had (a priority, the day to work on it) stay in
    // front of the date, as the Tasks order has them.
    var written = r.raw.substring(0, r.prefixLen) + words + " " + (r.marks || "") + Bound.tail(w.ms, 0)
    var rec = { stem: svc.noteDate, raw: r.raw, written: written, ms: w.ms, line: i }
    editor.typedRaw = ""
    root.writeLine(r, written)
    editor.setCursor(r.start + r.prefixLen + words.length + 1, true)
    root.used("cue", "tab")
    var d = root.twinOf(c.head, c.project, w.iso, w.ms)
    if (d) { root.numberLine(rec, d.id, false); return true }
    root.setBinding(root.binding.concat([rec]))
    dl.add(c.title, c.project, w.iso, function (id) { root.numberLine(rec, id, true) })
    return true
  }

  function setBinding(list) {
    root.binding = list
    var at = {}
    for (var i = 0; i < list.length; i++) at[Math.floor(list[i].ms / 60000)] = true
    editor.bindingAt = at
  }

  // The store's number reaches the line Tab bound: ` ^dN` at its end,
  // after the cursor, so whatever is being typed in the words goes on.
  // Nobody asked for it as a step: every undo state that holds the line as
  // Tab wrote it gets the number too. The line gone meanwhile (deleted,
  // Ctrl+Z, another note opened): the deadline made for it goes too.
  function numberLine(rec, id, made) {
    root.setBinding(root.binding.filter(function (x) { return x !== rec }))
    if (id <= 0) return
    var i = svc.noteDate === rec.stem ? Bound.tabBound(editor.rows, rec) : -1
    var r = editor.rows[i]
    if (!r) {
      if (made) root.unmake(id)
      root.decline(rec.raw)
      return
    }
    editor.rebase(rec.written, rec.written.replace(/\s+$/, "") + " ^d" + id)
    // Left already (Enter came first): tidied as leftLine tidies a bound
    // line. (The new tag sets off the check, which carries the words.)
    var next = Bound.numbered(r, id, root.lineIndexAt(editor.cursorPosition) !== i)
    editor.rebase(r.raw, next)
    root.putLine(r, next, true)
    root.autoBound = { id: id, raw: rec.raw, made: made }
    dl.set(id, ["--link", Bound.link(rec.stem, id)])
    root.used("bound")
  }

  // A deadline the page made for a line, taken back: removed from the
  // store, and remembered, because a check already running can bring it
  // back. It reads the open note from disk, where the line may still carry
  // the tag until the undo's save lands, and the store after the removal:
  // a tag with no deadline behind it is one made on another machine, and
  // the check adopts it; the next check finds its line gone and cancels it
  // (2026-11-25, the live page test on GitHub's Windows machine: "Ctrl+Z:
  // the words are back and the deadline it made is gone", the deadline
  // left cancelled). The page knows better: what it took back it removes
  // again (checkDone).
  function unmake(id) {
    if (root.unmade.indexOf(id) < 0) root.unmade = root.unmade.concat([id]).slice(-20)
    dl.remove(id)
  }

  // What changed among bound lines with the last edit. A line gone, back,
  // ticked or cancelled is the check's to carry to the store (one rule:
  // a deadline is cancelled exactly while no note holds its tag, and the
  // person is told, never asked — docs/tasks.md). The one exception is the
  // page's own binding taken back with Ctrl+Z: the words are back, the
  // deadline it made for them goes, and the line stays words.
  function boundEdited(was, now) {
    var e = Bound.edits(was, now)
    var changed = e.changed
    for (var i = 0; i < e.gone.length; i++) {
      var ab = root.autoBound
      // (The text, not editor.rows: they catch up after this signal.)
      if (ab && ab.id === e.gone[i] && editor.text.split("\n").indexOf(ab.raw) >= 0) {
        root.autoBound = null
        if (ab.made) root.unmake(ab.id)
        else dl.set(ab.id, ["--link", ""])
        root.decline(ab.raw)
        root.used("bound", "undone")
        continue
      }
      changed = true
    }
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
    // A box in a private block never becomes a deadline: the deadline list is
    // what the agent reads (2026-10-27, the student's call).
    if (!r || r.kind !== "task" || !svc.ready || root.quiet || !root.dayNote || r.priv) return
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
      var at = d ? new Date(d.due * 1000) : null
      var timed = at && !(at.getHours() === 23 && at.getMinutes() === 59)
      root.openWhen(r.raw, r.deadline, at ? Qt.formatDateTime(at, timed ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd") : "")
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

  // A day to work on a box (⏳), asked under its line (2026-11-27): a click
  // on the day drawn at its end, as the dashboard's `t` asks "do on?".
  // Empty takes the day off. Never the words: only the ⏳ field changes.
  function openDoOn(r) {
    root.whenFor = { raw: r.raw, id: 0, doOn: true }
    whenField.text = r.doDay
    whenField.forceActiveFocus()
    whenField.selectAll()
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

  // ------------------------------------------------------ making a project

  // A new project (2026-10-22, agent/projects.py), made by the runner and
  // only ever by the person: from the note, a `#tag` or `@name` nothing
  // goes by yet — its name asked under the line, then the tag written where
  // it was typed (Shift+Enter on `@` at a line's start writes its heading);
  // from the sidebar, a field for the name and, when not the name's words,
  // its #tag.
  property var newProject: null       // the note's "name?": { start, end, tag, heading }
  property bool addingProject: false  // the sidebar's field is open

  function askProjectName(a) {
    root.newProject = a
    nameField.text = ""
    nameField.forceActiveFocus()
  }

  function closeProjectName() {
    root.newProject = null
    editor.focusNote()
  }

  function submitProjectName() {
    var a = root.newProject
    if (!a) return
    var name = nameField.text.replace(/\s+/g, " ").trim() || a.tag
    root.newProject = null
    var text = a.heading ? "# " + name + " #" + a.tag : "#" + a.tag + " "
    editor.snapshot(true)
    editor.replace(a.start, a.end, text)
    editor.setCursor(a.start + text.length, true)
    root.makeProject(name, a.tag)
    root.used("project", "note")
  }

  function openSidebarProject(name) {
    root.addingProject = true
    Qt.callLater(function () {
      if (name) sidebar.projectFieldRef.text = name
      sidebar.projectFieldRef.forceActiveFocus()
    })
  }

  function closeSidebarProject() {
    root.addingProject = false
    if (root.sidebarOpen) sidebar.sidebarKeysRef.forceActiveFocus()
  }

  function submitSidebarProject(text) {
    var f = Tags.fromField(text, root.projects)
    if (f.tag === "") { root.showHint("a name, and its #tag when not the name's words"); return }
    if (f.taken) { root.showHint("#" + f.tag + " is a project already"); return }
    if (newProjectProc.running) { root.showHint("still making the last one"); return }
    root.makeProject(f.name, f.tag)
    // Its words, given back if it cannot be made; the keys go to it once it is.
    newProjectProc.typed = text
    newProjectProc.fromSidebar = true
    root.used("project", "sidebar")
    root.closeSidebarProject()
  }

  function makeProject(name, tag) {
    if (newProjectProc.running) { root.showHint("still making the last one"); return }
    newProjectProc.typed = ""
    newProjectProc.fromSidebar = false
    newProjectProc.made = tag
    newProjectProc.command = [svc.runner, "project", "--tag", tag, "--name", name]
    newProjectProc.running = true
  }

  function submitWhen() {
    var a = root.whenFor
    var text = whenField.text.trim()
    if (!a) { root.closeWhen(); return }
    if (a.doOn) {
      var on = root.rowByRaw(a.raw)
      if (!on) { root.closeWhen(); return }
      var read = text === "" ? null : Dates.read(text, new Date())
      if (text !== "" && !read) { root.showHint("that date did not read: " + text); return }
      root.closeWhen()
      root.writeLine(on, Task.setField(on.raw, "⏳", read ? read.iso.split(" ")[0] : ""))
      root.used("when", read ? "note" : "removed")
      Qt.callLater(root.refreshTasks)
      return
    }
    if (a.id > 0) {
      var r = root.rowByDeadline(a.id)
      if (!r) { root.closeWhen(); return }
      if (text === "") {
        root.closeWhen()
        // Unbound by hand: the date goes, and the deadline is asked about
        // like a deleted line's.
        editor.snapshot(true)
        editor.replace(r.bodyEnd + (r.marks || "").length, r.start + r.raw.length, "")
        return
      }
      var w = Dates.read(text, new Date())
      if (!w) { root.showHint("that date did not read: " + text); return }
      root.closeWhen()
      dl.set(a.id, dl.words(w.iso))
      var now = root.rowByDeadline(a.id)
      if (now) root.writeLine(now, now.raw.slice(0, now.raw.length - (now.dateTail || "").length) + Bound.tail(w.ms, a.id))
      return
    }
    if (text === "") { root.closeWhen(); return }
    var row = root.rowByRaw(a.raw)
    if (!row) { root.closeWhen(); return }
    var title = Bound.titleOf(row.body)
    if (title === "") { root.closeWhen(); root.showHint("write what it is first, then " + root.keyName("deadline")); return }
    var w2 = Dates.read(text, new Date())
    if (!w2) { root.showHint("that date did not read: " + text); return }
    root.closeWhen()
    var head = row.body
    var project = Bound.projectOf(row.body)
    if (root.bindTwin(a.raw, head, project, w2.iso, w2.ms)) return
    var stem = svc.noteDate
    dl.add(title, project, w2.iso, function (id) {
      if (id > 0 && svc.noteDate === stem) root.writeBinding(a.raw, head, w2.ms, id)
    })
  }

  // Opening a note: its bound lines catch up with the store — ticked or
  // unticked as the deadline is done or open, the date as the store has
  // it, and a line whose deadline is gone keeps its date but not its
  // anchor. Not while a check is still to come, even one only scheduled:
  // the store it answers to is behind the note, and catching the note up
  // with it would undo the edit that scheduled the check — Ctrl+Z on a
  // dropped deadline, pressed before the store's reload arrived, was put
  // back to cancelled (2026-10-28).
  function reconcile() {
    if (!root.reconcilePending || !dl.loaded || !svc.ready || root.checking || root.checkWanted || checkTimer.running) return
    root.reconcilePending = false
    var a = root.dayNote ? Bound.anchors(editor.text) : ({})
    for (var id in a) {
      var r = editor.rows[a[id].line]
      if (!r || r.deadline !== parseInt(id, 10)) continue
      root.catchUp(r, Bound.caughtUp(r, dl.byId[id]))
    }
    root.bound = Bound.anchors(editor.text)
    root.landOnGoto()
    root.landOnTask()
    root.landOnSection()
    root.landOnFocus()
    root.landOnLine()
    root.landOnLink()
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
  property var wroteIn: []           // deadlines written in from "not in a note yet", for the next check
  property var checkTold: []         // …those the running check was told
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
    root.authorMap = Authorship.restore(root.dayNote ? root.authorsStore[svc.noteDate] || [] : [], root.authorLines)
  }

  // An edit in the page: who made each line, carried.
  function carryAuthors(text) {
    var lines = String(text).split("\n")
    root.authorMap = Authorship.carry(root.authorLines, lines, root.authorMap)
    root.authorLines = lines
    root.keepAuthors()
  }

  // A sent block's conversation, on its lines (Threads.js): restored with
  // the note, carried through every edit, pinned when a reply arrives, and
  // kept by the lines' words in threads.json beside authors.json.
  property var threadsStore: ({})
  property var threadMap: ({})
  property var threadLines: []
  function restoreThreads(text) {
    root.threadLines = String(text).split("\n")
    root.threadMap = Threads.restore(root.dayNote ? root.threadsStore[svc.noteDate] || [] : [], root.threadLines)
    Qt.callLater(root.pinThreads)
  }
  function carryThreads(text) {
    var lines = String(text).split("\n")
    root.threadMap = Threads.carry(root.threadLines, lines, root.threadMap)
    root.threadLines = lines
    root.keepThreads()
  }
  function pinThreads() {
    if (!svc.ready || !root.dayNote) return
    var blocks = Blocks.split(editor.text)
    var m = {}
    for (var k in root.threadMap) m[k] = root.threadMap[k]
    var changed = false
    for (var i = 0; i < blocks.length; i++) {
      var b = blocks[i]
      var h = Queue.answered(agent.record(b.hash)) ? b.hash : (root.recordKeys[Blocks.fnv1a(Task.identity(b.text))] || "")
      if (h !== "" && Threads.pin(m, b, h)) changed = true
    }
    if (!changed) return
    root.threadMap = m
    root.keepThreads()
  }
  function keepThreads() {
    var stem = svc.noteDate
    if (!stem) return
    var recs = Threads.serialize(root.threadMap, root.threadLines)
    var was = root.threadsStore[stem] || []
    if (JSON.stringify(recs) === JSON.stringify(was)) return
    var st = {}
    for (var k in root.threadsStore) st[k] = root.threadsStore[k]
    if (recs.length > 0) st[stem] = recs
    else delete st[stem]
    root.threadsStore = st
    threadsSave.restart()
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
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") return "agent"
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
  property var dueDates: ({})       // id -> { firstDue, moves, later }: deadlines whose date has moved
  readonly property string checkPath: (svc.config && svc.config.check) || (Quickshell.env("HOME") + "/.local/bin/longhand-check")

  function scheduleCheck() { checkTimer.restart() }

  function startCheck() {
    checkTimer.stop()
    if (!root.dayNote) return
    root.checkWanted = true
    root.flush()
    root.runCheck()
  }

  function runCheck() {
    // Not while the page's own writes to the store are on their way: the
    // check read the store before a deadline the page was removing (Ctrl+Z
    // right after a binding) was gone, found its line gone, and cancelled
    // it after the removal, bringing it back as cancelled (2026-11-25, on
    // GitHub's Windows machine). It runs when they have landed (dl idle).
    if (!root.checkWanted || root.checking || !svc.ready || svc.saving || svc.pending || !root.dayNote || dl.busy) return
    root.checkWanted = false
    root.checking = true
    checkGuard.restart()
    root.checkTold = root.wroteIn
    checkProc.command = [root.checkPath, "--json", "--open", svc.noteDate].concat(
      [].concat.apply([], root.wroteIn.map(function (id) { return ["--waiting", id] })))
    checkProc.running = true
  }

  function checkDone(text) {
    if (!root.checking) return
    root.checking = false
    checkGuard.stop()
    var out = null
    try { out = JSON.parse(text) } catch (e) { out = null }
    if (out) {
      var told = root.checkTold
      root.wroteIn = root.wroteIn.filter(function (id) { return told.indexOf(id) < 0 })
      root.origins = out.origins || ({})
      root.dueDates = out.dates || ({})
      root.sayChecked(out)
      // A deadline the page took back, adopted again from a tag still on
      // disk (unmake): removed again, before any other check can start —
      // unless the note in the page holds its tag again, which is then
      // the person's to keep.
      var adopted = out.adopted || []
      for (var a = 0; a < adopted.length; a++) {
        var aid = adopted[a].id
        if (root.unmade.indexOf(aid) >= 0 && root.bound[String(aid)] === undefined) dl.remove(aid)
      }
    }
    // The store as the check left it, then the open note in line with it
    // (reconcile runs when the store's items arrive).
    root.reconcilePending = true
    dl.reload()
    // The check may have ticked lines in other notes (the bar popup, pomo).
    root.refreshDated()
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
    root.toggleDay("")
  }

  // The date, at the left, is the door to the left sidebar (2026-10-21):
  // a click lands on the side where the thing appears.
  function dateClicked() {
    root.used("date")
    // The date clicked asks for the calendar, not the row the keys were on.
    root.sideLast = null
    root.toggleSidebar()
  }

  function toggleSidebar() {
    var was = root.here
    if (!root.sidebarOpen && was !== "left") root.noteFrom("left")
    if (!root.sidebarOpen) root.ensureRoomFor("left")
    root.sidebarOpen = !root.sidebarOpen
    if (root.sidebarOpen) root.used("calendar")
    if (root.sidebarOpen) root.focusSidebar()
    else root.giveBack("left", was, "left")
  }

  // To a deadline's line: its note opened if need be, the cursor at the end
  // of its words. A deadline no line stands for says so.
  function goToDeadline(d) {
    root.used("goto-deadline")
    var l = d ? Bound.parseLink(d.link) : null
    // No line to go to: the keys stay where they are, on its row.
    if (!l) { root.showHint("“" + (d ? d.title : "") + "” is not written in a note yet"); return }
    root.pendingGoto = l.id
    var here = l.stem === svc.noteDate && svc.ready
    root.openNote(l.stem)
    if (here) root.landOnGoto()
    root.showNote()
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
    root.readToday.at = -1
    root.restoreSide()
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

  // Asked while a read is under way: once more when it ends, so a project
  // just made is never missed, and two reads never cut each other short.
  property bool projectsAgain: false
  function refreshProjects() {
    if (projectsProc.running) { root.projectsAgain = true; return }
    projectsProc.command = [svc.runner, "projects"]
    projectsProc.running = true
  }

  // "now · until 12:15 · Gold", "today 13:15 · Gold", "Wed 10:45 ·
  // Bronze", "19 Oct · Design Lab".
  // Reading svc.today ties every label to the day: when it turns, they are
  // said again (and the runner is asked again, onTodayChanged below).
  function sessionLabel(n) {
    svc.today
    return Say.saySession(n, new Date())
  }

  // A new section (once "start the class"; renamed 2026-10-28, Longhand
  // being not only for students): its heading on a new line at the end of
  // today's note, the cursor on the empty line under it. The words are the
  // project's name.
  property var pendingClass: null
  function startClass(p) {
    root.used("class", p.tag)
    root.reached(p.tag)
    root.pendingClass = p
    root.projFocus = -1
    var here = svc.isToday && svc.ready
    root.openNote(svc.todayStamp())
    if (here) root.writeClass()
    root.showNote()
  }

  function writeClass() {
    var p = root.pendingClass
    if (!p || !svc.isToday || !svc.ready) return
    root.pendingClass = null
    var t = editor.text
    var lead = t.replace(/\s+$/, "") === "" ? (t.charAt(t.length - 1) === "\n" || t === "" ? "" : "\n")
      : (/\n\n$/.test(t) ? "" : (/\n$/.test(t) ? "\n" : "\n\n"))
    editor.snapshot(true)
    editor.insert(t.length, lead + "# " + p.name + " #" + p.tag + "\n")
    editor.setCursor(editor.length, true)
  }

  // `#`: just the tag, where the cursor is.
  function insertTag(p) {
    // Into the note in the middle, never one hidden under a PDF or the
    // agent's page shown to read.
    if (!svc.ready || svc.readOnly || root.pdfShown) {
      root.showHint(root.pdfShown ? "a PDF is open: the tag goes into a note" : svc.readOnly ? "this page is the agent's, to read" : "no note open")
      return
    }
    root.used("tag", p.tag)
    root.reached(p.tag)
    root.projFocus = -1
    root.showNote()
    var pos = editor.cursorPosition
    var before = pos > 0 ? editor.text.charAt(pos - 1) : "\n"
    editor.snapshot(true)
    editor.insert(pos, (/\s/.test(before) ? "" : " ") + "#" + p.tag + " ")
  }

  // Today's note, from wherever the keys are: the dashboard and the margin
  // close, the calendar's cursor comes home too.
  function goToday() {
    root.used("today")
    root.calFocus = new Date()
    root.openNote(svc.todayStamp())
    root.toNote()
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
    root.toNote()
  }

  function openCalendarDay(d) {
    root.calFocus = d
    root.openNote(Days.stemFor(d, svc.dailyFormat(), root.dayIndex))
    root.showNote()
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
    if (stamp !== "" && (stamp !== svc.noteDate || root.pdfRel !== "")) { root.remember(); root.middleMoves() }
    if (stamp !== "") { pdfPane.keep(); root.pdfRel = "" }
    if (stamp === "" || stamp === svc.noteDate) return
    if (root.searchOpen) root.closeSearch("back")
    root.leftLine(root.lastLine)
    root.flush()
    var p = svc.configured ? Days.parse(stamp, svc.dailyFormat()) : null
    var today = new Date()
    today.setHours(0, 0, 0, 0)
    root.used("day", p ? Math.round((today - p.date) / 86400000) : "")
    root.marginOpen = false
    root.closeTalk(false)
    root.dashOpen = false
    root.marginFocus = -1
    if (svc.saving) { root.pendingStamp = stamp; root.pendingFile = null; return }
    svc.openDate(stamp)
  }

  // Put a file of the notes in the sheet (the Files space, docs/files.md):
  // yours to edit as a past day is, the agent's only to read. Whatever is
  // typed is written first, as for a day; the agent's pane, open, follows
  // it (middleMoves).
  function openFile(rel, readOnly) {
    if (/\.pdf$/i.test(rel)) { root.openPdf(rel); return }
    if (rel !== "" && (rel !== svc.filePath || root.pdfRel !== "")) { root.remember(); root.middleMoves() }
    pdfPane.keep()
    root.pdfRel = ""
    if (rel === "" || (rel === svc.filePath && svc.ready)) { root.showNote(); return }
    if (root.searchOpen) root.closeSearch("back")
    root.leftLine(root.lastLine)
    root.flush()
    root.used("file", readOnly ? "agent" : "mine")
    root.marginOpen = false
    root.closeTalk(false)
    root.dashOpen = false
    root.marginFocus = -1
    if (svc.saving) { root.pendingFile = { rel: rel, readOnly: !!readOnly }; root.pendingStamp = ""; root.showNote(); return }
    svc.openFile(rel, readOnly)
    root.showNote()
  }

  // ------------------------------------------------------------ search

  // Words selected in one line are what is looked for (2026-11-27), as the
  // PDF's find already did.
  function openSearch() {
    if (!root.searchOpen) {
      root.searchFrom = editor.cursorPosition
      root.used("find")
      var sel = editor.selectedSpan()
      var words = sel ? editor.text.slice(sel.a, sel.b) : ""
      if (words.trim() !== "" && words.indexOf("\n") < 0) { root.searchFrom = sel.a; searchField.text = words }
    }
    root.searchOpen = true
    searchField.forceActiveFocus()
    searchField.selectAll()
    root.runSearch()
  }

  property int matchesFolded: 0     // matches in lines folded away (Focus.js), not stepped to

  // Every case-insensitive occurrence in the words as drawn: emphasis
  // markers and a link's hidden address are not in them, so "read chapter"
  // finds `read **chapter 3**` (editor.drawnWords). The current match starts
  // as the first one at or after where the search began. With one project's
  // lines shown, those folded away are counted, not stepped to: a match
  // there was scrolled to as a fold's seam, with nothing to see (2026-11-27).
  function runSearch() {
    var q = searchField.text.toLowerCase()
    var out = []
    var folded = 0
    if (q !== "") {
      var rows = editor.rows
      for (var i = 0; i < rows.length; i++) {
        var r = rows[i]
        if (r.blank) continue
        var d = editor.drawnWords(i)
        var body = (d ? d.text : r.body).toLowerCase()
        var base = r.start + r.prefixLen
        for (var at = body.indexOf(q); at >= 0; at = body.indexOf(q, at + q.length)) {
          if (!editor.isShown(i)) { folded++; continue }
          out.push(d ? { start: base + d.at[at], end: base + d.at[at + q.length - 1] + 1 }
                     : { start: base + at, end: base + at + q.length })
        }
      }
    }
    var idx = -1
    for (var k = 0; k < out.length; k++) if (out[k].start >= root.searchFrom) { idx = k; break }
    if (idx < 0 && out.length > 0) idx = 0
    root.matches = out
    root.matchesFolded = folded
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
    root.matchesFolded = 0
    root.matchIndex = -1
    if (how === "select" && m) editor.select(m.start, m.end)
    else if (how === "stay" && m) editor.setCursor(m.start, true)
    else editor.setCursor(root.searchFrom, true)
  }

  function sendChat() {
    var raw = String(margin.chatFieldRef.text || "")
    if (root.answering && raw.trim() !== "") {
      root.showHint("the agent is still answering · " + root.keyName("marginBack") + " stops it")
      return
    }
    var msg = root.composed("margin", raw)
    if (msg === "" || root.currentHash === "") return
    // Not sent, and not cleared: a private note's chat would wait forever.
    if (!root.agentOn) { root.showHint("private: the agent sees nothing of this note"); return }
    var savedReplies = root.marginReplies.slice()
    var savedRefs = root.marginRefs.slice()
    var mentions = margin.chatFieldRef.liveMentions.slice()
    var rec = root.currentRecord
    margin.chatFieldRef.text = ""
    root.clearReplies("margin")
    root.pendingChat = { hash: root.currentRec, mark: root.currentHash, text: msg, raw: raw, replies: savedReplies, savedRefs: savedRefs,
                         mentions: mentions, subject: root.marginSubject, base: rec && rec.chat ? rec.chat.length : 0,
                         refs: savedRefs.map(function (r) { return { date: r.date || "", hash: r.hash || "", file: r.file || "", kind: r.kind, head: r.head } }) }
    root.requestChat(root.currentRec, msg, root.currentHash, root.takeMarginRefs())
  }
  // The chips a task's or a block's message carries besides its own
  // thing, as the runner reads them; the box lets go of them.
  function takeMarginRefs() {
    var refs = root.marginRefs.map(function (r) {
      return r.file ? { file: r.file } : r.hash ? { date: r.date, hash: r.hash } : { date: r.date, line: r.line }
    })
    if (refs.length > 0) root.used("chip", "sent-margin-" + refs.length)
    root.marginRefs = []
    return refs
  }
  // In a task's or a block's box: the `@` list's keys, then Backspace in
  // the empty box letting go of the last chip it added. True when taken.
  function marginMentionKey(event) {
    var m = root.dayMention
    if (m && m.margin && m.items.length > 0) {
      if (Sc.hit(event, "mentionUp")) { root.dayMentionFocus = Math.max(0, root.dayMentionFocus - 1); return true }
      if (Sc.hit(event, "mentionDown")) { root.dayMentionFocus = Math.min(m.items.length - 1, root.dayMentionFocus + 1); return true }
      if (Sc.hit(event, "mentionPick") || Sc.hit(event, "mentionClass")) { root.pickDayMention(root.dayMentionFocus); return true }
      if (Sc.hit(event, "mentionClose")) { root.dayMention = null; return true }
    }
    if (root.mentionNothing(event)) return true
    if (event.key === Qt.Key_Backspace && margin.chatFieldRef.text === "" && root.marginRefs.length > 0) {
      root.marginRefs = root.marginRefs.slice(0, -1)
      root.used("chip", "removed")
      return true
    }
    return false
  }

  // The runner has written the turn the page was holding: let go of it, so
  // the message is never drawn twice.
  function settleChat() {
    var p = root.pendingChat
    if (!p) return
    var rec = agent.record(p.hash)
    var turns = (rec && rec.chat) || []
    for (var i = turns.length - 1; i >= Math.min(p.base || 0, turns.length); i--)
      if (turns[i].role === "student" && turns[i].text === p.text) {
        root.pendingChat = null
        // Its answer with it: the run is only ending, and the block it was
        // asked from (the run's own hash, `mark`) is no longer away.
        var ran = root.runningHash.split(",")
        if (root.running && turns[i + 1] && (ran.indexOf(p.hash) >= 0 || ran.indexOf(p.mark || "") >= 0)) {
          root.runAnswered = true
          root.sending = root.sending.filter(function (h) { return h !== p.mark && h !== p.hash })
          root.scheduleRepaint()
        }
        root.openFromTurn(turns[i + 1])
        return
      }
  }

  // ------------------------------------------------------------ services

  Service {
    id: svc
    // Another note in the sheet: the whole of it (a project's part is
    // asked for again by openSection, once it has loaded).
    onFilePathChanged: editor.focusTag = ""
    // A new day: yesterday's sessions are behind, so the runner is asked
    // which come next (a page left open overnight, 2026-11-23).
    onTodayChanged: if (root.projectsListed.length > 0) root.refreshProjects()
    onLoaded: { root.applyText(svc.body); root.reconcilePending = true; root.startCheck(); root.reconcile(); root.openPass(); root.refreshDated() }
    // A write that never said it landed, written again (Service.unstick).
    onStall: root.showHint("a save did not land: writing it again")
    onToolWarningChanged: if (toolWarning !== "") root.showHint(toolWarning)
    onExternalChange: { root.applyText(svc.body, true); root.reconcilePending = true; root.startCheck(); root.reconcile(); root.notesChanged(); root.refreshDated() }
    onSavedNow: {
      root.notesChanged()
      root.refreshDated()
      // The list once the save it waited for has landed — and, while the
      // dashboard shows, after any save: one that lands after a read began
      // may hold a line the read did not see (a line written and the
      // dashboard opened at once, missing once in forty runs: plan.md
      // item 17).
      if (root.tasksAfterSave || root.dashOpen) { root.tasksAfterSave = false; root.refreshTasks() }
      if (root.exportAfterSave) { root.exportAfterSave = false; root.listExport() }
      root.runCheck()
      if (root.pendingStamp !== "") {
        var s = root.pendingStamp
        root.pendingStamp = ""
        svc.openDate(s)
      } else if (root.pendingFile) {
        var f = root.pendingFile
        root.pendingFile = null
        svc.openFile(f.rel, f.readOnly)
      }
      root.launchQueued()
    }
  }

  ThemeColors { id: pal }
  Paper { id: paperPart; page: root }
  ReadToday { id: readTodayPart; page: root }
  // What was read on each day, for the sidebar's READ list (ReadToday.qml):
  // false while a read is under way, so it is asked again a moment later.
  function readDaysRun() {
    if (readDaysProc.running) return false
    readDaysProc.command = [pdfPane.readPath, "days"]
    readDaysProc.running = true
    return true
  }
  Process {
    id: readDaysProc
    stdout: StdioCollector {
      id: readDaysOut
      onStreamFinished: { try { root.readToday.days = JSON.parse(readDaysOut.text).days || ({}) } catch (e) {} }
    }
  }

  Deadlines {
    id: dl
    onItemsChanged: { root.reconcile(); root.checkAccept(); if (!tickSettle.running) { root.doneNow = ({}); root.justTicked = "" } }
    onChanged: root.scheduleCheck()
    onIdle: {
      var waiting = root.afterWrites
      root.afterWrites = []
      for (var i = 0; i < waiting.length; i++) waiting[i]()
      if (root.checkWanted) root.runCheck()
    }
  }

  AgentState {
    id: agent
    config: svc.config
    date: svc.noteDate
    off: !root.dayNote
    onStateChanged: { root.scheduleRepaint(); root.checkAccept(); root.settleChat(); root.settleDay() }
  }

  Process {
    id: runner
    property string said: ""
    // `said` is not emptied here: a run that ends with another waiting
    // starts that one before what it said is read (below, a moment later),
    // and the reason it failed went with it (2026-11-20). Each way out of
    // `onExited` empties it instead.
    onRunningChanged: if (running) root.runnerPhase = ""
    stderr: SplitParser {
      onRead: function (line) {
        var ph = Queue.phase(line)
        if (ph !== "") { root.runnerPhase = ph; return }
        if (line.trim() !== "") {
          runner.said = (runner.said ? runner.said + "\n" : "") + line
          console.warn("longhand.page runner: " + line)
        }
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
      root.runAnswered = false
      root.runnerPhase = ""
      // The day's answer may have proposed: its cards are the dashboard's items.
      if (root.runningHash === "day") { Qt.callLater(root.refreshProposals); Qt.callLater(root.refreshTasks) }
      // …and so may a block's chat: a day or a drop is in the one list.
      else if (runner.command[1] === "chat") Qt.callLater(root.refreshProposals)
      if (root.runningHash.indexOf("note:") === 0) noteTalkFile.reload()
      var ran = root.runningHash
      root.runningHash = ""
      // Stopped on purpose: not a fault, and said already.
      if (root.runnerStopAsked) { root.runnerStopAsked = false; Qt.callLater(function () { runner.said = "" }) }
      else if (code !== 0) Qt.callLater(function () { root.runnerFailed(ran) })
      else Qt.callLater(function () {
        var fb = Queue.fallback(runner.said)
        runner.said = ""
        if (fb !== "") root.showHint(fb)
      })
      agent.reload()
      root.launchQueued()
      if (!root.running) root.doneSending()
    }
  }

  Process {
    id: acceptProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page accept: " + text.trim()) }
    // A deadline moved or added in the store: its line follows (the check),
    // and so does the dashboard.
    onExited: function (code, status) {
      agent.reload()
      if (code === 0) root.startCheck()
      if (root.talkThread !== "") {
        root.fetchTalk()
        root.refreshTasks()
      }
    }
  }

  Process {
    id: declineProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page decline: " + text.trim()) }
    onExited: function (code, status) {
      agent.reload()
      if (root.talkThread !== "") root.fetchTalk()
      root.nextDecline()
    }
  }

  Process {
    id: datedProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.dated = JSON.parse(text).days || ({}) } catch (e) { }
        if (root.datedAgain) { root.datedAgain = false; Qt.callLater(root.refreshDated) }
      }
    }
  }

  // The list as the runner reads it. A read that fails keeps the list it
  // had, and says why (`tasksError`), rather than showing "nothing open"
  // over boxes it could not read (2026-11-27); until the first read,
  // the dashboard says it is reading (`tasksRead`).
  property bool tasksRead: false
  property string tasksError: ""
  Process {
    id: tasksProc
    stderr: StdioCollector { id: tasksErr }
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var nx = JSON.parse(text)
          root.tasks = nx.tasks || []
          root.raised = nx.raised || []
          root.tasksError = ""
          root.tasksRead = true
        } catch (e) {
          var why = String(tasksErr.text || "").trim().split("\n").pop()
          root.tasksError = why !== "" ? why.slice(0, 160) : "its answer could not be read"
          console.warn("longhand.page next: " + root.tasksError)
        }
        root.pendingPrio = ({})
        // The list now says what was drawn ahead of it.
        root.doneNow = ({})
        root.justTicked = ""
        root.taskFocus = Math.min(root.taskFocus, Math.max(0, root.taskRows.length - 1))
        // Read after a box ticked, moved or put aside from the dashboard:
        // the project's list beside it counts them too.
        root.notesChanged()
        root.refreshDated()
        if (root.tasksAgain) { root.tasksAgain = false; Qt.callLater(root.refreshTasks) }
      }
    }
  }

  // Export as a PDF: the blocks listed, then the PDF written (openExport).
  Process {
    id: exportListProc
    property int code: 0
    stdout: StdioCollector { id: exportListOut }
    stderr: StdioCollector { id: exportListErr }
    onExited: function (code, status) {
      exportListProc.code = code
      Qt.callLater(function () { root.exportListed(exportListProc.code, exportListOut.text, exportListErr.text) })
    }
  }
  Process {
    id: exportProc
    property int code: 0
    stdout: StdioCollector { id: exportOut }
    stderr: StdioCollector { id: exportErr }
    onExited: function (code, status) {
      exportProc.code = code
      Qt.callLater(function () { root.exportWritten(exportProc.code, exportOut.text, exportErr.text) })
    }
  }

  Process {
    id: sectionsProc
    property string tag: ""
    stdout: StdioCollector {
      onStreamFinished: {
        // An answer for a project already left, or another one: not drawn.
        if (!root.projectOpen || sectionsProc.tag !== root.projectTag) return
        var prev = root.sections[root.sectionFocus]
        // A read that failed keeps the list as it was and says so; it
        // emptied it, which looked like a project with nothing in it.
        var got = null
        try { got = JSON.parse(text) } catch (e) { got = null }
        if (!Array.isArray(got)) { if (text.trim() !== "" || root.sections.length > 0) root.showHint("#" + root.projectTag + "'s sections could not be read again"); return }
        root.sections = got
        var at = Say.sameSection(got, prev)
        root.sectionFocus = at >= 0 ? at : Math.min(root.sectionFocus, Math.max(0, got.length - 1))
      }
    }
    onExited: function (code, status) { if (root.sectionsAgain) { root.sectionsAgain = false; Qt.callLater(root.refreshSections) } }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page sections: " + text.trim()) }
  }

  Process {
    id: dismissProc
    property var queue: []
    onExited: function (code, status) { root.refreshTasks(); agent.reload(); Qt.callLater(root.nextInTurn, dismissProc) }
  }

  // A box kept or put aside: the clock is written, then the list read again.
  Process {
    id: boxProc
    property var queue: []
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page box: " + text.trim()) }
    onExited: function (code, status) { root.refreshTasks(); Qt.callLater(root.nextInTurn, boxProc) }
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
      var missed = []
      for (var k = 0; k < mine.length; k++) {
        var tk = mine[k].task
        if (mine[k].how === "insert") {
          // A new box of the agent's (a deadline found in the writing).
          var ins = root.insertAt(lines, mine[k].arg.tag)
          lines.splice(ins, 0, mine[k].arg.line)
          changed = true
          continue
        }
        var tagged = tk.anchor > 0 ? Bound.anchors(lines.join("\n"))[tk.anchor] : null
        var at = tk.anchor > 0 ? (tagged ? tagged.line : -1) : Task.findWords(lines, tk.line, tk.text)
        // Its line is gone or its words changed since the list was read: said,
        // never done to another line (until 2026-11-27 it was dropped
        // silently, after the tick had been seen and heard).
        if (at < 0) { missed.push(tk); continue }
        if (mine[k].how === "remove") { lines.splice(at, 1); changed = true; continue }
        var next = root.applyEdit(lines[at], mine[k].how, mine[k].arg)
        if (next !== lines[at]) { lines[at] = next; changed = true }
      }
      if (changed) setText(lines.join("\n"))
      if (missed.length > 0) root.showHint("“" + Say.taskTitle(missed[0]) + "” is not in its note as it was — nothing changed; the list is read again")
      // (setText writes at once; waiting for a saved signal left the queue
      // stuck after the first file.)
      Qt.callLater(editFile.nextFile)
    }
    onLoadFailed: {
      var lost = editFile.queue.filter(function (q) { return q.task.file === editFile.path })
      editFile.queue = editFile.queue.filter(function (q) { return q.task.file !== editFile.path })
      if (lost.length > 0) root.showHint("could not open " + String(editFile.path).split("/").pop() + " — nothing changed in it")
      editFile.nextFile()
    }

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
    root.runInTurn(rateProc, [svc.runner, "rate", v, "--hash", root.currentRec, "--date", svc.noteDate])
    root.used("rate", v)
  }
  // The answers of a block's own chat, each rated on its own turn
  // (`rate --hash --turn`): what the margin draws are the record's own
  // turns, so a turn's place is found among them.
  function marginTurnIndex(t) {
    var rec = root.currentRecord
    return rec && rec.chat && t ? rec.chat.indexOf(t) : -1
  }
  function marginTurnRatable(t) {
    return !!t && t.role === "agent" && !t.error && !!t.text && t.who !== "planner" && !t.elsewhere && root.marginTurnIndex(t) >= 0
  }
  function marginTurnRating(t) {
    var i = root.marginTurnIndex(t)
    if (i < 0) return ""
    var now = root.ratingNow[root.currentRec + "#" + i]
    if (now !== undefined) return now === "none" ? "" : now
    return t.rating ? t.rating.value : ""
  }
  function rateMarginTurn(t, value) {
    if (!root.marginTurnRatable(t)) return
    var i = root.marginTurnIndex(t)
    var v = root.marginTurnRating(t) === value ? "none" : value
    var m = {}
    for (var k in root.ratingNow) m[k] = root.ratingNow[k]
    m[root.currentRec + "#" + i] = v
    root.ratingNow = m
    root.runInTurn(rateProc, [svc.runner, "rate", v, "--hash", root.currentRec, "--turn", String(i), "--date", svc.noteDate])
    root.used("rate", "chat-" + v)
  }
  // The last answer the margin can rate: its chat's last, else the reply.
  readonly property var marginLastAnswer: {
    var rows = root.marginStream
    for (var i = rows.length - 1; i >= 0; i--) if (rows[i].turn && root.marginTurnRatable(rows[i].turn)) return rows[i].turn
    return null
  }
  function rateMarginLast(value) {
    if (root.marginLastAnswer) root.rateMarginTurn(root.marginLastAnswer, value)
    else root.rateReply(value)
  }
  function ratingOf(hash) {
    if (root.ratingNow[hash] !== undefined) return root.ratingNow[hash] === "none" ? "" : root.ratingNow[hash]
    var rec = agent.record(hash)
    return rec && rec.rating ? rec.rating.value : ""
  }
  Process {
    id: rateProc
    property var queue: []
    onExited: function (code, status) { agent.reload(); Qt.callLater(root.nextInTurn, rateProc) }
  }

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
    folder: svc.configured ? Links.fileUrl(svc.config.vault + "/" + svc.config.daily.dir) : ""
    nameFilters: ["*.md"]
    showDirs: false
    showDotAndDotDot: false
    onStatusChanged: if (status === FolderListModel.Ready) root.collectDays()
    onCountChanged: root.collectDays()
  }

  Process { id: usageProc; onExited: root.flushUsage() }

  // The sessions move on while the sidebar stays open.
  Timer { interval: 300000; repeat: true; running: root.sidebarOpen && root.showing; onTriggered: root.refreshProjects() }

  // The runner makes the project's file; the list is read again for it.
  Process {
    id: newProjectProc
    property string made: ""
    property string typed: ""
    property bool fromSidebar: false
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") {
        root.showHint("#" + newProjectProc.made + " is a project now")
        if (newProjectProc.fromSidebar) root.projectToFocus = newProjectProc.made
        root.refreshProjects()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") {
        root.showHint(text.trim().replace(/^longhand-agent: /, ""))
        if (newProjectProc.fromSidebar && newProjectProc.typed !== "" && root.sidebarOpen) root.openSidebarProject(newProjectProc.typed)
        root.refreshProjects()
      }
    }
  }

  Process {
    id: projectsProc
    stdout: StdioCollector {
      onStreamFinished: {
        // A read cut short (asked again while running) says nothing; it
        // never empties the list under the keys.
        if (text.trim() === "") return
        try { root.projectsListed = JSON.parse(text) || [] } catch (e) { return }
        root.orderProjects()
      }
    }
    onExited: function (code, status) {
      // Asked again while it ran (an opening while the last one's fetch was
      // still going): what waits for the opening's fetch waits for that one,
      // not this (2026-11-25: the first pass and the plan went before the
      // fetch the opening asked for had begun). fetchPatience still lets
      // them go after 20 seconds.
      if (root.projectsAgain) { root.projectsAgain = false; Qt.callLater(root.refreshProjects); return }
      root.fetched()
    }
  }
  Timer { interval: 300000; running: root.usageBuf.length > 0; repeat: true; onTriggered: root.flushUsage() }

  // taught.json: which keys the page has named after a click, and how often
  // each came by key (docs/hints.md, C). The machine's state, not a choice.
  FileView {
    id: taughtFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/taught.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { var o = JSON.parse(text()); if (o && typeof o === "object") root.taught = o } catch (e) { console.warn("longhand.page taught.json: " + e) }
    }
  }

  // pane-widths.json: the agent's pane's two splits per screen width and
  // middle (the pane sized by hand, 2026-11-22). The machine's state.
  FileView {
    id: paneWidthsFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/pane-widths.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { var o = JSON.parse(text()); if (o && typeof o === "object") root.paneWidths = o } catch (e) { console.warn("longhand.page pane-widths.json: " + e) }
    }
  }

  // projects-used.json: when each project was last reached, four weeks of
  // it (Tags.byUse orders the sidebar's projects by it; plan.md item 19).
  // The machine's state, beside taught.json.
  FileView {
    id: projectUsesFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/projects-used.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { var o = JSON.parse(text()); if (o && typeof o === "object") { root.projectUses = o; root.orderProjects() } } catch (e) { console.warn("longhand.page projects-used.json: " + e) }
    }
  }

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
  Process { id: warpProc }
  // A moment for the keys to settle (a pane opening, the row it lands on)
  // before the pointer follows, so it moves once.
  Timer { id: warpTimer; interval: 40; onTriggered: root.warpNow() }

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

  FileView {
    id: noteTalkFile
    path: root.noteTalkPath
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.noteTalk = JSON.parse(text()) } catch (e) { root.noteTalk = null } ; root.settleDay() }
    onLoadFailed: root.noteTalk = null
    onFileChanged: reload()
  }
  Timer { id: sizeTimer; interval: 40; onTriggered: root.probeSizes() }
  Process {
    id: sizeProc
    property var batch: []
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text).split("\n")
        var sizes = {}
        for (var k in root.imageSizes) sizes[k] = root.imageSizes[k]
        for (var i = 0; i < sizeProc.batch.length; i++) {
          // The last "W x H" on the line: a JPEG's "density 1x1" comes first.
          var all = (lines[i] || "").match(/(\d+)\s*x\s*(\d+)/g)
          var m = all ? all[all.length - 1].match(/(\d+)\s*x\s*(\d+)/) : null
          sizes[sizeProc.batch[i]] = m && +m[1] > 0 && +m[2] > 0 ? { w: +m[1], h: +m[2] } : { none: true }
        }
        root.imageSizes = sizes
        root.imageSizesVersion++
        if (root.sizeQueue.length > 0) Qt.callLater(root.probeSizes)
      }
    }
  }
  Process {
    id: indexProc
    stdout: StdioCollector {
      onStreamFinished: {
        var cut = String(svc.config.vault).replace(/[\/\\]+$/, "").length + 1   // a trailing slash in `vault` cut a letter off every path
        var paths = String(text).split("\n").filter(function (p) { return p !== "" }).map(function (p) { return p.slice(cut) })
        root.vaultIndex = Links.index(paths)
        root.vaultIndexAt = Date.now()
        root.vaultIndexVersion++
        // A link that found nothing in the names read before: once more,
        // with the vault read again (a file added since the page opened).
        var again = root.followAgain
        root.followAgain = null
        if (again) root.followLink(again.link, again.from, true)
      }
    }
  }
  Process {
    id: horizonProc
    // Asked while it ran (2026-11-26: a setting changed during a read was
    // never read, on a slow machine): once more when it ends.
    property bool again: false
    onExited: if (horizonProc.again) { horizonProc.again = false; Qt.callLater(function () { horizonProc.running = true }) }
    stdout: StdioCollector { onStreamFinished: { try { root.horizonData = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: searchFoldersProc
    // Asked while it ran (2026-11-26: a setting changed during a read was
    // never read, on a slow machine): once more when it ends.
    property bool again: false
    onExited: if (searchFoldersProc.again) { searchFoldersProc.again = false; Qt.callLater(function () { searchFoldersProc.running = true }) }
    stdout: StdioCollector { onStreamFinished: { try { root.searchData = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: autonomyProc
    // Asked while it ran (2026-11-26: a setting changed during a read was
    // never read, on a slow machine): once more when it ends.
    property bool again: false
    onExited: if (autonomyProc.again) { autonomyProc.again = false; Qt.callLater(function () { autonomyProc.running = true }) }
    stdout: StdioCollector { onStreamFinished: { try { root.autonomyData = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: notebookProc
    // Asked while it ran (2026-11-26: a setting changed during a read was
    // never read, on a slow machine): once more when it ends.
    property bool again: false
    onExited: if (notebookProc.again) { notebookProc.again = false; Qt.callLater(function () { notebookProc.running = true }) }
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
    property var queue: []
    onExited: Qt.callLater(root.nextNotebookAct)
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
    onRunningChanged: if (running) root.planPhase = ""
    stdout: StdioCollector {
      onStreamFinished: {
        var r = null
        try { r = JSON.parse(text) } catch (e) {}
        root.planError = r && r.error ? root.sayPlanError(r.error) : (r && r.ran === false ? root.planError : "")
        if (root.planError !== "" && r && r.error) root.showHint("the agent could not plan: " + root.planError)
      }
    }
    stderr: SplitParser {
      onRead: function (line) {
        var ph = Queue.phase(line)
        if (ph !== "") { root.planPhase = ph; return }
        if (line.trim() !== "") console.warn("longhand.page plan: " + line)
      }
    }
    onExited: function (code, status) {
      root.planning = false
      root.planPhase = ""
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
          root.proposals = (p.open || []).filter(function (x) { return !x.auto }).concat(
            (p.told || []).map(function (x) { return Object.assign({ told: true }, x) }))
            .filter(function (x) { return !root.settledHere[x.id] })
          root.proposalsReadAt = root.proposalsAsked
          root.applyAuto(p.open || [])
          // What waited above the cap went quiet: said once, when it goes.
          if (p.trimmed > 0)
            root.showHint(p.trimmed + (p.trimmed === 1 ? " older proposal" : " older proposals")
                          + " set aside · the newest 3 a course wait for you")
          // Kept, not replaced: a conversation whose proposal was just
          // settled stays in the margin until it is closed.
          root.threads = p.threads || {}
          if (root.acceptAfterRefresh >= 0) {
            var agreed = root.proposals.filter(function (x) { return x.id === root.acceptAfterRefresh })[0]
            // A list read before the conversation's answer was written does
            // not have it yet: wait for the one asked for after it.
            if (agreed || !root.proposalsAgain) root.acceptAfterRefresh = -1
            if (agreed) {
              root.acceptPlanned({ kind: Say.askKind(agreed), item: agreed, task: root.taskOfKey(agreed.key) })
              root.showHint("accepted, as you agreed")
            }
          }
          if (root.proposalsAgain) { root.proposalsAgain = false; Qt.callLater(root.refreshProposals) }
          var d = {}
          for (var i = 0; i < (p.accepted || []).length; i++) d[p.accepted[i].key] = p.accepted[i].date
          root.agentDates = d
        } catch (e) {}
      }
    }
  }

  Process {
    id: convoViewProc
    stdout: StdioCollector {
      onStreamFinished: { try { root.convoView = JSON.parse(text) } catch (e) {} }
    }
  }

  Process {
    id: refFilesProc
    stdout: StdioCollector {
      onStreamFinished: { try { root.refFiles = JSON.parse(text).files || [] } catch (e) {} }
    }
  }

  Process {
    id: elsewhereProc
    property string asked: ""
    property string wanted: ""
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.elsewhere = d
          root.elsewhereFor = elsewhereProc.asked
        } catch (e) {}
      }
    }
    onExited: function (code, status) { if (elsewhereProc.wanted !== elsewhereProc.asked) Qt.callLater(root.loadElsewhere) }
  }

  Process {
    id: checkinProc
    // Asked while it ran (2026-11-26: a setting changed during a read was
    // never read, on a slow machine): once more when it ends.
    property bool again: false
    onExited: if (checkinProc.again) { checkinProc.again = false; Qt.callLater(function () { checkinProc.running = true }) }
    stdout: StdioCollector {
      onStreamFinished: { try { root.checkinData = JSON.parse(text) } catch (e) {} }
    }
  }

  Process {
    id: checkinSaveProc
    property bool kept: false
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.showHint("not kept — " + Queue.failure(text)) }
    onExited: function (code, status) {
      if (code !== 0) return
      root.showHint(checkinSaveProc.kept ? "kept — thank you; next week's is due Monday" : "skipped this week")
      root.loadCheckin()
      root.closeCheckin()
    }
  }

  Process {
    id: talkProc
    property string said: ""
    onRunningChanged: if (running) { talkProc.said = ""; root.talkPhase = "" }
    stdout: StdioCollector {
      // The planner's answer is JSON (`talk`); the margin's is a line
      // (`chat`). Either way the conversation is read again.
      onStreamFinished: {
        try { root.talkAnswered(JSON.parse(text)) } catch (e) { root.refreshProposals() }
        root.fetchTalk()
      }
    }
    stderr: SplitParser {
      onRead: function (line) {
        var ph = Queue.phase(line)
        if (ph !== "") { root.talkPhase = ph; return }
        if (line.trim() !== "") {
          talkProc.said = (talkProc.said ? talkProc.said + "\n" : "") + line
          console.warn("longhand.page talk: " + line)
        }
      }
    }
    onExited: function (code, status) {
      root.talkPhase = ""
      if (root.talkStopAsked) {
        root.talkStopAsked = false
        root.pendingTalk = null
        talkProc.said = ""
        return
      }
      if (code !== 0) {
        var p = root.pendingTalk
        root.pendingTalk = null
        Qt.callLater(function () {
          var first = Queue.failure(talkProc.said)
          talkProc.said = ""
          // What was written, back in the box (or kept with its task's chat).
          var back = false
          if (p && root.talkOpen && p.thread === root.talkThread) back = root.giveBackSent("talk", p)
          else if (p) root.keepMarginDraft("talk:" + p.thread, p)
          root.showHint("the agent could not answer" + (first === "" ? "" : " — " + first)
            + (back ? " · what you wrote is back in the box" : p ? " · what you wrote waits in its chat's box" : ""))
          root.refreshProposals()
        })
        return
      }
      Qt.callLater(function () {
        var fb = Queue.fallback(talkProc.said)
        talkProc.said = ""
        if (fb !== "") root.showHint(fb)
      })
    }
  }

  Process {
    id: threadProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (root.talkThread !== "") {
            root.talkData = d
            root.talkThread = d.thread
            root.markChatSeen(d)
            // A card just accepted leaves the keys on the next, or the box.
            if (root.talkCardFocus >= root.talkCards.length) {
              if (root.talkCards.length > 0) root.talkCardFocus = root.talkCards.length - 1
              else { root.talkCardFocus = -1; margin.chatFieldRef.forceActiveFocus() }
            }
            if (!root.talking) root.pendingTalk = null
          }
        } catch (e) {}
        if (root.talkFetchAgain) { root.talkFetchAgain = false; Qt.callLater(root.fetchTalk) }
      }
    }
  }

  Process {
    id: proposalProc
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page proposal: " + text.trim()) }
    // A filed document shows in its course in the sidebar at once.
    // What was just done on its own (a box ticked because the student asked
    // it in a chat) shows as told, to let stand or undo: the list read again.
    onExited: function (code, status) {
      var applied = (proposalProc.command || []).indexOf("applied") >= 0
      root.nextProposal()
      if (root.proposalQueue.length === 0) { root.refreshProjects(); if (applied) root.refreshProposals() }
    }
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

  FileView {
    id: threadsFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/threads.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { root.threadsStore = JSON.parse(text()) || {} } catch (e) { root.threadsStore = {} }
      if (svc.ready) root.restoreThreads(editor.text)
    }
  }
  Timer {
    id: threadsSave
    interval: 800
    onTriggered: threadsFile.setText(JSON.stringify(root.threadsStore, null, 1) + "\n")
  }

  Process {
    id: settingsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.settingsState = JSON.parse(text) } catch (e) { root.settingsNote = "the runner did not answer" }
        root.settingsBusy = false
        root.settingsBusyIndex = -1
        root.refreshProjects()
        if (root.timetableAgain !== null) {
          var again = root.timetableAgain
          root.timetableAgain = null
          root.settingsBusyIndex = again.index
          root.runTimetable(again.flags)
        }
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
        var next = root.hyprNext
        root.hyprNext = null
        if (next) root.hypr(next)
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.warn("longhand.page hyprkeys: " + text.trim()) }
  }
  Process { id: submapProc }
  Process { id: raiseProc }
  Process { id: fullProc }
  // The sheet stops waiting a little before Hyprland would leave the submap.
  Timer {
    id: hyprListenTimer
    interval: 25000
    onTriggered: if (root.keysListen && root.keysListen.hypr) { root.stopListening(); root.keysNote = "stopped waiting for a key — Enter to try again" }
  }

  // The zoom step and the dashboard's last visit survive restarts. Machine
  // state, not config, and never in the vault.
  FileView {
    id: zoomFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/page.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var st = JSON.parse(text())
        var z = Number(st.zoom)
        if (isFinite(z) && z >= 0.5 && z <= 3) root.zoom = z
        if (typeof st.dashSeen === "number") root.dashSeenId = st.dashSeen
        if (st.chatSeen && typeof st.chatSeen === "object") root.chatSeen = st.chatSeen
        if (Array.isArray(st.dashLens)) root.dashLens = st.dashLens.filter(function (t) { return typeof t === "string" })
        if (root.dashOrders.indexOf(st.dashOrder) >= 0) root.dashOrder = st.dashOrder
        // A month gone by takes its band's fold with it.
        if (st.dashFolds && typeof st.dashFolds === "object") {
          var folds = {}, month = "m" + Qt.formatDate(new Date(), "yyyy-MM")
          for (var id in st.dashFolds) if (!(/^m\d{4}-\d\d$/.test(id) && id < month)) folds[id] = !!st.dashFolds[id]
          root.dashFolds = folds
        }
      } catch (e) {}
    }
  }

  // The zoom level shows in the header for a moment after it changes.
  Timer { id: zoomHint; interval: 1500 }

  Timer {
    id: hintTimer
    interval: 6000
    onTriggered: root.hint = ""
  }

  Timer {
    id: tipCool
    interval: 300
    onTriggered: root.tipWarm = false
  }

  Timer {
    id: ctrlWait
    interval: 700
    onTriggered: root.ctrlShow()
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
    color: root.sheetColor
    Behavior on color { ColorAnimation { duration: 240 } }
    // Hyprland tiles it; Windows opens it at this size the first time,
    // wide enough for the note and one pane beside it (2026-11-27: at 680
    // the chat opened over a note at its floor).
    implicitWidth: Style.space(root.onWindows ? 1100 : 680)
    implicitHeight: Style.space(900)
    minimumSize: Qt.size(Style.space(360), Style.space(300))
    onVisibleChanged: {
      if (visible) Qt.callLater(root.focusPinned)
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
  FocusScope {
    id: content
    parent: root.overlayOpen ? panel.contentItem : win.contentItem
    anchors.fill: parent
    focus: true
    onWidthChanged: if (!root.canBothPanes && root.sidebarOpen && root.rightView !== "") root.ensureRoomFor(root.here === "left" ? "left" : "right")
    // Ctrl let go, wherever the keys are: a release no pane takes comes
    // up to here.
    Keys.onReleased: function (event) { if (event.key === Qt.Key_Control) root.ctrlLetGo() }

    // The keys in no pane at all: Hyprland has the window, but nothing in
    // it was given them (the place they were went away). Then a window
    // coming to the front, or a key pressed, puts them back in the middle,
    // and that key's page-wide meaning still counts (2026-11-17).
    function keysNowhere() {
      var f = content.Window.activeFocusItem
      return !f || f === content || f === content.parent
    }
    Window.onActiveChanged: Qt.callLater(function () {
      // Ctrl's release goes to the window that took the keys (Ctrl+Esc,
      // a click elsewhere): its keys shown would stay on screen.
      if (!content.Window.active) root.ctrlLetGo()
      else if (content.keysNowhere()) root.focusCenter()
    })
    Keys.onPressed: function (event) {
      if (!content.keysNowhere()) return
      root.focusCenter()
      if (root.anywhereKey(event)) event.accepted = true
      else if (Sc.hit(event, "close")) { root.dismiss(); event.accepted = true }
    }

    Rectangle {
      anchors.fill: parent
      visible: !root.alongside
      color: root.scrim
    }

    // A click outside the sheet: on the overlay, outside the cards, it
    // dismisses; between two cards, or in the window beside the column, it
    // goes back to writing. Until 2026-11-27 a click a little short of the
    // sidebar closed the whole overlay (the shape pass).
    MouseArea {
      anchors.fill: parent
      onClicked: function (mouse) {
        if (root.alongside || root.amongCards(mouse.x, mouse.y)) root.focusCenter()
        else root.dismiss()
      }
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

    // What the agent may do: Settings' third view. (AutonomySheet.qml)
    AutonomySheet { id: autonomySheet; page: root }
    // How it feels, once a week: Settings' fourth view. (CheckinSheet.qml)
    CheckinSheet { id: checkinSheet; page: root }

    // What the agent may search: Settings' fourth view. (SearchSheet.qml)
    SearchSheet { id: searchSheet; page: root }

    // The keys sheet (Ctrl+/, or "keys" at the sidebar's foot): every key the page
    // answers to, under where it works, each one movable. A list, so it
    // takes the dashboard's shape rather than the note's measure. (KeysSheet.qml)
    KeysSheet { id: keysSheet; page: root }

    // The switcher (Ctrl+O): a project by its letters, over whatever the
    // middle shows. (Switcher.qml)
    Switcher { id: switcherBox; page: root }
    // A press outside it lets the switcher go, as outside a menu: on empty
    // chrome too, where nothing takes the keys from its field. The press
    // goes on to what is under it.
    MouseArea {
      anchors.fill: parent
      z: 89
      visible: root.switcherOpen
      onPressed: function (mouse) { mouse.accepted = false; root.closeSwitcher() }
    }

    BorderSurface {
      id: sheet
      visible: !root.dashOpen && !root.keysOpen && !root.settingsOpen
      x: root.sheetX
      y: root.alongside ? 0 : root.sheetMargin
      width: root.sheetWidth
      // Recentring for a pane slides, quickly. The width snaps: text
      // reflowing every frame reads as shaking. While the pane's edge is
      // dragged the note follows the hand directly, with no lag behind it.
      Behavior on x { enabled: root.paneLive <= 0; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      height: root.alongside ? content.height : content.height - root.sheetMargin * 2
      radius: root.alongside ? 0 : root.overlayRadius
      color: root.sheetColor
      Behavior on color { ColorAnimation { duration: 240 } }
      borderSpec: root.cardSpec
      padding: root.sheetPadding

      // A click on the sheet's margins is the keys into the middle, into
      // whatever shows there: the note sent them to the note even under a
      // PDF or the export, where it is hidden (2026-11-25, the mouse pass).
      MouseArea {
        anchors.fill: parent
        onClicked: root.focusCenter()
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

          // The seal: Longhand's own mark, at the header's centre, and the
          // door to the day conversation in the right pane (2026-10-21; it
          // was the sidebar's before, from the left). Quiet until pointed
          // at, lit while the conversation is open. It identifies Longhand
          // and opens the conversation, nothing else: never a sign that the
          // agent answered or that something waits (docs/brand/README.md).
          LogoMark {
            id: seal
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: dateText.verticalCenter
            width: Math.round(dateText.implicitHeight * 1.05)
            height: width
            color: sealArea.containsMouse && root.handOn ? root.accent : root.dayShown ? root.foreground : root.faint
            Behavior on color { ColorAnimation { duration: 240 } }
            MouseArea {
              id: sealArea
              anchors.fill: parent
              anchors.margins: -root.sp(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.sealClicked()
              Tip {
                host: root
                act: "day"
                shown: parent.containsMouse
                // Both of the pane's keys, so the pair is remembered (2026-10-27).
                text: root.tips([[root.dayShown ? "Close the agent's pane" : "The agent's pane: the day's chat", "day"],
                                 ["Go there; in it, the day's chat ↔ this one", "pane3"]])
              }
            }
          }
          KeyBadge {
            host: root
            act: "day"
            words: "agent"
            anchors.top: seal.bottom
            anchors.topMargin: root.sp(6)
            anchors.horizontalCenter: seal.horizontalCenter
          }

          Text {
            id: dateText
            // The status line takes the date's place while it speaks.
            opacity: root.status === "" ? 1 : 0
            anchors.left: parent.left
            // A file's name can be long: it stops short of the seal, leaving
            // room for the way back (2026-10-27).
            width: Math.min(implicitWidth, Math.max(root.sp(80),
              seal.x - root.sp(36) - (backToday.visible ? backToday.implicitWidth : 0)))
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.noteLabel + (svc.readOnly ? " · the agent's, to read" : "")
            color: dateArea.containsMouse && root.handOn ? root.accent : root.sidebarOpen ? root.foreground : svc.isToday ? root.dim : root.foreground
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            // The door to the sidebar: the calendar, the projects, keys and settings.
            KeyBadge {
              host: root
              act: "sidebar"
              words: "sidebar"
              anchors.top: parent.bottom
              anchors.topMargin: root.sp(6)
              anchors.horizontalCenter: parent.horizontalCenter
            }
            MouseArea {
              id: dateArea
              anchors.fill: parent
              // Wider than the word, so it is easy to hit (2026-11-25, the mouse pass).
              anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
              anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
              enabled: root.status === ""
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dateClicked()
              Tip {
                host: root
                act: "sidebar"
                shown: parent.containsMouse
                text: root.tips([[root.sidebarOpen ? "Close the sidebar" : "The sidebar: calendar, projects, keys and settings", "sidebar"],
                                 ["Go there; in it, Time ↔ Files", "pane1"]])
              }
            }
          }

          // On another day: the way back to today.
          Text {
            id: backToday
            visible: (root.pdfShown || !svc.isToday && (svc.noteDate !== "" || svc.filePath !== "")) && root.status === ""
            anchors.left: dateText.right
            anchors.leftMargin: root.sp(12)
            anchors.verticalCenter: dateText.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, seal.x - root.sp(18) - x))
            elide: Text.ElideRight
            textFormat: Text.PlainText
            // Short of room (a long file name, a narrow window), the name
            // keeps its room and the way back says only "today".
            readonly property string full: root.pdfShown || !root.dayNote ? "back to today"
              : root.beforeHorizon ? "back to today · before the agent's horizon"
              : root.agentDay ? "back to today" : "back to today · agent off for this note"
            TextMetrics { id: backFull; font: backToday.font; text: backToday.full }
            text: seal.x - root.sp(36) - dateText.implicitWidth >= backFull.width ? full : "today"
            color: todayArea.containsMouse && root.handOn ? root.accent : root.faint
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            KeyBadge {
              host: root
              act: "today"
              anchors.top: parent.bottom
              anchors.topMargin: root.sp(6)
              anchors.horizontalCenter: parent.horizontalCenter
            }
            MouseArea {
              id: todayArea
              anchors.fill: parent
              // Wider than the word, so it is easy to hit (2026-11-25, the mouse pass).
              anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
              anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: root.goToday()
              Tip {
                host: root
                act: "today"
                shown: parent.containsMouse
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
            anchors.right: seal.left
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
              Tip { host: root; shown: parent.containsMouse && statusText.truncated; text: root.status }
            }
          }

          // The header's right side (2026-11-26, the header pass): one rule
          // for all of it, on Omarchy and on Windows alike.
          // - A word is a thing to click: faint at rest, the accent under the
          //   hand, the foreground while what it turns on is on. A click does
          //   what its key does, and the keys land where the key leaves them.
          // - A status shows only while it says something (the agent
          //   thinking, a reply waiting), after a hairline; the saved dot is
          //   the one quiet thing always there while a note can be written.
          // - What has no room goes, in one order: the shape, then the chat.
          //   The privacy word, a status and the saved dot never go. Nothing
          //   is cut off, so the key badges under the words show.
          Row {
            id: headerRight
            objectName: "headerRight"   // read by tests/page (headerWords)
            readonly property real room: Math.max(0, parent.width - (seal.x + seal.width) - root.sp(16))
            // The note's own words: not while a PDF or the export stands
            // in the middle, where a click would reach the hidden note.
            readonly property bool noteHere: !root.pdfShown && !root.exportOpen
            readonly property real gap: root.sp(10)
            // Measured, not guessed: whatever the face, the zoom or the scale.
            readonly property real kept: (zoomWord.visible ? zoomWord.implicitWidth + gap : 0)
              + (horizonMark.visible ? horizonMark.implicitWidth + gap : 0)
              + (privateWord.visible ? privateWord.implicitWidth + gap : 0)
              + (pdfPrivate.visible ? pdfPrivate.implicitWidth + gap : 0)
              + (agentStatus.visible ? agentStatus.implicitWidth + 1 + 2 * gap : 0)
              + (savedDot.visible ? savedDot.width : 0)
            readonly property bool chatWanted: root.agentOn && noteHere
            readonly property bool chatFits: chatWanted && kept + chatWord.implicitWidth + gap <= room
            readonly property bool askWanted: root.noteAskable && noteHere
            // "window", on the overlay only: in the window there is no other
            // shape to go to (F11 fills the screen there).
            readonly property real shapeWants: root.alongside ? 0 : pinWord.implicitWidth + gap
            // The note's chat says its full words while "window" still fits
            // beside them; else the short ones; else it goes.
            readonly property bool askFull: askWanted && kept + noteAskFull.width + shapeWants + gap <= room
            readonly property bool askFits: askWanted && (askFull || kept + noteAskShort.width + gap <= room)
            readonly property real asked: chatFits ? chatWord.implicitWidth + gap
              : askFits ? (askFull ? noteAskFull.width : noteAskShort.width) + gap : 0
            readonly property bool pinFits: !root.alongside && kept + asked + pinWord.implicitWidth + gap <= room
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: gap

            Text {
              id: zoomWord
              visible: zoomHint.running
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Math.round(root.zoom * 100) + "%"
              color: root.dim
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }

            // On the overlay, "window": keep this sheet as a window beside
            // your work (F11 or a click). Until 2026-11-27 it was "pin", lit
            // in the window and dim on the overlay — the reverse of what pin
            // means everywhere else, and gone from the header exactly when
            // the window was tiled narrow (the shape pass).
            Text {
              id: pinWord
              visible: headerRight.pinFits
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "window"
              color: pinArea.containsMouse && root.handOn ? root.accent : root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              KeyBadge {
                host: root
                act: "pin"
                anchors.top: parent.bottom
                anchors.topMargin: root.sp(6)
                anchors.horizontalCenter: parent.horizontalCenter
              }
              MouseArea {
                id: pinArea
                anchors.fill: parent
                // Wider than the word, so it is easy to hit (2026-11-25, the mouse pass).
                anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
                anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePin()
                Tip { host: root; act: "pin"; shown: parent.containsMouse; text: root.tip("Keep it open as a window beside your work", "pin") }
              }
            }

            // A day before the horizon says so where "private" would be: a
            // grey lock, since it is the rule and not a choice. Its tip
            // says which day the horizon is, and where it is moved.
            // An Item round a Row, its hover beside the Row and not in it: a
            // child sized from the Row it is laid out in polishes forever.
            Item {
              id: horizonMark
              visible: root.dayNote && root.beforeHorizon && headerRight.noteHere
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: horizonRow.implicitWidth
              implicitHeight: horizonRow.implicitHeight
              Row {
                id: horizonRow
                spacing: root.sp(6)
                LockMark { anchors.verticalCenter: parent.verticalCenter; width: root.sp(10); color: root.dim }
                Text {
                  textFormat: Text.PlainText
                  text: "before the horizon"
                  color: root.dim
                  font.family: root.fontFamily
                  font.styleName: root.fontStyle
                  font.pixelSize: root.fs(Style.font.bodySmall)
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                Tip {
                  host: root
                  shown: parent.containsMouse
                  text: root.tips([["The agent sees daily notes from " + root.sayHorizon(root.horizonData ? root.horizonData.horizon : "") + " on", ""],
                                   ["Settings, what the agent may search, moves it", "settings"]])
                }
              }
            }

            // Private: the one place that says whether the agent can see
            // this note, and the one control that changes it. Always in
            // sight, because a guarantee you cannot see is not one
            // (2026-10-15). When it is on, the block's chat and the agent's
            // status are not dimmed but gone — there is nothing to offer.
            // The lock and the word are one thing to hover and click.
            Item {
              id: privateWord
              visible: root.agentDay && !root.beforeHorizon && headerRight.noteHere
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: privateRow.implicitWidth
              implicitHeight: privateRow.implicitHeight
              Row {
                id: privateRow
                spacing: root.sp(6)
                LockMark {
                  visible: svc.notePrivate
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.sp(10)
                  color: root.magenta
                }
                Text {
                  id: privateText
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "private"
                  color: privateArea.containsMouse && root.handOn ? root.accent : svc.notePrivate ? root.foreground : root.faint
                  font.family: root.fontFamily
                  font.styleName: root.fontStyle
                  font.pixelSize: root.fs(Style.font.bodySmall)
                  Behavior on color { ColorAnimation { duration: 240 } }
                  // A row below the pin's, so the two never touch.
                  KeyBadge {
                    host: root
                    act: "private"
                    anchors.top: parent.bottom
                    anchors.topMargin: root.sp(6) + height + root.sp(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                  }
                }
              }
              MouseArea {
                id: privateArea
                anchors.fill: parent
                // Wider than the words, so it is easy to hit (2026-11-25, the mouse pass).
                anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
                anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.togglePrivate(); editor.focusNote() }
                Tip {
                  host: root
                  act: "private"
                  shown: parent.containsMouse
                  text: root.tip(svc.notePrivate ? "Let the agent see this note again" : "Make this note private: the agent sees nothing", "private")
                }
              }
            }

            // A private PDF says so, as a private note does; it is the
            // PDF's own mark, not a switch here.
            Item {
              id: pdfPrivate
              visible: root.pdfShown && !root.exportOpen && !!pdfPane.read && !!pdfPane.read.private
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: pdfPrivateRow.implicitWidth
              implicitHeight: pdfPrivateRow.implicitHeight
              Row {
                id: pdfPrivateRow
                spacing: root.sp(6)
                LockMark { anchors.verticalCenter: parent.verticalCenter; width: root.sp(10); color: root.magenta }
                Text {
                  textFormat: Text.PlainText
                  text: "private"
                  color: root.dim
                  font.family: root.fontFamily
                  font.styleName: root.fontStyle
                  font.pixelSize: root.fs(Style.font.bodySmall)
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                Tip { host: root; shown: parent.containsMouse; text: root.tip("Private: this PDF is never given to the agent", "") }
              }
            }

            // Ask about this note (docs/files.md): for what the agent does
            // not otherwise see — a file, a day before the horizon, a day
            // marked private. Asking is the consent; the note's own
            // conversation opens beside it, and the word says one exists.
            Text {
              id: noteAsk
              visible: headerRight.askFits
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              readonly property string full: root.noteTalkTurns > 0 ? "this note's chat · " + Math.ceil(root.noteTalkTurns / 2) : "chat about this note"
              readonly property string short: root.noteTalkTurns > 0 ? "chat · " + Math.ceil(root.noteTalkTurns / 2) : "chat"
              TextMetrics { id: noteAskFull; font: noteAsk.font; text: noteAsk.full }
              TextMetrics { id: noteAskShort; font: noteAsk.font; text: noteAsk.short }
              text: headerRight.askFull ? full : short
              color: noteAskArea.containsMouse && root.handOn ? root.accent : root.noteRoom && root.dayShown ? root.foreground : root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              // Ctrl+Shift+Enter opens this chat in a note from Files only:
              // on a day it opens the day's. A key it does not have is not
              // named on it.
              KeyBadge {
                host: root
                act: "dayChat"
                place: !root.dayNote
                anchors.top: parent.bottom
                anchors.topMargin: root.sp(6)
                anchors.horizontalCenter: parent.horizontalCenter
              }
              MouseArea {
                id: noteAskArea
                anchors.fill: parent
                // Wider than the word, so it is easy to hit (2026-11-25, the mouse pass).
                anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
                anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.noteRoom && root.dayShown ? root.closeDay() : root.openRoom("", true)
                Tip {
                  host: root
                  act: root.dayNote ? "" : "dayChat"
                  shown: parent.containsMouse
                  text: root.tip(root.noteTalkTurns > 0 ? "This note's chat" : "Chat about this note: chatting shares it, for this chat only", root.dayNote ? "" : "dayChat")
                }
              }
            }

            // This block's chat: the agent's visible way in, sending the
            // block the cursor is in — the same path as Ctrl+Enter — from
            // the header, outside the canvas, so nothing marks the
            // student's own words. Dim when this block carries a sign for
            // the agent, faint when it does not; lit while its chat is open,
            // and a click then closes it. Its key is named at the cursor,
            // where Ctrl held already says "chat about this block".
            Text {
              id: chatWord
              visible: headerRight.chatFits
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              // One word, whatever the chat holds (2026-10-27).
              text: "chat"
              color: askArea.containsMouse && root.handOn ? root.accent
                : root.marginOpen ? root.foreground
                : (root.currentTrigger !== "" || Queue.answered(root.currentRecord) ? root.dim : root.faint)
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                id: askArea
                anchors.fill: parent
                // Wider than the word, so it is easy to hit (2026-11-25, the mouse pass).
                anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
                anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Read on the press: by the click, the chat it closes is gone.
                property bool closing: false
                onPressed: closing = root.marginOpen
                onClicked: root.chatClicked()
                Tip {
                  host: root
                  act: askArea.closing ? "" : "ask"
                  shown: parent.containsMouse
                  // Asked only under the hand: whether the block is private
                  // is read from the whole note.
                  text: !parent.containsMouse ? ""
                    : root.marginOpen ? root.tip("Close this block's chat", "marginBack")
                    : root.currentHash === "" ? root.tip("Chat about the block the cursor is in", "ask")
                    : root.blockPrivate(root.currentHash) ? root.tip("Private: the agent sees nothing of this block", "privateBlock")
                    : root.tip(Queue.answered(root.currentRecord) ? "This block's chat"
                      : root.currentTrigger !== "" ? "Chat about this block: the agent answers first" : "Chat about this block", "ask")
                }
              }
            }

            // A hairline between the words to click and the agent's status.
            Rectangle {
              visible: agentStatus.visible && (pinWord.visible || privateWord.visible || horizonMark.visible || noteAsk.visible || chatWord.visible)
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: root.sp(10)
              color: Util.alpha(root.foreground, 0.18)
            }

            // The agent's status, while it has one: thinking (the
            // foreground), or a reply waiting in this note (the accent — a
            // click opens it, as the block's gutter bar does). At rest it is
            // not shown: "chat" already says the agent can be asked.
            Text {
              id: agentStatus
              visible: headerRight.noteHere && (root.replyWaiting || root.working)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.replyWaiting ? "a reply" : "thinking"
              color: root.replyWaiting ? root.accent : root.foreground
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                anchors.fill: parent
                anchors.topMargin: -root.sp(5); anchors.bottomMargin: -root.sp(5)
                anchors.leftMargin: -root.sp(3); anchors.rightMargin: -root.sp(3)
                hoverEnabled: true
                cursorShape: root.replyWaiting ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (root.replyWaiting) root.openUnread()
                Tip {
                  host: root
                  shown: parent.containsMouse
                  text: root.replyWaiting ? root.tips([["A reply is waiting in this note: open it", ""], ["The agent's pane", "pane3"]])
                    : root.tips([["The agent is thinking; Esc in its chat stops it", ""], ["The agent's pane", "pane3"]])
                }
              }
            }

            // Saved / unsaved: a dot that brightens while a write is
            // pending and settles once it landed; urgent while a write
            // that never said it landed is being written again, or when
            // the note cannot be written. Only where a note can be
            // written — or something is wrong, which always shows. A click
            // saves now, as Ctrl+S does.
            Rectangle {
              id: savedDot
              readonly property bool urgent: root.problem !== "" || svc.stalled
              visible: urgent || (svc.ready && headerRight.noteHere && !svc.readOnly)
              anchors.verticalCenter: parent.verticalCenter
              width: root.sp(6)
              height: width
              radius: width / 2
              color: urgent ? root.urgent : (savedArea.containsMouse && root.handOn ? root.accent : svc.pending || svc.saving ? root.foreground : root.faint)
              Behavior on color { ColorAnimation { duration: 180 } }
              MouseArea {
                id: savedArea
                anchors.fill: parent
                anchors.margins: -root.sp(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveNow()
                Tip {
                  host: root
                  act: "save"
                  shown: parent.containsMouse
                  text: root.tip(root.problem !== "" ? root.problem
                    : svc.stalled ? "Not saved yet: writing it again"
                    : svc.pending || svc.saving ? "Saving" : "Saved", "save")
                }
              }
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
            FieldMenu { page: root; field: parent }
            id: searchField
            anchors.left: parent.left
            anchors.right: searchCount.left
            anchors.rightMargin: root.sp(12)
            placeholderText: svc.filePath !== "" ? "find in this file" : svc.isToday ? "find in today's note" : "find in this day's note"
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
                + (root.matchesFolded > 0 ? " · " + root.matchesFolded + " in folded lines" : "")
            color: root.dim
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
          }
        }

        // Setup / error state: actionable guidance and Esc-dismissible so a
        // missing config.json or bad vault path never traps the overlay.
        FocusScope {
          id: problemCard
          visible: root.problem !== ""
          focus: visible
          anchors.top: searchBar.bottom
          anchors.topMargin: root.sp(24)
          anchors.left: parent.left
          anchors.right: parent.right
          height: problemCol.implicitHeight
          onVisibleChanged: if (visible && root.showing) Qt.callLater(problemCard.forceActiveFocus)
          // The page's own keys work here too (2026-11-25): settings, the
          // keys, the zoom, the window's shape.
          Keys.onPressed: function (event) { if (root.anywhereKey(event)) event.accepted = true }
          Keys.onEscapePressed: if (root.overlayOpen) root.dismiss()
          Column {
            id: problemCol
            width: parent.width
            spacing: root.sp(10)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.problem
              color: root.urgent
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.body)
            }
            Text {
              visible: svc.configError !== ""
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: "Copy config.example.json to " + svc.configPath + ", set \"vault\" to your Obsidian folder, and run `longhand-agent install`."
              color: root.dim
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            Text {
              visible: root.overlayOpen
              textFormat: Text.PlainText
              text: "Esc closes"
              color: root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.caption)
            }
          }
        }

        // Export as a PDF, in the note's place too (ExportSheet.qml).
        ExportSheet {
          id: exportSheet
          page: root
          anchors.top: searchBar.bottom
          anchors.topMargin: root.sp(24)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }

        // A PDF, in the note's place (PdfPane.qml).
        PdfPane {
          id: pdfPane
          page: root
          rel: root.pdfRel
          anchors.top: searchBar.bottom
          anchors.topMargin: root.sp(24)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }

        // One project's part of the day (Focus.js): which, and the way back
        // to the whole day.
        Item {
          id: focusBand
          visible: editor.focusTag !== "" && root.problem === "" && !root.pdfShown && !root.exportOpen
          anchors.top: searchBar.bottom
          anchors.topMargin: visible ? root.sp(16) : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? bandWhat.implicitHeight : 0
          Text {
            id: bandWhat
            anchors.left: parent.left
            anchors.right: bandBack.left
            anchors.rightMargin: root.sp(12)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.focusName + (root.focusName === "#" + editor.focusTag ? "" : "  ·  #" + editor.focusTag) + "  ·  only its part of this day"
            color: root.dim
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
          }
          Text {
            id: bandBack
            anchors.right: parent.right
            anchors.verticalCenter: bandWhat.verticalCenter
            textFormat: Text.PlainText
            text: "the whole day"
            color: bandArea.containsMouse && root.handOn ? root.accent : root.faint
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            KeyBadge {
              host: root
              act: "focusSection"
              anchors.top: parent.bottom
              anchors.topMargin: root.sp(6)
              anchors.horizontalCenter: parent.horizontalCenter
            }
            MouseArea {
              id: bandArea
              anchors.fill: parent
              anchors.margins: -root.sp(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.unfocus(); editor.focusNote() }
              Tip { host: root; act: "focusSection"; shown: parent.containsMouse; text: root.tips([["The whole day again", "close"], ["Again: only this project's part", "focusSection"]]) }
            }
          }
        }

        // The tasks this day is for, written on any day (2026-11-14): a
        // task written on Saturday "for Monday" is seen on Monday's page,
        // counted, and one click from its line. Folded it is one quiet line;
        // the arrow, a click or Ctrl+Shift+T unfolds the list.
        Column {
          id: dayBand
          readonly property int count: root.dayTasks.length
          readonly property int undone: count - root.dayTasksDone
          readonly property bool past: root.noteIso !== "" && root.noteIso < Days.format(new Date(), "YYYY-MM-DD")
          visible: count > 0 && editor.focusTag === "" && root.problem === "" && !root.pdfShown && !root.exportOpen
          anchors.top: focusBand.bottom
          anchors.topMargin: visible ? root.sp(16) : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? implicitHeight : 0
          spacing: root.sp(4)

          Item {
            width: parent.width
            height: dayWhat.implicitHeight
            Item {
              id: dayMark
              width: Math.round(root.fs(Style.font.bodySmall) * 0.72)
              height: width
              anchors.left: parent.left
              anchors.verticalCenter: dayWhat.verticalCenter
              Shape {
                id: dayArrow
                anchors.fill: parent
                rotation: root.dayTasksOpen ? 90 : 0
                layer.enabled: true
                layer.samples: 8
                readonly property real s: width
                ShapePath {
                  strokeColor: "transparent"
                  fillColor: dayHead.containsMouse && root.handOn ? root.accent : root.faint
                  startX: dayArrow.s * 0.2; startY: dayArrow.s * 0.08
                  PathLine { x: dayArrow.s * 0.88; y: dayArrow.s * 0.5 }
                  PathLine { x: dayArrow.s * 0.2; y: dayArrow.s * 0.92 }
                  PathLine { x: dayArrow.s * 0.2; y: dayArrow.s * 0.08 }
                }
              }
            }
            Text {
              id: dayWhat
              anchors.left: dayMark.right
              anchors.leftMargin: root.sp(8)
              textFormat: Text.PlainText
              text: (svc.isToday ? "For today" : "For this day") + "  ·  " + dayBand.count + (dayBand.count === 1 ? " task" : " tasks")
                + "  ·  " + (dayBand.undone === 0 ? "all done" : root.dayTasksDone + " done")
              color: root.dim
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            Text {
              visible: dayBand.undone > 0
              anchors.left: dayWhat.right
              anchors.baseline: dayWhat.baseline
              textFormat: Text.PlainText
              text: "  ·  " + dayBand.undone + (dayBand.past ? " still open" : " to do")
              color: dayBand.past ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            MouseArea {
              id: dayHead
              anchors.fill: parent
              anchors.margins: -root.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dayTasksOpen = !root.dayTasksOpen
              Tip { host: root; act: "dayTasks"; shown: parent.containsMouse; text: root.tips([[root.dayTasksOpen ? "Fold the list" : "The tasks this day is for, from every note", "dayTasks"]]) }
            }
          }

          Repeater {
            model: root.dayTasksOpen ? root.dayTasks : []
            Item {
              id: dayRow
              required property var modelData
              readonly property bool late: !modelData.done && dayBand.past
              width: dayBand.width
              height: dayRowText.implicitHeight + root.sp(4)
              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -root.sp(4)
                anchors.rightMargin: -root.sp(4)
                radius: Style.cornerRadius
                color: dayRowArea.containsMouse && root.handOn ? Style.hoverFill : "transparent"
              }
              Text {
                id: dayRowBox
                anchors.left: parent.left
                anchors.leftMargin: dayMark.width + root.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: dayRow.modelData.done ? "✓" : "○"
                color: dayRow.modelData.done ? root.dim : dayRow.late ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
              Text {
                id: dayRowText
                anchors.left: dayRowBox.right
                anchors.leftMargin: root.sp(8)
                anchors.right: dayRowMeta.left
                anchors.rightMargin: root.sp(12)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: dayRow.modelData.title
                color: dayRow.modelData.done ? root.dim : dayRow.late ? root.urgent : root.foreground
                font.strikeout: dayRow.modelData.done
                font.family: root.fontFamily
                font.styleName: root.fontStyle
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
              Text {
                id: dayRowMeta
                anchors.right: parent.right
                anchors.baseline: dayRowText.baseline
                textFormat: Text.PlainText
                text: {
                  var m = dayRow.modelData, parts = []
                  parts.push(m.how === "due" ? "due" + (m.due.length > 10 ? " " + m.due.slice(11) : "") : "to do")
                  if (m.project) parts.push("#" + m.project)
                  if (m.written !== root.noteIso) {
                    var w = m.written.split("-")
                    parts.push("written " + Qt.formatDate(new Date(+w[0], +w[1] - 1, +w[2]), "ddd d MMM"))
                  }
                  return parts.join("  ·  ")
                }
                color: root.faint
                font.family: root.fontFamily
                font.styleName: root.fontStyle
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
              MouseArea {
                id: dayRowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToTask(dayRow.modelData)
                Tip { host: root; shown: parent.containsMouse; text: root.tips([["Go to its line", ""]]) }
              }
            }
          }
        }

        Flickable {
          acceptedButtons: Qt.NoButton
          QC.ScrollBar.vertical: ScrollMark { page: root }
          id: flick
          visible: root.problem === "" && !root.pdfShown && !root.exportOpen
          anchors.top: dayBand.bottom
          anchors.topMargin: root.sp(24)
          anchors.left: parent.left
          anchors.leftMargin: -root.gutter
          anchors.right: parent.right
          // The scroll bar's lane, out in the sheet's margin: the note's
          // words and its date pills keep their width, and the bar never
          // takes a click meant for a pill at a line's end (2026-11-25).
          anchors.rightMargin: -root.barLane
          anchors.bottom: parent.bottom
          clip: true
          contentWidth: width
          contentHeight: editor.height + height * 0.4
          boundsBehavior: Flickable.StopAtBounds

          TouchScroll { flickable: flick }

          // `pad`: room kept above and below, so the line being written
          // never sits on the clipped edge (2026-11-27). A rect taller than
          // the view shows its top.
          function ensureVisible(r, pad) {
            pad = Math.min(pad || 0, height / 4)
            var top = Math.max(0, r.y - pad), bottom = r.y + r.height + pad
            if (contentY > top) contentY = top
            else if (contentY + height < bottom) contentY = Math.max(0, Math.min(top, bottom - height))
          }
          // The cursor's line, and what the page opened under it (the `@`
          // list, "when?", "name?"): their room grows below the line, which
          // never moves the cursor, so it was clipped off at the bottom.
          function keepCursor() {
            var c = editor.cursorRect
            var top = editor.roomRow >= 0 ? Math.min(c.y, editor.roomTop) : c.y
            var r = editor.roomRow >= 0
              ? Qt.rect(c.x, top, c.width, Math.max(c.y + c.height, editor.roomTop + editor.roomHeight) - top) : c
            flick.ensureVisible(r, editor.mouseLed ? 0 : c.height * 1.5)
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
              // Under the hand, an answered block's bar widens in the
              // accent: it opens the chat (barArea below; the second pass).
              readonly property bool lit: root.barHover === modelData.hash && root.handOn
              visible: modelData.reply || modelData.sending
              x: root.sp(2)
              y: modelData.y
              width: root.sp(lit ? 5 : 3)
              height: modelData.h
              clip: true

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: parent.modelData.sending ? root.dim
                  : parent.modelData.unread || parent.lit ? root.accent : root.dim
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
                radius: Style.cornerRadius
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
          // An answered block's bar opens its chat, as Ctrl+Enter in the
          // block does and as the dashboard's bar does (2026-11-25, the
          // mouse pass: it looked like the dashboard's and did nothing).
          // Over the bars, wider than them, so the narrow mark is easy to hit.
          Repeater {
            model: root.paint
            MouseArea {
              id: barArea
              required property var modelData
              visible: modelData.reply
              x: 0
              y: modelData.y
              width: root.sp(10)
              height: modelData.h
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: root.barHover = containsMouse ? barArea.modelData.hash : (root.barHover === barArea.modelData.hash ? "" : root.barHover)
              onClicked: {
                var r = editor.rows[barArea.modelData.line]
                if (!r) return
                editor.setCursor(r.start + r.prefixLen, true)
                root.sendCurrent()
                root.mouseDid("ask")
              }
              Tip { host: root; shown: parent.containsMouse; text: root.tip("Its chat", "ask") }
            }
          }

          // Private blocks, sunk into the darker paper, and their locks in
          // the gutter (B · Paper). Under the words, as the blip is.
          Repeater {
            model: root.privatePaint
            Item {
              required property var modelData
              x: 0
              // Over exactly the block's lines: its margin above and below
              // is inside them (NoteEditor's paperPad), so the paper never
              // reaches over the line before or after it.
              y: modelData.y
              width: flick.width
              height: modelData.h
              // The gutter is narrow (the agent's marks live there): the
              // paper reaches a little into it, the lock stands left of it.
              Rectangle {
                x: root.gutter - root.sp(5)
                width: editor.width + root.sp(10)
                height: parent.height
                radius: Style.cornerRadius
                color: root.sunk
              }
              LockMark {
                x: Math.max(0, root.gutter - root.sp(5) - width - root.sp(3))
                y: Math.round(modelData.lockY - modelData.y - height / 2)
                width: root.sp(10)
                color: root.magenta
              }
            }
          }

          // The blip (docs/files.md, 2026-10-27): as the keys go from the
          // note into the agent's pane, what goes with them — a block, or the
          // whole note — lights once under the words, so what is shared is
          // never a guess.
          Rectangle {
            id: blipMark
            x: root.gutter - root.sp(10)
            width: editor.width + root.sp(20)
            y: root.blipRect ? root.blipRect.y - root.sp(6) : 0
            height: root.blipRect ? root.blipRect.h + root.sp(12) : 0
            radius: Style.cornerRadius
            color: root.accent
            opacity: 0
            visible: opacity > 0
            SequentialAnimation {
              id: blipAnim
              NumberAnimation { target: blipMark; property: "opacity"; to: 0.16; duration: 160; easing.type: Easing.OutCubic }
              NumberAnimation { target: blipMark; property: "opacity"; to: 0; duration: 620; easing.type: Easing.InOutSine }
            }
          }

          NoteEditor {
            id: editor
            readOnly: svc.readOnly
            cues: root.dayNote
            resolveImage: root.resolveImage
            resolveVersion: root.vaultIndexVersion
            imageSize: root.imageSize
            sizeUnknown: root.sizeUnknown
            sizesVersion: root.imageSizesVersion
            linkColor: pal.blueText
            linkKnown: root.linkKnown
            onLinkActivated: function (i, l) { root.followLink(l) }
            onFoldClicked: root.scheduleRepaint()
            onFocusTagChanged: root.scheduleRepaint()
            viewTop: flick.contentY - y
            viewBottom: flick.contentY - y + flick.height
            // 0 until the item is on a screen; a picture is decoded for 1 then.
            pixelRatio: Math.max(1, Screen.devicePixelRatio || 1)
            // What the page shows under a line opens room there, so the
            // lines below move down rather than being drawn over.
            roomRow: whenBox.visible || mentionBox.visible || nameBox.visible ? root.lineIndexAt(root.newProject ? root.newProject.end : editor.cursorPosition) : -1
            roomHeight: (whenBox.visible ? whenBox.height : mentionBox.visible ? mentionBox.height : nameBox.visible ? nameBox.height : 0) + root.sp(12)
            boxTip: Component { Item { Tip { host: root; shown: true; text: root.tip("Tick or untick it", "checkbox") } } }
            pillTip: Component { Item { Tip { host: root; shown: true; text: editor.pillDoOnly ? root.tip("Another day to do it", "") : root.tip("Its new day", "deadline") } } }
            // A link's hint: where it goes, and how to edit it instead
            // (2026-11-25, the mouse pass: a click always followed it).
            linkTip: Component {
              Item {
                Tip {
                  host: root
                  shown: true
                  text: {
                    var l = parent && parent.parent ? parent.parent.link : null
                    if (!l) return ""
                    var to = l.url !== "" ? l.url : l.target !== "" ? l.target + (l.heading ? "#" + l.heading : "") : "#" + l.heading
                    // A note the vault does not have is drawn faint; the
                    // hint says why, rather than offering to open it
                    // (2026-11-27).
                    if (!root.linkKnown(l)) return root.tips([["No note “" + l.target + "” in the vault", ""], ["Edit it: Alt+click", ""]])
                    return root.tips([["Open " + to, "followLink"], ["Edit it: Alt+click", ""]])
                  }
                }
              }
            }
            boxBadge: Component { KeyBadge { host: root; act: "checkbox" } }
            handOn: root.handOn
            onBoxTicked: function (lineIndex, done) { if (done) root.tickSound() }
            onBoxClicked: root.mouseDid("checkbox")
            onDatePillClicked: function (i) {
              var r = editor.rows[i]
              if (!r) return
              editor.setCursor(r.start + r.prefixLen + r.body.length, true)
              if (r.deadline <= 0 && r.doDay !== "") { root.openDoOn(r); return }
              root.deadlineKey()
              root.mouseDid("deadline")
            }
            authors: root.shownAuthors
            x: root.gutter
            width: flick.width - root.gutter - root.barLane
            height: implicitHeight
            enabled: svc.ready
            fontFamily: root.fontFamily
            fontStyle: root.fontStyle
            codeFamily: root.codeFamily
            textSize: root.textSize
            leading: root.leading
            foreground: root.foreground
            background: root.background
            dim: root.dim
            faint: root.faint
            selectionColor: pal.selection
            cornerRadius: Style.cornerRadius
            accent: root.accent
            urgent: root.urgent
            headingColors: pal.headings
            markColor: Util.alpha(pal.yellow, 0.3)
            currentMarkColor: Util.alpha(pal.orange, 0.55)
            boxColor: pal.dim
            checkColor: pal.greenText
            bulletColor: root.accent
            quoteColor: pal.faint
            privateColor: root.magenta
            codeColor: pal.dim
            marks: root.matches
            currentMark: root.matchIndex
            tabStop: 4 * root.sp(8)
            keyFilter: root.pageKey
            chatKey: root.chatSelectionKey
            firstKey: function (e) {
              if (editMenu.opened && editMenu.key(e)) return true
              root.keysSeen(e)
              return false
            }
            viewport: flick
            onMenuAsked: function (x, y) { root.noteMenu(x, y) }
            onCursorRectChanged: flick.keepCursor()
            onRoomHeightChanged: Qt.callLater(flick.keepCursor)
            onRoomTopChanged: Qt.callLater(flick.keepCursor)
            onDeclineCarried: function (was, now) { root.decline(now) }
            onPrivateKept: root.showHint("a private line stays in its block · cut and paste moves it out")
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
            onPrivateUnwrap: root.togglePrivateBlock()
            declined: root.declined
            onCueDismissed: function (raw) { root.decline(raw); root.used("cue", "kept") }
            onTypedRawChanged: if (typedRaw !== "") root.autoBound = null
            onTextChanged: {
              if (root.searchOpen) Qt.callLater(root.runSearch)
              var was = root.bound
              root.bound = Bound.anchors(text)
              if (root.applying) { root.restoreAuthors(text); root.restoreThreads(text); return }
              root.carryAuthors(text)
              root.carryThreads(text)
              svc.markPending(text)
              saveTimer.restart()
              if (root.quiet) return
              root.boundEdited(was, root.bound)
              root.tickedCount = Queue.countTicked(text)
              root.scheduleRepaint()
              Qt.callLater(root.updateMention)
            }
          }

          // Below the last line: a click goes to the end of the note, so it
          // is still the page to write on — a text cursor, as over the lines.
          MouseArea {
            cursorShape: Qt.IBeamCursor
            y: editor.height
            width: flick.width
            height: Math.max(0, flick.contentHeight - editor.height)
            // The right button too: the note's menu, at the note's end (a
            // short note's blank page took none, 2026-11-25).
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // Pressed here and dragged up into the lines, it selects from
            // the note's end, as a drag below a document's last line does
            // (2026-11-27: it did nothing).
            preventStealing: true
            onPressed: function (mouse) {
              editor.mouseLed = true
              if (mouse.button === Qt.LeftButton) {
                editor.clearSelection()
                editor.setCursor(editor.length, true)
                return
              }
              if (!editor.hasSelection()) editor.setCursor(editor.length, true)
              var at = mapToItem(editor, mouse.x, mouse.y)
              root.noteMenu(at.x, at.y)
            }
            onPositionChanged: function (mouse) {
              if (!(pressedButtons & Qt.LeftButton)) return
              var at = mapToItem(editor, mouse.x, mouse.y)
              if (at.y >= editor.height) {
                if (editor.spanning) { editor.clearSelection(); editor.setCursor(editor.length, true) }
                return
              }
              var h = editor.hitTest(at.x, Math.max(0, at.y))
              var pos = editor.absOf(h.i, h.col)
              if (pos !== editor.length) editor.selectSpan(editor.length, pos)
            }
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
                  color: root.mentionFocus === index ? Style.selectedFill : mentionArea.containsMouse && root.handOn ? Style.hoverFill : "transparent"
                  Text {
                    id: mentionRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: root.sp(4)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: modelData.make ? "+ make #" + modelData.tag + " a project"
                      : "#" + modelData.tag + (modelData.name ? "  " + modelData.name : "")
                    color: modelData.make ? root.dim : root.foreground
                    font.family: root.fontFamily
                    font.styleName: root.fontStyle
                    font.pixelSize: root.fs(Style.font.bodySmall)
                  }
                  MouseArea {
                    id: mentionArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: { root.mentionFocus = index; root.acceptMention(false) }
                    Tip { host: root; shown: parent.containsMouse; text: modelData.make ? "Name it, and it is in the sidebar, @ and #"
                      : root.mention && root.mention.atLineStart
                      ? root.tips([["Write its #tag", "mentionPick"], ["New section", "mentionClass"]]) : root.tip("Write its #tag", "mentionPick") }
                  }
                }
              }
              Text {
                width: parent.width
                topPadding: root.sp(4)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.mentionFocus < 0
                  ? root.keyName("mentionDown") + " then " + root.keyName("mentionPick") + " makes it a project · " + root.keyName("mentionClose") + " leaves it"
                  : root.mention && root.mention.items[root.mentionFocus] && root.mention.items[root.mentionFocus].make
                  ? root.keyName("mentionPick") + " names the new project · " + root.keyName("mentionClose") + " leaves it"
                  : root.mention && root.mention.atLineStart
                  ? root.keyName("mentionPick") + " its tag · " + root.keyName("mentionClass") + " new section · " + root.keyName("mentionClose") + " leaves it"
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
              text: root.whenFor && root.whenFor.doOn ? "do on?" : "due?"
              color: root.dim
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            TextField {
              FieldMenu { page: root; field: parent }
              id: whenField
              width: root.sp(220)
              placeholderText: root.whenFor && root.whenFor.doOn ? "empty: no day" : root.whenFor && root.whenFor.id > 0 ? "empty: no deadline" : "fri 17:00 · in 3 days · 20 oct"
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
            Text {
              readonly property var parsed: whenField.text.trim() !== "" ? Dates.read(whenField.text.trim(), new Date()) : null
              visible: whenField.text.trim() !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                if (!parsed) return "not a date"
                var d = new Date(parsed.ms)
                var timed = !(d.getHours() === 23 && d.getMinutes() === 59)
                return "→ " + Qt.formatDateTime(d, timed ? "ddd d MMM HH:mm" : "ddd d MMM")
              }
              color: parsed ? root.dim : root.urgent
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
          }

          // A new project's name, asked the way Ctrl+D asks "when?": under
          // the line, in the room it opens there.
          Column {
            id: nameBox
            visible: !!root.newProject
            x: root.gutter
            y: editor.roomRow >= 0 ? editor.roomTop + root.sp(4) : editor.cursorRect.y + editor.cursorRect.height + root.sp(4)
            spacing: root.sp(2)
            z: 3
            Row {
              spacing: root.sp(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "name?"
                color: root.dim
                font.family: root.fontFamily
                font.styleName: root.fontStyle
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
              TextField {
                FieldMenu { page: root; field: parent }
                id: nameField
                width: root.sp(260)
                placeholderText: root.newProject ? "empty: " + root.newProject.tag : ""
                font.family: root.fontFamily
                font.styleName: root.fontStyle
                font.pixelSize: root.fs(Style.font.body)
                foreground: root.foreground
                Keys.onPressed: function (event) {
                  if (root.anywhereKey(event)) { event.accepted = true; return }
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitProjectName(); event.accepted = true }
                  else if (event.key === Qt.Key_Escape) { root.closeProjectName(); event.accepted = true }
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              text: root.newProject ? "Enter makes #" + root.newProject.tag + " a project · Esc leaves it as written" : ""
              color: root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.caption)
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

    // The day conversation: the right pane's home. (DayPane.qml)
    DayPane { id: dayPane; page: root }

    // One at a time (the window too narrow for the middle's least and the
    // pane's side by side): the side not shown waits in a strip at its own
    // edge, named with its key; a click or Alt+Z brings it. The chat's strip
    // carries a dot once an answer came while it waited.
    Repeater {
      model: ["middle", "chat"]
      Rectangle {
        required property string modelData
        readonly property bool chat: modelData === "chat"
        visible: root.paneAlone && root.paneSizable && root.rightView !== "" && root.paneTucked === chat
        x: chat ? content.width - root.edge - root.paneStrip : root.edge + (root.canBothPanes ? root.sideSpace : 0)
        y: root.alongside ? 0 : root.sheetMargin
        width: chat ? root.paneStrip : root.paneStrip + root.marginGap
        height: root.alongside ? content.height : content.height - root.sheetMargin * 2
        z: 45
        color: root.sunk
        Rectangle { width: 1; height: parent.height; color: root.faint; opacity: 0.5; anchors.left: parent.chat ? parent.left : undefined; anchors.right: parent.chat ? undefined : parent.right }
        Rectangle {
          visible: parent.chat && root.dayTurns.length > root.paneSeen
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.sp(24)
          width: root.sp(7); height: width; radius: width / 2
          color: root.accent
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.sp(42)
          rotation: 90
          transformOrigin: Item.TopLeft
          x: parent.width / 2 + implicitHeight / 2
          textFormat: Text.PlainText
          text: (parent.chat ? "THE CHAT" : root.paneKind === "paper" ? "THE PAPER" : "THE NOTE") + "  ·  " + root.keyName("paneFlip")
          color: stripArea.containsMouse && root.handOn ? root.accent : root.faint
          font.family: root.fontFamily
          font.styleName: root.fontStyle
          font.pixelSize: root.fs(Style.font.caption)
        }
        // Lit under the hand, as every word that acts (2026-11-25, the mouse pass).
        MouseArea { id: stripArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.flipPane() }
      }
    }

    // Where the keys are (docs/navigation.md): Omarchy's active border, on
    // the side panes, in the theme's own colours for it (its gradient and
    // angle, ThemeColors' activeBorder; the accent when it gives none). Each
    // side pane has a frame of its own, as each window
    // has its border in Hyprland, and the keys moving fade one out while the
    // other fades in, at Hyprland's own pace (Omarchy's `border` animation:
    // speed 5.39, so 539 ms, on easeOutQuint). Nothing travels: until
    // 2026-10-25 one frame slid from pane to pane across the note, which the
    // student did not like. Never around the middle (2026-10-24): there the
    // note's cursor, or the dashboard's lit row, says so already, so no
    // frame on screen means the keys are in the middle.
    Repeater {
      model: ["left", "right"]
      BorderSurface {
        required property string modelData
        readonly property Item pane: root.paneItem(modelData)
        visible: !!pane && pane.visible && opacity > 0
        opacity: root.here === modelData ? 1 : 0
        x: pane ? pane.x : 0
        y: pane ? pane.y : 0
        width: pane ? pane.width : 0
        height: pane ? pane.height : 0
        z: 50
        radius: root.alongside ? 0 : root.overlayRadius
        color: "transparent"
        borderSpec: root.frameSpec
        Behavior on opacity {
          NumberAnimation { duration: 539; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1] }
        }
      }
    }

    // Ctrl held: the block's chat beside the note's cursor, and the strip
    // of what else Ctrl does here, over the foot of the middle.
    KeyBadge {
      host: root
      act: "ask"
      words: "chat about this block"
      place: !!root.caretAt && root.centerView === "note"
      x: root.caretAt ? root.caretAt.x - width : 0
      y: root.caretAt ? root.caretAt.y - height / 2 : 0
    }
    Rectangle {
      id: ctrlStrip
      readonly property Item mid: root.paneItem("center")
      visible: root.ctrlShown && !!mid && root.ctrlStripItems.length > 0
      z: 60
      x: mid ? mid.x : 0
      width: mid ? mid.width : 0
      y: mid ? mid.y + mid.height - height : 0
      height: stripFlow.implicitHeight + root.sp(20)
      color: root.sunk
      Flow {
        id: stripFlow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.sp(28)
        anchors.rightMargin: root.sp(28)
        spacing: root.sp(14)
        Text {
          textFormat: Text.PlainText
          text: "Ctrl +"
          color: root.faint
          font.family: root.fontFamily
          font.styleName: root.fontStyle
          font.pixelSize: root.fs(Style.font.bodySmall)
        }
        Repeater {
          model: root.ctrlStripItems
          Row {
            required property var modelData
            spacing: root.sp(5)
            Text {
              textFormat: Text.PlainText
              text: parent.modelData.key
              color: root.accent
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
            Text {
              textFormat: Text.PlainText
              text: parent.modelData.words
              color: root.dim
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
            }
          }
        }
      }
    }

    // The mouse's menu on words: the note's and the chats' (EditMenu.qml).
    EditMenu { id: editMenu; page: root }

    // The student's own hand on the mouse: the pointer is left alone while
    // it moves, and the hints come back (a warp's own motion is not the
    // hand, nor a row sliding under a still pointer, which only redelivers
    // the same spot).
    HoverHandler {
      id: handHover
      onPointChanged: {
        var p = point.scenePosition
        var moved = Math.abs(p.x - root.handAt.x) + Math.abs(p.y - root.handAt.y) > 2
        root.handAt = p
        if (!moved || Date.now() - root.warpedAt <= 250) return
        root.handMovedAt = Date.now()
        root.handOn = true
        root.ctrlLetGo()
      }
    }
    // A press is the hand too (2026-11-25, the mouse pass): a click on a
    // control the pointer already rested on, just after typing, moved
    // nothing, so a pane the click changed to warped the pointer out from
    // under the hand. Over everything and taking no press, so every click
    // still reaches what it was on.
    Item {
      anchors.fill: parent
      z: 10000
      PointHandler {
        acceptedButtons: Qt.AllButtons
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onActiveChanged: if (active) { root.handMovedAt = Date.now(); root.handOn = true; root.pressedAt(point.scenePosition) }
      }
      // Ctrl and the wheel: the page larger or smaller, as Ctrl+= and
      // Ctrl+- (2026-11-25, the mouse pass), wherever the pointer is. It
      // did three things: the PDF's zoom, the sidebar's spaces, and a plain
      // scroll everywhere else. Over a PDF it sizes the PDF's pages (its
      // own wheel); beside one, the page still (the second pass: with a PDF
      // open it did nothing over the panes).
      WheelHandler {
        id: zoomWheel
        target: null
        acceptedModifiers: Qt.ControlModifier
        property real travel: 0
        onWheel: function (ev) {
          // Over a PDF's pages, the PDF's size; over a box above them (the
          // switcher, the PDF's own find or note), the page's, as everywhere
          // off the pages (the third pass: it sized the PDF under the box).
          if (root.pdfShown && pdfPane.visible) {
            var q = pdfPane.mapFromItem(parent, ev.x, ev.y)
            var sw = switcherBox.mapFromItem(parent, ev.x, ev.y)
            var overSwitcher = switcherBox.visible && sw.x >= 0 && sw.y >= 0 && sw.x < switcherBox.width && sw.y < switcherBox.height
            if (!overSwitcher && q.x >= 0 && q.y >= 0 && q.x < pdfPane.width && q.y < pdfPane.height && !pdfPane.overBox(q.x, q.y)) {
              pdfPane.wheel(ev); return
            }
          }
          var d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.pixelDelta.y * 4
          if ((d > 0) !== (zoomWheel.travel > 0)) zoomWheel.travel = 0
          zoomWheel.travel += d
          if (Math.abs(zoomWheel.travel) < 120) return
          root.zoomBy(zoomWheel.travel > 0 ? 1 : -1)
          zoomWheel.travel = 0
        }
      }
      // The mouse's own back and forward buttons, as the keys' back and
      // forward (2026-11-25, the mouse pass): in a PDF, back from a jump
      // in it first, as its Alt+← does.
      TapHandler {
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        gesturePolicy: TapHandler.WithinBounds
        onTapped: function (point, button) {
          if (button === Qt.BackButton && root.pdfShown && pdfPane.jumpBack) { pdfPane.jumpReturn(); return }
          root.goBack(button === Qt.BackButton ? -1 : 1)
        }
      }
    }
  }
}
