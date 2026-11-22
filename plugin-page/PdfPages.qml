import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import QtQuick.Shapes
import "PdfPlaces.js" as Places

// A PDF's pages, one under the next: Longhand's own view (2026-11-22,
// docs/explorations/pdf-view), in place of Qt's PdfMultiPageView. PDFium
// still draws and selects (PdfPageImage, PdfSelection, PdfLinkModel); what
// changed is who lays the pages out.
//
// A plain Flickable holding one light sheet of paper per page, each at the
// top its page's height and the ones before it add up to (PdfPlaces.tops),
// at any scale: a place worked out is the place shown. Only the pages in
// view, and half a view on either side, draw their picture, select words
// and carry the marks (`overlay`, the pane's); the others are blank paper.
// Qt's view guessed where the pages it had not laid were and kept stale
// places after a rescale, slid pages sideways on its own jumps, measured
// its column before taking in a new size, raced its pictures and fought
// word selection with its dragging: each of those fixes is gone with it.
//
// The view never pans on a drag: a drag selects. The touchpad scrolls it
// as it does the note (TouchScroll), a pinch sizes it about the fingers,
// the pane's wheel and keys do the rest.
Item {
  id: pages
  required property PdfDocument document
  // Pixels a point, as laid now (a pinch moves it frame by frame); the
  // pictures are drawn at `drawScale`, which follows once a pinch rests,
  // stretched meanwhile.
  property real renderScale: 1
  property real drawScale: 1
  property real minScale: 0.1
  property real maxScale: 10
  // Sized past `sidewaysScale` (the pane's: just past the fit), the pages
  // may be moved sideways, when wider than the view by more than `slack`
  // pixels; otherwise they stay centred.
  property real sidewaysScale: 1e9
  property real slack: 40
  // False until the pane has fitted a new PDF: nothing is drawn at a size
  // about to change.
  property bool live: false
  property bool dark: false
  property color paperColor: "white"
  property Component darkEffect: null
  // A layer over each page drawn (the pane's marks): given `index`.
  property Component overlay: null
  property string selectedText: ""
  readonly property real gap: 6
  readonly property alias flick: flick
  readonly property bool pinching: pinch.active
  signal selectionMade(string text)
  signal linkTapped(var link)
  signal pinched()

  readonly property bool ready: !!document && document.status === PdfDocument.Ready
  readonly property int count: ready ? document.pageCount : 0
  // Every page's size in points, read once a PDF is ready.
  readonly property var sizes: {
    var out = []
    for (var i = 0; i < pages.count; i++) out.push(pages.document.pagePointSize(i))
    return out
  }
  readonly property real maxWidth: {
    var m = 0
    for (var i = 0; i < pages.sizes.length; i++) m = Math.max(m, pages.sizes[i].width)
    return m
  }
  readonly property var heights: pages.sizes.map(function (z) { return z.height * pages.renderScale })
  readonly property var tops: Places.tops(pages.heights, pages.gap)
  readonly property real total: pages.tops.length ? pages.tops[pages.tops.length - 1] + pages.heights[pages.heights.length - 1] : 0
  // The pages drawn: those across the view and half a view either side,
  // { first, last }. One value, changed at once: two, the first moved
  // before the last on a jump up the paper, and for that moment every page
  // between the two places was drawn (4 GB on a 300-page PDF).
  property var range: ({ first: -1, last: -1 })
  function updateRange() {
    var m = flick.height / 2
    var a = Places.pageAt(pages.tops, flick.contentY - m), b = Places.pageAt(pages.tops, flick.contentY + flick.height + m)
    if (a !== pages.range.first || b !== pages.range.last) pages.range = { first: a, last: b }
  }
  onTopsChanged: pages.updateRange()
  // The page across the view's middle: the one being read.
  readonly property int currentPage: Math.max(0, Places.pageAt(pages.tops, flick.contentY + flick.height / 2))

  PdfStyle { id: style }

  // ------------------------------------------------------------ places

  // The page and how far down it (0 to 1) at `y`, in the scroller's pixels.
  function placeAt(y) {
    if (pages.tops.length === 0) return null
    var i = Places.pageAt(pages.tops, y)
    return { page: i, frac: Places.round(Math.max(0, Math.min(1, (y - pages.tops[i]) / Math.max(1, pages.heights[i])))) }
  }
  // Where the view's top goes for page `i`, `y` points down it.
  function placeOf(i, y) { return pages.clampY(pages.tops[i] + y * pages.renderScale) }
  // A page's top and left in the view (its own pixels, the view's top-left 0).
  function pageTop(i) { return pages.tops[i] - flick.contentY }
  function pageLeft(i) { return pages.pageX(i) - flick.contentX }
  function pageX(i) { return (flick.contentWidth - pages.sizes[i].width * pages.renderScale) / 2 }
  function clampY(y) { return Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), y)) }
  function clampX(x) { return Math.max(0, Math.min(Math.max(0, flick.contentWidth - flick.width), x)) }
  function canSideways() { return pages.renderScale > pages.sidewaysScale && flick.contentWidth - flick.width > pages.slack }
  function centre() { flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2) }
  // After a change of width: centred, unless it may be moved sideways.
  function settleX() {
    if (pages.canSideways()) flick.contentX = pages.clampX(flick.contentX)
    else pages.centre()
  }

  // ------------------------------------------------------------ moving

  // The view put there at once: opening where it was left, after a fit.
  function place(i, y) {
    pages.stop()
    if (i >= 0 && i < pages.count) flick.contentY = pages.placeOf(i, y)
  }
  // A jump to page `i`, `y` points down it at the view's top: a glide up
  // or down, never sideways (400 ms, slowing: as it was). To a page not
  // drawn, the view is first put most of a view short of it, on the side
  // it comes from, and glides the last stretch, so a far jump is a short
  // glide and the pages flown past are never drawn.
  function jumpTo(i, y) {
    if (i < 0 || i >= pages.count) return
    pages.stop()
    var from = flick.contentY, to = pages.placeOf(i, y)
    if (Math.abs(to - from) < 1) { flick.contentY = to; return }
    if (i < pages.range.first || i > pages.range.last) {
      var lead = Math.min(Math.abs(to - from), flick.height * 0.75)
      flick.contentY = to + (from < to ? -lead : lead)
    }
    glide.from = flick.contentY
    glide.to = to
    glide.start()
  }
  function scrollBy(dy) {
    pages.stop()
    flick.contentY = pages.clampY(flick.contentY + dy)
  }
  function stop() {
    glide.stop()
    flick.cancelFlick()
  }
  NumberAnimation { id: glide; target: flick; property: "contentY"; duration: 400; easing.type: Easing.OutQuart }

  // ------------------------------------------------------------ size

  // A new scale, the point at (ax, ay) in the view kept where it is: the
  // place on its page under it stays under it. `ax` below 0: the pages
  // centred (a key, the wheel, a fit keep the view's top, ay 0). `live`:
  // the pictures are left stretched until it rests (a pinch).
  function setScale(s, ax, ay, live) {
    s = Math.max(pages.minScale, Math.min(pages.maxScale, s))
    if (pages.count === 0) { pages.renderScale = s; pages.drawScale = s; return }
    if (Math.abs(s - pages.renderScale) < 1e-6) return
    var old = pages.renderScale
    var cy = flick.contentY + ay, i = Places.pageAt(pages.tops, cy)
    var py = (cy - pages.tops[i]) / old
    var px = (flick.contentX + Math.max(0, ax) - pages.pageX(i)) / old
    pages.renderScale = s
    flick.contentY = pages.clampY(pages.tops[i] + py * s - ay)
    if (ax >= 0 && pages.canSideways()) flick.contentX = pages.clampX(pages.pageX(i) + px * s - ax)
    else pages.centre()
    if (!live) { sharpen.stop(); pages.drawScale = s }
    else sharpen.restart()
  }
  Timer { id: sharpen; interval: 150; onTriggered: pages.drawScale = pages.renderScale }

  // A pinch, step by step: each step's change of size about the fingers,
  // so the words under them stay under them all the way, and nothing
  // moves when they lift (Qt's scaled one page alone, then laid them all
  // out again on the lift and centred them a moment later).
  function pinchBy(ratio, x, y) {
    if (pages.count === 0 || !(ratio > 0)) return
    pages.stop()
    pages.setScale(pages.renderScale * ratio, x, y, true)
    pages.pinched()
  }
  function pinchEnd() {
    sharpen.stop()
    pages.drawScale = pages.renderScale
  }
  PinchHandler {
    id: pinch
    target: null
    rotationAxis.enabled: false
    xAxis.enabled: false
    yAxis.enabled: false
    grabPermissions: PointerHandler.CanTakeOverFromAnything
    onScaleChanged: function (delta) { pages.pinchBy(delta, pinch.centroid.position.x, pinch.centroid.position.y) }
    onActiveChanged: if (!active) pages.pinchEnd()
  }

  // ------------------------------------------------------------ pages

  // The page's sheet as drawn now (its picture, selection, layer), or null.
  function sheet(i) {
    var s = slots.itemAt(i)
    return s ? s.sheet : null
  }
  // Where page `i` is laid, in the scroller's pixels (the harness checks
  // it against the pages' heights added up); null when there is no page.
  function laidTop(i) {
    var s = slots.itemAt(i)
    return s ? s.y : null
  }
  function drawn() {
    var out = []
    for (var i = Math.max(0, pages.range.first); i <= pages.range.last; i++) {
      var s = pages.sheet(i)
      if (s) out.push(s)
    }
    return out
  }
  function clearSelection(except) {
    var ds = pages.drawn()
    for (var i = 0; i < ds.length; i++) if (ds[i] !== except && ds[i].selection.text !== "") ds[i].selection.clear()
    if (!except) pages.selectedText = ""
  }

  Connections {
    target: pages.document
    function onSourceChanged() {
      pages.stop()
      flick.contentY = 0
      flick.contentX = 0
      pages.selectedText = ""
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: Math.max(width, pages.maxWidth * pages.renderScale)
    contentHeight: pages.total
    onWidthChanged: Qt.callLater(pages.settleX)
    onContentYChanged: pages.updateRange()
    onHeightChanged: pages.updateRange()
    onContentWidthChanged: Qt.callLater(pages.settleX)
    ScrollBar.vertical: ScrollBar {}
    ScrollBar.horizontal: ScrollBar {}

    TouchScroll { flickable: flick }

    Repeater {
      id: slots
      model: pages.count
      delegate: Rectangle {
        id: slot
        required property int index
        readonly property size pts: pages.sizes[index] || Qt.size(1, 1)
        readonly property Item sheet: load.item
        x: (flick.contentWidth - width) / 2
        y: pages.tops[index] || 0
        width: pts.width * pages.renderScale
        height: pts.height * pages.renderScale
        color: pages.paperColor
        Loader {
          id: load
          anchors.fill: parent
          active: pages.live && slot.index >= pages.range.first && slot.index <= pages.range.last
          sourceComponent: Item {
            id: sheet
            readonly property int index: slot.index
            readonly property alias selection: selection
            readonly property alias image: image
            readonly property Item marks: overlayLoader.item
            PdfPageImage {
              id: image
              anchors.fill: parent
              document: pages.document
              currentFrame: sheet.index
              asynchronous: true
              // The picture at the size before shown, stretched, until the
              // new one is drawn: never a blank page while sizing.
              retainWhileLoading: true
              fillMode: Image.Stretch
              sourceSize.width: Math.round(slot.pts.width * pages.drawScale * Screen.devicePixelRatio)
              sourceSize.height: 0
              layer.enabled: pages.dark && pages.darkEffect !== null
              layer.effect: pages.darkEffect
            }
            Shape {
              anchors.fill: parent
              ShapePath {
                strokeWidth: -1
                fillColor: style.selectionColor
                scale: Qt.size(pages.renderScale, pages.renderScale)
                PathMultiline { paths: selection.geometry }
              }
            }
            // A drag selects, with a mouse, a stylus or the touchpad (a
            // laptop's touchpad is its own kind of device: Qt's page took
            // only the first two, 2026-11-15); a click lets go of it.
            DragHandler {
              id: drag
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus | PointerDevice.TouchPad
              onActiveChanged: if (active) pages.clearSelection(sheet)
            }
            TapHandler {
              id: tap
              acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus | PointerDevice.TouchPad
            }
            Repeater {
              model: PdfLinkModel { document: pages.document; page: sheet.index }
              delegate: PdfLinkDelegate {
                x: rectangle.x * pages.renderScale
                y: rectangle.y * pages.renderScale
                width: rectangle.width * pages.renderScale
                height: rectangle.height * pages.renderScale
                onTapped: function (link) { pages.linkTapped(link) }
              }
            }
            PdfSelection {
              id: selection
              anchors.fill: parent
              document: pages.document
              page: sheet.index
              renderScale: pages.renderScale
              from: drag.centroid.pressPosition
              to: drag.centroid.position
              hold: !drag.active && !tap.pressed
              // No `focus`: a page drawn as it scrolls into view would take
              // the keys from the pane.
              onTextChanged: { pages.selectedText = text; pages.selectionMade(text) }
            }
            Loader {
              id: overlayLoader
              anchors.fill: parent
              sourceComponent: pages.overlay
              onLoaded: item.index = sheet.index
            }
            // Let go of with its page: words selected on a page scrolled
            // far away are no longer selected.
            Component.onDestruction: if (selection.text !== "" && pages.selectedText === selection.text) pages.selectedText = ""
          }
        }
      }
    }
  }
}
