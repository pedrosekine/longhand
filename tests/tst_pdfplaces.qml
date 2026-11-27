import QtQuick
import QtTest
import "../plugin-page/PdfPlaces.js" as Places

// Where each PDF was left (PdfPlaces.js, pdfs.json).
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_pdfplaces.qml
TestCase {
  name: "PdfPlaces"

  // Each page's top, and the page at a place: the view lays its pages
  // exactly at these tops, at any scale, and reads them back from them.
  function test_page_tops_and_the_page_at_a_place() {
    compare(Places.tops([1000, 500, 1000], 6), [0, 1006, 1512])
    compare(Places.tops([], 6), [])
    var t = Places.tops([1000, 500, 1000], 6)
    compare(Places.pageAt(t, 0), 0)
    compare(Places.pageAt(t, 1003), 0)        // in the gap: the page above
    compare(Places.pageAt(t, 1006), 1)
    compare(Places.pageAt(t, 1511.5), 1)
    compare(Places.pageAt(t, 1512), 2)
    compare(Places.pageAt(t, 99999), 2)       // past the end: the last
    compare(Places.pageAt(t, -40), 0)         // above the first: the first
    compare(Places.pageAt([], 0), -1)
    // Three hundred pages, any page found again from its own top.
    var hs = []
    for (var i = 0; i < 300; i++) hs.push(i % 7 === 0 ? 1188.4 : 1320.75)
    var big = Places.tops(hs, 6)
    for (var k = 0; k < 300; k += 13) {
      compare(Places.pageAt(big, big[k]), k)
      compare(Places.pageAt(big, big[k] + hs[k] + 5.9), k)
    }
  }

  function test_kept_and_found_again() {
    var r = Places.put({}, "a.pdf", { page: 3, frac: 0.4, zoom: 1.2 }, 100)
    compare(r["a.pdf"], { page: 3, frac: 0.4, zoom: 1.2, at: 100 })
    compare(Places.get(r, "a.pdf", 10), { page: 3, frac: 0.4, zoom: 1.2 })
    compare(Places.get(r, "b.pdf", 10), null)
    // The old record is left as it was.
    var r2 = Places.put(r, "a.pdf", { page: 5, frac: 0, zoom: 1 }, 200)
    compare(r["a.pdf"].page, 3)
    compare(r2["a.pdf"].page, 5)
  }

  function test_the_top_needs_nothing_kept() {
    var r = Places.put({}, "a.pdf", { page: 3, frac: 0.4, zoom: 1 }, 100)
    r = Places.put(r, "a.pdf", { page: 0, frac: 0, zoom: 1 }, 200)
    compare(Object.keys(r), [])
    // At the top but larger: the size is worth keeping.
    r = Places.put(r, "a.pdf", { page: 0, frac: 0, zoom: 1.44 }, 300)
    compare(Places.get(r, "a.pdf", 2), { page: 0, frac: 0, zoom: 1.44 })
  }

  function test_the_whole_page_fit_is_kept() {
    // At the top at its own size, but fitted by the whole page: kept.
    var r = Places.put({}, "a.pdf", { page: 0, frac: 0, zoom: 1, whole: true }, 100)
    compare(Places.get(r, "a.pdf", 2), { page: 0, frac: 0, zoom: 1, whole: true })
    r = Places.put(r, "a.pdf", { page: 0, frac: 0, zoom: 1 }, 200)
    compare(Object.keys(r), [], "fitted by its text again: nothing to keep")
  }

  function test_a_changed_pdf() {
    var r = { "a.pdf": { page: 8, frac: 0.6, zoom: 1, at: 1 } }
    compare(Places.get(r, "a.pdf", 4), { page: 3, frac: 0, zoom: 1 })   // fewer pages now: the last
    compare(Places.get(r, "a.pdf", 0), null)
    compare(Places.get({ "a.pdf": "nonsense" }, "a.pdf", 4), null)
    compare(Places.get({ "a.pdf": { page: -1 } }, "a.pdf", 4), null)
    compare(Places.get({ "a.pdf": { page: 1, frac: 7, zoom: 99 } }, "a.pdf", 4), { page: 1, frac: 1, zoom: 4 })
  }

  function test_only_the_newest_are_kept() {
    var r = {}
    for (var i = 0; i < Places.KEEP + 5; i++) r = Places.put(r, "f" + i + ".pdf", { page: 1, frac: 0, zoom: 1 }, i)
    compare(Object.keys(r).length, Places.KEEP)
    compare(r["f0.pdf"], undefined)
    compare(r["f4.pdf"], undefined)
    verify(r["f5.pdf"] !== undefined)
    verify(r["f" + (Places.KEEP + 4) + ".pdf"] !== undefined)
  }
}
