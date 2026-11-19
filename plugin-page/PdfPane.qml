import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Pdf
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc
import "PdfPlaces.js" as Places
import "PdfMarks.js" as Marks
import "Answers.js" as Answers

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
// Find (Ctrl+F or /, 2026-11-17): `longhand-read search` finds the words as
// a mark's are found, loosely — a word broken over a line, a ligature, an
// accent never hides one; a capital typed makes the case count. As letters
// are typed the next place from where it is read is shown, every place lit
// on the pages and listed with the words round it; Enter goes on, Shift+
// Enter back, ↑/↓ too, a row clicked to it. Esc closes, leaving the view
// where it was found, and the back key returns to where the reading was.
// Words selected when it opens are what it finds.
//
// Each PDF opens where it was left (plan.md, item 9, "Left by the build"):
// the page, how far down it, the size, kept in pdfs.json in the state
// folder by the file's path. Never in the vault: it is the machine's.
//
// Marks (plan.md, item 15, 2026-11-15): words selected with the mouse, then
// `m` keeps them as a highlight and `q` as a question; a mark clicked is
// picked, and then `m`/`q` switch its kind and `x`/Del/Backspace remove it
// (Esc, or a click on the page away from the marks, lets go of it);
// `n` writes a note under the mark picked, else the last one made. Every
// mark is kept in the paper's reading note in the vault by
// `longhand-read`, which also finds its words on the page again and hands
// back the rectangles drawn here, over Qt's own page (a layer put into each
// of its page delegates, which follows the page the delegate holds).
//
// Acronyms (plan.md item 18, 2026-11-16): `longhand-read acronyms` finds,
// once per paper, what each acronym stands for where the paper spells it
// out, and every place each is written. Hovered, one says so and on which
// page; a click or Enter goes there (the words lit a moment), and the
// page's back key returns to where it was read. One the paper never spells
// out says so, and Enter asks the paper's chat, as a guess. `a` lists them
// all, every one underlined on the pages while the list is open.
//
// A mark hovered says what came of it (2026-11-16): a question, the first
// sentences of its answer in the paper's chat (Answers.js), and Enter opens
// the chat at that exchange; a question not asked yet says so, and Enter
// asks it; a highlight with a note shows the note. Enter does the same for
// the mark clicked. A click still picks a mark, to change or remove it.
Item {
  id: pane
  required property Item page
  property string rel: ""
  property alias keysRef: keys
  property alias findRef: findField
  property alias findBarRef: findBar
  property alias noteRef: noteField
  property alias acroFieldRef: acroField
  // What the tip under the pointer says, for the harness.
  readonly property string tipSays: acroTipBox.visible ? (acroTipAsked.visible ? acroTipAsked.text + " | " : "") + acroTipLine.text + " | " + acroTipMore.text : ""
  property real zoom: 1                 // over the column's width
  property bool finding: false
  readonly property var view: loader.item ? loader.item.view : null
  readonly property int pages: loader.item ? loader.item.doc.pageCount : 0
  // The page being read: the one across the view's middle. Qt's own
  // currentPage moves only on a jump or a scrollbar drag, so after the
  // touchpad, the wheel or the keys it said the page jumped to last (the
  // foot read "page 5" over page 2, 2026-11-17); it is worked out here
  // from where the view is instead, as it scrolls.
  property int current: 0
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
  // A mark to show once the PDF is open and its marks are read (a waiting
  // question picked in a project's view, 2026-11-16); "" when none.
  property string showAfter: ""
  // Asked for while its paper is already open and read, nothing else would
  // show it: no arrival, no fresh read (seen 2026-11-19, a second question
  // picked in the project's list did nothing). Later, once whatever opens
  // in the same breath has opened; a paper still opening bails here and
  // shows it on arrival.
  onShowAfterChanged: if (showAfter !== "") Qt.callLater(pane.showPending)
  // Words to light once the PDF is open (a quote of another paper in a
  // chat, 2026-11-19): { page, words }, null when none.
  property var flashAfter: null
  onFlashAfterChanged: if (flashAfter) Qt.callLater(pane.showPending)
  function showPending() {
    if (pane.flashAfter && pane.settled) {
      var w = pane.flashAfter
      pane.flashAfter = null
      pane.flash(w.page, w.words)
    }
    if (pane.showAfter === "" || !pane.settled || !pane.markById(pane.showAfter)) return
    var id = pane.showAfter
    pane.showAfter = ""
    pane.showMark(id)
  }
  property string picked: ""            // a mark clicked
  property string lastMade: ""          // the last mark made while it is open
  property string readError: ""
  property bool noting: false
  property string notingId: ""
  property bool awaitingMark: false
  property bool askAfter: false
  // The project asked for on a paper's first mark: the projects, narrowing
  // as a name or tag is typed.
  property bool askingTag: false
  property int tagFocus: 0
  property string tagSaid: ""          // "#thesis": said a moment in the foot, once given
  Timer { id: tagSaidTimer; interval: 4000; onTriggered: pane.tagSaid = "" }
  readonly property var tagChoices: {
    var q = tagField.text.toLowerCase().replace(/^#/, "")
    return page.projects.filter(function (p) {
      return q === "" || String(p.tag).toLowerCase().indexOf(q) >= 0 || String(p.name).toLowerCase().indexOf(q) >= 0
    }).slice(0, 8)
  }
  function askProject() {
    pane.askingTag = true
    pane.tagFocus = 0
    tagField.text = ""
    tagField.forceActiveFocus()
  }
  function chooseProject(tag) {
    pane.askingTag = false
    if (tag) { pane.readRun(["tag", "--tag", tag]); pane.tagSaid = "#" + tag; tagSaidTimer.restart(); page.used("pdf", "project") }
    keys.forceActiveFocus()
  }
  // The paper's acronyms (longhand-read acronyms): short → { short, long,
  // page, rects, defined }, and where each is written, page → [{ r, a }].
  property var acro: ({ byShort: {}, list: [], spots: {} })
  property var hoverAcro: null          // { a, item, page }: the one under the pointer
  property bool tipOn: false           // a tip shown (a moment after the pointer stops)
  property bool acroListing: false      // `a`: the list open, every acronym underlined
  property int acroFocus: 0
  property var jumpBack: null           // where a jump to a definition left from
  readonly property var acroChoices: {
    var q = acroField.text.trim().toLowerCase()
    return pane.acro.list.filter(function (x) {
      return q === "" || x.short.toLowerCase().indexOf(q) === 0 || (x.long || "").toLowerCase().indexOf(q) >= 0
    }).sort(function (a, b) {
      // What starts with the letters typed first, then those spelled out, then by their letters (Qt's sort is not
      // stable, so the order is said whole).
      var sa = a.short.toLowerCase().indexOf(q) === 0 ? 0 : 1, sb = b.short.toLowerCase().indexOf(q) === 0 ? 0 : 1
      if (sa !== sb) return sa - sb
      if (a.defined !== b.defined) return a.defined ? -1 : 1
      return a.short.toLowerCase() < b.short.toLowerCase() ? -1 : a.short.toLowerCase() > b.short.toLowerCase() ? 1 : 0
    })
  }
  function acroRead(o) {
    var by = {}, list = []
    ;(o.acronyms || []).forEach(function (x) { by[x.short] = { short: x.short, long: x.long, page: x.page, rects: x.rects, defined: true }; list.push(by[x.short]) })
    ;(o.undefined || []).forEach(function (x) { by[x.short] = { short: x.short, long: "", page: x.page, count: x.count, defined: false }; list.push(by[x.short]) })
    pane.acro = { byShort: by, list: list, spots: o.spots || {} }
  }
  function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
  // A place found, as a row: a few words before it, it, the words after.
  function findRow(h) {
    var before = h.before.length > 42 ? "…" + h.before.substring(h.before.length - 42).replace(/^\S*\s/, "") : h.before
    return pane.esc(before) + (before ? " " : "") + "<b><font color=\"" + page.foreground + "\">" + pane.esc(h.match) + "</font></b> " + pane.esc(h.after)
  }
  function acroOn(index) { return pane.acro.spots[String(index)] || [] }
  // Is the spot `r` on page `index` (from 0) the place the acronym is spelled out?
  function acroIsDef(a, index, r) {
    var d = pane.acro.byShort[a]
    if (!d || !d.defined || d.page - 1 !== index) return false
    var cx = r[0] + r[2] / 2, cy = r[1] + r[3] / 2
    return d.rects.some(function (q) { return cx >= q[0] && cx <= q[0] + q[2] && cy >= q[1] && cy <= q[1] + q[3] })
  }
  function acroHover(a, item, index) {
    pane.hoverAcro = { a: a, item: item, page: index }
    pane.tipWait()
  }
  function acroLeave(item) {
    if (!pane.hoverAcro || pane.hoverAcro.item !== item) return
    tipLeaveTimer.restart()
  }
  function tipWait() {
    tipLeaveTimer.stop()
    if (!pane.tipOn) tipShowTimer.restart()
  }
  // The marks under the pointer (one inside another: both), each a
  // rectangle of it: { id, item, area }. The smallest is the one meant.
  property var markHovers: []
  readonly property var hoverMarkAt: {
    var best = null
    for (var i = 0; i < pane.markHovers.length; i++)
      if (!best || pane.markHovers[i].area < best.area) best = pane.markHovers[i]
    return best
  }
  readonly property string hoverMark: pane.hoverMarkAt ? pane.hoverMarkAt.id : ""
  function markHover(id, item, area) {
    pane.markHovers = pane.markHovers.filter(function (h) { return h.item !== item }).concat([{ id: id, item: item, area: area }])
    pane.tipWait()
  }
  function markLeave(item) {
    pane.markHovers = pane.markHovers.filter(function (h) { return h.item !== item })
    if (pane.markHovers.length === 0 && !pane.hoverAcro) tipLeaveTimer.restart()
  }
  // What a mark's tip says: { line (styled), more (plain) }, or null.
  function markTip(id) {
    var m = pane.markById(id)
    if (!m) return null
    if (m.kind !== "q") return m.note ? { line: pane.esc(m.note), more: "your note · " + page.keyName("pdfNote") + " edits it"
      + (page.paper.askable ? " · " + page.keyName("pdfGo") + " talks about it in the paper's chat" : "") } : null
    var a = Answers.forMark(page.noteTalk && page.noteTalk.turns ? page.noteTalk.turns : [], id)
    if (a) {
      var g = Answers.gist(a.text, 260)
      return { asked: Answers.gist(a.asked, 200).text, line: pane.esc(g.text), more: page.keyName("pdfGo") + " opens it in the paper's chat"
        + (a.more > 0 ? " · " + a.more + (a.more === 1 ? " more answer" : " more answers") + " after it" : "") }
    }
    if (page.dayPending && (page.dayPending.marks || []).indexOf(id) >= 0) return { line: "<i>being answered…</i>", more: "" }
    if (!page.paper.askable) return { line: "<i>your question</i>", more: pane.read.private ? "a private PDF is never sent to the agent" : "" }
    return { line: "<i>your question, not asked yet</i>", more: page.keyName("pdfGo") + " asks it" }
  }
  // Enter on a mark: an answered question's exchange in the chat; else the
  // paper's chat with it attached, for the words to be typed — a question
  // not asked yet, or a highlight to talk about (2026-11-17: Enter on a
  // highlight wrote its note, as `n` does, and nothing took a highlight to
  // the agent from the page; now Enter does here what it does on a row of
  // the paper's marks). Nothing is sent by Enter.
  function markGo(id) {
    var m = pane.markById(id)
    if (!m) return false
    pane.tipOn = false
    pane.markHovers = []
    if (m.kind === "q" && page.paper.showAnswer(id)) return true
    if (!page.paper.askable) {
      pane.readError = pane.read.private ? "a private PDF is never sent to the agent" : "this PDF has no words to ask about"
      return true
    }
    page.paper.askAbout(id)
    return true
  }
  Timer {
    id: tipShowTimer
    interval: 250
    onTriggered: {
      var t = pane.table()
      pane.tipY = t ? t.contentY : 0
      pane.tipOn = pane.tipHas()
    }
  }
  // A scroll takes the word from under the tip: it goes. Not the view
  // settling a pixel or two after a jump (2026-11-16: it let go of the
  // acronym hovered just after End, so Enter did nothing).
  property real tipY: 0
  function tipScrolled() {
    var t = pane.table()
    if (!pane.tipOn || !t || Math.abs(t.contentY - pane.tipY) < page.sp(12)) return
    pane.tipOn = false
    pane.hoverAcro = null
    pane.markHovers = []
  }
  Timer { id: tipLeaveTimer; interval: 180; onTriggered: { pane.hoverAcro = null; pane.tipOn = pane.tipHas() } }
  // Something to say under the pointer: an acronym, or a mark with a tip (a
  // highlight with no note has none).
  function tipHas() {
    return pane.hoverAcro !== null || (pane.hoverMarkAt !== null && pane.markTip(pane.hoverMarkAt.id) !== null)
  }
  // To where the paper spells it out: the place read now kept for the back
  // key, the words lit a moment. One it never spells out: its chat asked.
  function acroGo(a) {
    var d = pane.acro.byShort[a]
    if (!d) return
    pane.hoverAcro = null
    pane.tipOn = false
    if (!d.defined) { page.paper.askAcronym(a); return }
    var box = { page: d.page - 1, rects: d.rects }
    pane.jumpBack = pane.here()
    pane.flashMissed = ""
    pane.flashBoxes = [box]
    pane.goToBox(box)
    flashTimer.restart()
    keys.forceActiveFocus()
    page.used("pdf", "acronym")
  }
  function jumpReturn() {
    var p = pane.jumpBack
    pane.jumpBack = null
    if (!p || !pane.view || !loader.item) return
    var h = loader.item.doc.pagePointSize(p.page).height
    pane.view.goToLocation(p.page, Qt.point(0, p.frac * h + 10 / pane.view.renderScale), 0)
    pane.alignSoon()
    page.used("pdf", "acronym-back")
  }
  function openAcronyms() {
    if (pane.acro.list.length === 0) { pane.readError = "no acronyms found in this paper"; return }
    pane.acroListing = true
    pane.acroFocus = 0
    acroField.text = ""
    acroField.forceActiveFocus()
    page.used("pdf", "acronyms")
  }
  // Enter in the list: the row chosen, gone to.
  function acroPick() {
    var c = pane.acroChoices[pane.acroFocus]
    pane.closeAcronyms()
    if (c) pane.acroGo(c.short)
  }
  function closeAcronyms() {
    pane.acroListing = false
    keys.forceActiveFocus()
  }

  // Words the agent quoted, shown where they are for a moment (never kept).
  property var flashBoxes: []
  property string flashMissed: ""
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
    pane.zoom = 1; pane.finding = false; findField.text = ""; pane.clearFind()
    pane.settled = false; pane.resumed = null
    pane.read = ({ marks: [], unplaced: 0, text: true, note: "", tags: [] })
    pane.wholePage = false
    pane.askingTag = false
    pane.dressed = []
    pane.picked = ""; pane.lastMade = ""; pane.readError = ""; pane.noting = false; noteField.text = ""
    pane.readQueue = []
    pane.acro = ({ byShort: {}, list: [], spots: {} })
    pane.hoverAcro = null; pane.tipOn = false; pane.markHovers = []; pane.acroListing = false; pane.jumpBack = null
    if (pane.rel !== "" && pane.rel.charAt(0) !== "/") pane.readRun(["state"])
    if (pane.rel !== "") pane.readRun(["acronyms"])
    Qt.callLater(pane.arrive)
  }

  // Where the view is now, or null while there is nothing to read: the
  // page and how far down it at the view's top, or `down` (0 to 1) of the
  // way down the view.
  function here(down) {
    var t = pane.table()
    if (!t || !pane.ready || !loader.item) return null
    var doc = loader.item.doc, s = pane.view.renderScale, heights = []
    for (var i = 0; i < pane.pages; i++) heights.push(doc.pagePointSize(i).height * s)
    var at = Places.at(heights, t.rowSpacing || 0, t.contentY - t.originY + (down || 0) * t.height)
    if (!at) return null
    at.zoom = pane.zoom
    return at
  }
  function track() {
    var at = pane.here(0.5)
    pane.current = at ? at.page : 0
  }
  Timer { id: trackTimer; interval: 50; onTriggered: pane.track() }
  Connections {
    target: pane.table()
    ignoreUnknownSignals: true
    function onContentYChanged() { trackTimer.restart() }
    function onHeightChanged() { trackTimer.restart() }
  }
  // A page down or up (PgDn, Space, PgUp): as far down the next page as
  // the view's top is down this one. Qt's goToPage counted from its own
  // current page, which the touchpad never moved.
  function turn(d) {
    var at = pane.here()
    if (!at || !pane.view) return
    var to = Math.max(0, Math.min(pane.pages - 1, at.page + d))
    if (to === at.page) return
    var h = loader.item.doc.pagePointSize(to).height
    pane.view.goToLocation(to, Qt.point(0, at.frac * h + 10 / pane.view.renderScale), 0)
    pane.alignSoon()
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
      pane.track()
      pane.dress()
      pane.alignSoon()
      pane.redrawSoon()
      pane.showPending()
    })
  }

  function url() {
    // A path in the vault, or a whole one: an export written to Downloads.
    var v = pane.page.noteService.config.vault
    // A scan read (plan.md item 15, step 5): its copy with words, which
    // looks as the scan does; the scan itself is never written.
    var path = pane.read && pane.read.ocr ? pane.read.ocr : pane.rel.charAt(0) === "/" ? pane.rel : v + "/" + pane.rel
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
  // Fitted by its text (2026-11-15): a paper's margins are a fifth of its
  // width or more, so the text, not the paper, is fitted to the column.
  // Qt's view keeps a page larger than the column centred (and its left
  // side out of reach), so the fit is made about the page's middle: as
  // large as the text's farther side allows. A paper with even margins
  // fills the column; a lopsided one a little less, never cut. `0`
  // switches to the whole page and back. A PDF with no words (or too few)
  // is fitted by its page.
  property bool wholePage: false
  readonly property var span: !pane.wholePage && pane.read && pane.read.span ? pane.read.span : null
  readonly property real spanPad: 14     // points kept beside the text
  function fit() {
    if (!pane.view || !pane.ready) return
    var w = Math.max(100, pane.width)
    if (pane.span) {
      var mid = pane.span.w / 2
      var reach = Math.max(mid - pane.span.x0, pane.span.x1 - mid) + pane.spanPad
      pane.view.renderScale = (w / 2) / Math.max(1, reach)
    }
    // The column's whole width: the view lays a narrower page against its
    // right edge rather than centring it.
    else pane.view.scaleToWidth(w, pane.height)
    pane.view.renderScale = pane.view.renderScale * pane.zoom
    pane.alignSoon()
    pane.redrawSoon()
  }
  // The view's own column is a little wider than the pane (its scrollbar);
  // centred in it, so the page's middle is the pane's.
  function align() {
    var t = pane.table()
    if (!t) return
    t.contentX = t.originX + Math.max(0, (t.contentWidth - t.width) / 2)
  }
  Timer { id: alignTimer; interval: 60; onTriggered: pane.align() }
  function alignSoon() { alignTimer.restart() }
  // A page's picture is drawn asynchronously by Qt, and two drawings can
  // race: the page the view was put back to on opening, and the same pages
  // again at the size the fit to the text makes (the text's span arrives
  // after the PDF). The older could land last, and a page showed another
  // page's picture under its own marks (2026-11-18: page 2's words, page 5's
  // two questions, "page 5" in the foot). So once things settle — after
  // opening, a fit, a scroll — each page shown is drawn again, its own:
  // the same frame at a size one pixel off, which Qt draws anew, the old
  // picture kept until the new one is ready.
  property bool nudged: false
  Timer { id: redrawTimer; interval: 350; onTriggered: pane.redrawPages() }
  function redrawSoon() { redrawTimer.restart() }
  function redrawPages() {
    pane.nudged = !pane.nudged
    for (var i = 0; i < pane.dressed.length; i++) {
      var h = pane.dressed[i]
      var paper = h && h.selection ? h.selection.parent : null
      if (!paper) continue
      for (var k = 0; k < paper.data.length; k++) {
        var o = paper.data[k]
        if (String(o).indexOf("PdfPageImage") < 0) continue
        if (o.currentFrame !== h.index) o.currentFrame = h.index
        var w = paper.pagePointSize.width * pane.view.renderScale * Screen.devicePixelRatio
        o.sourceSize.width = Math.round(w) + (pane.nudged ? 1 : 0)
      }
    }
  }
  Connections {
    target: pane.table()
    ignoreUnknownSignals: true
    function onContentWidthChanged() { pane.alignSoon() }
  }
  onWidthChanged: Qt.callLater(pane.fit)
  onZoomChanged: Qt.callLater(pane.fit)
  onSpanChanged: Qt.callLater(pane.fit)
  onReadyChanged: if (ready) { Qt.callLater(pane.fit); Qt.callLater(pane.arrive); dressTimer.restart() }
  // The view makes its page delegates when it lays out; a moment after it
  // is ready, and as it scrolls, each gets its layer of marks.
  Timer { id: dressTimer; interval: 300; onTriggered: pane.dress() }

  // A pause in scrolling notes the place.
  Timer { id: keepTimer; interval: 800; onTriggered: pane.keep() }
  Connections {
    target: pane.settled ? pane.table() : null
    ignoreUnknownSignals: true
    function onContentYChanged() { keepTimer.restart(); Qt.callLater(pane.dress); pane.tipScrolled() }
  }
  FileView {
    id: placesFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/pdfs.json"
    atomicWrites: true
    printErrors: false
    // Read again when written elsewhere: `longhand-read` moves a paper's
    // place with the paper (2026-11-16), and the next keep() must not
    // write the old record back over it.
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { var o = JSON.parse(text()); if (o && typeof o === "object") pane.places = o } catch (e) { console.warn("longhand.page pdfs.json: " + e) }
    }
  }

  // ---------------------------------------------------------- find

  property var findHits: []             // longhand-read search's: { page, rects, before, match, after }
  property var findOnPage: ({})         // page (from 0) → [{ r, i }]
  property int findTotal: 0             // how many there are (the first 500 are listed)
  property int findAt: -1               // the one shown
  property bool findCased: false        // a capital typed: the case counts
  property string findFor: ""           // the words the hits are for
  property string findSaid: ""          // "from the top again", a moment
  property var findFrom: null           // where the reading was before the first shown
  readonly property bool findBusy: searchProc.running || findTimer.running
  Timer { id: findTimer; interval: 120; onTriggered: pane.runFind() }
  Timer { id: findSaidTimer; interval: 2500; onTriggered: pane.findSaid = "" }

  function openFind() {
    if (pane.rel === "") return
    var sel = pane.selected(), was = findField.text
    if (sel) findField.text = sel.text.replace(/[\ufffe\u00ad]\s*/g, "").replace(/\s+/g, " ").trim().substring(0, 120)
    pane.finding = true
    pane.findFrom = null
    findField.forceActiveFocus()
    findField.selectAll()
    // The same words as before: their places again, from where it is now.
    if (findField.text === was) { findTimer.stop(); pane.runFind() }
    page.used("pdf", "find")
  }
  // The find field's keys; the rest are typed.
  function findKey(event) {
    if (page.anywhereKey(event)) return true
    var seq = Sc.fromEvent(event)
    if (seq === "Enter" || seq === "Down") pane.findGo(1)
    else if (seq === "Shift+Enter" || seq === "Up") pane.findGo(-1)
    else if (seq === "Esc") pane.closeFind()
    else if (Sc.hit(event, "pdfFind") && seq !== "/") findField.selectAll()
    else if (seq === "PgDn") pane.turn(1)
    else if (seq === "PgUp") pane.turn(-1)
    else return false
    return true
  }
  function clearFind() {
    findTimer.stop()
    pane.findHits = []; pane.findOnPage = ({}); pane.findTotal = 0; pane.findAt = -1
    pane.findFor = ""; pane.findSaid = ""; pane.findCased = false
  }
  // Esc: the view stays where it was found; the back key returns to where
  // the reading was, if it moved.
  function closeFind() {
    var from = pane.findFrom, now = pane.here()
    pane.finding = false
    pane.clearFind()
    if (from && now && (from.page !== now.page || Math.abs(from.frac - now.frac) > 0.02)) pane.jumpBack = from
    pane.findFrom = null
    keys.forceActiveFocus()
  }
  function runFind() {
    findTimer.stop()
    var q = findField.text.trim()
    if (q.length < 2 || pane.rel === "") { pane.clearFind(); return }
    if (searchProc.running) { searchProc.again = true; return }
    searchProc.command = [pane.readPath, "search", "--pdf", pane.rel, "--text", q]
    searchProc.running = true
  }
  function findDone(out) {
    var o = null
    try { o = JSON.parse(out) } catch (e) { o = null }
    if (!o || o.pdf !== pane.rel || !pane.finding || o.search !== findField.text.trim()) return
    var by = {}
    o.hits.forEach(function (h, i) {
      var k = String(h.page)
      by[k] = (by[k] || []).concat(h.rects.map(function (r) { return { r: r, i: i } }))
    })
    var start = pane.findStart(o.hits)
    pane.findHits = o.hits
    pane.findOnPage = by
    pane.findTotal = o.total
    pane.findCased = !!o.cased
    pane.findFor = o.search
    pane.findAt = -1
    if (start >= 0) pane.findShow(start)
  }
  // The first place at or after the one shown, else at or after the top of
  // the view: typing on narrows from where it is, never back to page 1.
  function findStart(hits) {
    if (hits.length === 0) return -1
    var from = null
    var cur = pane.findAt >= 0 ? pane.findHits[pane.findAt] : null
    if (cur) from = { page: cur.page, y: cur.rects[0][1] }
    else {
      var at = pane.here()
      if (at && loader.item) from = { page: at.page, y: at.frac * loader.item.doc.pagePointSize(at.page).height }
    }
    if (!from) return 0
    for (var i = 0; i < hits.length; i++)
      if (hits[i].page > from.page || (hits[i].page === from.page && hits[i].rects[0][1] >= from.y - 1)) return i
    pane.findSaid = "from the top again"
    findSaidTimer.restart()
    return 0
  }
  function findGo(d) {
    if (findTimer.running) { pane.runFind(); return }
    var n = pane.findHits.length
    if (n === 0) return
    var i = pane.findAt + d
    if (i >= n) { i = 0; pane.findSaid = "from the top again"; findSaidTimer.restart() }
    else if (i < 0) { i = n - 1; pane.findSaid = "from the end again"; findSaidTimer.restart() }
    else pane.findSaid = ""
    pane.findShow(i)
  }
  function findShow(i) {
    var h = pane.findHits[i]
    if (!h) return
    if (pane.findFrom === null) pane.findFrom = pane.here()
    pane.findAt = i
    pane.reveal(h)
  }
  // A place brought into view, a third of the way down it, unless it is in
  // view already (above the find bar): the pages move only when they must.
  function reveal(box) {
    if (!pane.view || !box || !box.rects || box.rects.length === 0) return
    var s = pane.view.renderScale, first = box.rects[0], last = box.rects[box.rects.length - 1]
    for (var k = 0; k < pane.dressed.length; k++) {
      var h = pane.dressed[k]
      if (!h || h.index !== box.page || !h.visible || !h.selection || !h.selection.parent) continue
      var top = h.selection.parent.mapToItem(pane, 0, first[1] * s).y
      var foot = h.selection.parent.mapToItem(pane, 0, (last[1] + last[3]) * s).y
      var bottom = pane.finding ? findBar.y : pane.height
      if (top >= page.sp(24) && foot <= bottom - page.sp(12)) return
      break
    }
    var room = (pane.finding ? findBar.y : pane.height) * 0.3
    pane.view.goToLocation(box.page, Qt.point(0, Math.max(0, first[1] - room / s)), 0)
    pane.alignSoon()
  }
  Process {
    id: searchProc
    property bool again: false
    stdout: StdioCollector { id: searchOut; onStreamFinished: pane.findDone(searchOut.text) }
    stderr: StdioCollector {
      id: searchErr
      onStreamFinished: { var t = searchErr.text.trim(); if (t !== "") console.warn("longhand.page search: " + t) }
    }
    onRunningChanged: if (!running && again) { again = false; Qt.callLater(pane.runFind) }
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
    if (o.acronyms !== undefined) { pane.acroRead(o); return }
    if (o.found !== undefined && o.marks === undefined) { pane.flashDone(o); return }
    if (pane.awaitingMark) {
      var before = (pane.read.marks || []).map(function (m) { return m.id })
      var fresh = o.marks.filter(function (m) { return before.indexOf(m.id) < 0 })
      if (fresh.length === 1) pane.lastMade = fresh[0].id
      pane.awaitingMark = false
      // The paper's first mark: its project, guessed when plain, else
      // asked once (Esc leaves it with none; its note can name one later).
      if (fresh.length === 1 && (pane.read.marks || []).length === 0 && (o.tags || []).length === 0) {
        var guess = page.paperProject(pane.rel)
        if (guess !== "") { pane.readRun(["tag", "--tag", guess]); pane.tagSaid = "#" + guess; tagSaidTimer.restart() }
        else if (page.projects.length > 0) pane.askProject()
      }
      // A question marked: its chat opens with it attached, for the
      // question in words; nothing is sent until Enter (plan.md item 15).
      if (fresh.length === 1 && fresh[0].kind === "q" && pane.askAfter) Qt.callLater(function () { page.paper.askAbout(fresh[0].id) })
      pane.askAfter = false
    }
    if (pane.picked !== "" && !o.marks.some(function (m) { return m.id === pane.picked })) pane.picked = ""
    pane.read = o
    pane.readError = ""
    Qt.callLater(pane.showPending)
  }

  // Words quoted in the paper's chat, “like this” (p. 12): found on their
  // page (or around it) and lit there a moment, the page brought to them.
  function flash(page1, words) {
    pane.flashBoxes = []
    pane.flashMissed = ""
    pane.readRun(["find", "--page", String(page1), "--text", words])
  }
  function flashDone(o) {
    if (!o.boxes || o.boxes.length === 0) { pane.flashMissed = "not found on that page"; flashTimer.restart(); return }
    pane.flashBoxes = o.boxes
    pane.goToBox(o.boxes[0])
    flashTimer.restart()
  }
  Timer { id: flashTimer; interval: 2600; onTriggered: { pane.flashBoxes = []; pane.flashMissed = "" } }
  function flashOn(index) {
    var out = []
    for (var b = 0; b < pane.flashBoxes.length; b++)
      if (pane.flashBoxes[b].page === index) out = out.concat(pane.flashBoxes[b].rects)
    return out
  }
  // The view brought to a box's first line, a little above it.
  function goToBox(box) {
    if (!pane.view || !box || !box.rects || box.rects.length === 0) return
    pane.view.goToLocation(box.page, Qt.point(0, Math.max(0, box.rects[0][1] - 60)), 0)
    pane.alignSoon()
  }
  // A mark chosen in the paper's list: shown and picked.
  function showMark(id) {
    var m = pane.markById(id)
    if (!m) return
    pane.picked = id
    if (m.boxes && m.boxes.length) pane.goToBox(m.boxes[0])
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
    // Sideways only when it is sized up past the fit: fitted, the margins
    // beside the text are out of view on purpose.
    if (dx !== 0 && pane.zoom > 1.01 && t.contentWidth - t.width > page.sp(40))
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
      // Another PDF opened in its place keeps the view and its holders: a
      // holder already dressed for the one before is not dressed again
      // (it drew every mark twice, a shade darker).
      if (pane.hasLayer(paper)) { pane.dressed = pane.dressed.concat([h]); continue }
      marksLayer.createObject(paper, { holder: h, paper: paper })
      pane.watch(h)
      pane.touchpad(paper)
      pane.darken(paper)
      pane.dressed = pane.dressed.concat([h])
    }
  }
  function hasLayer(paper) {
    for (var i = 0; i < paper.children.length; i++)
      if (paper.children[i].holder !== undefined && paper.children[i].count !== undefined) return true
    return false
  }
  // Dark pages (plan.md item 15, step 4): `i` draws the paper's pages in
  // the theme's colours — white paper the ground, black ink the text, a
  // figure's colours kept (dark-page.frag) — off by default, kept per paper
  // in pdf-dark.json in the state folder.
  property var darkPapers: ({})
  // The page's ground: the sheet's, a breath towards the ink, so a page's
  // edge still shows against the pane.
  readonly property color darkGround: Qt.tint(page.sheetColor, Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.05))
  readonly property bool dark: !!pane.darkPapers[pane.rel]
  function toggleDark() {
    if (pane.rel === "") return
    var d = JSON.parse(JSON.stringify(pane.darkPapers))
    if (d[pane.rel]) delete d[pane.rel]
    else d[pane.rel] = true
    pane.darkPapers = d
    darkFile.setText(JSON.stringify(d) + "\n")
    page.used("pdf", pane.dark ? "dark" : "light")
  }
  Component {
    id: darkPage
    ShaderEffect {
      property color ground: pane.darkGround
      property color ink: page.foreground
      fragmentShader: Qt.resolvedUrl("dark-page.frag.qsb")
    }
  }
  function darken(paper) {
    // Qt lays each page's picture on a white sheet (the paper, the picture
    // see-through around the ink): the sheet takes the ground too.
    paper.color = Qt.binding(function () { return pane.dark ? pane.darkGround : "white" })
    for (var i = 0; i < paper.data.length; i++) {
      var o = paper.data[i]
      if (String(o).indexOf("PdfPageImage") < 0) continue
      o.layer.effect = darkPage
      o.layer.enabled = Qt.binding(function () { return pane.dark })
    }
  }
  FileView {
    id: darkFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/pdf-dark.json"
    atomicWrites: true
    printErrors: false
    onLoaded: { try { var o = JSON.parse(text()); if (o && typeof o === "object") pane.darkPapers = o } catch (e) {} }
  }

  // A scan has no words to select, find or ask about. `r` reads it
  // (`longhand-read ocr`: each page drawn and read by tesseract into a copy
  // with an invisible text layer), saying how far it is; read, the copy
  // takes its place and it is marked as any paper is.
  property var ocrProgress: null        // { page, pages } while it reads
  readonly property bool ocrable: pane.rel !== "" && pane.rel.charAt(0) !== "/" && !!pane.read.scanned && !pane.read.ocr
  function readScan() {
    if (!pane.ocrable || ocrProc.running) return
    pane.ocrProgress = { page: 0, pages: pane.pages }
    ocrProc.forRel = pane.rel
    ocrProc.command = [pane.readPath, "ocr", "--pdf", pane.rel]
    ocrProc.running = true
    page.used("pdf", "ocr")
  }
  Process {
    id: ocrProc
    property string forRel: ""
    stdout: SplitParser {
      onRead: function (line) {
        var o = null
        try { o = JSON.parse(line) } catch (e) { return }
        if (ocrProc.forRel !== pane.rel) return
        // The state at the end has `ocr` too (the copy's path): it is told
        // apart by `pdf`.
        if (o.pdf === pane.rel) { pane.ocrProgress = null; pane.read = o; pane.readRun(["acronyms"]) }
        else if (o.ocr && typeof o.ocr === "object") pane.ocrProgress = o.ocr
      }
    }
    stderr: StdioCollector {
      id: ocrErr
      onStreamFinished: { var t = ocrErr.text.trim(); if (t !== "") { pane.readError = t.replace(/^longhand-read:\s*/, ""); pane.ocrProgress = null } }
    }
    onRunningChanged: if (!running && ocrProc.forRel === pane.rel) pane.ocrProgress = null
  }

  // Qt's page selects words with a drag from a mouse or a stylus only; on
  // a laptop the touchpad is its own kind of device, so a drag there
  // selected nothing (2026-11-15, seen on both laptops: first as the pages
  // sliding, then as nothing at all). The page's drag and click take the
  // touchpad too.
  function touchpad(paper) {
    for (var i = 0; i < paper.data.length; i++) {
      var o = paper.data[i], name = String(o)
      if ((name.indexOf("DragHandler") >= 0 || name.indexOf("TapHandler") >= 0)
          && o.acceptedDevices !== undefined && (o.acceptedDevices & PointerDevice.Mouse))
        o.acceptedDevices = o.acceptedDevices | PointerDevice.TouchPad
    }
  }
  // Words selected on a page bring the keys here, wherever they were (a
  // PDF opened from the Files tree leaves them in the sidebar): `m` and `q`
  // must reach the words just selected.
  function watch(h) {
    // A holder handed another page as the view scrolls: drawn again once
    // the scrolling stops (redrawPages says why).
    h.indexChanged.connect(function () { pane.redrawSoon() })
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
    if (!pane.markable) { pane.readError = pane.rel.charAt(0) === "/" ? "only a PDF in the vault keeps marks" : "a scan, no words to mark: " + page.keyName("pdfOcr") + " reads it"; return false }
    var args = ["mark", "--page", String(pageIndex + 1), "--text", text, "--kind", kind]
    if (y !== undefined && y !== null && !isNaN(y)) args.push("--y", String(Math.round(y * 10) / 10))
    pane.awaitingMark = true
    pane.askAfter = kind === "q"
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
  // A click on the marks of page `index`, at `x`/`y` in the page's own
  // points: the smallest mark there, again the next larger (PdfMarks.js),
  // so a word highlighted inside a question can be clicked (2026-11-16).
  // Each mark's rectangle under the click hears it: it is acted on once.
  property var lastTap: null
  function tapAt(index, x, y, s) {
    if (pane.rel === "") return
    var now = Date.now(), t = pane.lastTap
    pane.lastTap = { at: now, index: index, x: x, y: y }
    if (t && now - t.at < 80 && t.index === index && Math.abs(t.x - x) < 2 && Math.abs(t.y - y) < 2) return
    pane.tapPick = Marks.pick(pane.read.marks || [], index, x, y, pane.picked, 1.5 / Math.max(0.01, s))
    Qt.callLater(pane.settleTap)
  }
  // A click heard by a mark and by an acronym inside it is one click: the
  // acronym's (its definition), never both. Settled once both have heard it.
  property var tapPick: undefined
  property string tapAcro: ""
  function acroTap(a) {
    pane.tapAcro = a
    Qt.callLater(pane.settleTap)
  }
  function settleTap() {
    var a = pane.tapAcro, p = pane.tapPick
    pane.tapAcro = ""
    pane.tapPick = undefined
    if (a !== "") { pane.acroGo(a); return }
    if (p !== undefined) { pane.picked = p; keys.forceActiveFocus() }
  }
  // A click on the page away from every mark lets go of the mark picked,
  // as Esc does (2026-11-17: picked, it stayed until another was clicked).
  // The marks under a click hear it themselves (tapAt).
  function tapAway(index, x, y, s) {
    if (pane.picked === "" || pane.noting) return
    if (Marks.under(pane.read.marks || [], index, x, y, 1.5 / Math.max(0.01, s)).length > 0) return
    pane.picked = ""
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
    // Not `layer`: every Item has a `layer` of its own (its effects), and
    // inside a mark's Rectangle that name meant the Rectangle's, so every
    // mark came out with no size (2026-11-15).
    Item {
      id: sheet
      property Item holder
      property Item paper
      anchors.fill: parent
      readonly property int index: holder ? holder.index : -1
      readonly property real s: paper && paper.pageScale ? paper.pageScale : 1
      readonly property var rects: pane.rectsOn(sheet.index)
      readonly property int count: painted.count
      TapHandler {
        acceptedDevices: PointerDevice.AllDevices
        onTapped: function (point) { pane.tapAway(sheet.index, point.position.x / sheet.s, point.position.y / sheet.s, sheet.s) }
      }
      // The marks see-through, each place painted once: where two cover the
      // same words the colour is the same, never darker (2026-11-15), and
      // where a question crosses a highlight the later one shows. No layer
      // (PdfMarks.paint says why).
      Repeater {
        id: painted
        model: Marks.paint(sheet.rects, 1.5 / sheet.s)
        delegate: Rectangle {
          required property var modelData
          x: modelData.x * sheet.s
          y: modelData.y * sheet.s
          width: modelData.w * sheet.s
          height: modelData.h * sheet.s
          radius: modelData.round ? 2 : 0
          readonly property color ink: modelData.kind === "q" ? page.palette.blue : page.palette.yellow
          color: Qt.rgba(ink.r, ink.g, ink.b, 0.4)
        }
      }
      // Each mark's own rectangles, unseen: what the pointer hovers and clicks.
      Repeater {
        model: sheet.rects
        delegate: Item {
          id: box
          required property var modelData
          readonly property real pad: 1.5
          x: modelData.r[0] * sheet.s - pad
          y: modelData.r[1] * sheet.s
          width: modelData.r[2] * sheet.s + 2 * pad
          height: modelData.r[3] * sheet.s
          HoverHandler {
            onHoveredChanged: hovered ? pane.markHover(box.modelData.id, box, box.width * box.height) : pane.markLeave(box)
          }
          TapHandler {
            acceptedDevices: PointerDevice.AllDevices
            onTapped: function (point) {
              pane.tapAt(sheet.index, (box.x + point.position.x) / sheet.s, (box.y + point.position.y) / sheet.s, sheet.s)
            }
          }
        }
      }
      // The acronyms written on this page: hovered, each says what it
      // stands for; underlined while hovered, and all while the list is open.
      Repeater {
        model: pane.acroOn(sheet.index)
        delegate: Item {
          id: spot
          required property var modelData
          readonly property var def: pane.acro.byShort[modelData.a] || null
          readonly property bool lit: pane.hoverAcro !== null && pane.hoverAcro.item === spot
          x: modelData.r[0] * sheet.s
          y: modelData.r[1] * sheet.s
          width: modelData.r[2] * sheet.s
          height: modelData.r[3] * sheet.s
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -Math.max(1, sheet.s)
            height: Math.max(1, sheet.s * 0.7)
            color: spot.def && spot.def.defined ? page.accent : page.dim
            opacity: spot.lit ? 0.9 : pane.acroListing ? 0.5 : 0
          }
          HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: hovered ? pane.acroHover(spot.modelData.a, spot, sheet.index) : pane.acroLeave(spot)
          }
          TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            onTapped: pane.acroTap(spot.modelData.a)
          }
        }
      }
      // Words the agent quoted, lit a moment where they are.
      Repeater {
        model: pane.flashOn(sheet.index)
        delegate: Rectangle {
          required property var modelData
          x: modelData[0] * sheet.s - 2
          y: modelData[1] * sheet.s - 1
          width: modelData[2] * sheet.s + 4
          height: modelData[3] * sheet.s + 2
          radius: 2
          color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0.22)
          border.width: 2
          border.color: page.accent
          opacity: flashTimer.running ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 400 } }
        }
      }
      // What Ctrl+F found, lit while it is open; the one shown, outlined.
      Repeater {
        model: pane.finding ? pane.findOnPage[String(sheet.index)] || [] : []
        delegate: Rectangle {
          required property var modelData
          readonly property bool shown: modelData.i === pane.findAt
          x: modelData.r[0] * sheet.s - 2
          y: modelData.r[1] * sheet.s - 1
          width: modelData.r[2] * sheet.s + 4
          height: modelData.r[3] * sheet.s + 2
          radius: 2
          color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, shown ? 0.3 : 0.14)
          border.width: shown ? 2 : 0
          border.color: page.accent
        }
      }
      // The mark picked, outlined at full strength above them.
      Repeater {
        model: pane.picked === "" ? [] : sheet.rects.filter(function (r) { return r.id === pane.picked })
        delegate: Rectangle {
          required property var modelData
          x: modelData.r[0] * sheet.s - 1.5
          y: modelData.r[1] * sheet.s
          width: modelData.r[2] * sheet.s + 3
          height: modelData.r[3] * sheet.s
          radius: 2
          color: "transparent"
          border.width: 2
          border.color: page.accent
        }
      }
    }
  }

  function key(event) {
    // Back from a definition gone to, before the page's own back.
    if (pane.jumpBack && Sc.hit(event, "linkBack")) { pane.jumpReturn(); return true }
    if (page.anywhereKey(event)) return true
    if (page.chatSelectionKey(event, !!(pane.view && pane.view.selectedText !== ""))) return true
    if (Sc.hit(event, "pdfGo")) {
      if (pane.hoverAcro) { pane.acroGo(pane.hoverAcro.a); return true }
      if (pane.hoverMark !== "") return pane.markGo(pane.hoverMark)
      if (pane.picked !== "") return pane.markGo(pane.picked)
    }
    if (Sc.hit(event, "pdfAcronyms")) { pane.openAcronyms(); return true }
    if (Sc.hit(event, "pdfMark")) return pane.mark("h")
    if (Sc.hit(event, "pdfQuestion")) return pane.mark("q")
    if (Sc.hit(event, "pdfNote")) { pane.startNote(); return true }
    if (pane.picked !== "" && Sc.hit(event, "pdfRemove")) return pane.remove()
    if (Sc.hit(event, "keysHere")) { page.toggleKeys(); return true }
    if (Sc.hit(event, "pdfDark")) { pane.toggleDark(); return true }
    if (Sc.hit(event, "pdfOcr")) { if (pane.ocrable) pane.readScan(); else pane.readError = pane.read.ocr ? "this scan was read already" : "this PDF has words of its own"; return true }
    if (Sc.hit(event, "pdfClose")) {
      // Esc lets go of what is picked or selected first.
      if (pane.picked !== "") { pane.picked = ""; return true }
      if (pane.view && pane.view.selectedText !== "") { pane.clearSelection(); return true }
    }
    var step = page.sp(60)
    if (Sc.hit(event, "pdfDown")) pane.scrollBy(step)
    else if (Sc.hit(event, "pdfUp")) pane.scrollBy(-step)
    else if (Sc.hit(event, "pdfNextPage")) pane.turn(1)
    else if (Sc.hit(event, "pdfPrevPage")) pane.turn(-1)
    // The ends: the top of the first page, the top of the last (as far as
    // it goes). goToPage keeps the place inside the page, so it is not
    // used for them: from the foot of a page it would land on another's foot.
    else if (Sc.hit(event, "pdfFirst")) { if (pane.view) pane.view.goToLocation(0, Qt.point(0, 0), 0); pane.alignSoon() }
    else if (Sc.hit(event, "pdfLast")) { if (pane.view) pane.view.goToLocation(Math.max(0, pane.pages - 1), Qt.point(0, 0), 0); pane.alignSoon() }
    else if (Sc.hit(event, "pdfBigger")) pane.zoom = Math.min(4, pane.zoom * 1.2)
    else if (Sc.hit(event, "pdfSmaller")) pane.zoom = Math.max(0.3, pane.zoom / 1.2)
    else if (Sc.hit(event, "pdfFit")) {
      // Sized: back to the fit. Fitted: the whole page ↔ its text.
      if (Math.abs(pane.zoom - 1) > 0.01) pane.zoom = 1
      else { pane.wholePage = !pane.wholePage; Qt.callLater(pane.fit) }
    }
    else if (Sc.hit(event, "pdfFind")) pane.openFind()
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

  // The tip of the acronym under the pointer.
  Rectangle {
    id: acroTipBox
    readonly property var d: pane.hoverAcro ? pane.acro.byShort[pane.hoverAcro.a] || null : null
    // A mark's, when no acronym is under the pointer.
    readonly property var m: !d && pane.hoverMark !== "" ? pane.markTip(pane.hoverMark) : null
    readonly property Item anchor: d && pane.hoverAcro ? pane.hoverAcro.item : pane.hoverMarkAt ? pane.hoverMarkAt.item : null
    readonly property point at: {
      pane.tipOn
      if (!anchor) return Qt.point(0, 0)
      return anchor.mapToItem(pane, 0, anchor.height)
    }
    readonly property bool here: !!(d !== null && pane.hoverAcro !== null && pane.hoverAcro.item
      && pane.acroIsDef(d.short, pane.hoverAcro.page, pane.hoverAcro.item.modelData.r))
    visible: pane.tipOn && (d !== null || m !== null)
    z: 4
    width: Math.min(pane.width - page.sp(16), Math.max(acroTipLine.width, acroTipMore.implicitWidth,
                                                        acroTipAsked.visible ? acroTipAsked.width : 0) + page.sp(20))
    height: acroTipCol.implicitHeight + page.sp(14)
    x: Math.max(page.sp(8), Math.min(pane.width - width - page.sp(8), at.x - page.sp(10)))
    y: at.y + page.sp(6) + height > pane.height - foot.height ? at.y - (anchor ? anchor.height : 0) - height - page.sp(6) : at.y + page.sp(6)
    radius: Style.cornerRadius
    color: page.sunk
    border.width: 1
    border.color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
    Column {
      id: acroTipCol
      x: page.sp(10)
      y: page.sp(7)
      spacing: page.sp(3)
      // The question as it was asked, over its answer (2026-11-16: "can I
      // see the question that was asked?").
      Text {
        id: acroTipAsked
        visible: !!(acroTipBox.m && acroTipBox.m.asked)
        width: Math.min(implicitWidth, page.sp(440), pane.width - page.sp(36))
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: acroTipBox.m && acroTipBox.m.asked ? "you asked: “" + acroTipBox.m.asked + "”" : ""
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.italic: true
        font.pixelSize: page.fs(Style.font.caption)
      }
      Text {
        id: acroTipLine
        width: Math.min(implicitWidth, page.sp(440), pane.width - page.sp(36))
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        text: acroTipBox.m ? acroTipBox.m.line : !acroTipBox.d ? "" : "<b>" + acroTipBox.d.short + "</b>&nbsp;&nbsp;"
          + (acroTipBox.d.defined ? pane.esc(acroTipBox.d.long) : "<i>not spelled out in this paper</i>")
        color: page.foreground
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      Text {
        id: acroTipMore
        textFormat: Text.PlainText
        text: acroTipBox.m ? acroTipBox.m.more : !acroTipBox.d ? ""
          : !acroTipBox.d.defined ? (page.paper.askable ? "Enter or a click asks the paper's chat, as a guess" : "")
          : acroTipBox.here ? "spelled out here"
          : "p. " + acroTipBox.d.page + " · Enter or a click goes there"
        visible: text !== ""
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
  }

  // Ctrl+F: the words to find, how many places, and each with the words
  // round it; the one shown is the row lit.
  Rectangle {
    id: findBar
    visible: pane.finding
    z: 3
    anchors.bottom: foot.top
    anchors.bottomMargin: page.sp(6)
    anchors.right: parent.right
    width: Math.min(parent.width, page.sp(480))
    height: findColumn.implicitHeight + page.sp(16)
    radius: Style.cornerRadius
    color: page.palette.background
    border.width: 1
    border.color: page.accent
    readonly property string count: findField.text.trim().length < 2 ? ""
      : pane.findBusy && pane.findFor !== findField.text.trim() ? "…"
      : pane.findTotal === 0 ? "none"
      : (pane.findAt + 1) + " of " + pane.findTotal
    readonly property string says: pane.read.text === false && !pane.read.ocr
        ? (pane.ocrable ? "a scan, no words to find: " + page.keyName("pdfOcr") + " reads it" : "no words in this PDF to find")
      : findField.text.trim().length < 2 ? "words to find in this paper · Esc"
      : pane.findFor !== "" && pane.findTotal === 0 && !pane.findBusy
        ? "not in this paper" + (pane.findCased ? " (with these capitals: small letters find any)" : "")
      : "Enter next · Shift+Enter before · Esc closes"
        + (pane.findCased ? " · capitals count" : "")
        + (pane.findTotal > pane.findHits.length ? " · the first " + pane.findHits.length + " listed" : "")
    Column {
      id: findColumn
      x: page.sp(10)
      y: page.sp(8)
      width: parent.width - page.sp(20)
      spacing: page.sp(4)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: findBar.says + (pane.findSaid !== "" ? " · " + pane.findSaid : "")
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      Item {
        width: parent.width
        height: findField.implicitHeight
        TextField {
          id: findField
          anchors.left: parent.left
          anchors.right: findCount.left
          anchors.rightMargin: page.sp(8)
          placeholderText: "find in this paper"
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
          foreground: page.foreground
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) { if (pane.findKey(event)) event.accepted = true }
          onTextChanged: if (pane.finding) findTimer.restart()
        }
        Text {
          id: findCount
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: findBar.count
          color: findBar.count === "none" ? page.urgent : page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
      ListView {
        id: findRows
        visible: pane.findHits.length > 0
        width: parent.width
        height: visible ? Math.min(contentHeight, page.sp(200)) : 0
        clip: true
        model: pane.findHits
        currentIndex: pane.findAt
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: findRows.width
          height: findRowText.implicitHeight + page.sp(4)
          radius: Style.cornerRadius
          color: pane.findAt === index ? Style.selectedFill : "transparent"
          Text {
            id: findRowText
            anchors.left: parent.left
            anchors.leftMargin: page.sp(4)
            anchors.right: findRowPage.left
            anchors.rightMargin: page.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: pane.findRow(modelData)
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            id: findRowPage
            anchors.right: parent.right
            anchors.rightMargin: page.sp(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "p. " + (modelData.page + 1)
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { pane.findSaid = ""; pane.findShow(parent.index); findField.forceActiveFocus() }
          }
        }
      }
    }
  }

  // `a`: the paper's acronyms, narrowing as letters are typed; Enter goes
  // to where the one chosen is spelled out.
  Rectangle {
    id: acroList
    visible: pane.acroListing
    z: 3
    anchors.bottom: foot.top
    anchors.bottomMargin: page.sp(6)
    anchors.right: parent.right
    width: Math.min(parent.width, page.sp(460))
    height: acroColumn.implicitHeight + page.sp(16)
    radius: Style.cornerRadius
    color: page.palette.background
    border.width: 1
    border.color: page.accent
    Column {
      id: acroColumn
      x: page.sp(10)
      y: page.sp(8)
      width: parent.width - page.sp(20)
      spacing: page.sp(4)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: pane.acro.list.length + " acronyms, underlined on the pages · Enter goes to where it is spelled out · Esc"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      TextField {
        id: acroField
        width: parent.width
        placeholderText: "an acronym, or words of what it stands for"
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
        foreground: page.foreground
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (page.anywhereKey(event)) { event.accepted = true; return }
          var seq = Sc.fromEvent(event)
          if (seq === "Enter") { pane.acroPick(); event.accepted = true }
          else if (seq === "Esc") { pane.closeAcronyms(); event.accepted = true }
          else if (seq === "Up") { pane.acroFocus = Math.max(0, pane.acroFocus - 1); event.accepted = true }
          else if (seq === "Down") { pane.acroFocus = Math.min(pane.acroChoices.length - 1, pane.acroFocus + 1); event.accepted = true }
        }
        onTextChanged: pane.acroFocus = 0
      }
      ListView {
        id: acroRows
        width: parent.width
        height: Math.min(contentHeight, page.sp(300))
        clip: true
        model: pane.acroChoices
        currentIndex: pane.acroFocus
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: acroRows.width
          height: acroRowText.implicitHeight + page.sp(4)
          radius: Style.cornerRadius
          color: pane.acroFocus === index ? Style.selectedFill : "transparent"
          Text {
            id: acroRowText
            anchors.left: parent.left
            anchors.leftMargin: page.sp(4)
            anchors.right: acroRowPage.left
            anchors.rightMargin: page.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: "<b>" + modelData.short + "</b>&nbsp;&nbsp;" + (modelData.defined ? pane.esc(modelData.long) : "<i>not spelled out</i>")
            color: modelData.defined ? page.foreground : page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            id: acroRowPage
            anchors.right: parent.right
            anchors.rightMargin: page.sp(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: modelData.defined ? "p. " + modelData.page : "ask"
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { pane.closeAcronyms(); pane.acroGo(parent.modelData.short) } }
        }
      }
    }
  }

  // Which project the paper is for, asked once on its first mark.
  Rectangle {
    id: tagAsk
    visible: pane.askingTag
    z: 3
    anchors.bottom: foot.top
    anchors.bottomMargin: page.sp(6)
    width: Math.min(parent.width, page.sp(420))
    height: tagColumn.implicitHeight + page.sp(16)
    radius: Style.cornerRadius
    color: page.palette.background
    border.width: 1
    border.color: page.accent
    Column {
      id: tagColumn
      x: page.sp(10)
      y: page.sp(8)
      width: parent.width - page.sp(20)
      spacing: page.sp(4)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Which project is this paper for? Enter keeps it in its reading note · Esc: none"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
      TextField {
        id: tagField
        width: parent.width
        placeholderText: "a project's name or #tag"
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
        foreground: page.foreground
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (page.anywhereKey(event)) { event.accepted = true; return }
          var seq = Sc.fromEvent(event)
          if (seq === "Enter") { var c = pane.tagChoices[pane.tagFocus]; pane.chooseProject(c ? c.tag : ""); event.accepted = true }
          else if (seq === "Esc") { pane.chooseProject(""); event.accepted = true }
          else if (seq === "Up") { pane.tagFocus = Math.max(0, pane.tagFocus - 1); event.accepted = true }
          else if (seq === "Down") { pane.tagFocus = Math.min(pane.tagChoices.length - 1, pane.tagFocus + 1); event.accepted = true }
        }
        onTextChanged: pane.tagFocus = 0
      }
      Repeater {
        model: pane.tagChoices
        Rectangle {
          required property var modelData
          required property int index
          width: tagColumn.width
          height: tagRowText.implicitHeight + page.sp(4)
          radius: Style.cornerRadius
          color: pane.tagFocus === index ? Style.selectedFill : "transparent"
          Text {
            id: tagRowText
            anchors.left: parent.left
            anchors.leftMargin: page.sp(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "#" + modelData.tag + "  " + modelData.name
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pane.chooseProject(parent.modelData.tag) }
        }
      }
    }
  }

  Loader {
    id: loader
    active: pane.rel !== ""
    anchors.top: parent.top
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
      : pane.flashMissed !== "" ? "those words are " + pane.flashMissed
      : "page " + (pane.current + 1) + " of " + pane.pages
        + (pane.ocrProgress ? " · reading the scan, page " + Math.max(1, pane.ocrProgress.page) + " of " + (pane.ocrProgress.pages || pane.pages) + "…"
           : pane.ocrable ? " · a scan, no words in it: " + page.keyName("pdfOcr") + " reads it (a few seconds a page)"
           : pane.read.ocr ? " · read from a scan" : "")
        + (foot.count > 0 ? " · " + foot.count + (foot.count === 1 ? " mark" : " marks") : "")
        + ((pane.read.tags || []).length > 0 ? " · " + pane.read.tags.map(function (x) { return "#" + x }).join(" ") : "")
        + (pane.tagSaid !== "" ? " (kept in its reading note)" : "")
        + (pane.read.unplaced > 0 ? ", " + pane.read.unplaced + " not found on its page" : "")
        + "   " + (pane.jumpBack ? page.keyName("linkBack") + " back to where you were · " : "")
        + (pane.selected() ? page.keyName("pdfMark") + " highlight · " + page.keyName("pdfQuestion") + " question"
                   : pane.picked !== "" ? (page.paper.askable ? page.keyName("pdfGo") + " to the paper's chat · " : "") + page.keyName("pdfMark") + "/" + page.keyName("pdfQuestion") + " its kind · " + page.keyName("pdfNote") + " a note · " + page.keyName("pdfRemove") + " remove · " + page.keyName("pdfClose") + " or a click away lets go"
                   : (pane.markable ? "select words to mark them · " : "")
                     + (pane.acro.list.length > 0 ? page.keyName("pdfAcronyms") + " acronyms · " : "")
                     + page.keyName("pdfOpen") + " opens it elsewhere")
    color: pane.error !== "" || pane.readError !== "" ? page.urgent : page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
}
