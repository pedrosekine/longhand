import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import "page"
import "page/Shortcuts.js" as Sc
import "page/Say.js" as Say
import "page/Queue.js" as Queue

// The page under test: a stand-in for omarchy-shell (toggle / summon / hide
// as shell.qml does them), plus IPC handles to drive the page without a
// keyboard. tests/page/run.py builds a throwaway config around this file.
ShellRoot {
  QtObject {
    id: fakeShell
    function hide(id) { page.close(); return true }
    property var seenRows: []    // dashDrawn's: the drawn rows seen so far
  }
  Page { id: page; shell: fakeShell; windowTitle: "Page scratch" }
  // Real pointer events, delivered through the page's window as a mouse's
  // are (QtTest's), for what only a drag shows: a selection in a PDF.
  TestCase { id: pointer; name: "pointer"; when: false }
  IpcHandler {
    target: "page"
    function summon(payload: string): void { page.open(payload) }
    function toggle(payload: string): void { if (page.opened) fakeShell.hide("longhand.page"); else page.open(payload) }
    function closeAll(): void { page.windowOpen = false; page.close() }
    function state(): string { return JSON.stringify({ overlay: page.overlayOpen, window: page.windowOpen, ready: page.editorItem.enabled }) }
    // The note
    function text(): string { return page.editorItem.text }
    // The page photographs itself, whatever is in front of it on screen.
    function shot(path: string): void { page.contentItem.grabToImage(function (r) { r.saveToFile(path) }) }
    function insert(s: string): void { var e = page.editorItem; e.insert(e.cursorPosition, s) }
    // Each letter written and saved at once, so the saves overlap: the
    // last one must be what the file and the page are left with — and until
    // it has landed, the page knows a save is on its way (the check waits
    // for that). Says whether it knew, right after the last save began.
    function saveBurst(s: string): bool {
      var e = page.editorItem
      for (var i = 0; i < s.length; i++) { e.insert(e.length, s.charAt(i)); page.flush() }
      return page.noteSaving
    }
    // As fingers do it: into the focused line's field, so the editor sees
    // typing (typed()), and Enter as the key does it.
    // The row the fingers would be in: the focused one, or — since this
    // window is told never to take focus — the one the cursor sits on.
    function type(s: string): void {
      var e = page.editorItem
      var it = e.rowItem(e.focusedRow) || e.rowItem(page.lineIndexAt(e.cursorPosition))
      // A row with emphasis in it is rich text, and a rich field reads what
      // is handed to `insert` as html — which keys never are. Go through the
      // note there, the way the key path ends up doing.
      if (it.rich) e.insert(e.cursorPosition, s)
      else it.field.insert(it.field.cursorPosition, s)
    }
    // Typing that stops once the note holds `stop`, checked in the same
    // breath, so no key lands after it unseen.
    function typeUnless(s: string, stop: string): bool {
      if (page.editorItem.text.indexOf(stop) >= 0) return false
      type(s)
      return true
    }
    function backspace(n: int): void {
      var e = page.editorItem
      var f = (e.rowItem(e.focusedRow) || e.rowItem(page.lineIndexAt(e.cursorPosition))).field
      var at = f.cursorPosition
      f.remove(Math.max(0, at - n), at)
    }
    function enter(): void {
      var e = page.editorItem
      e.returnKey(e.rowItem(e.focusedRow) || e.rowItem(page.lineIndexAt(e.cursorPosition)), false)
    }
    function undo(): void { page.editorItem.undo() }
    function pending(line: int): bool { var it = page.editorItem.rowItem(line); return !!it && it.pending }
    function cursor(pos: int): void { page.editorItem.setCursor(pos, true) }
    function cursorEnd(): void { page.editorItem.setCursor(page.editorItem.length, true) }
    function cursorLine(): int { return page.lineIndexAt(page.editorItem.cursorPosition) }
    function cursorAt(): int { return page.editorItem.cursorPosition }
    function tick(line: int): void { page.editorItem.toggleCheckbox(line) }
    function erase(a: int, b: int): void { page.editorItem.remove(a, b) }
    // The whole lines, marker and tail, deleted as a selection is (an undo
    // step of its own). Both ends are set as they are: a selection's
    // moving end only stops where the cursor can, inside a line's words.
    function removeLines(first: int, last: int): void {
      var e = page.editorItem, a = e.rows[first], b = e.rows[last]
      e.selAnchor = a.start
      e.selCursor = Math.min(e.text.length, b.start + b.raw.length + 1)
      e.removeSpan()
    }
    function removeLine(line: int): void { removeLines(line, line) }
    function openDay(stem: string): void { page.openNote(stem) }
    function header(): string { return page.dateLabel }
    // Prompts and keys
    // Nothing is asked under the cursor any more (2026-10-17): always null.
    function ask(): string { return "null" }
    function marks(): string { return JSON.stringify(page.paint.map(function (m) { return m.sending ? "sending" : m.reply ? (m.unread ? "reply:unread" : "reply") : "other" })) }
    function trigger(): string { return page.triggerForBlock(page.currentHash) }
    function sign(): string { return page.currentTrigger }
    function askNow(): void { page.sendCurrent() }
    // Privacy: the note the agent may not see.
    function togglePrivate(): void { page.togglePrivate() }
    function isPrivate(): bool { return page.noteService.notePrivate }
    function agentOn(): bool { return page.agentOn }
    // `@` calling a project
    function mention(): string { return JSON.stringify(page.mention ? page.mention.items.map(function (p) { return (p.make ? "+" : "") + p.tag }) : null) }
    function mentionFocus(): int { return page.mentionFocus }
    // Making a project: the note's "name?", and the sidebar's field.
    function askingName(): string { return JSON.stringify(page.newProject) }
    function projectName(s: string): void { page.projectNameInput.text = s; page.submitProjectName() }
    function closeProjectName(): void { page.closeProjectName() }
    function sidebarProject(s: string): void { page.openSidebarProject(); page.submitSidebarProject(s) }
    function addingProject(): bool { return page.addingProject }
    // How a line is drawn: whether its emphasis is drawn rather than shown,
    // and the plain text the field holds under it — which must be the line.
    function drawn(line: int): string {
      var it = page.editorItem.rowItem(line)
      return it ? JSON.stringify({ rich: it.rich, plain: it.plain(), len: it.field.length }) : "null"
    }
    function shown(line: int): string { var it = page.editorItem.rowItem(line); return it ? it.field.shown : "" }
    // The band above a day's note: the tasks the day is for, from any note.
    function refreshDated(): void { page.refreshDated() }
    function dayTasks(): string { return JSON.stringify({ open: page.dayTasksOpen, done: page.dayTasksDone, titles: page.dayTasks.map(function (t) { return t.title }) }) }
    // Typing straight into a drawn line's field, as keys do: what it holds
    // is read back through `plain()`. Only for text with no html in it.
    function typeField(s: string): void {
      var e = page.editorItem
      var it = e.rowItem(e.focusedRow) || e.rowItem(page.lineIndexAt(e.cursorPosition))
      it.field.insert(it.field.cursorPosition, s)
    }

    function focusedRow(): string { var e = page.editorItem; return e.focusedRow + "/" + e.rows.length + " item=" + (!!e.rowItem(e.focusedRow)) }
    // Whether the note has the keys (a line's field has them), and where
    // its cursor is: the checkpoint a pane closing gives back.
    function noteFocus(): string {
      var e = page.editorItem, it = e.rowItem(e.focusedRow)
      return JSON.stringify({ row: e.focusedRow, at: e.cursorPosition, active: !!it && it.field.activeFocus })
    }
    function mentionPick(i: int, shift: bool): void { page.mentionFocus = i; page.acceptMention(shift) }
    function hint(): string { return page.hint }
    function clearHint(): void { page.hint = "" }
    // Hover hints (docs/hints.md): the hand on the mouse, and a click's key named.
    function handOn(): bool { return page.handOn }
    function hand(): void { page.handOn = true }
    function mouseDid(id: string): void { page.nameKey(id) }
    // Nothing taught yet: the keys the suite pressed so far forgotten.
    function untaught(): void { Sc.takeUses(); page.taught = {} }
    // Hold Ctrl (docs/hints.md, F): shown, and what it shows.
    function ctrlShown(): bool { return page.ctrlShown }
    function ctrlKey(id: string): string { return page.ctrlKey(id) }
    function ctrlStrip(): string { return JSON.stringify(page.ctrlStripItems) }
    // A hint drawn on demand, for a look at it (tools, not the suite).
    function tipDemo(text: string, x: real, y: real): void {
      var c = Qt.createComponent(Qt.resolvedUrl("page/Tip.qml"))
      var t = c.createObject(page.contentItem, { host: page, text: text, x: x, y: y, delay: 0 })
      page.handOn = true
      t.shown = true
    }
    function yes(): void { page.acceptAsk() }
    function no(): void { page.declineAsk() }
    // A key as the note's own filter sees it (Qt.Key_*, Qt modifiers).
    function keyPage(key: int, mods: int): bool { return page.pageKey({ key: key, text: "", modifiers: mods }) }
    // A key as the cursor's line takes it, in its own field.
    function lineKey(key: int, mods: int): bool {
      var e = page.editorItem, it = e.rowItem(e.focusedRow) || e.rowItem(page.lineIndexAt(e.cursorPosition))
      var ev = { key: key, text: "", modifiers: mods, accepted: false }
      e.key(ev, it)
      return ev.accepted
    }
    function ctrlD(): void { page.deadlineKey() }
    function closeWhen(): void { page.closeWhen() }
    // Where a row sits, and the room a line has opened under it.
    function rowY(i: int): real { var it = page.editorItem.rowItem(i); return it ? it.y : -1 }
    function room(): string { var e = page.editorItem; return JSON.stringify({ row: e.roomRow, top: e.roomTop, height: e.roomHeight }) }
    function status(): string { return page.status }
    function when(s: string): void { page.whenInput.text = s; page.submitWhen() }
    // Panels
    function sidebar(): void { page.toggleSidebar() }
    function seal(): void { page.sealClicked() }
    function dateClick(): void { page.dateClicked() }
    function searchKey(key: int, mods: int): bool { return page.searchFoldersKey({ key: key, text: "", modifiers: mods }) }
    function searchFolders(): string { return JSON.stringify(page.searchData ? page.searchData.folders.map(function (f) { return f.folder + "=" + (f.on ? "on" : "off") }) : []) }
    function searchFocus(i: int): void { page.searchFocus = i }
    function loadHorizon(): void { page.loadHorizon() }
    // The sidebar's spaces and the Files space (docs/files.md).
    function files(): string {
      var f = page.sidebarItem.filesPaneRef, s = page.noteService
      return JSON.stringify({ space: page.sidebarSpace, open: page.sidebarOpen, here: page.here, pick: f.pick,
        rows: f.shown.map(function (r) { return (r.dir ? (r.open ? "v " : "> ") : "") + r.name + (r.where ? " @" + r.where : "") }),
        filePath: s.filePath, readOnly: s.readOnly, dayNote: page.dayNote, agentOn: page.agentOn, label: page.noteLabel })
    }
    function filesFocus(i: int): void { page.sidebarItem.filesPaneRef.pick = i }
    function filesKey(key: int, mods: int): bool { return page.sidebarItem.keyPressed({ key: key, text: "", modifiers: mods }) }
    function filesFilter(text: string): void { page.sidebarItem.filesPaneRef.filterFieldRef.text = text }
    function openFile(rel: string, readOnly: bool): void { page.openFile(rel, readOnly) }
    // A note's own conversation, and the blip (docs/files.md).
    function noteTalk(): string {
      return JSON.stringify({ room: page.noteRoom, shown: page.dayShown, askable: page.noteAskable, turns: page.noteTalkTurns,
        blip: page.blipWhat, here: page.here, path: page.noteTalkPath })
    }
    function askNote(): void { page.openRoom("", true) }
    // How private looks (B · Paper).
    function privateLook(): string { return JSON.stringify({ sunk: page.sheetSunk, blocks: page.privatePaint.length }) }
    // A PDF in the middle (step 5).
    function pdf(): string {
      var p = page.pdfItem
      return JSON.stringify({ shown: page.pdfShown, label: page.noteLabel, ready: p.ready, pages: p.pages, finding: p.finding,
        found: p.view && p.view.searchModel ? p.view.searchModel.count : 0, here: page.here,
        at: p.here(), settled: p.settled, resumed: p.resumed, zoom: p.zoom,
        scale: p.view ? p.view.renderScale : 0, x: p.table() ? p.table().contentX : 0, whole: p.wholePage, width: p.width,
        span: p.read && p.read.span ? p.read.span : null, dark: p.dark,
        darkDrawn: p.dressed.some(function (h) { if (!h || !h.selection) return false; var ds = h.selection.parent.data
          for (var i = 0; i < ds.length; i++) if (String(ds[i]).indexOf("PdfPageImage") >= 0 && ds[i].layer.enabled) return true
          return false }) })
    }
    function pdfKey(key: int, mods: int): bool { return page.pdfItem.key({ key: key, text: "", modifiers: mods }) }
    function tasksTrace(): string { return JSON.stringify(page.tasksTrace) }
    // Marks (plan.md, item 15): what longhand-read said, the marks drawn on
    // the first page (those with a size: a mark once came out with none),
    // what is selected.
    function pdfMarks(): string {
      var p = page.pdfItem, drawn = 0
      for (var i = 0; i < p.dressed.length; i++) {
        var h = p.dressed[i]
        if (!h || h.index !== 0) continue
        var kids = h.selection.parent.children
        for (var k = 0; k < kids.length; k++) {
          if (kids[k].holder === undefined || kids[k].count === undefined) continue
          var groups = kids[k].children
          for (var gi = 0; gi < groups.length; gi++) {
            var boxes = groups[gi].children
            for (var b = 0; b < boxes.length; b++)
              if (boxes[b].modelData !== undefined && boxes[b].color.a > 0.5 && boxes[b].width > 4 && boxes[b].height > 4) drawn++
          }
        }
      }
      var sel = p.selected()
      return JSON.stringify({ read: p.read, picked: p.picked, lastMade: p.lastMade, error: p.readError, noting: p.noting,
        dressed: p.dressed.length, drawn: drawn, selected: sel ? sel.text : "", markable: p.markable,
        dragPans: p.table() ? p.table().interactive : null })
    }
    // A mouse wheel turned on the PDF: how far down it is after.
    function pdfWheel(dy: int): real {
      var p = page.pdfItem
      p.wheel({ pixelDelta: Qt.point(0, 0), angleDelta: Qt.point(0, dy), modifiers: 0, accepted: true })
      return p.table().contentY
    }
    // Select on a page (from 0) from one point to another, in points: both
    // on the words, as a drag starts (pdfium finds no text elsewhere).
    function pdfSelect(pageIndex: int, x0: real, y0: real, x1: real, y1: real): bool {
      var p = page.pdfItem, s = p.view.renderScale
      for (var i = 0; i < p.dressed.length; i++) {
        var h = p.dressed[i]
        if (!h || h.index !== pageIndex) continue
        // Qt's selection takes new points only while not held (a drag).
        h.selection.hold = false
        h.selection.from = Qt.point(x0 * s, y0 * s)
        h.selection.to = Qt.point(x1 * s, y1 * s)
        h.selection.hold = true
        return true
      }
      return false
    }
    function pdfPick(id: string): void { page.pdfItem.pick(id) }
    // The open project's papers (plan.md item 5's first part).
    function projectPapers(): string { return JSON.stringify({ open: page.projectOpen, papers: page.projectPapers.map(function (x) { return x.title }), focus: page.projectPaperFocus, doc: page.docFocus }) }
    // The project asked for on a paper's first mark.
    function pdfAsk(): string { var p = page.pdfItem; return JSON.stringify({ asking: p.askingTag, choices: p.tagChoices.map(function (c) { return c.tag }), said: p.tagSaid, tags: p.read.tags || [] }) }
    function pdfChooseProject(tag: string): void { page.pdfItem.chooseProject(tag) }
    // A scan read (plan.md item 15, step 5).
    function pdfScan(): string { var p = page.pdfItem; return JSON.stringify({ scanned: !!p.read.scanned, ocr: p.read.ocr || "", text: p.read.text, ocrable: p.ocrable, progress: p.ocrProgress, error: p.readError, url: p.url() }) }
    // What was read on the calendar's day (plan.md item 15, step 3).
    function readToday(): string {
      return JSON.stringify({ rows: page.readToday.rows.map(function (r) { return r.title + " · " + page.readToday.summary(r) }),
        focus: page.readToday.at, due: page.dueFocus, proj: page.projFocus, day: Qt.formatDate(page.calFocus, "yyyy-MM-dd") })
    }
    // A paper's room (plan.md item 15, step 2): what the agent's pane shows.
    function paper(): string {
      return JSON.stringify({ room: page.paper.room, shown: page.dayShown, list: page.paper.listing, filter: page.paper.filter,
        focus: page.paper.at, rows: page.paper.rows.map(function (m) { return m.id }), marks: page.paper.marks,
        waiting: page.paper.waiting.map(function (m) { return m.id }), answered: Object.keys(page.paper.answered),
        kept: page.paper.kept, here: page.here, picked: page.pdfItem.picked, askable: page.paper.askable,
        flash: page.pdfItem.flashBoxes.length, missed: page.pdfItem.flashMissed, hint: page.hint })
    }
    function paperKey(key: int, mods: int): bool { return page.paper.keyPressed({ key: key, text: "", modifiers: mods }) }
    function paperLinks(text: string): string { return page.linkCitations(text) }
    function openLink(link: string): void { page.openCitation(link) }
    // Words kept as a mark as `m` / `q` keep a selection (for scenes with
    // many marks; the keys' own path is checked with a real drag).
    function pdfMarkText(pageIndex: int, text: string, kind: string): bool { return page.pdfItem.markText(pageIndex, text, null, kind) }
    // A click on a PDF's page (from 0), at a point in points, through the window.
    function pdfClick(pageIndex: int, x: real, y: real): bool {
      var p = page.pdfItem, s = p.view.renderScale
      for (var i = 0; i < p.dressed.length; i++) {
        var h = p.dressed[i]
        if (!h || h.index !== pageIndex) continue
        pointer.mouseClick(h.selection.parent, x * s, y * s, Qt.LeftButton)
        return true
      }
      return false
    }
    // A drag across a PDF's page (from 0), from one point to another in
    // points, through the window: what a hand does. QtTest sends it from
    // the session's main pointer, on a laptop its touchpad — the device a
    // drag on a PDF once selected nothing from.
    function pdfDrag(pageIndex: int, x0: real, y0: real, x1: real, y1: real): bool {
      var p = page.pdfItem, s = p.view.renderScale
      for (var i = 0; i < p.dressed.length; i++) {
        var h = p.dressed[i]
        if (!h || h.index !== pageIndex) continue
        var paper = h.selection.parent
        pointer.mousePress(paper, x0 * s, y0 * s, Qt.LeftButton)
        for (var k = 1; k <= 12; k++)
          pointer.mouseMove(paper, (x0 + (x1 - x0) * k / 12) * s, (y0 + (y1 - y0) * k / 12) * s, 5, Qt.LeftButton)
        pointer.mouseRelease(paper, x1 * s, y1 * s, Qt.LeftButton)
        return true
      }
      return false
    }
    function keysToSidebar(): void { if (!page.sidebarOpen) page.toggleSidebar(); page.sidebarSpace = "time"; page.focusSidebar() }
    // Acronyms (plan.md item 18): what the paper's are, the one hovered and
    // its tip, the back key's place, the list.
    function pdfAcronyms(): string {
      var p = page.pdfItem
      return JSON.stringify({ list: p.acro.list.map(function (x) { return x.short + "=" + (x.long || "?") }),
        spots: [p.acroOn(0), p.acroOn(1), p.acroOn(2)], hover: p.hoverAcro ? p.hoverAcro.a : "", tip: p.acroTip,
        back: p.jumpBack !== null, flash: p.flashBoxes.length, listing: p.acroListing,
        choices: p.acroChoices.map(function (x) { return x.short }), page: p.current })
    }
    // The pointer resting on a page at (x, y) in its points, no button down.
    function pdfHover(pageIndex: int, x: real, y: real): bool {
      var p = page.pdfItem, s = p.view.renderScale
      for (var i = 0; i < p.dressed.length; i++) {
        var h = p.dressed[i]
        if (!h || h.index !== pageIndex) continue
        pointer.mouseMove(h.selection.parent, x * s, y * s)
        return true
      }
      return false
    }
    function pdfAcroType(text: string): void { page.pdfItem.acroFieldRef.text = text }
    function pdfAcroEnter(): void { page.pdfItem.acroPick() }
    function pdfWriteNote(text: string): void { page.pdfItem.noteRef.text = text; page.pdfItem.saveNote() }
    // Export as a PDF (ExportSheet.qml): the sheet as its keys see it.
    function exportState(): string {
      return JSON.stringify({ open: page.exportOpen, busy: page.exportBusy, error: page.exportError, title: page.exportTitle,
        look: page.exportLook, words: page.exportWords, focus: page.exportFocus, here: page.here,
        from: page.exportData ? page.exportData.from || null : null,
        rows: page.exportRows.map(function (r) { return { text: r.text.split("\n")[0], in: !!page.exportPicks[r.hash], why: r.why } }) })
    }
    function exportKey(key: int, mods: int): bool { return page.exportKey({ key: key, text: "", modifiers: mods }) }
    function exportTitle(s: string): void { page.exportTitle = s }
    function pdfFind(text: string): void { page.pdfItem.findRef.text = text }
    // The read view (docs/files.md): what each line is drawn as.
    function rowKinds(): string { return JSON.stringify(page.editorItem.rows.map(function (r) { return r.kind })) }
    function imageShown(i: int): string {
      var it = page.editorItem.rowItem(i)
      return JSON.stringify(it ? { src: it.imgSource, natural: it.natural, width: it.imgWidth, reveal: it.reveal } : null)
    }
    function blipReset(): void { page.blipWhat = "" }
    function horizon(): string { return JSON.stringify({ data: page.horizonData, before: page.beforeHorizon, agentOn: page.agentOn }) }
    function linkCitations(text: string): string { return page.linkCitations(text) }
    function openCitation(link: string): void { page.openCitation(link) }
    function dive(): void { page.diveIn(true) }
    function back(): void { page.backToNote() }
    function dayShown(): bool { return page.dayShown }
    function daySend(text: string): void { page.sendDay(text) }
    function dayKey(key: int, mods: int): bool { return page.dayKey({ key: key, text: "", modifiers: mods }) }
    function dayTurns(): string { return JSON.stringify(page.dayTurns.map(function (t) { return t.role + ": " + t.text })) }
    function dayBlockText(): string { return page.dayBlockText }
    function dayType(text: string): void { var f = page.dayFieldItem(); f.text = text; f.cursorPosition = text.length }
    function dayFieldText(): string { return page.dayFieldItem().text }
    function dayReadOnly(): bool { return page.dayFieldItem().readOnly }
    function dayMention(): string { return JSON.stringify(page.dayMention ? page.dayMention.items.map(function (m) { return m.head }) : []) }
    function dayCardFocus(): int { return page.dayCardFocus }
    function dayCards(): string {
      var out = []
      page.dayTurns.forEach(function (t) { (t.proposals || []).forEach(function (c) { out.push({ kind: c.kind, state: page.dayCardState(c, t.at) }) }) })
      return JSON.stringify(out)
    }
    function sidebarOpen(): bool { return page.sidebarOpen }
    function surfaces(): string { return JSON.stringify(page.surfaces()) }
    function marginOpen(on: bool): void { page.marginOpen = on }
    function calDay(y: int, m: int, d: int): void { page.calFocus = new Date(y, m - 1, d) }
    function calAt(): string { return Qt.formatDate(page.calFocus, "yyyy-MM-dd") }
    // A key as the sidebar's own handler gets it: the calendar, the day's
    // deadlines, the projects. Where it stands in them: -1 is not in it.
    function sideKey(key: int, mods: int): bool {
      var sb = page.contentItem.children.filter(function (k) { return k.sidebarKeysRef !== undefined })[0]
      return sb.keyPressed({ key: key, text: "", modifiers: mods })
    }
    function sideFocus(): string { return JSON.stringify({ due: page.dueFocus, proj: page.projFocus }) }
    function goFirstDue(): void { page.goToDeadline(page.focusDue[0]) }
    // The day's deadline list as the keyboard drives it: focus a row, a key.
    function dueKey(i: int, key: int, mods: int): bool { page.dueFocus = i; return page.dueKey({ key: key, text: "", modifiers: mods }) }
    function tasks(): void { page.toggleTasks() }
    function rows(): string { return JSON.stringify(page.taskRows.map(function (r) { return r.kind + ":" + (r.deadline ? r.deadline.title : (r.date || "")) })) }
    function focusRow(i: int): void { page.taskFocus = i }
    function activate(): void { page.activateTask() }
    function tickRow(): void { page.tickFocused() }
    function acceptAt(i: int): void { page.acceptProposal(i) }
    // A block's cards from the one list (2026-11-15): Del on one, and how
    // each reads — open while the list has it, else as the page settled it.
    function declineAt(i: int): void { page.settleListedCard(page.currentProposals[i], "decline") }
    function marginListed(): string {
      return JSON.stringify(page.currentProposals.filter(function (c) { return !!c.ledger }).map(function (c) {
        return { kind: c.kind, live: !!page.dayCardLive({ id: c.ledger }), state: page.dayCardSettled[c.ledger] || "" }
      }))
    }
    // What omarchy-shell's own applyTheme does when a theme is set.
    function applyTheme(colorsB64: string, shellB64: string): string { Commons.Color.loadColors(Qt.atob(colorsB64)); Commons.Color.loadShell(Qt.atob(shellB64)); return "ok" }
    function palette(): string { var p = page.palette; return "keys=" + Object.keys(p.keys).length + " accent=" + p.accent + " dim=" + p.dim + " faint=" + p.faint + " h=" + p.headings.join(",") + " eh=" + page.editorItem.headingColors + " bullet=" + page.editorItem.bulletColor + " fg=" + page.foreground + " bg=" + page.background }
    function search(q: string): void { page.openSearch(); page.searchInput.text = q }
    function selectSpan(a: int, b: int): void { page.editorItem.selectSpan(a, b) }
    // Inside one line, the way a drag selects: the field's own selection.
    function selectInLine(a: int, b: int): void { page.editorItem.select(a, b) }
    function projects(): string { return JSON.stringify(page.projects.map(function (p) { return p.tag + "|" + page.sessionLabel(p.next) })) }
    function startClass(i: int): void { page.startClass(page.projects[i]) }
    function openProject(i: int): void { page.openProject(page.projects[i]) }
    // The project's view as one list (ProjectView.js): its rows, the one
    // picked, a step, Enter.
    function projectRows(): string { return JSON.stringify({ rows: page.projectRows.map(function (r) { return r.kind + "|" + r.key }), focus: page.projectFocusKey }) }
    function projectStep(d: int): void { page.moveSectionFocus(d) }
    function projectPick(key: string): void { page.pickProjectRow(key) }
    function projectOpenRow(): void { page.openInProject() }
    function sections(): string { return JSON.stringify(page.sections.map(function (s) { return s.date + "|" + s.title + "|" + Say.sectionUnder(s) })) }
    function openSection(i: int): void { page.sectionFocus = i; page.openSection(page.sections[i]) }
    // One project's part of the day (Focus.js): its tag, and the lines drawn.
    function sectionFocus(): int { return page.sectionFocus }
    function sectionCounts(): string { return JSON.stringify(page.sections.map(function (s) { return Say.sectionCounts(s) })) }
    function focusTag(): string { return page.editorItem.focusTag }
    function shownLines(): string {
      var ed = page.editorItem
      return JSON.stringify(ed.rows.filter(function (r, i) { return ed.isShown(i) }).map(function (r) { return r.raw }))
    }
    function toggleFocus(): void { page.toggleFocus() }
    function unfocus(): void { page.unfocus() }
    function projectDocs(): string { return JSON.stringify(page.projectDocs()) }
    function docFocus(): int { return page.docFocus }
    function moveSectionFocus(d: int): void { page.moveSectionFocus(d) }
    function leaveProject(): void { page.leaveProject() }
    // The projects list as the keyboard drives it: focus a row, then Enter.
    function projectEnter(i: int, ctrl: bool, shift: bool): void {
      page.projFocus = i
      page.projectsKey({ key: Qt.Key_Return, text: "\r", modifiers: (ctrl ? Qt.ControlModifier : 0) | (shift ? Qt.ShiftModifier : 0) })
    }
    // A key on a row of the projects list, as its own handler gets it.
    function projectKey(i: int, key: int, mods: int): bool {
      page.projFocus = i
      return page.projectsKey({ key: key, text: "", modifiers: mods })
    }
    function panel(): string { return JSON.stringify({ project: page.projectOpen, tasks: page.tasksOpen, margin: page.marginOpen, focus: page.sectionFocus }) }
    // The conversation as the margin draws it, and whether the box has the
    // keyboard — which is where Ctrl+Enter on an answered block must land.
    function chat(): string { return JSON.stringify(page.chatTurns.map(function (t) { return t.role + ": " + t.text })) }
    function answering(): bool { return page.answering }
    function heldTurn(): string { return JSON.stringify(page.pendingChat) }
    function chatFocused(): bool { return page.marginFocus === page.currentProposals.length }
    function sendChat(text: string): void { page.pendingChat = { hash: page.currentRec, text: text }; page.requestChat(page.currentRec, text, page.currentHash) }
    function reply(): string { var r = page.currentRecord; return r && r.reply ? r.reply : "" }
    function askWord(): string { return Queue.answered(page.currentRecord) ? "reply" : "ask" }
    function insertTag(i: int): void { page.insertTag(page.projects[i]) }
    // The keys sheet, and a key as the page's own filter would get it.
    function keys(): void { page.toggleKeys() }
    function keysOpen(): bool { return page.keysOpen }
    function keysFind(s: string): void { page.keysFilter = s; page.keysFocus = page.nextKeyRow(-1, 1) }
    function keysKey(key: int, mods: int): bool { return page.keysKey({ key: key, text: "", modifiers: mods }) }
    function keysNote(): string { return page.keysNote }
    function keyRows(): string { return JSON.stringify(page.keyRows) }
    function keysOf(id: string): string { page.keysVersion; return JSON.stringify(Sc.keysOf(id).map(Sc.show)) }
    // Hyprland's six, as hyprkeys.py last answered, and whether it is busy.
    function hyprKeys(): string { return JSON.stringify(page.hyprKeys) }
    function keysListening(): bool { return !!page.keysListen }
    // A hover's hint for an action, as the mouse would see it.
    function tip(id: string): string { return page.tip("does", id) }
    function pageKey(key: int, mods: int): bool { return page.pageKey({ key: key, text: "", modifiers: mods }) }
    function moveLines(d: int): void { page.editorItem.moveLines(d) }

    // The dashboard
    function editQueue(): string { return JSON.stringify(page.editQueueState) }
    function checkState(): string { return JSON.stringify({ wanted: page.checkWanted, checking: page.checking, hint: page.hint }) }
    // Talking with the planner about a proposal, beside the dashboard.
    function talk(): string {
      var m = page.marginItem
      return JSON.stringify({ open: page.talkOpen, id: page.talkId, thread: page.talkThread, settled: page.talkSettled,
        item: !page.talkItem ? "" : page.talkItem.kind === "question" ? page.talkItem.question : Say.sayAsk(page.talkItem, false), talking: page.talking, visible: m.visible,
        turns: page.talkTurns.map(function (t) { return t.role + ": " + t.text }),
        marginX: m.x, marginWidth: m.width, dashX: page.dashItem.x, dashWidth: page.dashItem.width, chatFocus: m.chatFieldRef.activeFocus })
    }
    function sayDate(d: string): string { return Say.sayDate(d) }
    function noteTurns(): string { return JSON.stringify(page.noteTurns.map(function (t) { return (t.who === "planner" ? "planner " : "") + t.role + ": " + t.text })) }
    function talkSend(text: string): void { page.marginItem.chatFieldRef.text = text; page.sendTalk() }
    function talkKey(key: int, mods: int): bool { return page.talkKey({ key: key, text: "", modifiers: mods }) }
    function dash(): void { page.toggleDash() }
    function dashOpen(): bool { return page.dashOpen }
    function dashFocused(): bool { return page.dashItem.dashKeysRef.activeFocus }
    function dashFocus(i: int): void { page.taskFocus = i }
    function focusedDashRow(): string { var r = page.taskRows[page.taskFocus]; return r ? r.kind + "/" + (r.item ? r.item.kind : (r.task ? Say.taskTitle(r.task) : "")) : "" }
    function acceptRow(rowKind: string, ask: string): bool {
      for (var i = 0; i < page.taskRows.length; i++) {
        var r = page.taskRows[i]
        if (r.kind === rowKind && r.item && r.item.kind === ask) { page.acceptPlanned(r); return true }
      }
      return false
    }
    // Find the row and press the key in one step, so a list read again in
    // between cannot move the key onto another row.
    function dashKeyOn(rowKind: string, ask: string, key: int, mods: int): bool {
      for (var i = 0; i < page.taskRows.length; i++) {
        var r = page.taskRows[i]
        if (r.kind === rowKind && r.item && r.item.kind === ask) { page.taskFocus = i; return page.dashKey({ key: key, text: "", modifiers: mods }) }
      }
      return false
    }
    function dashAt(): int { return page.taskFocus }
    function dashAgent(): string { return JSON.stringify(page.dashAgent) }
    function dashStatus(): string { return page.dashStatus }
    function clickAgentChip(): string { page.clickAgentChip(); return String(page.taskFocus) }
    function newSince(): string { return page.newAfterId + " | " + page.proposals.map(function (x) { return x.id }).join(",") }
    function ticksHeard(): int { return page.ticksHeard }
    function plan(force: bool): void { page.runPlan(force) }
    function refreshProposals(): void { page.refreshProposals() }
    function setAutonomy(kind: string, level: string): void { page.setAutonomy(kind, level) }
    function autonomyKey(key: int, mods: int): bool { return page.autonomyKey({ key: key, text: "", modifiers: mods }) }
    function autonomyKinds(): string { return JSON.stringify(page.autonomyData ? page.autonomyData.kinds.map(function (k) { return k.kind + "=" + k.level }) : []) }
    function autonomyFocus(i: int): void { page.autonomyFocus = i }
    function sayReads(rec: string): string { return page.sayReads(JSON.parse(rec)) }
    function rate(value: string): void { page.rateReply(value) }
    // Who made it
    function markAgent(line: int): void { page.markAuthor(line, "agent") }
    function markAuthor(line: int, author: string): void { page.markAuthor(line, author) }
    function authorOf(line: int): string { return page.shownAuthors[line] || "" }
    function authorsStore(): string { return JSON.stringify(page.authorsStore) }
    function rowAuthor(i: int): string { return page.rowAuthor(page.taskRows[i]) }
    function tickSoundToggle(): void { page.toggleTickSound() }
    // The panes (docs/navigation.md): which are open, what each shows,
    // where the focus frame is drawn.
    function panes(): string {
      return JSON.stringify({ panes: page.panes, here: page.here, center: page.centerView, right: page.rightView,
                              pointer: page.pointerMode })
    }
    // Where the note and the panes beside it are drawn (Layout.js).
    function sides(): string {
      var c = page.contentItem
      var sb = c.children.filter(function (k) { return k.sidebarKeysRef !== undefined })[0]
      var dp = c.children.filter(function (k) { return k.dayFieldRef !== undefined })[0]
      return JSON.stringify({ x: page.sheetX, w: page.sheetWidth, gap: page.marginGap, width: c.width, edge: page.edge,
                              left: sb && sb.visible ? sb.x : null, leftEnd: sb && sb.visible ? sb.x + sb.width : null,
                              right: dp && dp.visible ? dp.x : null, rightEnd: dp && dp.visible ? dp.x + dp.width : null })
    }
    function closePanes(): void { if (page.sidebarOpen) page.toggleSidebar(); page.closeRight(); if (page.dashOpen) page.toggleDash() }
    // As the dashboard's own handler does: the global keys first.
    function dashKey(key: int, mods: int): bool { var e = { key: key, text: "", modifiers: mods }; return page.anywhereKey(e) || page.dashKey(e) }
    function dashType(ch: string): bool { return page.dashKey({ key: ch.toUpperCase().charCodeAt(0), text: ch, modifiers: 0 }) }
    function strip(): string {
      return JSON.stringify({ at: page.stripAt, open: page.stripOpen, pick: page.stripPick, lens: page.dashLens, query: page.dashQuery,
                              order: page.dashOrder, chips: page.stripChips.map(function (c) { return c.label }),
                              shown: page.dashCourses.shown, total: page.dashCourses.total })
    }
    function dashWhen(phrase: string): void { page.dashWhenText = phrase; page.commitDashWhen() }
    function dashWhenStart(): void { page.startDashWhen() }
    function dashWhenField(): string { var f = page.dashItem.dashWhenFieldRef; return JSON.stringify({ focus: f.focus, text: f.text }) }
    // The rows as drawn: each shown one's words, in the order on screen,
    // and how many drawn rows were made anew since the last call (a mark
    // left on each one seen) — typing into ⌕ makes none (2026-11-13).
    function dashDrawn(): string {
      page.dashItem.dashColumnRef.forceLayout()
      var kids = page.dashItem.dashColumnRef.children, shown = [], fresh = 0
      var rows = kids.filter(function (k) { return k.rowId !== undefined })
      rows.sort(function (a, b) { return a.y - b.y })
      for (var i = 0; i < rows.length; i++) {
        var k = rows[i]
        if (fakeShell.seenRows.indexOf(k) < 0) { fresh++; fakeShell.seenRows.push(k) }
        if (!k.visible) continue
        var d = k.modelData
        shown.push(d.kind === "task" ? d.task.text : d.kind === "deadline" ? d.deadline.title : d.kind + ":" + (d.text || d.id || ""))
      }
      return JSON.stringify({ shown: shown, fresh: fresh })
    }
    // ⌕'s line of text (2026-11-13): whether it has the keys, what it
    // holds and where its caret is; and words put into it as typing does.
    function dashSearchField(): string {
      var f = page.dashItem.searchFieldRef
      return JSON.stringify({ focus: f.activeFocus, text: f.text, cursor: f.cursorPosition, query: page.dashQuery, pending: page.dashSearchPending })
    }
    function dashSearchInsert(s: string): void { var f = page.dashItem.searchFieldRef; f.insert(f.cursorPosition, s) }
    function dashSearchCursor(pos: int): void { page.dashItem.searchFieldRef.cursorPosition = pos }
    function dashSearchKey(key: int, mods: int): bool {
      return page.dashSearchKey({ key: key, text: "", modifiers: mods }, page.dashItem.searchFieldRef)
    }
    function dashRows(): string {
      return JSON.stringify(page.taskRows.map(function (r) {
        return r.kind === "head" ? { kind: "head", text: r.text, tag: r.tag || "" }
          : r.kind === "month" ? { kind: "month", text: r.text }
          : r.kind === "band" ? { kind: "band", id: r.id, text: r.text, count: r.count, open: r.open }
          : r.kind === "shelf" || r.kind === "grading" ? { kind: r.kind, count: r.count }
          : r.kind === "raised" ? { kind: "raised", text: r.item.text }
          : r.kind === "proposal" || r.kind === "told" ? { kind: r.kind, id: r.item.id, date: r.item.date, why: r.item.why,
                                      under: r.task ? Say.taskTitle(r.task) : "", file: r.item.kind === "file" ? r.item.name : "",
                                      ask: r.item.kind, say: Say.sayAsk(r.item, !!r.task), fresh: page.isNewAsk(r.item) }
          : r.kind === "question" ? { kind: "question", id: r.item.id, text: r.item.question, recommended: r.item.recommended,
                                      fresh: page.isNewAsk(r.item) }
          : r.kind === "deadline" ? { kind: "deadline", text: r.deadline.title, due: r.deadline.due, status: r.deadline.status,
                                      where: page.deadlineWhere(r.deadline), grade: r.deadline.grade,
                                      mark: Say.taskMark(page.taskOfAnchor(r.deadline.id)),
                                      pills: page.pillsFor(r).map(function (x) { return x.text }),
                                      chat: page.chatState(r), last: page.chatOf(r) ? page.chatOf(r).text : "" }
          : { kind: "task", text: Say.taskTitle(r.task), where: Say.taskWhere(r.task, undefined, page.projects),
              date: r.task.date, prio: r.task.priority, when: r.task.when, away: r.task.away || "", done: !!r.task.done,
              priv: !!r.task["private"], chat: page.chatState(r), last: page.chatOf(r) ? page.chatOf(r).text : "" }
      }))
    }

    // Settings
    function settings(): void { page.toggleSettings() }
    function settingsOpen(): bool { return page.settingsOpen }
    function settingsSave(url: string): void { page.addCalendar(url) }
    function settingsFocus(i: int): void { page.settingsFocus = i }
    // A row of the settings list by its kind ("notebook", "sound", …), as ↑↓ would pick it.
    function settingsPick(kind: string): void { page.settingsFocus = page.settingsAt(kind) }
    function settingsPicked(): string { return page.settingsPicked() }
    function settingsAsking(): int { return page.settingsAsking }
    function settingsType(t: string): void { page.settingsSheetItem.settingsFieldRef.text = t }
    function tickSoundOn(): bool { return page.settingsData.tickSound !== false }
    function pointerMode(): string { return page.pointerMode }
    function settingsKey(key: int, mods: int): bool { return page.settingsKey({ key: key, text: "", modifiers: mods }) }
    function settingsLines(): string { return JSON.stringify(page.settingsLines().map(function (l) { return l.text })) }
    function settingsNote(): string { return page.settingsNote }
    function settingsView(): string { return page.settingsView }
    function notebookKey(key: int, mods: int): bool { return page.notebookKey({ key: key, text: "", modifiers: mods }) }
    function notebookRows(): string { return JSON.stringify(page.notebookList) }
    function notebookFocus(i: int): void { page.notebookFocus = i }
    function notebookPicked(): int { return page.notebookFocus }
    function notebookNote(): string { return page.notebookNote }
    function notebookCorrecting(): bool { return page.notebookCorrecting }
    function notebookAsking(): bool { return page.notebookAsking }
    function notebookType(t: string): void { page.notebookSheetItem.notebookFieldRef.text = t }

    // The measure
    function zoom(z: real): void { page.setZoom(z) }
    function layout(): string { return JSON.stringify({ chars: page.editorItem.width / page.chWidth, x: page.sheetX, w: page.sheetWidth }) }
  }
}
