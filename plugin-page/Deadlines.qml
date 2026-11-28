import QtQuick
import Quickshell
import Quickshell.Io
import "Store.js" as Store

// The deadline store, as the page sees it. Reads `deadlines.tsv` (watched,
// so the popup's and the CLI's changes arrive on their own) and changes it
// only through `pomo deadline …`, one command at a time: the CLI rewrites
// the file whole, so two in flight would race. The store wins over the
// notes; the page brings bound lines in line with it, never the reverse.
Item {
  id: root

  property var items: []          // every deadline, hidden ones included
  property var byId: ({})
  // True only once the file has been read. A store that could not be read
  // is unknown, not empty: nothing may be concluded from it (a note's
  // bound lines must not lose their anchors because the file was missing).
  property bool loaded: false

  readonly property string filePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/longhand/deadlines.tsv"

  // A tick asked for and not yet written: id → the status it asked for.
  // It is the list's at once, so a second Ctrl+L or Space right after the
  // first unticks rather than ticking again from a list the store has not
  // caught up with yet (2026-11-26: a slow machine, and a quick hand,
  // ticked twice; Windows CI caught it). The store's own word replaces it
  // once the command is through.
  property var pending: ({})

  // The columns are the CLI's (Store.js).
  function parse(raw) {
    var out = Store.parse(raw)
    var map = {}
    for (var i = 0; i < out.length; i++) {
      var want = root.pending[out[i].id]
      if (want !== undefined && out[i].status !== want) out[i] = root.withStatus(out[i], want)
      map[out[i].id] = out[i]
    }
    root.items = out
    root.byId = map
    root.loaded = true
  }

  FileView {
    id: file
    path: root.filePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: { root.items = []; root.byId = ({}); root.loaded = false }
    onFileChanged: reload()
  }

  // ------------------------------------------------------------ commands

  property var queue: []
  property var job: null
  // A command running or waiting; `idle` when the last one is done (its
  // `done` already run), so what it wrote is in the note too.
  readonly property bool busy: root.job !== null || root.queue.length > 0
  signal idle()
  // The store was changed by the page (not a date being read): the notes'
  // other lines follow, through the check.
  signal changed()
  property int exitCode: 0
  property bool exited: false
  property bool streamed: false

  function run(args, done) {
    root.queue = root.queue.concat([{ args: args, done: done || null }])
    root.next()
  }

  function next() {
    if (root.job || root.queue.length === 0) return
    root.job = root.queue[0]
    root.queue = root.queue.slice(1)
    root.exited = false
    root.streamed = false
    proc.command = ["pomo", "deadline"].concat(root.job.args)
    proc.running = true
  }

  // A command is over when it has exited and its output is read, in
  // whichever order those arrive.
  function finish() {
    if (!root.exited || !root.streamed || !root.job) return
    var j = root.job
    root.job = null
    if (root.exitCode !== 0) console.warn("longhand.page pomo " + j.args.join(" ") + ": " + err.text.trim())
    // A first deadline creates the file, which a watch on a missing file
    // does not see: read it again after every change.
    else if (j.args[0] !== "when") { file.reload(); root.changed() }
    if (j.done) j.done(root.exitCode, out.text)
    root.next()
    if (!root.busy) root.idle()
  }

  Process {
    id: proc
    stdout: StdioCollector { id: out; onStreamFinished: { root.streamed = true; root.finish() } }
    stderr: StdioCollector { id: err }
    onExited: function (code, status) { root.exitCode = code; root.exited = true; root.finish() }
  }

  function words(s) { return String(s).trim().split(/\s+/).filter(function (w) { return w !== "" }) }

  // How a date phrase reads: done({ ms, label }) or done(null).
  function when(phrase, done) {
    root.run(["when"].concat(root.words(phrase)), function (code, text) {
      var f = text.trim().split("\t")
      done(code === 0 && f.length === 2 ? { ms: parseInt(f[0], 10) * 1000, label: f[1] } : null)
    })
  }

  // A new deadline: done(id) with its id, or done(0).
  function add(title, project, phrase, done) {
    var args = ["add", title]
    if (project !== "") args.push("--project", project)
    root.run(args.concat(root.words(phrase)), function (code, text) {
      var m = text.match(/#(\d+)/)
      done(code === 0 && m ? parseInt(m[1], 10) : 0)
    })
  }

  function set(id, args, done) { root.run(["set", String(id)].concat(args), done) }
  function withStatus(d, status) {
    var c = {}
    for (var k in d) c[k] = d[k]
    c.status = status
    // Closed now, as the store will say: with no moment of its own it read
    // as closed before today, and stood under "waiting for a grade" until
    // the store was read again (2026-11-27).
    c.doneAt = status === "open" ? 0 : Math.floor(Date.now() / 1000)
    return c
  }
  function ask(id, status, args) {
    var p = {}
    for (var k in root.pending) p[k] = root.pending[k]
    p[id] = status
    root.pending = p
    var d = root.byId[id]
    if (d && d.status !== status) {
      var c = root.withStatus(d, status), map = {}
      for (var m in root.byId) map[m] = root.byId[m]
      map[id] = c
      root.byId = map
      root.items = root.items.map(function (x) { return x.id === id ? c : x })
    }
    root.run(args, function () {
      if (root.pending[id] !== status) return       // asked again meanwhile
      var q = {}
      for (var k2 in root.pending) if (String(k2) !== String(id)) q[k2] = root.pending[k2]
      root.pending = q
    })
  }
  function markDone(id) { root.ask(id, "done", ["done", String(id)]) }
  function reopen(id) { root.ask(id, "open", ["reopen", String(id)]) }
  function remove(id) { root.run(["rm", String(id)]) }
  function hide(id) { root.run(["hide", String(id)]) }
  function cancel(id) { root.run(["cancel", String(id)]) }
  // A grade, as the popup takes it; empty clears it. Grading one still open
  // hands it in (pomo).
  function grade(id, text) { root.run(["grade", String(id)].concat(root.words(text))) }
  // Read the file again now, rather than when the watch says so: after a
  // check, the page wants the store as it was left before it catches up.
  function reload() { file.reload() }
}
