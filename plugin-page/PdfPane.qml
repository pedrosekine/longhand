import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Pdf
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc
import "PdfPlaces.js" as Places

// A PDF in the middle, in the note's place (docs/files.md, step 5,
// 2026-10-27): Qt's own view, fitted to the column, the pages drawn as they
// come into view. Loaded only while a PDF is open — the document and its
// pages are let go of when it closes — so a page that never opens a PDF
// pays nothing for it. Read only: a PDF is not written here.
//
// Keys (Shortcuts.js, "in a PDF"): arrows or j/k scroll, PgUp/PgDn and
// Space a page, Home/End the ends, Ctrl+F finds, + / - / 0 size it, o opens
// it in its own application, Esc closes it (back to the note under it).
//
// Each PDF opens where it was left (plan.md, item 9, "Left by the build"):
// the page, how far down it, the size, kept in pdfs.json in the state
// folder by the file's path. Never in the vault: it is the machine's.
//
// Marks (plan.md, item 15, 2026-11-15): words selected with the mouse, then
// `m` keeps them as a highlight and `q` as a question; a mark clicked is
// picked, and then `m`/`q` switch its kind and `x`/Del/Backspace remove it;
// `n` writes a note under the mark picked, else the last one made. Every
// mark is kept in the paper's reading note in the vault by
// `longhand-read`, which also finds its words on the page again and hands
// back the rectangles drawn here, over Qt's own page (a layer put into each
// of its page delegates, which follows the page the delegate holds).
Item {
  id: pane
  required property Item page
  property string rel: ""
  property alias keysRef: keys
  property alias findRef: findField
  property alias noteRef: noteField
  property real zoom: 1                 // over the column's width
  property bool finding: false
  readonly property var view: loader.item ? loader.item.view : null
  readonly property int pages: loader.item ? loader.item.doc.pageCount : 0
  readonly property int current: view ? view.currentPage : 0
  readonly property bool ready: loader.item ? loader.item.doc.status === PdfDocument.Ready : false
  readonly property string error: loader.item && loader.item.doc.status === PdfDocument.Error ? "this PDF could not be read" : ""

  // Where each PDF was left: path → { page, frac, zoom, at } (PdfPlaces.js).
  property var places: ({})
  // False until the PDF just opened is back at its place, so the scroll that
  // opening makes is never taken for where it was left.
  property bool settled: false
  // The place it opened at, or null at the top (the harness reads it).
  property var resumed: null

  // The paper's marks, as longhand-read last said: its note, tags, marks
  // (each with its rectangles), how many could not be placed, whether the
  // PDF has words at all.
  property var read: ({ marks: [], unplaced: 0, text: true, note: "", tags: [] })
  property string picked: ""            // a mark clicked
  property string lastMade: ""          // the last mark made while it is open
  property string readError: ""
  property bool noting: false
  property string notingId: ""
  property bool awaitingMark: false
  // Marks are kept only for a PDF in the vault, with words in it.
  readonly property bool markable: rel !== "" && rel.charAt(0) !== "/" && read.text !== false
  readonly property string readPath: (page.noteService.config && page.noteService.config.read)
    || (Quickshell.env("HOME") + "/.local/bin/longhand-read")
  property var readQueue: []
  // The page delegates a layer of marks was put into.
  property var dressed: []
  property int selectionRev: 0

  visible: rel !== ""
  onRelChanged: {
    pane.zoom = 1; pane.finding = false; findField.text = ""
    pane.settled = false; pane.resumed = null
    pane.read = ({ marks: [], unplaced: 0, text: true, note: "", tags: [] })
    pane.picked = ""; pane.lastMade = ""; pane.readError = ""; pane.noting = false; noteField.text = ""
    pane.readQueue = []
    if (pane.rel !== "" && pane.rel.charAt(0) !== "/") pane.readRun(["state"])
    Qt.callLater(pane.arrive)
  }

  // Where the view is now, or null while there is nothing to read.
  function here() {
    var t = pane.table()
    if (!t || !pane.ready || !loader.item) return null
    var doc = loader.item.doc, s = pane.view.renderScale, heights = []
    for (var i = 0; i < pane.pages; i++) heights.push(doc.pagePointSize(i).height * s)
    var at = Places.at(heights, t.rowSpacing || 0, t.contentY - t.originY)
    if (!at) return null
    at.zoom = pane.zoom
    return at
  }
  // Note where this PDF is, now; Page.qml asks before it opens another or
  // closes this one, and a pause in scrolling asks too.
  function keep() {
    if (!pane.settled || pane.rel === "") return
    var at = pane.here()
    if (!at) return
    var next = Places.put(pane.places, pane.rel, at, Date.now())
    if (JSON.stringify(next) === JSON.stringify(pane.places)) return
    pane.places = next
    placesFile.setText(JSON.stringify(next) + "\n")
  }
  // The PDF is read: back to where it was left, or at the top.
  function arrive() {
    // The document must be this PDF, not the one before it (Qt writes a
    // URL's spaces decoded, so both are compared decoded).
    if (pane.settled || !pane.ready || !loader.item
        || decodeURIComponent(String(loader.item.doc.source)) !== decodeURIComponent(pane.url())) return
    var p = Places.get(pane.places, pane.rel, pane.pages)
    if (p) pane.zoom = p.zoom
    Qt.callLater(function () {
      pane.fit()
      if (p && pane.view) {
        var h = loader.item.doc.pagePointSize(p.page).height
        // The view sets a jump 10 px below the top; give it back.
        pane.view.goToLocation(p.page, Qt.point(0, p.frac * h + 10 / pane.view.renderScale), 0)
        pane.resumed = p
      }
      pane.settled = true
      pane.dress()
    })
  }

  function url() {
    // A path in the vault, or a whole one: an export written to Downloads.
    var v = pane.page.noteService.config.vault
    var path = pane.rel.charAt(0) === "/" ? pane.rel : v + "/" + pane.rel
    return "file://" + path.split("/").map(encodeURIComponent).join("/")
  }

  // The view keeps its scroller to itself; it is the child that scrolls.
  function table() {
    if (!pane.view) return null
    var kids = pane.view.children
    for (var i = 0; i < kids.length; i++) if (kids[i].rowSpacing !== undefined && kids[i].contentY !== undefined) return kids[i]
    return null
  }
  function scrollBy(dy) {
    var t = pane.table()
    if (!t) return
    t.contentY = Math.max(t.originY, Math.min(t.originY + t.contentHeight - t.height, t.contentY + dy))
  }
  function fit() {
    if (!pane.view || !pane.ready) return
    // The column's whole width: the view lays a narrower page against its
    // right edge rather than centring it.
    pane.view.scaleToWidth(Math.max(100, pane.width), pane.height)
    pane.view.renderScale = pane.view.renderScale * pane.zoom
  }
  onWidthChanged: Qt.callLater(pane.fit)
  onZoomChanged: Qt.callLater(pane.fit)
  onReadyChanged: if (ready) { Qt.callLater(pane.fit); Qt.callLater(pane.arrive); dressTimer.restart() }
  // The view makes its page delegates when it lays out; a moment after it
  // is ready, and as it scrolls, each gets its layer of marks.
  Timer { id: dressTimer; interval: 300; onTriggered: pane.dress() }

  // A pause in scrolling notes the place.
  Timer { id: keepTimer; interval: 800; onTriggered: pane.keep() }
  Connections {
    target: pane.settled ? pane.table() : null
    ignoreUnknownSignals: true
    function onContentYChanged() { keepTimer.restart(); Qt.callLater(pane.dress) }
  }
  FileView {
    id: placesFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/pdfs.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { var o = JSON.parse(text()); if (o && typeof o === "object") pane.places = o } catch (e) { console.warn("longhand.page pdfs.json: " + e) }
    }
  }

  function find(dir) {
    if (!pane.view) return
    pane.view.searchString = findField.text
    if (dir > 0) pane.view.searchForward()
    else if (dir < 0) pane.view.searchBack()
  }

  // ---------------------------------------------------------- marks

  // One longhand-read command at a time, in the order asked.
  function readRun(args) {
    if (pane.rel === "") return
    pane.readQueue = pane.readQueue.concat([[pane.readPath, args[0], "--pdf", pane.rel].concat(args.slice(1))])
    pane.readNext()
  }
  function readNext() {
    if (readProc.running || pane.readQueue.length === 0) return
    readProc.command = pane.readQueue[0]
    pane.readQueue = pane.readQueue.slice(1)
    readProc.running = true
  }
  function readDone(out) {
    var o = null
    try { o = JSON.parse(out) } catch (e) { o = null }
    if (!o || o.pdf !== pane.rel) return
    if (pane.awaitingMark) {
      var before = (pane.read.marks || []).map(function (m) { return m.id })
      var fresh = o.marks.filter(function (m) { return before.indexOf(m.id) < 0 })
      if (fresh.length === 1) pane.lastMade = fresh[0].id
      pane.awaitingMark = false
    }
    if (pane.picked !== "" && !o.marks.some(function (m) { return m.id === pane.picked })) pane.picked = ""
    pane.read = o
    pane.readError = ""
  }

  // The rectangles to draw on page `index` (from 0): { id, kind, r }.
  function rectsOn(index) {
    var out = []
    var ms = pane.read.marks || []
    for (var i = 0; i < ms.length; i++)
      for (var b = 0; b < ms[i].boxes.length; b++)
        if (ms[i].boxes[b].page === index)
          for (var r = 0; r < ms[i].boxes[b].rects.length; r++)
            out.push({ id: ms[i].id, kind: ms[i].kind, r: ms[i].boxes[b].rects[r] })
    return out
  }
  function markById(id) {
    var ms = pane.read.marks || []
    for (var i = 0; i < ms.length; i++) if (ms[i].id === id) return ms[i]
    return null
  }

  // A mouse drag selects words; it never moves the pages. Qt's view is a
  // Flickable a little wider than the column, so a drag panned it sideways
  // (or up and down) instead of selecting (seen 2026-11-15). Its dragging is
  // turned off; the touchpad scrolls it as it does the note (TouchScroll,
  // with its glide), a mouse wheel through `wheel` below.
  property Item tamed: null
  function tame(t) {
    if (pane.tamed === t) return
    t.interactive = false
    touchScroll.createObject(t.contentItem, { flickable: t })
    pane.tamed = t
  }
  Component { id: touchScroll; TouchScroll {} }
  function wheel(ev) {
    var t = pane.table()
    if (!t || (ev.modifiers & Qt.ControlModifier)) { ev.accepted = false; return }
    var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y * 2 : ev.angleDelta.y / 120 * page.sp(60)
    var dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x * 2 : ev.angleDelta.x / 120 * page.sp(60)
    if (dy !== 0) pane.scrollBy(-dy)
    // Sideways only when the page is wider than the column (sized up): the
    // few pixels the view's scrollbar adds are no reason to slide.
    if (dx !== 0 && t.contentWidth - t.width > page.sp(40))
      t.contentX = Math.max(t.originX, Math.min(t.originX + t.contentWidth - t.width, t.contentX - dx))
  }
  WheelHandler {
    target: null
    onWheel: function (ev) { pane.wheel(ev) }
  }

  // Put a layer of marks into every page delegate the view has made.
  function dress() {
    var t = pane.table()
    if (!t || !t.contentItem) return
    pane.tame(t)
    var kids = t.contentItem.children
    for (var i = 0; i < kids.length; i++) {
      var h = kids[i]
      if (h.selection === undefined || h.index === undefined || pane.dressed.indexOf(h) >= 0) continue
      var paper = h.selection.parent
      if (!paper) continue
      marksLayer.createObject(paper, { holder: h, paper: paper })
      pane.watch(h)
      pane.dressed = pane.dressed.concat([h])
    }
  }
  // Words selected on a page bring the keys here, wherever they were (a
  // PDF opened from the Files tree leaves them in the sidebar): `m` and `q`
  // must reach the words just selected.
  function watch(h) {
    h.selection.textChanged.connect(function () {
      pane.selectionRev++
      if (h.selection && h.selection.text !== "" && !pane.noting) keys.forceActiveFocus()
    })
  }
  Connections {
    target: pane.table() ? pane.table().contentItem : null
    ignoreUnknownSignals: true
    function onChildrenChanged() { Qt.callLater(pane.dress) }
  }

  // The words selected now: { page (from 0), text, y (points), holder }, or null.
  function selected() {
    pane.selectionRev
    if (!pane.view || pane.view.selectedText === "") return null
    for (var i = 0; i < pane.dressed.length; i++) {
      var h = pane.dressed[i]
      if (!h || h.selection === undefined || h.selection.text === "" || h.selection.text !== pane.view.selectedText) continue
      var s = pane.view.renderScale || 1
      return { page: h.index, text: h.selection.text, y: Math.min(h.selection.from.y, h.selection.to.y) / s, holder: h }
    }
    return null
  }
  function clearSelection() {
    for (var i = 0; i < pane.dressed.length; i++) if (pane.dressed[i] && pane.dressed[i].selection) pane.dressed[i].selection.clear()
    if (pane.view) pane.view.selectedText = ""
  }

  // Keep the words given as a mark (`h` or `q`).
  function markText(pageIndex, text, y, kind) {
    if (!pane.markable) { pane.readError = pane.rel.charAt(0) === "/" ? "only a PDF in the vault keeps marks" : "this PDF has no words to mark (scanned)"; return false }
    var args = ["mark", "--page", String(pageIndex + 1), "--text", text, "--kind", kind]
    if (y !== undefined && y !== null && !isNaN(y)) args.push("--y", String(Math.round(y * 10) / 10))
    pane.awaitingMark = true
    pane.readRun(args)
    page.used("pdf", kind === "q" ? "question" : "highlight")
    return true
  }
  function mark(kind) {
    var sel = pane.selected()
    if (sel) {
      if (pane.markText(sel.page, sel.text, sel.y, kind)) pane.clearSelection()
      keys.forceActiveFocus()
      return true
    }
    var m = pane.markById(pane.picked)
    if (m) {
      if (m.kind !== kind) pane.readRun(["kind", "--id", m.id, "--kind", kind])
      return true
    }
    pane.readError = "select words first, then " + page.keyName(kind === "q" ? "pdfQuestion" : "pdfMark")
    return true
  }
  function pick(id) {
    if (pane.rel === "") return
    pane.picked = pane.picked === id ? "" : id
    keys.forceActiveFocus()
  }
  function remove() {
    if (pane.picked === "") return false
    pane.readRun(["remove", "--id", pane.picked])
    page.used("pdf", "remove")
    pane.picked = ""
    return true
  }
  // The mark a note goes under: the one picked, else the last made, else
  // the first on the page in view.
  function noteTarget() {
    if (pane.markById(pane.picked)) return pane.picked
    if (pane.markById(pane.lastMade)) return pane.lastMade
    var ms = pane.read.marks || []
    for (var i = 0; i < ms.length; i++) if (ms[i].placed && ms[i].boxes.length && ms[i].boxes[0].page === pane.current) return ms[i].id
    return ""
  }
  function startNote() {
    var id = pane.noteTarget()
    if (id === "") { pane.readError = "no mark to write a note under"; return }
    pane.notingId = id
    pane.picked = id
    noteField.text = pane.markById(id).note || ""
    pane.noting = true
    noteField.forceActiveFocus()
    noteField.selectAll()
  }
  function saveNote() {
    if (pane.notingId !== "") pane.readRun(["note", "--id", pane.notingId, "--text", noteField.text])
    page.used("pdf", "note")
    pane.noting = false
    keys.forceActiveFocus()
  }

  Process {
    id: readProc
    stdout: StdioCollector { id: readOut; onStreamFinished: pane.readDone(readOut.text) }
    stderr: StdioCollector {
      id: readErr
      onStreamFinished: {
        var t = readErr.text.trim()
        if (t !== "") { pane.readError = t.replace(/^longhand-read:\s*/, ""); console.warn("longhand.page " + t) }
      }
    }
    onRunningChanged: if (!running) Qt.callLater(pane.readNext)
  }

  // The layer put into each page delegate: the marks on the page it holds.
  Component {
    id: marksLayer
    Item {
      id: layer
      property Item holder
      property Item paper
      anchors.fill: parent
      readonly property int index: holder ? holder.index : -1
      readonly property real s: paper && paper.pageScale ? paper.pageScale : 1
      readonly property int count: drawn.count
      Repeater {
        id: drawn
        model: pane.rectsOn(layer.index)
        delegate: Rectangle {
          id: box
          required property var modelData
          readonly property real pad: 1.5
          readonly property color tint: modelData.kind === "q" ? page.palette.blue : page.palette.yellow
          x: modelData.r[0] * layer.s - pad
          y: modelData.r[1] * layer.s - pad
          width: modelData.r[2] * layer.s + 2 * pad
          height: modelData.r[3] * layer.s + 2 * pad
          radius: 2
          color: Qt.rgba(tint.r, tint.g, tint.b, 0.38)
          border.width: modelData.id === pane.picked ? 2 : 0
          border.color: page.accent
          TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus | PointerDevice.TouchScreen
            onTapped: pane.pick(box.modelData.id)
          }
        }
      }
    }
  }

  function key(event) {
    if (page.anywhereKey(event)) return true
    if (Sc.hit(event, "pdfMark")) return pane.mark("h")
    if (Sc.hit(event, "pdfQuestion")) return pane.mark("q")
    if (Sc.hit(event, "pdfNote")) { pane.startNote(); return true }
    if (pane.picked !== "" && Sc.hit(event, "pdfRemove")) return pane.remove()
    if (Sc.hit(event, "keysHere")) { page.toggleKeys(); return true }
    if (Sc.hit(event, "pdfClose")) {
      // Esc lets go of what is picked or selected first.
      if (pane.picked !== "") { pane.picked = ""; return true }
      if (pane.view && pane.view.selectedText !== "") { pane.clearSelection(); return true }
    }
    var step = page.sp(60)
    if (Sc.hit(event, "pdfDown")) pane.scrollBy(step)
    else if (Sc.hit(event, "pdfUp")) pane.scrollBy(-step)
    else if (Sc.hit(event, "pdfNextPage")) { if (pane.view) pane.view.goToPage(Math.min(pane.pages - 1, pane.current + 1)) }
    else if (Sc.hit(event, "pdfPrevPage")) { if (pane.view) pane.view.goToPage(Math.max(0, pane.current - 1)) }
    // The ends: the top of the first page, the top of the last (as far as
    // it goes). goToPage keeps the place inside the page, so it is not
    // used for them: from the foot of a page it would land on another's foot.
    else if (Sc.hit(event, "pdfFirst")) { if (pane.view) pane.view.goToLocation(0, Qt.point(0, 0), 0) }
    else if (Sc.hit(event, "pdfLast")) { if (pane.view) pane.view.goToLocation(Math.max(0, pane.pages - 1), Qt.point(0, 0), 0) }
    else if (Sc.hit(event, "pdfBigger")) pane.zoom = Math.min(4, pane.zoom * 1.2)
    else if (Sc.hit(event, "pdfSmaller")) pane.zoom = Math.max(0.3, pane.zoom / 1.2)
    else if (Sc.hit(event, "pdfFit")) pane.zoom = 1
    else if (Sc.hit(event, "pdfFind")) { pane.finding = true; findField.forceActiveFocus(); findField.selectAll() }
    else if (Sc.hit(event, "pdfOpen")) { page.used("pdf", "open-elsewhere"); Qt.openUrlExternally(pane.url()) }
    else if (Sc.hit(event, "pdfClose")) page.closePdf()
    else return false
    return true
  }

  Item {
    id: keys
    anchors.fill: parent
    Keys.onPressed: function (event) { if (pane.key(event)) event.accepted = true }
  }

  TextField {
    id: findField
    visible: pane.finding
    anchors.top: parent.top
    width: Math.min(parent.width, page.sp(360))
    placeholderText: "find in this PDF"
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.bodySmall)
    foreground: page.foreground
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      var seq = Sc.fromEvent(event)
      if (seq === "Enter") { pane.find(1); event.accepted = true }
      else if (seq === "Shift+Enter") { pane.find(-1); event.accepted = true }
      else if (seq === "Esc") { pane.finding = false; keys.forceActiveFocus(); event.accepted = true }
    }
    onTextChanged: if (pane.view) pane.view.searchString = text
  }

  TextField {
    id: noteField
    visible: pane.noting
    anchors.bottom: foot.top
    anchors.bottomMargin: page.sp(4)
    width: Math.min(parent.width, page.sp(520))
    placeholderText: {
      var m = pane.markById(pane.notingId)
      if (!m) return "a note"
      var t = m.text.length > 40 ? m.text.substring(0, 40) + "…" : m.text
      return "a note on “" + t + "” (p. " + m.page + ")"
    }
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.bodySmall)
    foreground: page.foreground
    z: 2
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      var seq = Sc.fromEvent(event)
      if (seq === "Enter") { pane.saveNote(); event.accepted = true }
      else if (seq === "Esc") { pane.noting = false; keys.forceActiveFocus(); event.accepted = true }
    }
  }

  Loader {
    id: loader
    active: pane.rel !== ""
    anchors.top: pane.finding ? findField.bottom : parent.top
    anchors.topMargin: pane.finding ? page.sp(8) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: foot.top
    sourceComponent: Item {
      property alias doc: doc
      property alias view: view
      PdfDocument { id: doc; source: pane.url() }
      PdfMultiPageView {
        id: view
        anchors.fill: parent
        document: doc
        clip: true
      }
    }
  }

  Text {
    id: foot
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    textFormat: Text.PlainText
    readonly property int count: (pane.read.marks || []).length
    text: pane.error !== "" ? pane.error
      : !pane.ready ? "reading…"
      : pane.readError !== "" ? pane.readError
      : "page " + (pane.current + 1) + " of " + pane.pages
        + (pane.view && pane.finding && pane.view.searchModel.count > 0 ? " · " + pane.view.searchModel.count + " found" : "")
        + (pane.read.text === false && pane.rel.charAt(0) !== "/" ? " · no words in it (scanned): nothing to mark" : "")
        + (foot.count > 0 ? " · " + foot.count + (foot.count === 1 ? " mark" : " marks") : "")
        + (pane.read.unplaced > 0 ? ", " + pane.read.unplaced + " not found on its page" : "")
        + "   " + (pane.selected() ? page.keyName("pdfMark") + " highlight · " + page.keyName("pdfQuestion") + " question"
                   : pane.picked !== "" ? page.keyName("pdfMark") + "/" + page.keyName("pdfQuestion") + " its kind · " + page.keyName("pdfNote") + " a note · " + page.keyName("pdfRemove") + " remove"
                   : (pane.markable ? "select words to mark them · " : "") + page.keyName("pdfOpen") + " opens it elsewhere")
    color: pane.error !== "" || pane.readError !== "" ? page.urgent : page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
}
