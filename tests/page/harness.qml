import Quickshell
import Quickshell.Io
import QtQuick
import "page"

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
    function toggle(payload: string): void { if (page.opened) fakeShell.hide("student.page"); else page.open(payload) }
    function closeAll(): void { page.windowOpen = false; page.close() }
    function state(): string { return JSON.stringify({ overlay: page.overlayOpen, window: page.windowOpen, ready: page.editorItem.enabled }) }
    // The note
    function text(): string { return page.editorItem.text }
    function insert(s: string): void { var e = page.editorItem; e.insert(e.cursorPosition, s) }
    function cursor(pos: int): void { page.editorItem.setCursor(pos, true) }
    function cursorEnd(): void { page.editorItem.setCursor(page.editorItem.length, true) }
    function cursorLine(): int { return page.lineIndexAt(page.editorItem.cursorPosition) }
    function tick(line: int): void { page.editorItem.toggleCheckbox(line) }
    function removeLine(line: int): void { var e = page.editorItem; var r = e.rows[line]; e.remove(r.start, r.start + r.raw.length + 1) }
    function openDay(stem: string): void { page.openNote(stem) }
    function header(): string { return page.dateLabel }
    // Prompts and keys
    function ask(): string { return JSON.stringify(page.ask) }
    function hint(): string { return page.hint }
    function yes(): void { page.acceptAsk() }
    function no(): void { page.declineAsk() }
    function typeAtPrompt(ch: string): bool { return page.askKey({ key: ch.toUpperCase().charCodeAt(0), text: ch, modifiers: 0 }) }
    function enterAtPrompt(): bool { return page.askKey({ key: Qt.Key_Return, text: "\r", modifiers: 0 }) }
    function rightAtPrompt(): bool { return page.askKey({ key: Qt.Key_Right, text: "", modifiers: 0 }) }
    function ctrlD(): void { page.deadlineKey() }
    function when(s: string): void { page.whenInput.text = s; page.submitWhen() }
    // Panels
    function sidebar(): void { page.toggleSidebar() }
    function calDay(y: int, m: int, d: int): void { page.calFocus = new Date(y, m - 1, d) }
    function goFirstDue(): void { page.goToDeadline(page.focusDue[0]) }
    function tasks(): void { page.toggleTasks() }
    function rows(): string { return JSON.stringify(page.taskRows.map(function (r) { return r.kind + ":" + (r.deadline ? r.deadline.title : (r.date || "")) })) }
    function focusRow(i: int): void { page.taskFocus = i }
    function activate(): void { page.activateTask() }
    function tickRow(): void { page.tickFocused() }
    function acceptAt(i: int): void { page.acceptProposal(i) }
  }
}
