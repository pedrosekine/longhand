import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import "page"
import "page/Shortcuts.js" as Sc

// The page under test: a stand-in for omarchy-shell (toggle / summon / hide
// as shell.qml does them), plus IPC handles to drive the page without a
// keyboard. tests/page/run.py builds a throwaway config around this file.
ShellRoot {
  QtObject {
    id: fakeShell
    function hide(id) { page.close(); return true }
  }
  Page { id: page; shell: fakeShell; windowTitle: "Page scratch" }
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
    function noSign(): bool { return page.noSignHint }
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

    function focusedRow(): string { var e = page.editorItem; return e.focusedRow + "/" + e.rows.length + " item=" + (!!e.rowItem(e.focusedRow)) }
    function mentionPick(i: int, shift: bool): void { page.mentionFocus = i; page.acceptMention(shift) }
    function hint(): string { return page.hint }
    function yes(): void { page.acceptAsk() }
    function no(): void { page.declineAsk() }
    // A key as the note's own filter sees it (Qt.Key_*, Qt modifiers).
    function keyPage(key: int, mods: int): bool { return page.pageKey({ key: key, text: "", modifiers: mods }) }
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
    function goFirstDue(): void { page.goToDeadline(page.focusDue[0]) }
    // The day's deadline list as the keyboard drives it: focus a row, a key.
    function dueKey(i: int, key: int, mods: int): bool { page.dueFocus = i; return page.dueKey({ key: key, text: "", modifiers: mods }) }
    function tasks(): void { page.toggleTasks() }
    function rows(): string { return JSON.stringify(page.taskRows.map(function (r) { return r.kind + ":" + (r.deadline ? r.deadline.title : (r.date || "")) })) }
    function focusRow(i: int): void { page.taskFocus = i }
    function activate(): void { page.activateTask() }
    function tickRow(): void { page.tickFocused() }
    function acceptAt(i: int): void { page.acceptProposal(i) }
    // What omarchy-shell's own applyTheme does when a theme is set.
    function applyTheme(colorsB64: string, shellB64: string): string { Commons.Color.loadColors(Qt.atob(colorsB64)); Commons.Color.loadShell(Qt.atob(shellB64)); return "ok" }
    function palette(): string { var p = page.palette; return "keys=" + Object.keys(p.keys).length + " accent=" + p.accent + " dim=" + p.dim + " faint=" + p.faint + " h=" + p.headings.join(",") + " eh=" + page.editorItem.headingColors + " bullet=" + page.editorItem.bulletColor + " fg=" + page.foreground + " bg=" + page.background }
    function search(q: string): void { page.openSearch(); page.searchInput.text = q }
    function selectSpan(a: int, b: int): void { page.editorItem.selectSpan(a, b) }
    function projects(): string { return JSON.stringify(page.projects.map(function (p) { return p.tag + "|" + page.sessionLabel(p.next) })) }
    function startClass(i: int): void { page.startClass(page.projects[i]) }
    function openProject(i: int): void { page.openProject(page.projects[i]) }
    function sections(): string { return JSON.stringify(page.sections.map(function (s) { return s.date + "|" + s.title + "|" + page.sectionUnder(s) })) }
    function openSection(i: int): void { page.sectionFocus = i; page.openSection(page.sections[i]) }
    function projectDocs(): string { return JSON.stringify(page.projectDocs()) }
    function docFocus(): int { return page.docFocus }
    function moveSectionFocus(d: int): void { page.moveSectionFocus(d) }
    function leaveProject(): void { page.leaveProject() }
    // The projects list as the keyboard drives it: focus a row, then Enter.
    function projectEnter(i: int, ctrl: bool, shift: bool): void {
      page.projFocus = i
      page.projectsKey({ key: Qt.Key_Return, text: "\r", modifiers: (ctrl ? Qt.ControlModifier : 0) | (shift ? Qt.ShiftModifier : 0) })
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
    function askWord(): string { return page.answered(page.currentRecord) ? "reply" : "ask" }
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
        item: !page.talkItem ? "" : page.talkItem.kind === "question" ? page.talkItem.question : page.sayAsk(page.talkItem, false), talking: page.talking, visible: m.visible,
        turns: page.talkTurns.map(function (t) { return t.role + ": " + t.text }),
        marginX: m.x, marginWidth: m.width, dashX: page.dashItem.x, dashWidth: page.dashItem.width, chatFocus: m.chatFieldRef.activeFocus })
    }
    function sayDate(d: string): string { return page.sayDate(d) }
    function noteTurns(): string { return JSON.stringify(page.noteTurns.map(function (t) { return (t.who === "planner" ? "planner " : "") + t.role + ": " + t.text })) }
    function talkSend(text: string): void { page.marginItem.chatFieldRef.text = text; page.sendTalk() }
    function talkKey(key: int, mods: int): bool { return page.talkKey({ key: key, text: "", modifiers: mods }) }
    function dash(): void { page.toggleDash() }
    function dashOpen(): bool { return page.dashOpen }
    function dashFocus(i: int): void { page.taskFocus = i }
    function focusedDashRow(): string { var r = page.taskRows[page.taskFocus]; return r ? r.kind + "/" + (r.item ? r.item.kind : (r.task ? page.taskTitle(r.task) : "")) : "" }
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
    function dashCount(): string { return page.dashCount }
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
      return JSON.stringify({ x: page.sheetX, w: page.sheetWidth, gap: page.marginGap,
                              left: sb && sb.visible ? sb.x + sb.width : null, right: dp && dp.visible ? dp.x : null })
    }
    function closePanes(): void { if (page.sidebarOpen) page.toggleSidebar(); page.closeRight(); if (page.dashOpen) page.toggleDash() }
    function dashKey(key: int, mods: int): bool { return page.dashKey({ key: key, text: "", modifiers: mods }) }
    function dashType(ch: string): bool { return page.dashKey({ key: ch.toUpperCase().charCodeAt(0), text: ch, modifiers: 0 }) }
    function dashWhen(phrase: string): void { page.dashWhenText = phrase; page.commitDashWhen() }
    function dashWhenStart(): void { page.startDashWhen() }
    function dashWhenField(): string { var f = page.dashItem.dashWhenFieldRef; return JSON.stringify({ focus: f.focus, text: f.text }) }
    function dashRows(): string {
      return JSON.stringify(page.taskRows.map(function (r) {
        return r.kind === "head" ? { kind: "head", text: r.text, tag: r.tag || "" }
          : r.kind === "month" ? { kind: "month", text: r.text }
          : r.kind === "shelf" || r.kind === "grading" ? { kind: r.kind, count: r.count }
          : r.kind === "raised" ? { kind: "raised", text: r.item.text }
          : r.kind === "proposal" || r.kind === "told" ? { kind: r.kind, id: r.item.id, date: r.item.date, why: r.item.why,
                                      under: r.task ? page.taskTitle(r.task) : "", file: r.item.kind === "file" ? r.item.name : "",
                                      ask: r.item.kind, say: page.sayAsk(r.item, !!r.task), fresh: page.isNewAsk(r.item) }
          : r.kind === "question" ? { kind: "question", id: r.item.id, text: r.item.question, recommended: r.item.recommended,
                                      fresh: page.isNewAsk(r.item) }
          : r.kind === "deadline" ? { kind: "deadline", text: r.deadline.title, due: r.deadline.due,
                                      where: page.deadlineWhere(r.deadline), grade: r.deadline.grade }
          : { kind: "task", text: page.taskTitle(r.task), where: page.taskWhere(r.task),
              date: r.task.date, prio: r.task.priority, when: r.task.when, away: r.task.away || "", done: !!r.task.done }
      }))
    }

    // Settings
    function settings(): void { page.toggleSettings() }
    function settingsOpen(): bool { return page.settingsOpen }
    function settingsSave(url: string): void { page.addCalendar(url) }
    function settingsFocus(i: int): void { page.settingsFocus = i }
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
    function notebookType(t: string): void { page.notebookSheetItem.notebookFieldRef.text = t }

    // The measure
    function zoom(z: real): void { page.setZoom(z) }
    function layout(): string { return JSON.stringify({ chars: page.editorItem.width / page.chWidth, x: page.sheetX, w: page.sheetWidth }) }
  }
}
