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
  property bool loaded: false

  readonly property string filePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/omarchy-student/deadlines.tsv"

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
      if (status !== "done" && status !== "hidden") status = "open"
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
    path: root.filePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: root.parse("")
    onFileChanged: reload()
  }

  // ------------------------------------------------------------ commands

  property var queue: []
  property var job: null
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
    if (root.exitCode !== 0) console.warn("student.page pomo " + j.args.join(" ") + ": " + err.text.trim())
    if (j.done) j.done(root.exitCode, out.text)
    root.next()
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
}
