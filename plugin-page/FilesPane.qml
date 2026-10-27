import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc

// The sidebar's Files space (docs/files.md, 2026-10-26): the notes as folders
// and files. Two roots, two rights: yours (the notes root, `human/` here),
// opened to edit as a past day is; the agent's (`agents/`), opened to read.
//
// Light on memory: a folder is listed when it is opened (`find`, one level),
// never the vault up front, and the list is a ListView, so only the rows on
// screen exist. The filter (`/`) is the one thing that reads every name, and
// only while it is open.
//
// `page` is the page itself; `sidebar` the pane this sits in.
Item {
  id: files
  required property Item page
  required property Item sidebar
  readonly property var svc: page.noteService
  property alias filterFieldRef: filterField

  // What the tree shows: rows of { rel, name, depth, dir, open, side, head }.
  // `side` is "mine" or "agent"; a head is a root's title row.
  property var rows: []
  property int pick: 0
  // The filter's results replace the tree while it has words in it.
  property string query: ""
  property var allNames: null          // every file's rel, read once the filter opens
  readonly property var shown: query === "" ? rows : matches(query)

  readonly property string vault: svc.configured ? svc.config.vault : ""
  readonly property string notesRoot: svc.notesRoot
  readonly property string agentRoot: svc.agentRoot
  readonly property string dailyDir: svc.configured ? String(svc.config.daily.dir).replace(/^\/+|\/+$/g, "") : ""

  function abs(rel) { return files.vault + (rel === "" ? "" : "/" + rel) }

  // What is never listed (docs/files.md): dot and underscore names
  // (`_Attachments`, `_Archive`, `_Secrets`), Templates, the daily folder
  // (the Time space has it) and, when the notes are the vault itself, the
  // agent's root (it has a root of its own here). Files: notes, and in yours
  // PDFs too (opened in the page's PDF view, 2026-10-27).
  function listed(rel, name, dir, side) {
    if (name.charAt(0) === "." || name.charAt(0) === "_") return false
    if (dir) {
      if (name === "Templates") return false
      if (side === "mine" && (rel === files.dailyDir || rel === files.agentRoot)) return false
      return true
    }
    return side === "mine" ? /\.(md|pdf)$/i.test(name) : /\.md$/i.test(name)
  }

  function roots() {
    return files.vault === "" ? [] : [
      { rel: files.notesRoot, name: "yours", depth: 0, dir: true, open: false, side: "mine", head: true },
      { rel: files.agentRoot, name: "the agent's", depth: 0, dir: true, open: false, side: "agent", head: true }
    ]
  }
  function key(r) { return r.side + ":" + r.rel }

  // Listed afresh, as the folders are now: each time the space is come
  // back to, the folders open before open again and the same row picked
  // (a folder is read when it is shown, never watched).
  property var reopen: ({})
  property string pickKey: ""
  function refresh() {
    if (files.query !== "") return
    var keep = {}
    if (files.rows.length === 0) keep["mine:" + files.notesRoot] = true
    files.rows.forEach(function (r) { if (r.dir && r.open) keep[files.key(r)] = true })
    var cur = files.rows[files.pick]
    files.pickKey = cur ? files.key(cur) : ""
    files.reopen = keep
    files.rows = files.roots()
    files.pick = 0
    for (var i = 0; i < files.rows.length; i++) if (keep[files.key(files.rows[i])]) files.expand(i)
  }
  onVaultChanged: { files.rows = []; files.query = ""; files.allNames = null; if (visible) refresh() }
  onVisibleChanged: if (visible) refresh()
  Connections {
    target: page
    function onSidebarOpenChanged() { if (files.visible) files.refresh() }
  }

  // ----------------------------------------------------------- listing

  property var queue: []
  function list(rel, side, then) {
    files.queue = files.queue.concat([{ rel: rel, side: side, then: then }])
    if (!lister.running) files.next()
  }
  function next() {
    if (files.queue.length === 0) return
    var q = files.queue[0]
    lister.command = ["find", files.abs(q.rel), "-mindepth", "1", "-maxdepth", "1", "-printf", "%y\t%f\n"]
    lister.running = true
  }
  Process {
    id: lister
    stdout: StdioCollector {
      onStreamFinished: {
        var q = files.queue[0]
        files.queue = files.queue.slice(1)
        var out = []
        String(text).split("\n").forEach(function (l) {
          var t = l.indexOf("\t")
          if (t < 0) return
          var kind = l.slice(0, t), name = l.slice(t + 1)
          var rel = (q.rel === "" ? "" : q.rel + "/") + name
          var dir = kind === "d"
          if (files.listed(rel, name, dir, q.side)) out.push({ rel: rel, name: name, dir: dir })
        })
        out.sort(function (a, b) {
          if (a.dir !== b.dir) return a.dir ? -1 : 1
          return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
        })
        q.then(out)
        files.next()
      }
    }
  }

  // Open a folder in place: its children right under it, one level deeper.
  function expand(i) {
    var r = files.rows[i]
    if (!r || !r.dir || r.open) return
    var rel = r.rel
    files.list(rel, r.side, function (kids) {
      var at = files.rows.findIndex(function (x) { return x.rel === rel && x.side === r.side })
      if (at < 0 || files.rows[at].open) return
      var rows = files.rows.slice()
      rows[at] = Object.assign({}, rows[at], { open: true })
      var add = kids.map(function (k) {
        return { rel: k.rel, name: k.dir ? k.name : k.name.replace(/\.md$/i, ""), depth: r.depth + 1,
                 dir: k.dir, open: false, side: r.side, head: false }
      })
      if (add.length === 0) add = [{ rel: rel + "/", name: "(empty)", depth: r.depth + 1, dir: false, open: false, side: r.side, head: false, none: true }]
      files.rows = rows.slice(0, at + 1).concat(add, rows.slice(at + 1))
      // Coming back: the folders that were open, open again; the row that
      // was picked, picked.
      var k = files.rows.findIndex(function (x) { return files.key(x) === files.pickKey })
      if (k >= 0) { files.pick = k; files.pickKey = "" }
      add.forEach(function (a) { if (a.dir && files.reopen[files.key(a)]) files.expand(files.rows.indexOf(a)) })
    })
  }

  // Fold a folder: everything deeper than it, up to its next sibling, goes.
  function collapse(i) {
    var r = files.rows[i]
    if (!r || !r.dir || !r.open) return
    var end = i + 1
    while (end < files.rows.length && files.rows[end].depth > r.depth) end++
    var rows = files.rows.slice(0, i + 1).concat(files.rows.slice(end))
    rows[i] = Object.assign({}, r, { open: false })
    files.rows = rows
    if (files.pick > i && files.pick < end) files.pick = i
    else if (files.pick >= end) files.pick -= end - i - 1
  }

  function parentOf(i) {
    var d = files.rows[i] ? files.rows[i].depth : 0
    for (var k = i - 1; k >= 0; k--) if (files.rows[k].depth < d) return k
    return -1
  }

  // ----------------------------------------------------------- filter

  // Every note's path, read once when the filter opens and let go when it
  // closes: the one time the whole tree is read.
  Process {
    id: walker
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var cut = files.vault.length + 1
        String(text).split("\n").forEach(function (p) {
          if (p === "") return
          var rel = p.slice(cut)
          var side = files.agentRoot !== "" && (rel === files.agentRoot || rel.indexOf(files.agentRoot + "/") === 0) ? "agent" : "mine"
          var parts = rel.split("/")
          for (var k = 0; k < parts.length; k++) {
            var sub = parts.slice(0, k + 1).join("/")
            if (!files.listed(sub, parts[k], k < parts.length - 1, side)) return
          }
          out.push({ rel: rel, side: side })
        })
        files.allNames = out
      }
    }
  }

  function openFilter() {
    if (files.allNames === null && !walker.running) {
      var roots = [files.abs(files.notesRoot)]
      if (files.agentRoot !== "" && files.notesRoot !== "") roots.push(files.abs(files.agentRoot))
      walker.command = ["find"].concat(roots, ["-type", "f", "(", "-iname", "*.md", "-o", "-iname", "*.pdf", ")"])
      walker.running = true
    }
    page.used("files-filter")
    filterField.forceActiveFocus()
  }

  function closeFilter() {
    filterField.text = ""
    files.query = ""
    files.allNames = null
    files.pick = Math.min(files.pick, Math.max(0, files.rows.length - 1))
    files.sidebar.sidebarKeysRef.forceActiveFocus()
  }

  // Every word somewhere in the path, case and accents aside; the name's
  // own matches first, then shorter paths.
  function matches(q) {
    if (!files.allNames) return []
    var fold = function (s) { return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase() }
    var words = fold(q).split(/\s+/).filter(function (w) { return w !== "" })
    var hits = []
    files.allNames.forEach(function (n) {
      var p = fold(n.rel)
      for (var k = 0; k < words.length; k++) if (p.indexOf(words[k]) < 0) return
      var name = p.slice(p.lastIndexOf("/") + 1)
      var inName = words.filter(function (w) { return name.indexOf(w) >= 0 }).length
      var slash = n.rel.lastIndexOf("/")
      hits.push({ rel: n.rel, name: n.rel.slice(slash + 1).replace(/\.md$/i, ""), where: n.rel.slice(0, Math.max(0, slash)),
                  depth: 0, dir: false, open: false, side: n.side, head: false, score: inName * 1000 - n.rel.length })
    })
    hits.sort(function (a, b) { return b.score - a.score })
    return hits.slice(0, 200)
  }

  // ----------------------------------------------------------- acting

  function move(d) {
    var n = files.shown.length
    if (n === 0) return
    var i = files.pick
    do { i = Math.max(0, Math.min(n - 1, i + d)) } while (files.shown[i] && files.shown[i].none && i > 0 && i < n - 1)
    files.pick = i
  }

  function act(i) {
    var r = files.shown[i]
    if (!r || r.none) return
    files.pick = i
    if (r.dir) { r.open ? files.collapse(i) : files.expand(i); return }
    page.openFile(r.rel, r.side === "agent")
  }

  function into() {
    var r = files.shown[files.pick]
    if (!r || files.query !== "") return
    if (r.dir && !r.open) files.expand(files.pick)
    else if (r.dir) files.move(1)
  }

  function out() {
    if (files.query !== "") return
    var r = files.rows[files.pick]
    if (r && r.dir && r.open) files.collapse(files.pick)
    else { var p = files.parentOf(files.pick); if (p >= 0) files.pick = p }
  }

  // The pane's keys (the sidebar hands them over in this space). True when
  // taken.
  function keyPressed(event) {
    if (Sc.hit(event, "filesUp")) files.move(-1)
    else if (Sc.hit(event, "filesDown")) files.move(1)
    else if (Sc.hit(event, "filesOpen")) files.act(files.pick)
    else if (Sc.hit(event, "filesInto")) files.into()
    else if (Sc.hit(event, "filesOut")) files.out()
    else if (Sc.hit(event, "filesFilter")) files.openFilter()
    else if (Sc.hit(event, "filesBack")) { if (files.query !== "") files.closeFilter(); else page.toggleSidebar() }
    else return false
    return true
  }

  // ----------------------------------------------------------- drawn

  TextField {
    id: filterField
    visible: activeFocus || text !== ""
    anchors.top: parent.top
    width: parent.width
    placeholderText: files.allNames === null ? "reading the names…" : "filter by name"
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.bodySmall)
    foreground: page.foreground
    onTextChanged: { files.query = text.trim(); files.pick = 0 }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      var seq = Sc.fromEvent(event)
      if (seq === "Esc") { files.closeFilter(); event.accepted = true }
      else if (seq === "Up") { files.move(-1); event.accepted = true }
      else if (seq === "Down") { files.move(1); event.accepted = true }
      else if (seq === "Enter") { files.act(files.pick); event.accepted = true }
    }
  }

  ListView {
    id: list
    anchors.top: filterField.visible ? filterField.bottom : parent.top
    anchors.topMargin: filterField.visible ? page.sp(8) : 0
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    model: files.shown
    currentIndex: files.pick
    highlightFollowsCurrentItem: false
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

    TouchScroll { flickable: list }

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      readonly property bool picked: files.pick === index
      readonly property bool lit: picked && page.here === "left" && page.sidebarSpace === "files"
      onLitChanged: page.selected(row, "left", lit)
      width: list.width
      height: line.implicitHeight + page.sp(modelData.head && index > 0 ? 16 : 6)

      Rectangle {
        anchors.fill: parent
        anchors.topMargin: row.modelData.head && row.index > 0 ? page.sp(10) : 0
        radius: Style.cornerRadius
        color: row.lit ? Style.selectedFill : row.picked ? Qt.rgba(Style.selectedFill.r, Style.selectedFill.g, Style.selectedFill.b, 0.4) : "transparent"
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.modelData.none ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: { page.focusPane("left"); files.act(row.index) }
      }

      Column {
        id: line
        anchors.bottom: parent.bottom
        anchors.bottomMargin: page.sp(3)
        x: page.sp(6) + row.modelData.depth * page.sp(12)
        width: parent.width - x - page.sp(6)
        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.modelData.head ? (row.modelData.open ? "▾ " : "▸ ") + row.modelData.name.toUpperCase()
            : (row.modelData.dir ? (row.modelData.open ? "▾ " : "▸ ") : "") + row.modelData.name
          color: row.modelData.head ? page.dim
            : row.modelData.none ? page.faint
            : row.modelData.side === "agent" ? page.dim : page.foreground
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.italic: row.modelData.side === "agent" && !row.modelData.head
          font.pixelSize: page.fs(row.modelData.head ? Style.font.caption : Style.font.bodySmall)
        }
        Text {
          visible: !!row.modelData.where
          width: parent.width
          elide: Text.ElideLeft
          textFormat: Text.PlainText
          text: row.modelData.where || ""
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
    }
  }

  Text {
    visible: files.query !== "" && files.allNames !== null && files.shown.length === 0
    anchors.top: list.top
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "no note's name has “" + files.query + "”"
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.bodySmall)
  }
}
