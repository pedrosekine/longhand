import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import qs.Ui
import "Blocks.js" as Blocks
import "Bound.js" as Bound
import "Dates.js" as Dates
import "Days.js" as Days
import "Task.js" as Task
import "Authorship.js" as Authorship
import "Threads.js" as Threads
import "Tags.js" as Tags
import "Shortcuts.js" as Sc
import "Layout.js" as Layout
import "Links.js" as Links

// The page: today's note as a blank sheet in the shell, with the agent in
// the margin. Two shapes of the same sheet: the overlay (a layer over
// everything, Esc leaves) and alongside (a normal Hyprland window you tile
// next to slides or a PDF; Esc does nothing there). F11 pins the overlay
// into a window and back; the pin mark in the header says which you are in.
//
// Where the keys are, and how they move between the sidebar, the middle and
// the agent's pane, is docs/navigation.md (and "panes", below).
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
// the cursor back where it was. Ctrl+T opens the dashboard: every open checkbox
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
  function needIndex() {
    if (root.vaultIndex !== null || indexProc.running || !svc.configured) return
    indexProc.command = ["find", svc.config.vault, "-name", ".*", "-prune", "-o", "-type", "f", "-regextype", "posix-extended",
                         "-iregex", ".*\\.(md|png|jpe?g|gif|webp|bmp|svg|avif)", "-print"]
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
    return { stem: svc.noteDate, file: svc.filePath, readOnly: svc.readOnly, at: editor.cursorPosition, pdf: root.pdfRel }
  }
  function goTo(place) {
    if (place.pdf) { root.openPdf(place.pdf); return }
    root.pdfRel = ""
    root.pendingLink = { at: place.at }
    if (place.stem !== "") { if (place.stem === svc.noteDate) root.landOnLink(); else root.openNote(place.stem) }
    else if (place.file === svc.filePath) root.landOnLink()
    else root.openFile(place.file, place.readOnly)
    root.showNote()
  }
  function followLink(l) {
    root.used("link", l.url ? "web" : l.kind)
    if (l.url) { Qt.openUrlExternally(l.url); return }
    if (l.target === "") { root.pendingLink = { heading: l.heading }; root.landOnLink(); return }
    if (root.vaultIndex === null) { root.needIndex(); root.showHint("reading the vault's names…"); return }
    var rel = Links.resolve(root.vaultIndex, l.target, root.noteRel, l.kind !== "md")
    if (rel === "") { root.showHint("no note “" + l.target + "” in the vault"); return }
    if (/\.pdf$/i.test(rel)) {
      root.backStack = root.backStack.concat([root.placeNow()]).slice(-50)
      root.foreStack = []
      root.openPdf(rel)
      return
    }
    if (!/\.md$/i.test(rel)) { Qt.openUrlExternally("file://" + (svc.config.vault + "/" + rel).split("/").map(encodeURIComponent).join("/")); return }
    root.backStack = root.backStack.concat([root.placeNow()]).slice(-50)
    root.foreStack = []
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
    sizeProc.command = ["file", "-b", "-L", "--"].concat(batch.map(function (u) { return decodeURIComponent(u.replace(/^file:\/\//, "")) }))
    sizeProc.running = true
  }

  // A picture's file url, "" when the vault has none such, "?" while the
  // index is still being read.
  function resolveImage(target, wiki) {
    if (!svc.configured) return ""
    if (root.vaultIndex === null) { root.needIndex(); return "?" }
    var rel = Links.resolve(root.vaultIndex, target, root.noteRel, wiki)
    if (rel === "") return ""
    return "file://" + (svc.config.vault + "/" + rel).split("/").map(encodeURIComponent).join("/")
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
  readonly property alias dashItem: dash
  readonly property alias marginItem: margin
  property bool overlayOpen: false
  property bool windowOpen: false
  readonly property bool opened: overlayOpen          // what the shell's toggle asks
  readonly property bool showing: overlayOpen || windowOpen
  readonly property bool alongside: !overlayOpen      // where the sheet is drawn

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
  readonly property color accent: pal.accent
  readonly property color dim: pal.dim
  readonly property color faint: pal.faint
  readonly property color urgent: pal.red
  readonly property color magenta: pal.magenta       // private things' lock
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
  // The overlay's sheet has a border, inside which the padding starts:
  // without it the overlay held 71½ characters, and a line of 72 wrapped
  // there and not in the window (found by run.py --overlay, 2026-10-25).
  readonly property int sheetFor: root.measure + 2 * root.sheetPadding
    + (root.alongside ? 0 : Math.ceil(Border.left(root.borderSpec) + Border.right(root.borderSpec)))
  // Where the note sits: one rule for both shapes and both sides
  // (Layout.js, 2026-10-24) — centred, and a pane opening at the window's
  // edge does not move it while there is room for both. Until then the window
  // recentred the note in the room the sidebar left (so the sidebar pushed
  // it and the right pane did not), and on the overlay the right pane
  // shrank instead. Stepping aside slides (`sheet`'s x).
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
  readonly property int rightSpace: (root.marginOpen && !root.wideOpen) || root.dayBesideNote ? root.marginWidth + root.marginGap : 0
  readonly property var notePlace: Layout.note(content.width, root.sheetFor, root.edge, root.sideSpace, root.rightSpace)
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
  // The right pane beside the note: the sidebar's kind of width, the same
  // in both shapes; a narrow window narrows the note, not the pane.
  // It takes the room the note leaves, up to a width a conversation reads
  // well at (2026-10-25: at 300 it held five words a line); never less
  // than before, so a narrow window still narrows the note first.
  readonly property int marginWidth: Math.max(0, Math.min(Math.round(content.width * 0.45),
    Math.max(root.sp(300), Math.min(root.sp(440), content.width - 2 * root.edge - root.sheetFor - root.marginGap - root.sideSpace))))

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
  // A PDF in the middle, in the note's place (PdfPane.qml, step 5): the note
  // stays loaded under it, and Esc goes back to it.
  property string pdfRel: ""
  readonly property bool pdfShown: root.pdfRel !== ""

  // How private looks (docs/files.md, B · Paper, chosen 2026-10-27): what
  // the agent may not see is sunk into a darker paper — a private block as
  // an inset of it with a lock in the gutter, the agent's lane; a private
  // day, or a day before the horizon, as the whole sheet. An answer keeps
  // its solid bar in the gutter, so private and answered never share a look.
  readonly property color sunk: pal.sunk
  readonly property bool sheetSunk: svc.ready && !root.pdfShown && (svc.notePrivate || root.beforeHorizon)
  readonly property color sheetColor: root.sheetSunk ? root.sunk : root.background
  property var privatePaint: []         // [{ y, h }]: the private blocks, in editor coordinates
  function openPdf(rel) {
    if (rel === "") return
    if (root.searchOpen) root.closeSearch("back")
    root.leftLine(root.lastLine)
    root.flush()
    root.used("pdf", "open")
    root.marginOpen = false
    root.closeTalk(false)
    root.dayOpen = false
    root.noteRoom = false
    root.dashOpen = false
    root.marginFocus = -1
    root.pdfRel = rel
    root.showNote()
  }
  function closePdf() {
    if (!root.pdfShown) return
    root.pdfRel = ""
    root.showNote()
  }
  // The header's name for what is in the sheet: the day, or the file's
  // name (where it is, the Files tree shows).
  readonly property string noteLabel: root.pdfShown ? root.pdfRel.replace(/^.*\//, "")
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
    if (horizonProc.running || !svc.configured) return
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
    if (!svc.ready || !root.dayNote) return
    var on = !svc.notePrivate
    svc.setPrivate(on)
    root.flush()
    root.used("private", on ? "on" : "off")
    root.showHint(on ? "private — the agent sees nothing in this note" : "the agent can be asked about this note again")
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
    root.sidebarSpace = name
    root.used("space", name)
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
  // Whose turn (2026-10-23): what the agent proposed since the dashboard was
  // last left is new until it is left again. By the ledger's ids, which
  // only grow — not by `at`, which is when a plan began, so a plan that
  // ends after the dashboard was left would never be new.
  property int dashSeenId: 0         // the highest id on the list when the dashboard was last left
  property int newAfterId: 0         // …as it was when this visit began
  onDashOpenChanged: {
    if (root.dashOpen) { root.newAfterId = root.dashSeenId; return }
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
  property bool projectOpen: false   // the margin is showing one project's notes
  property var sections: []          // [{ date, line, heading, title, sub, preview, open, done }]
  property string projectTag: ""
  property string projectName: ""
  property int sectionFocus: 0
  // The project's filed documents above its sections (docs/agent.md, slice
  // 4): -1 while the keys are on the sections, else the document picked.
  property int docFocus: -1
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

  // The day conversation (docs/agent.md, "The day conversation",
  // 2026-10-21): the student talks to the day, not to a line, in the right
  // pane — from anywhere (Ctrl+J), from a block pointing at it
  // (Ctrl+Shift+Enter), or by the seal. The day is the pane's home: a
  // block's or a task's conversation is a room stepped into on purpose, and
  // leaving it comes back here. The open note's day is shown (a past day's,
  // read-only); only today's is talked in.
  property bool dayOpen: false
  property string dayBlock: ""          // a block pointed at, going with the next message
  property string dayBlockText: ""
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
  readonly property bool noteAskable: svc.ready && root.noteRel !== "" && (!root.dayNote || root.beforeHorizon || svc.notePrivate)
  readonly property string noteTalkPath: svc.agentDir !== "" && root.noteRel !== ""
    ? svc.agentDir + "/notes/" + Qt.md5(root.noteRel).slice(0, 16) + ".json" : ""
  property var noteTalk: null
  onNoteTalkPathChanged: if (root.noteTalkPath === "") root.noteTalk = null
  readonly property int noteTalkTurns: root.noteTalk && root.noteTalk.turns ? root.noteTalk.turns.length : 0

  readonly property var dayState: root.noteRoom ? root.noteTalk : agent.state && agent.state.day ? agent.state.day : null
  readonly property var dayTurns: {
    var t = root.dayState && root.dayState.turns ? root.dayState.turns.slice() : []
    if (root.dayPending && (svc.isToday || root.noteRoom)) t.push({ role: "student", text: root.dayPending.text, block: root.dayPending.block })
    return t
  }
  // The morning's observation is the conversation's opening line, waiting.
  readonly property var dayOpening: {
    if (root.noteRoom) return []
    var obs = agent.state && agent.state.observations ? agent.state.observations : []
    return obs.filter(function (o) { return o && o.text && o.trigger === "open" }).map(function (o) { return o.text })
  }
  readonly property string roomHash: root.noteRoom ? "note" : "day"
  readonly property bool dayThinking: root.runningHash === root.roomHash
    || root.queued.some(function (q) { return q.hash === root.roomHash })
  readonly property bool dayCanSend: root.noteRoom ? root.noteAskable : svc.isToday && root.agentDay && !root.beforeHorizon
  readonly property bool dayShown: root.dayOpen && !root.marginOpen && !root.talkOpen && !root.keysOpen && !root.settingsOpen
  readonly property bool dayBesideNote: root.dayShown && !root.dashOpen
  readonly property bool dayBesideDash: root.dayShown && root.dashOpen

  function toggleDay(block) {
    if (root.dayShown && block === "") { root.closeDay(); return }
    root.openDay(block)
  }

  // A file has no day: its pane is its own conversation.
  function openDay(block) {
    root.openRoom(block, !root.dayNote)
  }

  // "ask about this note" in the header, and the agent's pane on a file.
  function openRoom(block, note) {
    note = !!note
    if (note && !root.noteAskable) return
    if (root.here !== "right") root.noteFrom("right", root.keysOpen || root.settingsOpen ? "center" : root.here)
    if (root.keysOpen) root.toggleKeys()
    if (root.settingsOpen) root.toggleSettings()
    root.marginOpen = false
    root.marginFocus = -1
    root.closeTalk(false)
    if (note !== root.noteRoom) { root.dayPending = null; root.dayBlock = ""; root.dayBlockText = "" }
    root.noteRoom = !!note
    root.dayOpen = true
    if (block) {
      var b = root.blockBounds(block)
      root.dayBlock = b ? block : ""
      root.dayBlockText = b ? b.text.split("\n")[0].replace(/^\s*([-*+] (\[.\] )?|#+ )/, "").slice(0, 80) : ""
    }
    root.used(note ? "note-talk" : "day", block ? "block" : "")
    Qt.callLater(function () { dayPane.dayFieldRef.forceActiveFocus() })
  }

  function dayFieldItem() { return dayPane.dayFieldRef }

  // A block's first words, for the "↳" a message carries; "a block" when
  // the note no longer has it as it was.
  function blockHead(hash) {
    var b = root.blockBounds(hash)
    return b ? b.text.split("\n")[0].replace(/^\s*([-*+] (\[.\] )?|#+ )/, "").slice(0, 80) : "a block"
  }

  function closeDay() {
    var was = root.here
    root.dayOpen = false
    root.noteRoom = false
    root.dayBlock = ""
    root.dayBlockText = ""
    root.giveBack("right", was, "right")
  }

  function sendDay(text) {
    var msg = String(text || "").trim()
    if (msg === "" || !root.dayCanSend) return false
    var cmd = root.noteRoom ? [svc.runner, "note", "--file", root.noteRel, "--message", msg] : [svc.runner, "day", "--message", msg]
    if (root.dayBlock !== "") cmd = cmd.concat(["--block", root.dayBlock])
    root.dayPending = { text: msg, block: root.dayBlock }
    root.dayBlock = ""
    root.dayBlockText = ""
    root.flush()
    root.enqueue(cmd, root.roomHash)
    root.used(root.noteRoom ? "note-talk" : "day", "send")
    return true
  }

  // The runner has written the turn the page was holding.
  function settleDay() {
    var p = root.dayPending
    if (!p || !root.dayState) return
    var turns = root.dayState.turns || []
    for (var i = turns.length - 1; i >= 0; i--)
      if (turns[i].role === "student" && turns[i].text === p.text) { root.dayPending = null; return }
  }

  // `@` in the day's box points at a block of the open note, as `@` in the
  // note calls a project: the list narrows as you type, newest writing
  // first, never a private block; Enter or Tab makes it the "↳" the next
  // message carries.
  property var dayMention: null         // { start, query, items: [{ hash, head }] }
  property int dayMentionFocus: 0
  function updateDayMention() {
    var f = dayPane.dayFieldRef
    var m = f.text.substring(0, f.cursorPosition).match(/(^|\s)@([^\s@]*)$/)
    if (!m || !root.dayCanSend) { root.dayMention = null; return }
    var q = m[2].toLowerCase()
    var items = Blocks.split(editor.text).filter(function (b) {
      return !b.private && b.kind !== "frontmatter" && b.text.trim() !== "" && (q === "" || b.text.toLowerCase().indexOf(q) >= 0)
    }).reverse().slice(0, 8).map(function (b) { return { hash: b.hash, head: root.blockHead(b.hash) } })
    root.dayMention = { start: f.cursorPosition - m[2].length - 1, query: m[2], items: items }
    if (root.dayMentionFocus > items.length - 1) root.dayMentionFocus = Math.max(0, items.length - 1)
  }
  function pickDayMention(i) {
    var m = root.dayMention
    var it = m && m.items[i]
    if (!it) return
    var f = dayPane.dayFieldRef
    f.remove(m.start, f.cursorPosition)
    root.dayBlock = it.hash
    root.dayBlockText = it.head
    root.dayMention = null
    root.used("day", "at")
  }

  // The cards under the day's answers (slice 3): what it proposed, the
  // same items as the dashboard's rows, checked and recorded by the runner.
  // A card is open while the dashboard still has its item; once settled —
  // here, on its row, or by a plan since — it stays, faint, saying how.
  property var dayCardSettled: ({})     // id -> "accepted" | "declined" | "undone" | "kept"
  property int dayCardFocus: -1         // which open card the keys act on; -1: the box
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
              "drop": "drop it", "done": "looks done", "project": "a new project" })[x.kind] || x.kind
  }
  // What a card says beside its pill: the box, and what changes in it.
  function dayCardFacts(x) {
    if (x.kind === "priority") return (x.priority === 2 ? "▲ high" : x.priority === 1 ? "medium" : "▽ low") + " · " + (x.title || "")
    if (x.kind === "steps") return (x.title || "") + (x.steps || []).map(function (s, i) { return "\n" + (i + 1) + ". " + s }).join("")
    if (x.kind === "project") return (x.title || "") + " #" + x.project
    return x.title || ""
  }
  function dayCardPill(x) {
    return x.kind === "do-date" && x.date ? "do " + root.sayDate(x.date)
      : x.kind === "deadline" && x.date ? "📅 " + root.sayDate(x.date) : ""
  }
  function settleDayCard(i, how) {
    var p = root.dayOpenCards[i]
    if (!p) return
    var s = {}
    for (var k in root.dayCardSettled) s[k] = root.dayCardSettled[k]
    if (how === "accept" && p.told) {
      root.resolveProposal(p, "accept", "")              // what it did on its own: let it stand
      s[p.id] = "kept"
    } else if (how === "accept") {
      // Written by the page, the one writer of notes, as from its row; a
      // box no longer on the list leaves the card open, and says so.
      if (!root.applyProposal(p, root.taskOfKey(p.key))) return
      root.resolveProposal(p, "accept", "")
      s[p.id] = "accepted"
    } else if (p.told) {
      root.undoProposal(p)
      s[p.id] = "undone"
    } else {
      root.resolveProposal(p, "decline", "")
      s[p.id] = "declined"
    }
    root.dayCardSettled = s
    root.used("day", "card-" + how)
    Qt.callLater(function () {
      var n = root.dayOpenCards.length
      root.dayCardFocus = n === 0 ? -1 : Math.min(root.dayCardFocus, n - 1)
    })
  }

  // The student's word on an answer in the day's conversation, as on a
  // reply in the margin: shown at once, kept on the turn by the runner with
  // the prompt and model that made it, read by the weekly review.
  property var dayRatingNow: ({})       // "<note date>#<turn>" -> "up" | "down" | "none", until the state says so
  function dayRatingOf(i) {
    var now = root.dayRatingNow[svc.noteDate + "#" + i]
    if (now !== undefined) return now === "none" ? "" : now
    var t = root.dayState && root.dayState.turns ? root.dayState.turns[i] : null
    return t && t.rating ? t.rating.value : ""
  }
  function rateDay(i, value) {
    if (root.noteRoom) return
    var turns = root.dayState && root.dayState.turns ? root.dayState.turns : []
    if (i < 0) for (var k = turns.length - 1; k >= 0 && i < 0; k--) if (turns[k].role === "agent" && !turns[k].error) i = k
    if (i < 0 || !turns[i] || turns[i].role !== "agent" || turns[i].error) return
    var v = root.dayRatingOf(i) === value ? "none" : value
    var m = {}
    for (var j in root.dayRatingNow) m[j] = root.dayRatingNow[j]
    m[svc.noteDate + "#" + i] = v
    root.dayRatingNow = m
    root.runInTurn(rateProc, [svc.runner, "rate", v, "--day", String(i), "--date", svc.noteDate])
    root.used("rate", "day-" + v)
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
  function copyChatSelection(event, box) {
    if (event.key !== Qt.Key_C || (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier)) !== Qt.ControlModifier) return false
    if (box && box.selectedText !== "") return false
    var s = root.chatSelection
    if (!s || s.selectedText === "") return false
    s.copy()
    return true
  }

  function dayKey(event) {
    if (root.copyChatSelection(event, dayPane.dayFieldRef)) return true
    if (Sc.hit(event, "dayHelpful")) { root.rateDay(-1, "up"); return true }
    if (Sc.hit(event, "dayNotHelpful")) { root.rateDay(-1, "down"); return true }
    // On the cards: ↑↓ between them, Enter or Space does what one says, Del
    // declines it (a thing done by itself: undoes it), Esc or ↓ past the
    // last goes back to the box; typing goes back too.
    if (root.dayCardFocus >= 0) {
      var n = root.dayOpenCards.length
      if (n === 0) root.dayCardFocus = -1
      else {
        if (Sc.hit(event, "marginUp")) { root.dayCardFocus = Math.max(0, root.dayCardFocus - 1); return true }
        if (Sc.hit(event, "marginDown")) { root.dayCardFocus = root.dayCardFocus >= n - 1 ? -1 : root.dayCardFocus + 1; return true }
        if (Sc.hit(event, "marginAccept")) { root.settleDayCard(root.dayCardFocus, "accept"); return true }
        if (Sc.hit(event, "marginDecline")) { root.settleDayCard(root.dayCardFocus, "decline"); return true }
        if (Sc.hit(event, "marginBack")) { root.dayCardFocus = -1; return true }
        root.dayCardFocus = -1
      }
    } else if (Sc.hit(event, "marginUp") && dayPane.dayFieldRef.text === "" && !root.dayMention && root.dayOpenCards.length > 0) {
      root.dayCardFocus = root.dayOpenCards.length - 1
      return true
    }
    if (root.dayMention && root.dayMention.items.length > 0) {
      if (Sc.hit(event, "mentionUp")) { root.dayMentionFocus = Math.max(0, root.dayMentionFocus - 1); return true }
      if (Sc.hit(event, "mentionDown")) { root.dayMentionFocus = Math.min(root.dayMention.items.length - 1, root.dayMentionFocus + 1); return true }
      if (Sc.hit(event, "mentionPick") || Sc.hit(event, "mentionClass")) { root.pickDayMention(root.dayMentionFocus); return true }
      if (Sc.hit(event, "mentionClose")) { root.dayMention = null; return true }
    }
    if (root.anywhereKey(event)) return true
    if (Sc.hit(event, "marginBack")) { root.closeDay(); return true }
    if (Sc.hit(event, "chatSend")) { if (root.sendDay(dayPane.dayFieldRef.text)) dayPane.dayFieldRef.text = ""; return true }
    // Backspace in an empty box lets go of the block pointed at.
    if (event.key === Qt.Key_Backspace && dayPane.dayFieldRef.text === "" && root.dayBlock !== "") {
      root.dayBlock = ""; root.dayBlockText = ""; return true
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
    if (root.pendingTalk && root.pendingTalk.thread === root.talkThread) t.push({ role: "student", text: root.pendingTalk.text })
    return t
  }
  // Where a message goes: to the planner while the conversation is about
  // one of its proposals not yet settled — also in the moment after a
  // revision, before the list is read again; else to the margin, about the
  // task's block.
  readonly property bool talkToPlanner: root.talkId >= 0 && root.talkSettled === ""
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
  // A block's conversation: under its own hash; else found by its words
  // (a tick, a date, a priority leave them); else the one its lines carry
  // through an edit of its words (Threads.js).
  function recordHash(hash, text, block) {
    if (hash === "" || root.answered(agent.record(hash))) return hash
    var byWords = root.recordKeys[Blocks.fnv1a(Task.identity(text))]
    if (byWords) return byWords
    var carried = Threads.find(root.threadMap, block)
    return carried !== "" && root.answered(agent.record(carried)) ? carried : hash
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
      turns.push({ role: "student", text: root.pendingChat.text })
    return turns
  }
  // This block is away: asked and not back. `runningHash` can name a whole
  // list submission.
  readonly property bool answering: root.currentHash !== ""
    && (root.runningHash.split(",").indexOf(root.currentHash) >= 0
        || root.runningHash.split(",").indexOf(root.currentRec) >= 0
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
    return (m ? m.title : p.title) + ((p.project || p.subject) && !m ? " · " + (p.project || p.subject) : "")
  }
  // The day as the page says days ("Fri 20 Nov", "tomorrow"); words the
  // agent wrote that are not a date ("friday") as written.
  function marginCardPill(p) {
    var when = /^\d{4}-\d{2}-\d{2}( \d{1,2}:\d{2})?$/.test(p.when || "") ? root.sayDate(p.when) : p.when
    return p.moves ? Qt.formatDate(new Date(p.moves.due * 1000), "ddd d MMM") + " → " + when : "📅 " + when
  }
  readonly property var taskRows: root.buildTaskRows()
  // The dashboard's cursor stays on the same row when the list is drawn
  // again — rows added above it (a plan, the agent's steps) must not move
  // the next key onto another row. Only when its row is gone does the
  // cursor keep its place in the list.
  property string taskFocusKey: ""
  onTaskFocusChanged: root.taskFocusKey = root.rowKey(root.taskRows[root.taskFocus])
  onTaskRowsChanged: {
    if (root.taskFocusKey === "") return
    for (var i = 0; i < root.taskRows.length; i++) {
      if (root.rowKey(root.taskRows[i]) === root.taskFocusKey) {
        if (i !== root.taskFocus) root.taskFocus = i
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
    } else {
      root.overlayOpen = true
    }
    if (fresh) {
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
    root.savePageState()
    root.scheduleRepaint()
  }

  function savePageState() {
    zoomFile.setText(JSON.stringify({ zoom: root.zoom, dashSeen: root.dashSeenId, chatSeen: root.chatSeen }) + "\n")
  }

  // The global keys: the page itself and where you are in it, wherever the
  // keyboard is — every place's handler asks this first, a box you type in
  // too. Every key the page answers to is named in Shortcuts.js, where the
  // student can move it (the keys sheet, below); the ones read here are
  // its "any" place.
  function anywhereKey(event) {
    if (Sc.hit(event, "zoomIn")) { root.zoomBy(1); return true }
    if (Sc.hit(event, "zoomOut")) { root.zoomBy(-1); return true }
    if (Sc.hit(event, "zoomReset")) { root.setZoom(1); return true }
    if (Sc.hit(event, "keys")) { root.toggleKeys(); return true }
    if (Sc.hit(event, "settings")) { root.toggleSettings(); return true }
    if (Sc.hit(event, "pane1")) { root.paneKey("left"); return true }
    if (Sc.hit(event, "pane2")) { root.paneKey("center"); return true }
    if (Sc.hit(event, "pane3")) { root.paneKey("right"); return true }
    if (Sc.hit(event, "sidebar")) { root.toggleSidebar(); return true }
    if (Sc.hit(event, "dayChat")) { root.openDay(""); return true }
    if (Sc.hit(event, "linkBack")) { root.goBack(-1); return true }
    if (Sc.hit(event, "linkForward")) { root.goBack(1); return true }
    if (Sc.hit(event, "day")) { root.toggleRight(); return true }
    if (Sc.hit(event, "paneLeft")) { root.movePane(-1); return true }
    if (Sc.hit(event, "paneRight")) { root.movePane(1); return true }
    if (Sc.hit(event, "today")) { root.goToday(); return true }
    if (Sc.hit(event, "pin")) { root.togglePin(); return true }
    return false
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
    if (root.dayShown) what = root.dayBlock !== "" ? root.dayBlock : (root.noteRoom || (svc.isToday && root.agentOn)) ? "sheet" : ""
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
    : margin.marginKeysRef.activeFocus || margin.chatFieldRef.activeFocus || dayPane.dayFieldRef.activeFocus ? "right"
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
      if (root.addingProject) sidebar.projectFieldRef.forceActiveFocus()
      else sidebar.sidebarKeysRef.forceActiveFocus()
      return true
    }
    if (p === "right") {
      var v = root.rightView
      if (v === "") return false
      if (v === "day") dayPane.dayFieldRef.forceActiveFocus()
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
      else settingsSheet.settingsFieldRef.forceActiveFocus()
    } else if (v === "dash") (root.dashWhenFor ? dash.dashWhenFieldRef : dash.dashKeysRef).forceActiveFocus()
    else if (root.searchOpen) searchField.forceActiveFocus()
    else if (root.whenFor) whenField.forceActiveFocus()
    else if (root.newProject) nameField.forceActiveFocus()
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
      else if (root.rightView === "day") root.openThisChat()
      else root.openDay("")
      return
    }
    if (root.here !== "center") root.focusCenter()
    else if (root.keysOpen) root.toggleKeys()
    else if (root.settingsOpen) root.toggleSettings()
    else root.toggleDash()
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
        && root.currentHash !== "" && root.marginWidth > 0) { root.diveIn(); return }
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
  // active one. `pointer` in settings.json: "every" (the default), "panes",
  // "off".
  readonly property string pointerMode: ["every", "panes", "off"].indexOf(root.settingsData.pointer) >= 0 ? root.settingsData.pointer : "every"
  property var marks: ({})          // pane -> the item selected in it, as rows say (`selected`)
  property real handMovedAt: 0      // the student's own pointer, last moved
  property real warpedAt: 0

  // A row the keys come to says so (`on`), and again when they leave it;
  // the pointer goes to it while its pane has the keys.
  function selected(item, pane, on) {
    if (on) root.marks[pane] = item
    else if (root.marks[pane] === item) delete root.marks[pane]
    else return
    if (root.pointerMode === "every" && pane === root.here) warpTimer.restart()
  }

  onHereChanged: {
    if (root.pointerMode !== "off") warpTimer.restart()
    if (root.hereWas === "center" && root.here === "right") Qt.callLater(root.blipContext)
    root.hereWas = root.here
  }
  onCenterViewChanged: if (root.pointerMode !== "off") warpTimer.restart()
  onRightViewChanged: if (root.pointerMode !== "off" && root.here === "right") warpTimer.restart()

  // What the pointer goes to in the pane with the keys: the row selected,
  // the note's cursor, the box typed in; at worst the pane itself.
  function pointerTarget() {
    var pane = root.here
    if (pane === "center" && root.centerView === "note" && !root.searchOpen && !root.whenFor && !root.newProject) {
      var r = editor.cursorRect
      var at = editor.mapToItem(content, r.x + root.sp(14), r.y + r.height / 2)
      return { x: at.x, y: at.y, w: root.sp(28), h: r.height }
    }
    var it = root.marks[pane]
    var ok = false
    try { ok = !!it && it.visible && it.width > 0 && root.paneOf(it) === pane } catch (e) { ok = false }
    // No row: the box being typed in, else the pane itself (its middle,
    // as Hyprland's warp goes to a window's).
    if (!ok) it = root.boxes().filter(function (b) { return b.activeFocus })[0] || root.paneItem(pane)
    if (!it) return null
    var c = it.mapToItem(content, Math.min(it.width / 2, root.sp(160)), it.height / 2)
    return { x: c.x, y: c.y, w: Math.min(it.width, root.sp(320)), h: it.height }
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
      : root.settingsView === "search" ? searchSheet : settingsSheet
    return sheet
  }

  function warpNow() {
    if (!root.showing || root.pointerMode === "off") return
    if (Date.now() - root.handMovedAt < 700) return
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
    var order = ["every", "panes", "off"]
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
    root.dayBlock = ""
    root.dayBlockText = ""
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

  property string hint: ""   // a passing word (a date that did not read, what a check did, …)
  // What the page says in passing, in the header's status line. It used to
  // float under the cursor and print over the line below it (2026-10-17);
  // up there it covers nothing, so it can stay long enough to be read.
  readonly property string status: root.hint
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

  // Ctrl+Enter, and the header's "chat": this block's chat. A block with a
  // sign for the agent (a checkbox, a closing ?, a tick) is sent, and the
  // agent speaks first; any other block opens its chat with the box ready,
  // and you do (2026-10-27: a block without a sign used to be refused, while
  // Alt+→ opened the same chat). One answered already is not asked again.
  function sendCurrent() {
    if (root.currentHash === "" || !root.dayNote) return
    if (!root.agentOn) { root.showHint("private: the agent sees nothing of this note"); return }
    if (root.blockPrivate(root.currentHash)) { root.showHint("private: the agent sees nothing of this block"); return }
    if (root.answered(root.currentRecord)) { root.openBlockChat("reopen"); return }
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

  function openBlockChat(how) {
    if (root.marginWidth <= 0) { root.showHint("the window is too narrow for the chat"); return }
    root.used(how === "reopen" ? "reopen" : "chat", how)
    root.diveIn(true)
  }

  function blockPrivate(hash) {
    var blocks = Blocks.split(editor.text)
    for (var i = 0; i < blocks.length; i++) if (blocks[i].hash === hash) return !!blocks[i].private
    return false
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
      var rec = agent.record(root.recordHash(b.hash, b.text, b))
      var flying = root.sending.indexOf(b.hash) >= 0
      if (!rec && !flying) continue
      var r = editor.blockRect(b.start, b.end)
      if (!r) continue
      out.push({ hash: b.hash, y: r.y, h: r.h, sending: flying,
                 reply: !!rec && rec.state === "reply",
                 unread: !!rec && rec.state === "reply" && !rec.read })
    }
    root.paint = out
    var priv = []
    for (var k = 0; k < blocks.length; k++) {
      if (!blocks[k].private || blocks[k].kind !== "callout") continue
      var pr = editor.blockRect(blocks[k].start, blocks[k].end)
      if (pr) priv.push({ y: pr.y, h: pr.h })
    }
    root.privatePaint = priv
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
    editor.remove(m.start, to)
    if (shift && m.atLineStart) {
      editor.insert(m.start, "# " + (pr.name || pr.tag) + " #" + pr.tag)
      root.used("mention", "class")
    } else {
      editor.insert(m.start, "#" + pr.tag + " ")
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
    if (Sc.hit(event, "close")) { if (!root.alongside) root.dismiss(); return true }
    if (Sc.hit(event, "private")) { root.togglePrivate(); return true }
    if (Sc.hit(event, "privateBlock")) { root.togglePrivateBlock(); return true }
    if (Sc.hit(event, "ask")) { root.sendCurrent(); return true }
    // Selecting to the same edges is the editor's (selectToBlockEdge).
    if (Sc.hit(event, "blockStart")) { root.walkBlocks(-1); return true }
    if (Sc.hit(event, "blockEnd")) { root.walkBlocks(1); return true }
    if (Sc.hit(event, "dayPrev")) { root.stepDay(-1); return true }
    if (Sc.hit(event, "dayNext")) { root.stepDay(1); return true }
    if (Sc.hit(event, "find")) { root.openSearch(); return true }
    if (Sc.hit(event, "followLink")) { var l = editor.linkAtCursor(); if (l) root.followLink(l); else root.showHint("no link here"); return true }
    // Emphasis, where every editor puts it. The sidebar moved to the
    // shifted pair on 2026-10-15 so that Ctrl+B could be bold.
    if (Sc.hit(event, "bold")) { editor.emphasise("**"); return true }
    if (Sc.hit(event, "italic")) { editor.emphasise("*"); return true }
    if (Sc.hit(event, "code")) { editor.emphasise("`"); return true }
    if (Sc.hit(event, "strike")) { editor.emphasise("~~"); return true }
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
    if (root.here !== "right") root.noteFrom("right")
    root.marginOpen = true
    if (root.currentProposals.length > 0 && toChat !== true) {
      root.marginFocus = 0
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
    if (was === "right" && root.rightView === "day") dayPane.dayFieldRef.forceActiveFocus()
    else root.giveBack("right", was, "right")
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
      if (!agentChecksProc.running) {
        agentChecksProc.command = [svc.runner, "eval", "status", "--json"]
        agentChecksProc.running = true
      }
      Qt.callLater(settingsSheet.settingsFieldRef.forceActiveFocus)
    } else {
      root.giveBack("settings", was, "center")
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
    if (Sc.hit(event, "settingsPointer")) { root.cyclePointer(); return true }
    if (Sc.hit(event, "settingsNotebook")) { root.openNotebook(); return true }
    if (Sc.hit(event, "settingsAutonomy")) { root.openAutonomy(); return true }
    if (Sc.hit(event, "settingsSearch")) { root.openSearchFolders(); return true }
    return false
  }

  // What the agent may do (Settings → The agent, Ctrl+M; docs/agent.md,
  // "Actions, and how far each may go"): each kind at ask me, do it and
  // tell me, or never — the person's to set, kept in settings.json — with
  // its record, and past 9 of the last 10 accepted, the suggestion that it
  // could do more. Nothing is ever raised but by the person.
  property var autonomyData: null          // `longhand-agent autonomy`
  property int autonomyFocus: 0
  readonly property var autonomyLevels: ["ask", "do", "never"]

  function loadAutonomy() {
    if (autonomyProc.running || !svc.configured) return
    autonomyProc.command = [svc.runner, "autonomy"]
    autonomyProc.running = true
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
    if (seq === "Up") { root.autonomyFocus = Math.max(0, root.autonomyFocus - 1); return true }
    if (seq === "Down") { root.autonomyFocus = Math.max(0, Math.min(n - 1, root.autonomyFocus + 1)); return true }
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

  // What the agent may search (Settings, Ctrl+F; docs/agent.md, "The day
  // conversation"): each folder of the vault, on or off, the student's to
  // set in settings.json (`searchFolders`). Private notes and blocks,
  // `_Secrets`, other types and documents of identity, money, health,
  // contracts or secrets are never searched, whatever is switched on.
  property var searchData: null         // `longhand-agent search --folders`
  property int searchFocus: 0

  function loadSearchFolders() {
    if (searchFoldersProc.running || !svc.configured) return
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
    if (seq === "Up") { root.searchFocus = Math.max(-1, root.searchFocus - 1); return true }
    if (seq === "Down") { root.searchFocus = Math.max(-1, Math.min(n - 1, root.searchFocus + 1)); return true }
    if (root.searchFocus < 0) {
      if (seq === "Left" || seq === "Right") { root.moveHorizon(seq === "Left" ? -1 : 1); return true }
      if (seq === "Shift+Left" || seq === "Shift+Right") { root.moveHorizon(seq === "Shift+Left" ? -12 : 12); return true }
      if (seq === "Backspace" || seq === "Delete") { root.setHorizon(""); return true }
      return seq === "Space" || seq === "Enter"
    }
    if (seq === "Space" || seq === "Enter") { root.toggleSearchFolder(root.searchFocus); return true }
    return false
  }

  // A reply's citations — `path` line N, or p. N — made links: a daily
  // note opens at that line, any other file in its own application.
  function linkCitations(text) {
    return String(text || "").replace(/`([^`\n]+\.(?:md|txt|pdf))`(?:,?\s*(line|p\.)\s*(\d+))?/g, function (m, path, kind, n) {
      var label = path.replace(/^.*\//, "").replace(/\.md$/, "") + (n ? (kind === "line" ? " · line " : " · p. ") + n : "")
      return "[" + label + "](cite:" + encodeURIComponent(path) + (n ? "#" + n : "") + ")"
    })
  }

  property int pendingLine: -1
  function openCitation(link) {
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
    Qt.openUrlExternally("file://" + svc.config.vault + "/" + path)
  }

  function landOnLine() {
    if (root.pendingLine < 0 || !svc.ready) return
    var i = Math.min(root.pendingLine - 1, editor.rows.length - 1)
    root.pendingLine = -1
    var r = editor.rows[Math.max(0, i)]
    if (r) editor.setCursor(r.start, true)
  }

  // Under an answer of the day's: what it searched for and read.
  function sayFetched(t) {
    if (!t) return ""
    var bits = []
    ;(t.searched || []).forEach(function (s) { bits.push("searched “" + s.words + "”" + (s.hits && s.hits.length ? "" : " (nothing)")) })
    ;(t.files || []).forEach(function (f) { bits.push("read " + f.path.replace(/^.*\//, "")) })
    var docs = root.sayReads(t)
    if (docs !== "") bits.push(docs)
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
    var was = root.here
    if (!root.dashOpen) root.noteFrom("dash")
    root.dashOpen = !root.dashOpen
    root.closeTalk(false)
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
      if (root.keysOpen) root.toggleKeys()
      if (root.settingsOpen) root.toggleSettings()
      dash.dashKeysRef.forceActiveFocus()
    } else {
      root.giveBack("dash", was, "center")
    }
  }

  function refreshTasks() {
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
  }
  property bool tasksAfterSave: false
  property bool tasksAgain: false

  Timer { id: tasksHold; onTriggered: root.refreshTasks() }

  // A row's identity across the list being read again.
  function rowKey(row) {
    if (!row) return ""
    if (row.kind === "deadline") return "d" + row.deadline.id
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") return "p" + row.item.id
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
    root.docFocus = -1
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
    else if (Sc.hit(event, "listNext")) { root.dueFocus = -1; root.projFocus = 0 }
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
    // The row after the last project makes a new one.
    var pr = root.projects[root.projFocus]
    if (Sc.hit(event, "listUp")) root.projFocus = Math.max(0, root.projFocus - 1)
    else if (Sc.hit(event, "listDown")) root.projFocus = Math.min(root.projects.length, root.projFocus + 1)
    else if (Sc.hit(event, "listTag")) { if (pr) root.insertTag(pr) }
    else if (Sc.hit(event, "listClass")) { if (pr) root.startClass(pr) }
    else if (Sc.hit(event, "listOpen")) { if (pr) root.openProject(pr); else root.openSidebarProject() }
    else if (Sc.hit(event, "listInto")) { if (pr) root.openProject(pr) }
    else if (Sc.hit(event, "listNext") || Sc.hit(event, "listBack")) root.projFocus = -1
    else if (!(event.modifiers & Qt.ControlModifier)) { root.projFocus = -1; return false }
    else return false
    return true
  }

  // Back out of a project to the list it came from.
  function leaveProject() {
    root.projectOpen = false
    root.docFocus = -1
    root.sections = []
    var i = -1
    for (var k = 0; k < root.projects.length; k++) if (root.projects[k].tag === root.projectTag) i = k
    root.projFocus = Math.max(0, i)
    sidebar.sidebarKeysRef.forceActiveFocus()
  }

  function moveSectionFocus(d) {
    var docs = root.projectDocs().length
    if (root.docFocus >= 0) {
      var i = root.docFocus + d
      if (i >= docs && root.sections.length > 0) { root.docFocus = -1; root.sectionFocus = 0 }
      else root.docFocus = Math.max(0, Math.min(docs - 1, i))
      return
    }
    if (d < 0 && root.sectionFocus === 0 && docs > 0) { root.docFocus = docs - 1; return }
    if (root.sections.length === 0) return
    root.sectionFocus = Math.max(0, Math.min(root.sections.length - 1, root.sectionFocus + d))
  }

  // The open project's documents, as the runner listed them with the
  // projects; opened in the PDF viewer, never in the page.
  function projectDocs() {
    for (var k = 0; k < root.projects.length; k++)
      if (root.projects[k].tag === root.projectTag) return root.projects[k].docs || []
    return []
  }

  function openDocument(d) {
    if (!d) return
    Qt.openUrlExternally("file://" + d.path)
    root.used("document", "open")
  }

  // Enter in a project: the document picked, or the section.
  function openInProject() {
    if (root.docFocus >= 0) root.openDocument(root.projectDocs()[root.docFocus])
    else root.openSection(root.sections[root.sectionFocus])
  }

  // Enter: the note itself, the cursor on the section's own heading. The
  // list stays in the sidebar, as the calendar does after opening a day, so
  // the next section is one key away.
  function openSection(s) {
    if (!s) return
    root.pendingSection = s
    if (s.date === svc.noteDate && svc.ready) root.landOnSection()
    else root.openNote(s.date)
    root.showNote()
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
    var h = root.dueDates[String(d.id)]
    if (h && h.moves > 0)
      bits.push("moved " + (h.moves === 1 ? "once" : h.moves === 2 ? "twice" : h.moves + " times")
                + (h.firstDue ? ", first due " + Qt.formatDate(new Date(h.firstDue * 1000), "d MMM") : ""))
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
        out.push({ kind: root.askKind(mine[m]), item: mine[m], task: t })
      }
    }
    // A document to file, or a deadline found in the writing — about no box
    // yet — goes in its course's band, when the list has one.
    for (var f = 0; f < props.length; f++) {
      if (used[props[f].id] || (props[f].kind !== "file" && props[f].kind !== "deadline") || !props[f].project) continue
      for (var b = 0; b < out.length; b++) {
        if (out[b].kind !== "head" || out[b].tag !== props[f].project) continue
        out.splice(b + 1, 0, { kind: root.askKind(props[f]), item: props[f], task: null })
        used[props[f].id] = true
        break
      }
    }
    var rest = props.filter(function (x) { return !used[x.id] })
    if (rest.length === 0) return out
    var at = -1
    for (var h = 0; h < out.length; h++) if (out[h].kind === "head" && out[h].text === "FROM THE AGENT") at = h
    var extra = rest.map(function (x) {
      return { kind: root.askKind(x), item: x, task: root.taskOfKey(x.key) }
    })
    if (at < 0) return out.concat([{ kind: "head", text: "FROM THE AGENT", tag: "" }]).concat(extra)
    return out.slice(0, at + 1).concat(extra).concat(out.slice(at + 1))
  }

  // A row's kind: a question, something the agent did and tells (told), or
  // something it proposes.
  function askKind(x) { return x.told ? "told" : x.kind === "question" ? "question" : "proposal" }

  // What a proposal or a told row says, by its kind.
  function sayAsk(x, under) {
    var what = x.kind === "do-date" ? "do " + root.sayDate(x.date) + (under ? "" : " · " + (x.title || ""))
      : x.kind === "file" ? "file “" + x.name.replace(/\.pdf$/, "") + "” in " + (x.title || x.project)
      : x.kind === "deadline" ? "deadline: " + x.title + " · 📅 " + root.sayDate(x.date)
      : x.kind === "project" ? "make it a project: " + x.title + " #" + x.project
      : x.kind === "priority" ? "priority " + (x.priority === 2 ? "▲ high" : x.priority === 1 ? "medium" : "▽ low")
        + (under ? "" : " · " + x.title)
      : x.kind === "steps" ? "steps: " + x.steps.join(" · ")
      : x.kind === "drop" ? "drop it?" + (under ? "" : " · " + x.title)
      : x.kind === "done" ? "looks done — tick it?" + (under ? "" : " · " + x.title)
      : x.title || ""
    return x.told ? "done: " + what : what
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
    root.talkData = null
    root.used("talk", how)
    root.fetchTalk()
    root.marginFocus = 1
    Qt.callLater(function () { margin.chatFieldRef.forceActiveFocus() })
  }

  function talkFocused() {
    var row = root.taskRows[root.taskFocus]
    if (!row) return
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") root.openTalk(row.item)
    else if (row.kind === "task") root.openTaskTalk(row.task)
    else if (row.kind === "deadline") root.openTaskTalk(root.taskOfAnchor(row.deadline.id))
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
    root.marginFocus = -1
    if (focusRows !== false) dash.dashKeysRef.forceActiveFocus()
  }

  // Esc in a task's conversation: to the day's, when it is open beside
  // the dashboard (the pane's home), else back where the keys came from.
  function leaveTalk() {
    var was = root.here
    root.closeTalk(false)
    if (was === "right" && root.rightView === "day") dayPane.dayFieldRef.forceActiveFocus()
    else root.giveBack("right", was, "right")
  }

  function sendTalk() {
    var msg = margin.chatFieldRef.text.trim()
    if (msg === "" || root.talking || !root.talkCanSend) return
    root.pendingTalk = { thread: root.talkThread, text: msg }
    margin.chatFieldRef.text = ""
    var c = root.talkData ? root.talkData.chat : null
    talkProc.command = root.talkToPlanner ? [svc.runner, "talk", "--id", String(root.talkId), "--message", msg]
      : [svc.runner, "chat", "--hash", c.hash, "--message", msg, "--date", c.date]
    talkProc.running = true
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
    root.acceptPlanned({ kind: root.askKind(p), item: p, task: root.taskOfKey(p.key) })
    root.talkSettled = p.kind === "question" ? "answered" : p.told ? "kept" : "accepted"
  }

  // The keys on the pinned proposal, in one function so they can be
  // driven without a keyboard (tests/page/run.py).
  function talkKey(e) {
    if (Sc.hit(e, "marginBack")) { root.leaveTalk(); return true }
    if (Sc.hit(e, "marginAccept")) { root.acceptTalked(); return true }
    if (Sc.hit(e, "marginDecline")) { root.declineTalked(); return true }
    if (Sc.hit(e, "marginDown")) { root.marginFocus = 1; margin.chatFieldRef.forceActiveFocus(); return true }
    return Sc.hit(e, "marginUp")
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
    if (p.kind === "file") { root.resolveProposal(p, "accept", ""); root.showHint("filed in " + (p.title || p.project)); return }
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
    else if (p.kind === "done") root.tickTask(t)
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
    if (p.kind === "do-date" && t) root.editTask(t, "when", "")
    else if (p.kind === "priority" && t) root.editTask(t, "prio", p.was || 0)
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
  // section when today has one, else at the end of the note.
  function insertAt(lines, tag) {
    var end = lines.length
    if (tag) {
      var re = new RegExp("^(#{1,6}) .*#" + tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(\\b|$)")
      for (var i = 0; i < lines.length; i++) {
        var m = re.exec(lines[i])
        if (!m) continue
        var level = m[1].length
        end = lines.length
        for (var j = i + 1; j < lines.length; j++) {
          var h = /^(#{1,6}) /.exec(lines[j])
          if (h && h[1].length <= level) { end = j; break }
        }
        break
      }
    }
    while (end > 0 && lines[end - 1].trim() === "") end--
    return end
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
      var lines = editor.text.split("\n")
      var at = root.insertAt(lines, tag)
      var pos = lines.slice(0, at).join("\n").length
      editor.snapshot(true)
      root.quiet = true
      editor.insert(pos, (at > 0 ? "\n" : "") + line + (at === 0 && lines.length > 0 && editor.text !== "" ? "\n" : ""))
      root.quiet = false
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
      out.push({ text: root.sayDate(Qt.formatDateTime(at, timed ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd")),
                 tone: d.status !== "open" ? "done" : (d.due * 1000 < Date.now() ? "late" : "due") })
      if (lt && lt.est) out.push({ text: lt.est, tone: "est" })
      return out
    }
    if (row.kind !== "task") return out
    var t = row.task
    if (t.when) out.push(root.doPill(t))
    if (t.due) out.push({ text: root.sayDate(t.due), tone: "due" })
    if (t.est) out.push({ text: t.est, tone: "est" })
    return out
  }

  function doPill(t) {
    return { text: "do " + root.sayDate(t.when) + (root.agentDates[t.key] === t.when ? " ◇" : ""), tone: "do" }
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
    var fresh = root.proposals.filter(root.isNewAsk).length
    if (open === 0 && done === 0 && asks === 0) return root.planning ? "planning…" : root.planError !== "" ? "the agent could not plan" : ""
    return open + " open" + (due > 0 ? "   ·   " + due + " with a date to meet" : "")
      + (done > 0 ? "   ·   " + done + " done today" : "")
      + (asks > 0 ? "   ·   " + asks + " from the agent" + (fresh > 0 ? ", " + fresh + " new" : "") : "")
      + (root.planning ? "   ·   planning…" : root.planError !== "" ? "   ·   the agent could not plan: " + root.planError : "")
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
      Qt.openUrlExternally("file://" + (row.item.filed || row.item.src)); root.used("document", "open"); return
    }
    if (row.kind === "proposal" || row.kind === "question" || row.kind === "told") { root.openTalk(row.item); return }
    if (row.kind === "shelf") { root.showShelf = true; return }
    if (row.kind === "grading") { root.showGrading = true; return }
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
    if (row && row.kind === "told") { root.undoProposal(row.item); return }
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
    var t = root.focusedLine()
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
    if (!root.focusedLine()) return
    root.dashFieldKind = "when"
    root.dashFieldStart = ""
    root.dashWhenFor = root.focusedLine()
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
    if (how === "drop") return Task.setField(Task.setState(line, "-"), "❌", Qt.formatDate(new Date(), "yyyy-MM-dd"))
    if (how === "undrop") return Task.setField(Task.setState(line, " "), "❌", "")
    if (how === "prio") return Task.setPriority(line, arg)
    if (how === "when") return Task.setField(line, "⏳", arg)
    if (how === "state") return Task.setState(line, arg)
    if (how === "done") return Task.setField(Task.setState(line, "x"), "✅", Qt.formatDate(new Date(), "yyyy-MM-dd"))
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
    if (Sc.hit(e, "dashBack")) { root.toggleDash(); return true }
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
    if (Sc.hit(e, "dashTalk")) { root.talkFocused(); return true }
    if (Sc.hit(e, "dashNextAsk")) { root.focusAsk(1); return true }
    if (Sc.hit(e, "dashPrevAsk")) { root.focusAsk(-1); return true }
    return false
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
    if (row && (row.kind === "proposal" || row.kind === "question" || row.kind === "told")) { root.acceptPlanned(row); return }
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
    root.toNote()
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
    root.toNote()
    if (t.date === svc.noteDate && svc.ready) root.landOnTask()
    else root.openNote(t.date)
    root.showNote()
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

  // `keep`: only what differs is written, so a cursor in the line's words
  // stays where it is (the line is being written on).
  function putLine(r, raw, keep) {
    root.quiet = true
    if (keep) editor.replaceLine(r, raw)
    else editor.replace(r.start, r.start + r.raw.length, raw)
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
    var d = root.twinOf(head, project, phrase, ms)
    if (!d) return false
    root.writeBinding(raw, head, ms, d.id, auto, false)
    return true
  }

  // That deadline, given the line's date (and its #tag if it has none); null
  // when there is none.
  function twinOf(head, project, phrase, ms) {
    var key = Bound.titleKey(head), tw = Bound.wordsOf(head)
    var day = new Date(ms).toDateString()
    for (var i = 0; i < dl.items.length; i++) {
      var d = dl.items[i]
      if (d.status !== "open" || d.link !== "" || new Date(d.due * 1000).toDateString() !== day) continue
      if (Bound.titleKey(d.title) !== key && Bound.overlap(tw, Bound.wordsOf(d.title)) < 0.5) continue
      var args = dl.words(phrase)
      if (project !== "" && d.project === "") args = ["--project", project].concat(args)
      dl.set(d.id, args)
      return d
    }
    return null
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
    var written = r.raw.substring(0, r.prefixLen) + words + " " + Bound.tail(w.ms, 0)
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

  // The line Tab bound, as it is now: a box still carrying that date and no
  // number, the nearest to where it was (Enter may have moved it); -1 when
  // there is none.
  function lineTabBound(rec) {
    var rows = editor.rows, best = -1
    for (var i = 0; i < rows.length; i++) {
      var x = rows[i]
      if (x.kind !== "task" || x.deadline > 0 || Math.floor(x.dueAt / 60000) !== Math.floor(rec.ms / 60000)) continue
      if (best < 0 || Math.abs(i - rec.line) < Math.abs(best - rec.line)) best = i
    }
    return best
  }

  // The store's number reaches the line Tab bound: ` ^dN` at its end,
  // after the cursor, so whatever is being typed in the words goes on.
  // Nobody asked for it as a step: every undo state that holds the line as
  // Tab wrote it gets the number too. The line gone meanwhile (deleted,
  // Ctrl+Z, another note opened): the deadline made for it goes too.
  function numberLine(rec, id, made) {
    root.setBinding(root.binding.filter(function (x) { return x !== rec }))
    if (id <= 0) return
    var i = svc.noteDate === rec.stem ? root.lineTabBound(rec) : -1
    var r = editor.rows[i]
    if (!r) {
      if (made) dl.remove(id)
      root.decline(rec.raw)
      return
    }
    var tag = " ^d" + id
    editor.rebase(rec.written, rec.written.replace(/\s+$/, "") + tag)
    // Left already (Enter came first): tidied as leftLine tidies a bound
    // line. (The new tag sets off the check, which carries the words.)
    var left = root.lineIndexAt(editor.cursorPosition) !== i
    var next = left ? r.raw.substring(0, r.prefixLen) + r.body.replace(/\s+$/, "") + r.suffix.replace(/\s+$/, "") + tag
      : r.raw.replace(/\s+$/, "") + tag
    editor.rebase(r.raw, next)
    root.putLine(r, next, true)
    root.autoBound = { id: id, raw: rec.raw, made: made }
    dl.set(id, ["--link", Bound.link(rec.stem, id)])
    root.used("bound")
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
    editor.remove(a.start, a.end)
    editor.insert(a.start, text)
    editor.setCursor(a.start + text.length, true)
    root.makeProject(name, a.tag)
    root.used("project", "note")
  }

  function openSidebarProject() {
    root.addingProject = true
    Qt.callLater(function () { sidebar.projectFieldRef.forceActiveFocus() })
  }

  function closeSidebarProject() {
    root.addingProject = false
    if (root.sidebarOpen) sidebar.sidebarKeysRef.forceActiveFocus()
  }

  function submitSidebarProject(text) {
    var f = Tags.fromField(text, root.projects)
    if (f.tag === "") { root.showHint("a name, and its #tag when not the name's words"); return }
    if (f.taken) { root.showHint("#" + f.tag + " is a project already"); return }
    root.makeProject(f.name, f.tag)
    root.used("project", "sidebar")
    root.closeSidebarProject()
  }

  function makeProject(name, tag) {
    if (newProjectProc.running) { root.showHint("still making the last one"); return }
    newProjectProc.made = tag
    newProjectProc.command = [svc.runner, "project", "--tag", tag, "--name", name]
    newProjectProc.running = true
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
    var a = root.dayNote ? Bound.anchors(editor.text) : ({})
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
      var h = root.answered(agent.record(b.hash)) ? b.hash : (root.recordKeys[Blocks.fnv1a(Task.identity(b.text))] || "")
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
    if (!root.checkWanted || root.checking || !svc.ready || svc.saving || svc.pending || !root.dayNote) return
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
      root.dueDates = out.dates || ({})
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
    root.toggleDay("")
  }

  // The date, at the left, is the door to the left sidebar (2026-10-21):
  // a click lands on the side where the thing appears.
  function dateClicked() {
    root.used("date")
    root.toggleSidebar()
  }

  function toggleSidebar() {
    var was = root.here
    if (!root.sidebarOpen && was !== "left") root.noteFrom("left")
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
    if (!l) { root.showHint("“" + (d ? d.title : "") + "” is not written in a note yet"); root.showNote(); return }
    root.pendingGoto = l.id
    if (l.stem === svc.noteDate && svc.ready) root.landOnGoto()
    else root.openNote(l.stem)
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
    root.showNote()
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
    root.showNote()
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
    if (stamp !== "") root.pdfRel = ""
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
    if (root.noteRoom) { root.noteRoom = false; root.dayOpen = false }
    if (svc.saving) { root.pendingStamp = stamp; root.pendingFile = null; return }
    svc.openDate(stamp)
  }

  // Put a file of the notes in the sheet (the Files space, docs/files.md):
  // yours to edit as a past day is, the agent's only to read. Whatever is
  // typed is written first, as for a day; the agent's pane, which belongs
  // to a day, closes.
  function openFile(rel, readOnly) {
    if (/\.pdf$/i.test(rel)) { root.openPdf(rel); return }
    root.pdfRel = ""
    if (rel === "" || (rel === svc.filePath && svc.ready)) { root.showNote(); return }
    if (root.searchOpen) root.closeSearch("back")
    root.leftLine(root.lastLine)
    root.flush()
    root.used("file", readOnly ? "agent" : "mine")
    root.marginOpen = false
    root.closeTalk(false)
    root.dayOpen = false
    root.noteRoom = false
    root.dashOpen = false
    root.marginFocus = -1
    if (svc.saving) { root.pendingFile = { rel: rel, readOnly: !!readOnly }; root.pendingStamp = ""; root.showNote(); return }
    svc.openFile(rel, readOnly)
    root.showNote()
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
      if (root.tasksAfterSave) { root.tasksAfterSave = false; root.refreshTasks() }
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
    off: !root.dayNote
    onStateChanged: { root.scheduleRepaint(); root.checkAccept(); root.settleChat(); root.settleDay() }
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
      // The day's answer may have proposed: its cards are the dashboard's items.
      if (root.runningHash === "day") { Qt.callLater(root.refreshProposals); Qt.callLater(root.refreshTasks) }
      if (root.runningHash === "note") noteTalkFile.reload()
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
    // A deadline moved or added in the store: its line follows (the check),
    // and so does the dashboard.
    onExited: function (code, status) { agent.reload(); if (code === 0) root.startCheck() }
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
        if (root.tasksAgain) { root.tasksAgain = false; Qt.callLater(root.refreshTasks) }
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
        if (at < 0) continue
        if (mine[k].how === "remove") { lines.splice(at, 1); changed = true; continue }
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
    root.runInTurn(rateProc, [svc.runner, "rate", v, "--hash", root.currentRec, "--date", svc.noteDate])
    root.used("rate", v)
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

  // The runner makes the project's file; the list is read again for it.
  Process {
    id: newProjectProc
    property string made: ""
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") { root.showHint("#" + newProjectProc.made + " is a project now"); root.refreshProjects() }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") { root.showHint(text.trim().replace(/^longhand-agent: /, "")); root.refreshProjects() }
    }
  }

  Process {
    id: projectsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.projects = JSON.parse(text) || [] } catch (e) { root.projects = [] }
        root.projFocus = Math.min(root.projFocus, root.projects.length - 1)
      }
    }
    onExited: function (code, status) { root.fetched() }
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
        var cut = svc.config.vault.length + 1
        var paths = String(text).split("\n").filter(function (p) { return p !== "" }).map(function (p) { return p.slice(cut) })
        root.vaultIndex = Links.index(paths)
        root.vaultIndexVersion++
      }
    }
  }
  Process {
    id: horizonProc
    stdout: StdioCollector { onStreamFinished: { try { root.horizonData = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: searchFoldersProc
    stdout: StdioCollector { onStreamFinished: { try { root.searchData = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: autonomyProc
    stdout: StdioCollector { onStreamFinished: { try { root.autonomyData = JSON.parse(text) } catch (e) {} } }
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
          root.proposals = (p.open || []).filter(function (x) { return !x.auto }).concat(
            (p.told || []).map(function (x) { return Object.assign({ told: true }, x) }))
          root.proposalsReadAt = root.proposalsAsked
          root.applyAuto(p.open || [])
          // Kept, not replaced: a conversation whose proposal was just
          // settled stays in the margin until it is closed.
          root.threads = p.threads || {}
          if (root.acceptAfterRefresh >= 0) {
            var agreed = root.proposals.filter(function (x) { return x.id === root.acceptAfterRefresh })[0]
            // A list read before the conversation's answer was written does
            // not have it yet: wait for the one asked for after it.
            if (agreed || !root.proposalsAgain) root.acceptAfterRefresh = -1
            if (agreed) {
              root.acceptPlanned({ kind: root.askKind(agreed), item: agreed, task: root.taskOfKey(agreed.key) })
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
    id: talkProc
    stdout: StdioCollector {
      // The planner's answer is JSON (`talk`); the margin's is a line
      // (`chat`). Either way the conversation is read again.
      onStreamFinished: {
        try { root.talkAnswered(JSON.parse(text)) } catch (e) { root.refreshProposals() }
        root.fetchTalk()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") { console.warn("longhand.page talk: " + text.trim()); root.pendingTalk = null; root.refreshProposals() }
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
    onExited: function (code, status) { root.nextProposal(); if (root.proposalQueue.length === 0) root.refreshProjects() }
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
      onClicked: root.alongside ? root.focusCenter() : root.dismiss()
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

    // What the agent may search: Settings' fourth view. (SearchSheet.qml)
    SearchSheet { id: searchSheet; page: root }

    // The keys sheet (Ctrl+/, or "keys" at the sidebar's foot): every key the page
    // answers to, under where it works, each one movable. A list, so it
    // takes the dashboard's shape rather than the note's measure. (KeysSheet.qml)
    KeysSheet { id: keysSheet; page: root }

    BorderSurface {
      id: sheet
      visible: !root.dashOpen && !root.keysOpen && !root.settingsOpen
      x: root.sheetX
      y: root.alongside ? 0 : root.sheetMargin
      width: root.sheetWidth
      // Stepping aside for a pane slides, with the panes beside it (their
      // x follows this one), quickly. The width snaps:
      // text reflowing every frame reads as shaking.
      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      height: root.alongside ? content.height : content.height - root.sheetMargin * 2
      radius: root.alongside ? 0 : Style.cornerRadius
      color: root.sheetColor
      Behavior on color { ColorAnimation { duration: 240 } }
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
            color: sealArea.containsMouse ? root.accent : root.dayShown ? root.foreground : root.faint
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
                // Both of the pane's keys, so the pair is remembered (2026-10-27).
                text: root.tips([[root.dayShown ? "Close the agent's pane" : "The agent's pane: the day's chat", "day"],
                                 ["Go there; in it, the day's chat ↔ this one", "pane3"]])
              }
            }
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
            color: dateArea.containsMouse ? root.accent : root.sidebarOpen ? root.foreground : svc.isToday ? root.dim : root.foreground
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            // The door to the sidebar: the calendar, the projects, keys and settings.
            MouseArea {
              id: dateArea
              anchors.fill: parent
              enabled: root.status === ""
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dateClicked()
              PanelToolTip {
                visible: parent.containsMouse
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
            color: todayArea.containsMouse ? root.accent : root.faint
            font.family: root.fontFamily
            font.styleName: root.fontStyle
            font.pixelSize: root.fs(Style.font.bodySmall)
            MouseArea {
              id: todayArea
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
              color: pinArea.containsMouse ? root.accent : root.alongside ? root.foreground : root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                id: pinArea
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
            // A day before the horizon says so where "private" would be: a
            // grey lock, since it is the rule and not a choice.
            Row {
              visible: root.dayNote && root.beforeHorizon && !root.pdfShown
              anchors.verticalCenter: parent.verticalCenter
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
            LockMark {
              visible: svc.notePrivate && root.agentDay && !root.beforeHorizon && !root.pdfShown
              anchors.verticalCenter: parent.verticalCenter
              width: root.sp(10)
              color: pal.magenta
            }
            Text {
              visible: root.agentDay && !root.beforeHorizon && !root.pdfShown
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "private"
              color: privateArea.containsMouse ? root.accent : svc.notePrivate ? root.foreground : root.faint
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

            // Ask about this note (docs/files.md): for what the agent does
            // not otherwise see — a file, a day before the horizon, a day
            // marked private. Asking is the consent; the note's own
            // conversation opens beside it, and the word says one exists.
            Text {
              id: noteAsk
              // Hidden where even the short word has no room (a sheet squeezed
              // between both panes): the pane's key and the seal still open it.
              visible: root.noteAskable && !root.pdfShown && headerRight.parent.width / 2 - root.sp(120) >= root.sp(60)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              // Its full words while the right half of the header has room
              // for them beside the pin; else the short ones.
              readonly property string full: root.noteTalkTurns > 0 ? "this note's chat · " + Math.ceil(root.noteTalkTurns / 2) : "chat about this note"
              TextMetrics { id: noteAskFull; font: noteAsk.font; text: noteAsk.full }
              // (A day before the horizon has its own words beside it.)
              text: headerRight.parent.width / 2 - root.sp(120) - (root.beforeHorizon ? root.sp(140) : 0) >= noteAskFull.width ? full
                : root.noteTalkTurns > 0 ? "chat · " + Math.ceil(root.noteTalkTurns / 2) : "chat"
              color: noteAskArea.containsMouse ? root.accent : root.noteRoom && root.dayShown ? root.foreground : root.faint
              font.family: root.fontFamily
              font.styleName: root.fontStyle
              font.pixelSize: root.fs(Style.font.bodySmall)
              Behavior on color { ColorAnimation { duration: 240 } }
              MouseArea {
                id: noteAskArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.noteRoom && root.dayShown ? root.closeDay() : root.openRoom("", true)
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.tip(root.noteTalkTurns > 0 ? "This note's chat" : "Chat about this note: chatting shares it, for this chat only", "dayChat")
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
              visible: svc.header !== "" && root.agentOn && !root.pdfShown
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              // One word, whatever the chat holds (2026-10-27: it was "ask",
              // then "reply" once answered, and a word that changes says the
              // key under it changes too). It opens this block's chat; a block
              // with a sign is sent first, and one answered is not asked again.
              text: "chat"
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
                  text: root.tip(root.answered(root.currentRecord) ? "This block's chat"
                    : root.currentTrigger !== "" ? "Chat about this block: the agent answers first" : "Chat about this block", "ask")
                }
              }
            }

            // The agent mark: faint at rest, brighter from the moment
            // something is asked until it comes back, accent while a reply
            // in this note is still unread.
            Text {
              visible: svc.header !== "" && root.agentOn && !root.pdfShown
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
                                   ["This block's chat", "ask"], ["The agent's pane", "pane3"]])
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

        Flickable {
          id: flick
          visible: root.problem === "" && !root.pdfShown
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

          // Private blocks, sunk into the darker paper, and their locks in
          // the gutter (B · Paper). Under the words, as the blip is.
          Repeater {
            model: root.privatePaint
            Item {
              required property var modelData
              x: 0
              y: modelData.y - root.sp(8)
              width: flick.width
              height: modelData.h + root.sp(16)
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
                y: root.sp(10)
                width: root.sp(10)
                color: pal.magenta
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
            linkColor: pal.blue
            linkKnown: root.linkKnown
            onLinkActivated: function (i, l) { root.followLink(l) }
            viewTop: flick.contentY - y
            viewBottom: flick.contentY - y + flick.height
            // 0 until the item is on a screen; a picture is decoded for 1 then.
            pixelRatio: Math.max(1, Screen.devicePixelRatio || 1)
            // What the page shows under a line opens room there, so the
            // lines below move down rather than being drawn over.
            roomRow: whenBox.visible || mentionBox.visible || nameBox.visible ? root.lineIndexAt(root.newProject ? root.newProject.end : editor.cursorPosition) : -1
            roomHeight: (whenBox.visible ? whenBox.height : mentionBox.visible ? mentionBox.height : nameBox.visible ? nameBox.height : 0) + root.sp(12)
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
              if (root.applying) { root.restoreAuthors(text); root.restoreThreads(text); return }
              root.carryAuthors(text)
              root.carryThreads(text)
              svc.markPending(text)
              saveTimer.restart()
              if (root.quiet) return
              root.boundEdited(was, root.bound)
              root.tickedCount = root.countTicked(text)
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
                  color: root.mentionFocus === index ? Style.selectedFill : mentionArea.containsMouse ? Style.hoverFill : "transparent"
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
                    PanelToolTip { visible: parent.containsMouse; text: modelData.make ? "Name it, and it is in the sidebar, @ and #"
                      : root.mention && root.mention.atLineStart
                      ? root.tips([["Write its #tag", "mentionPick"], ["Start the class", "mentionClass"]]) : root.tip("Write its #tag", "mentionPick") }
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
        radius: root.alongside ? 0 : Style.cornerRadius
        color: "transparent"
        borderSpec: root.frameSpec
        Behavior on opacity {
          NumberAnimation { duration: 539; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1] }
        }
      }
    }

    // The student's own hand on the mouse: the pointer is left alone while
    // it moves (a warp's own motion is not the hand).
    HoverHandler {
      id: handHover
      onPointChanged: if (Date.now() - root.warpedAt > 250) root.handMovedAt = Date.now()
    }
  }
}
