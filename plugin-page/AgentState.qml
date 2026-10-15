import QtQuick
import Quickshell
import Quickshell.Io

// A day's agent state (today's unless told otherwise), read-only: which
// blocks the runner has seen, which carry a reply, which replies the student
// has not looked at yet. Shared by the page (paints blocks, fills the
// margin) and the bar glyph (accent when something is waiting). The runner
// writes the file atomically; this only ever reads it.
Item {
  id: root

  property var config: ({})
  readonly property bool configured: !!(config && config.vault && config.daily && config.daily.dir)

  function momentToQt(fmt) {
    return fmt.replace(/YYYY/g, "yyyy").replace(/YY/g, "yy").replace(/DD/g, "dd").replace(/HH/g, "HH").replace(/mm/g, "mm")
  }

  property string stamp: ""
  function refreshStamp() {
    root.stamp = configured ? Qt.formatDate(new Date(), momentToQt((config.daily && config.daily.format) || "YYYY-MM-DD")) : ""
  }
  onConfigChanged: refreshStamp()
  Component.onCompleted: refreshStamp()
  Timer { interval: 60000; repeat: true; running: true; onTriggered: root.refreshStamp() }

  readonly property string agentDir: configured ? config.vault + "/" + (config.agentDir || "agents/student") : ""
  // The day whose state is read: today unless the page is showing another.
  property string date: ""
  readonly property string day: date !== "" ? date : stamp
  readonly property string path: agentDir !== "" && day !== "" ? agentDir + "/daily/" + day + ".json" : ""

  property var state: ({})
  readonly property var blocks: root.blocksOf(root.state)
  property int unread: 0

  // Read from `state` itself, never from the `blocks` binding: a binding is
  // not refreshed until after the handlers of the property it depends on
  // have run, so anything reached from `onStateChanged` — the page settling
  // a chat turn, an accepted proposal, this count — would be looking at the
  // state before the one that just arrived (found 2026-10-15, a sent chat
  // message drawn twice).
  function blocksOf(st) { return (st && st.blocks) || ({}) }

  function recount() {
    var n = 0
    var b = root.blocksOf(root.state)
    for (var h in b) if (b[h].state === "reply" && !b[h].read) n++
    root.unread = n
  }

  function record(hash) { return root.blocksOf(root.state)[hash] || null }

  function reload() { file.reload() }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.state = JSON.parse(text()) } catch (e) { root.state = ({}) }
      root.recount()
    }
    onLoadFailed: { root.state = ({}); root.recount() }
    onFileChanged: reload()
  }
}
