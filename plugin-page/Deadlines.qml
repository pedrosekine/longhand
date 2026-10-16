import QtQuick
import Quickshell
import Quickshell.Io

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

  // Same columns as the CLI writes: id, due (epoch), title, status, done_at,
  // grade, project, link. Shorter, older lines read as the CLI reads them.
  function parse(raw) {
    var out = []
    var map = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("\t")
      if (f.length < 3) continue
      var id = parseInt(f[0], 10)
      var due = parseInt(f[1], 10)
      if (!isFinite(id) || !isFinite(due)) continue
      var status = f.length > 3 ? f[3] : "open"
      if (status !== "done" && status !== "hidden" && status !== "cancelled") status = "open"
      var doneAt = f.length > 4 ? parseInt(f[4], 10) : 0
      var d = { id: id, due: due, title: f[2], status: status, doneAt: isFinite(doneAt) ? doneAt : 0,
                grade: f.length > 5 ? f[5] : "", project: f.length > 6 ? f[6] : "", link: f.length > 7 ? f[7] : "" }
      out.push(d)
      map[id] = d
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
  function markDone(id) { root.run(["done", String(id)]) }
  function reopen(id) { root.run(["reopen", String(id)]) }
  function remove(id) { root.run(["rm", String(id)]) }
  function hide(id) { root.run(["hide", String(id)]) }
  function cancel(id) { root.run(["cancel", String(id)]) }
  // Read the file again now, rather than when the watch says so: after a
  // check, the page wants the store as it was left before it catches up.
  function reload() { file.reload() }
}
