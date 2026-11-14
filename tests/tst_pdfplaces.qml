import QtQuick
import QtTest
import "../plugin-page/PdfPlaces.js" as Places

// Where each PDF was left (PdfPlaces.js, pdfs.json).
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_pdfplaces.qml
TestCase {
  name: "PdfPlaces"

  function test_where_the_view_is() {
    // Three pages of 1000 px, 10 px between them.
    var hs = [1000, 1000, 1000]
    compare(Places.at(hs, 10, 0), { page: 0, frac: 0 })
    compare(Places.at(hs, 10, 500), { page: 0, frac: 0.5 })
    compare(Places.at(hs, 10, 1005), { page: 0, frac: 1 })      // in the gap: still the page above
    compare(Places.at(hs, 10, 1010), { page: 1, frac: 0 })
    compare(Places.at(hs, 10, 2270), { page: 2, frac: 0.25 })
    compare(Places.at(hs, 10, 99999), { page: 2, frac: 1 })     // past the end: the last page's foot
    compare(Places.at(hs, 10, -40), { page: 0, frac: 0 })
    compare(Places.at([], 10, 0), null)
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
