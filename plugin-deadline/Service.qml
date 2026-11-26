import QtQuick
import Quickshell
import Quickshell.Io
import "Store.js" as Store

// Live deadline list. Watches the CLI's deadlines.tsv (one
// "id<TAB>epoch<TAB>title<TAB>status<TAB>done_at<TAB>grade<TAB>project<TAB>link"
// per line; older lines stop after grade or after title) and
// recomputes countdowns locally every second — same no-polling shape as the
// pomodoro Service. All writes go through the CLI so the file has one owner.
Item {
  id: root

  property var settings: ({})

  // Parsed file contents, hidden ones dropped, sorted open-first then by due.
  property var items: []
  property int nowSec: Math.floor(Date.now() / 1000)

  readonly property string filePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/longhand/deadlines.tsv"

  // What the bar shows: the soonest *open* deadline still ahead, or — when
  // every open one has already passed — the least-late one. Done deadlines
  // are off the clock. Mirrors `pomo deadline next`.
  readonly property var nextItem: pickNext()

  function pickNext() {
    var last = null
    for (var i = 0; i < items.length; i++) {
      if (items[i].status !== "open") continue
      if (items[i].due >= nowSec) return items[i]
      last = items[i]
    }
    return last
  }

  // Urgency bands, shared by the bar label and the popup rows.
  readonly property int soonSecs: 24 * 3600
  readonly property int nearSecs: 3 * 24 * 3600

  function isLate(due) {
    return due < nowSec
  }

  function isUrgent(due) {
    return due - nowSec < soonSecs
  }

  function isNear(due) {
    return due - nowSec < nearSecs
  }

  function unit(secs) { // largest whole unit: 4d / 3h / 25m
    var a = Math.abs(secs)
    if (a >= 86400) return Math.floor(a / 86400) + "d"
    if (a >= 3600) return Math.floor(a / 3600) + "h"
    return Math.floor(a / 60) + "m"
  }

  function fmtRel(due) { // "in 4d" / "2h late"
    var d = due - nowSec
    return d < 0 ? unit(d) + " late" : "in " + unit(d)
  }

  function fmtWhen(due) { // "Fri 11 Sep 17:00"
    return Qt.formatDateTime(new Date(due * 1000), "ddd d MMM HH:mm")
  }

  function fmtDay(ts) { // "11 Sep"
    return Qt.formatDateTime(new Date(ts * 1000), "d MMM")
  }

  // Bar label: bare countdown, no "in" — the calendar glyph already says what
  // it is, and bar space is the scarcest thing on screen. A tick means the
  // list is not empty but everything on it is handed in.
  readonly property string labelText: nextItem
    ? " " + (isLate(nextItem.due) ? "late" : unit(nextItem.due - nowSec))
    : (items.length > 0 ? " ✓" : " --")

  readonly property string tooltipText: nextItem
    ? nextItem.title + " — " + fmtWhen(nextItem.due) + " (" + fmtRel(nextItem.due) + ")"
    : (items.length > 0
      ? "All deadlines handed in"
      : "No deadlines — pomo deadline add \"Essay draft\" friday")

  function tick() {
    nowSec = Math.floor(Date.now() / 1000)
  }

  // The columns are the CLI's (Store.js, which tools/install-plugins puts
  // beside this file). Hidden and cancelled ones are not the list's.
  function applyText(raw) {
    var out = Store.parse(raw).map(root.asAsked).filter(function (d) { return d.status !== "hidden" && d.status !== "cancelled" })
    // Open ones first (they are what the list is for), then done ones fade
    // out at the bottom. Same order as `pomo deadline list`.
    out.sort(function (a, b) {
      if (a.status !== b.status) return a.status === "open" ? -1 : 1
      return a.due - b.due
    })
    items = out
  }

  function fileGone() {
    items = []
  }

  // Fire-and-forget CLI actions; the FileView picks up the result. One
  // action at a time: the file is rewritten whole, so two in flight would
  // race each other. The ones asked meanwhile wait their turn (2026-11-26:
  // they were dropped, so Space twice quickly ticked and never unticked).
  property var queue: []            // [{ args, id, status }]
  property var job: null
  function run(args, id, status) {
    root.queue = root.queue.concat([{ args: args, id: id, status: status }])
    root.next()
  }
  function next() {
    if (actionProc.running || root.queue.length === 0) return
    root.job = root.queue[0]
    root.queue = root.queue.slice(1)
    actionProc.command = ["pomo", "deadline"].concat(root.job.args)
    actionProc.running = true
  }
  // A command through: its tick is the store's own word now, unless the
  // same one was asked for again meanwhile.
  function jobDone() {
    var j = root.job
    root.job = null
    if (j && j.status !== undefined && root.pending[j.id] === j.status) {
      var q = {}
      for (var k in root.pending) if (String(k) !== String(j.id)) q[k] = root.pending[k]
      root.pending = q
    }
    root.next()
  }

  // A tick asked for and not yet written (id → status) is the list's at
  // once, so a second press acts on what the first made, as in the page
  // (Deadlines.qml, `pending`).
  property var pending: ({})
  function asAsked(d) {
    var want = root.pending[d.id]
    if (want === undefined || d.status === want) return d
    var c = {}
    for (var k in d) c[k] = d[k]
    c.status = want
    return c
  }
  function ask(id, status, args) {
    var p = {}
    for (var k in root.pending) p[k] = root.pending[k]
    p[id] = status
    root.pending = p
    root.items = root.items.map(root.asAsked)
    root.run(args, id, status)
  }

  // Nothing is deleted from here: cancelling marks the line `[-]` and keeps
  // the deadline as history (docs/tasks.md).
  function cancel(id) { run(["cancel", String(id)]) }
  function markDone(id) { root.ask(id, "done", ["done", String(id)]) }
  function reopen(id) { root.ask(id, "open", ["reopen", String(id)]) }
  function hide(id) { run(["hide", String(id)]) }
  function grade(id, text) { run(["grade", String(id), String(text)]) }

  function toggleDone(item) {
    if (item.status === "open") markDone(item.id)
    else reopen(item.id)
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  FileView {
    path: root.filePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyText(text())
    onLoadFailed: root.fileGone()
  }

  // After every change, the note lines follow (one copy of a task); and
  // when the popup opens, edits made elsewhere are caught. One at a time.
  function check() {
    if (checkProc.running) { checkProc.again = true; return }
    checkProc.running = true
  }

  Process {
    id: actionProc
    running: false
    onExited: { root.check(); root.jobDone() }
  }

  Process {
    id: checkProc
    property bool again: false
    command: ["longhand-check", "--quiet"]
    running: false
    onExited: if (checkProc.again) { checkProc.again = false; checkProc.running = true }
  }
}
