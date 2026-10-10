import QtQuick
import Quickshell
import Quickshell.Io

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
    || Quickshell.env("HOME") + "/.local/state") + "/omarchy-student/deadlines.tsv"

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

  function applyText(raw) {
    var out = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("\t")
      if (f.length < 3) continue
      var id = parseInt(f[0], 10)
      var due = parseInt(f[1], 10)
      if (!isFinite(id) || !isFinite(due)) continue
      // Columns past the eighth are ignored rather than folded into the
      // title: the widget is installed as a *copy* of this file, so a newer
      // CLI adding a column must not make a stale install render it as text.
      var status = f.length > 3 ? f[3] : "open"
      if (status !== "done" && status !== "hidden") status = "open"
      if (status === "hidden") continue
      var doneAt = f.length > 4 ? parseInt(f[4], 10) : 0
      out.push({
        id: id,
        due: due,
        title: f[2],
        status: status,
        doneAt: isFinite(doneAt) ? doneAt : 0,
        grade: f.length > 5 ? f[5] : "",
        project: f.length > 6 ? f[6] : "",
        link: f.length > 7 ? f[7] : ""
      })
    }
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
  // race each other.
  function run(args) {
    if (actionProc.running) return
    actionProc.command = ["pomo", "deadline"].concat(args)
    actionProc.running = true
  }

  function remove(id) { run(["rm", String(id)]) }
  function markDone(id) { run(["done", String(id)]) }
  function reopen(id) { run(["reopen", String(id)]) }
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

  Process {
    id: actionProc
    running: false
  }
}
