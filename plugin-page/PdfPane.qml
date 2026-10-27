import Quickshell
import QtQuick
import QtQuick.Pdf
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc

// A PDF in the middle, in the note's place (docs/files.md, step 5,
// 2026-10-27): Qt's own view, fitted to the column, the pages drawn as they
// come into view. Loaded only while a PDF is open — the document and its
// pages are let go of when it closes — so a page that never opens a PDF
// pays nothing for it. Read only: a PDF is not written here.
//
// Keys (Shortcuts.js, "in a PDF"): arrows or j/k scroll, PgUp/PgDn and
// Space a page, Home/End the ends, Ctrl+F finds, + / - / 0 size it, o opens
// it in its own application, Esc closes it (back to the note under it).
Item {
  id: pane
  required property Item page
  property string rel: ""
  property alias keysRef: keys
  property alias findRef: findField
  property real zoom: 1                 // over the column's width
  property bool finding: false
  readonly property var view: loader.item ? loader.item.view : null
  readonly property int pages: loader.item ? loader.item.doc.pageCount : 0
  readonly property int current: view ? view.currentPage : 0
  readonly property bool ready: loader.item ? loader.item.doc.status === PdfDocument.Ready : false
  readonly property string error: loader.item && loader.item.doc.status === PdfDocument.Error ? "this PDF could not be read" : ""

  visible: rel !== ""
  onRelChanged: { pane.zoom = 1; pane.finding = false; findField.text = "" }

  function url() {
    var v = pane.page.noteService.config.vault
    return "file://" + (v + "/" + pane.rel).split("/").map(encodeURIComponent).join("/")
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
  onReadyChanged: if (ready) Qt.callLater(pane.fit)

  function find(dir) {
    if (!pane.view) return
    pane.view.searchString = findField.text
    if (dir > 0) pane.view.searchForward()
    else if (dir < 0) pane.view.searchBack()
  }

  function key(event) {
    if (page.anywhereKey(event)) return true
    var step = page.sp(60)
    if (Sc.hit(event, "pdfDown")) pane.scrollBy(step)
    else if (Sc.hit(event, "pdfUp")) pane.scrollBy(-step)
    else if (Sc.hit(event, "pdfNextPage")) { if (pane.view) pane.view.goToPage(Math.min(pane.pages - 1, pane.current + 1)) }
    else if (Sc.hit(event, "pdfPrevPage")) { if (pane.view) pane.view.goToPage(Math.max(0, pane.current - 1)) }
    else if (Sc.hit(event, "pdfFirst")) { if (pane.view) pane.view.goToPage(0) }
    else if (Sc.hit(event, "pdfLast")) { if (pane.view) pane.view.goToPage(Math.max(0, pane.pages - 1)) }
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
    text: pane.error !== "" ? pane.error
      : !pane.ready ? "reading…"
      : "page " + (pane.current + 1) + " of " + pane.pages
        + (pane.view && pane.finding && pane.view.searchModel.count > 0 ? " · " + pane.view.searchModel.count + " found" : "")
        + "   " + page.keyName("pdfOpen") + " opens it elsewhere"
    color: pane.error !== "" ? page.urgent : page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
}
